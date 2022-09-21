use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use XML::LibXML qw(:libxml);
use Getopt::Long;
use LWP::Simple;
use LWP::UserAgent;
use Time::HiRes;
use JSON;
use File::Basename;
use File::Spec;


use Data::Dumper;
use ParCzech::PipeLine::FileManager "udpipe";

my $scriptname = $0;
my $dirname = dirname($scriptname);

my $udsyn_taxonomy = File::Spec->catfile($dirname,'tei_udsyn_taxonomy.xml');

my ($debug, $try2continue_on_error, $test, $no_lemma_tag, $no_parse, $model, $elements_names, $sub_elements_names, $append_metadata, $replace_colons_with_underscores, $try2fix_spaces);

my$xmlNS = 'http://www.w3.org/XML/1998/namespace';

my $xpc = ParCzech::PipeLine::FileManager::TeiFile::new_XPathContext();

my $url = 'http://lindat.mff.cuni.cz/services/udpipe/api/process';
$elements_names = "seg,head";
$sub_elements_names = "ref";
my $word_element_name = 'w';
my $punct_element_name = 'pc';
my $sent_element_name = 's';

my $soft_max_text_length = 100000;
# 100 000 -> udpipe: 30seconds , script: 3seconds

GetOptions ( ## Command line options
            'colon2underscore' => \$replace_colons_with_underscores, # replace colons in extended syntax relations with underscore
            'debug' => \$debug, # debugging mode
            'try2continue-on-error' => \$try2continue_on_error,
            'try2fix-spaces' => \$try2fix_spaces,
            'test' => \$test, # tokenize, tag and lemmatize and parse to stdout, do not change the database
            'append-metadata=s' => \$append_metadata, # add metadata from file (prefixes, taxonomy)
            'no-lemma-tag' => \$no_lemma_tag, # no tags and lemmas
            'no-parse' => \$no_parse, # no dependency parsing
            'model=s' => \$model, # udpipe model tagger
            'elements=s' => \$elements_names,
            'sub-elements=s' => \$sub_elements_names, # child elements that are also tokenized
            'word-element=s' => \$word_element_name,
            'punct-element=s' => \$punct_element_name,
            'sent-element=s' => \$sent_element_name,
            ParCzech::PipeLine::FileManager::opts()
#            'tags=s' => \@tags, # tag attribute name|format (pos cs::pdt)
            );

usage_exit() unless ParCzech::PipeLine::FileManager::process_opts();


usage_exit() unless $model;

my %sub_elements_names_filter = map {$_ => 1} split(',', $sub_elements_names);

if ( $elements_names =~ m/[\s"']/ ){
  usage_exit();
}


my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });
my $current_file;

while($current_file = ParCzech::PipeLine::FileManager::next_file('tei', xpc => $xpc)) {
  next unless defined($current_file->{dom});

  my $doc = $current_file->get_doc();

  my @parents = $xpc->findnodes('//tei:text//tei:*[contains(" '.join(' ',split(',',$elements_names)).' ", concat(" ",name()," "))]',$doc);
  while(@parents) {
    my @nodes = (); # {parent: ..., node: ..., text: ..., tokenize: boolean}
    my $text = '';
    my $parent_cnt = 0;
    my $grandpa = undef;
    while(my $parent = shift @parents) {
      my $contain_text = undef;
      my $parent_id = $parent->getAttributeNS('http://www.w3.org/XML/1998/namespace','id');
      $parent_cnt++;
      for my $chnode ($parent->childNodes()) {
        $chnode->unbindNode();
        my $child = {
          parent => $parent,
          parent_id => $parent_id,
          parent_cnt => $parent_cnt,
          node => $chnode,
          text => ($try2fix_spaces?' ':''),
          len => ($try2fix_spaces?1:0),
          textptr => length($text),
          tokenize => 0
        };
        if ( $chnode->nodeType == XML_TEXT_NODE || exists $sub_elements_names_filter{$chnode->nodeName}) {
          $child->{text} = $chnode->textContent();
          $child->{text} =~ s/[\n\r ]+/ /g;
          $child->{len} = length($child->{text});
          if($chnode->nodeType != XML_TEXT_NODE) {
            if ( $chnode->textContent =~ /^\s*$/ ) {
              $ParCzech::PipeLine::FileManager::logger->log_line("SKIPPING element: does not contains text to be tokenized",$chnode );
            } else {
              $child->{tokenize} = 1;
            }
          }
          $chnode->removeChildNodes()
          # TODO test if it does not contain element_node -> warn !!!
        }
        $text .= $child->{text};
        $child->{textptr_end} = length($text);
        push @nodes,$child;
        $contain_text = 1;
      }
      unless($contain_text){
        $ParCzech::PipeLine::FileManager::logger->log_line("SKIPPING paragraph-like element: does not contains text to be tokenized",$parent );
        next;
      }
      # do not append next paragraph when punctation is not at the end of current paragraph:
      last unless $text =~ m/[\.!?|)}\]"']\s*/;
      # newline between segments !!!
      $text .= "\r\n\r\n"; # force html4.01 endlines "CR LF" to not break tokenRanges https://github.com/libwww-perl/HTTP-Message/blob/b8a00e5b149d4a2396c88f3b00fd2f6e1386407f/lib/HTTP/Request/Common.pm#L91
      my $grandpa_a = $parent->parentNode();
      last if length($text) > $soft_max_text_length and not($grandpa == $grandpa_a);
      $grandpa = $grandpa_a;
    }
    my $nodeptr = 0;
    while($text){
      my $act_text = $text;
      my $conll = run_udpipe($act_text);
      my $text_index = 0;
      my $space='';
      if($text_index = find_first_merged_paragraph($conll)){
        $act_text = substr $text, 0, $text_index, '';
        ($space,$text) = $text =~ /^([\r\n]*)(.*)$/s;
        $text_index += length $space;
        $conll = run_udpipe($act_text);
      } else {
        $text = '';
      }
      $ParCzech::PipeLine::FileManager::logger->log_line("Starting annotating at:",$nodes[$nodeptr]?$nodes[$nodeptr]->{parent_id}:'no node') if $debug;
      $nodeptr = fill_conllu_data_doc($conll, $act_text, $nodeptr, @nodes); # return nodeptr -> number of nodes used
      if ($text_index){
        $ParCzech::PipeLine::FileManager::logger->log_line("UDPipe request splitted at",$nodes[$nodeptr]->{parent_id},"node");
        for my $i ($nodeptr..$#nodes){ # patch index to text
          $nodes[$i]->{textptr} -= $text_index;
          $nodes[$i]->{textptr_end} -= $text_index;
        }
      }

    }
  }

  $current_file->add_static_data('udpipe2.app-'.$model, $append_metadata) if $append_metadata;
  $current_file->add_static_data('udpipe2.prefix-pdt', $append_metadata) if $append_metadata and ! $no_lemma_tag;
  $current_file->add_static_data('udpipe2.ud-syn', $append_metadata) if $append_metadata and ! $no_parse;

  #print STDERR $xpc->findnodes('//tei:text',$doc);
  if($test) {
    $current_file->print();
  } else {
    $current_file->save();
  }
}



sub run_udpipe {
  my ($_text, $_model, $_url) = (@_, $model, $url);
  my %form = (
    "tokenizer" => "ranges",
    $no_lemma_tag ? () : ("tagger" => "1"),
    $no_parse ? () : ("parser" => "1"),
    "model" => $_model,
    "data" => $_text
  );
  my $c = () = $_text =~ m/\r\n\r\n/g;
  $c--;
  $ParCzech::PipeLine::FileManager::logger->log_line("sending text to udpipe:",length($_text),"chars,", $c,"paragraphs");
  my ($pref_text,$inter_text,$suf_text) = $_text =~ m/^(.{0,20})(.*?)(.{0,20})$/s;
  $ParCzech::PipeLine::FileManager::logger->log_line("'$pref_text...SKIPPING",length($inter_text), "CHARS...$suf_text'");

  #open FH, ">TMP.data.$c";
  #binmode ( FH, ":utf8" );
  #print FH $_text;
  #close FH;

  my $res;
  my $json;
  my $req_cnt = 0;
  my $t0;
  my $dur;
  while($req_cnt < 10){
    do {
      $req_cnt++;
      last if $req_cnt >= 10;
      $ParCzech::PipeLine::FileManager::logger->log_line("request counter: $req_cnt");
      $t0 = [Time::HiRes::gettimeofday];
      $res = $ua->post( $_url, \%form );
      $dur = Time::HiRes::tv_interval($t0);
    } until ($res->is_success);
    last if eval {$json = decode_json($res->decoded_content)}
  }
  unless($json){
    $ParCzech::PipeLine::FileManager::logger->log_line("server error - no result");
    return '';
  }

  if($debug) {
    local $/;
    $/=undef;
    my ($parcnt, $sentcnt,$tokcnt) = (0,0,0);
    $parcnt++ while $json->{'result'} =~ /# newpar/g;
    $sentcnt++ while $json->{'result'} =~ /# sent_id/g;
    $tokcnt++ while $json->{'result'} =~ /[\r\n]\d+\t/g;
    $ParCzech::PipeLine::FileManager::logger->log_line(sprintf("received: par=%d, sent=%d, tokens=%d, duration=%.2f s, speed=%.2f tok/s",$parcnt,$sentcnt,$tokcnt,$dur,$tokcnt/$dur));
  }

  Time::HiRes::sleep(1);
  #open FH, ">TMP.conll.$c";
  #binmode ( FH, ":utf8" );
  #print FH $json->{'result'};
  #close FH;
  return $json->{'result'};
};

sub find_first_merged_paragraph {
  my $conll = shift;
  my ($bad_split_line) = $conll =~ m/(\d*[^\n]*SpacesAfter=(?:(?:\\r)\\n){2,}\|TokenRange=[\d:]*)\n\d/s;
  if( $bad_split_line ){
    $ParCzech::PipeLine::FileManager::logger->log_line("bad split line: ",$bad_split_line);
    my ($index) = $bad_split_line =~ m/TokenRange=\d*:(\d*)/;
    return $index;
  }
  return 0;
}

sub fill_conllu_data_doc {
  my ($conll_text, $text,$nodesptr, @node_list) = @_;
  my $nodeFeeder = NodeFeeder->new($text,$nodesptr, @node_list);
  $nodeFeeder->set_no_parse(1) if $no_parse;
  $nodeFeeder->set_no_lemma_tag(1) if $no_lemma_tag;
  my @lines = split /\n/, $conll_text;
  while(@lines){
    my %parent_tokens = ();

    while (my $line = shift @lines) { ## reading until first empty line or undefined (this loop is for sentences)
      if($line =~ /^# newpar/) {
        $nodeFeeder->new_paragraph();
      } elsif ($line =~ /^# sent_id = (\d+)/) { # sentence beginning
        $nodeFeeder->new_sentence();
      } elsif ($line =~ /^# text = (.*)/) {
        my $text = $1;
        $nodeFeeder->add_sentence_text($text);
        $nodeFeeder->add_xml_comment($text); # TEMPORARY !!!
      } elsif ($line =~ /^(\d+)\t([^\t]+)\t/) {
        my ($ti,$tt,$tl,$tp,$tg,$tf,$th,$tr, undef ,$tsp) = split(/\t/, $line);
        $tr =~ s/:/_/g if $replace_colons_with_underscores;
        $nodeFeeder->add_token(
            line => $line,
            i=>$ti,
            form => $tt,
            lemma => $tl,
            upos => $tp,
            xpos => $tg,
            feat => $tf,
            head => $th,
            deprel => $tr,
            spacing => $tsp,
            $parent_tokens{$ti} ? (parent_token => $parent_tokens{$ti}) : ()
          );

      } elsif ($line =~ /^(\d+)-(\d+)\t/) {
        my (undef,$tt,undef,undef,undef,undef,undef,undef, undef ,$tsp) = split(/\t/, $line);
        my $token = $nodeFeeder->add_token(
            line => $line,
            form => $tt,
            spacing => $tsp,
          );
        $parent_tokens{$_} = $token for ($1..$2);
      } else {
        # print STDERR "SKIPPING: $line\n";
      }
    }
    $nodeFeeder->close_sentence();
  }
  $nodeFeeder->close_paragraph();
  return $nodeFeeder->get_nodes_pointer();
}



sub usage_exit {
   my ($fm_args,$fm_desc) =  @{ParCzech::PipeLine::FileManager::usage('tei')};
   print
"Usage: udpipe2.pl  $fm_args --model <STRING> [--test] [--no-parse] [--no-lemma-tag] [OPTIONAL]

$fm_desc

\t--model=s\tspecific UDPipe model
\t--test\tprint result to stdout - don't change any file
\t--append-metadata\tappend metadata to header from file
\t--no-parse\tno dependency parsing
\t--no-lemma-tag\tno lemmas and tags

OPTIONAL:
\t--elements=s\tcomma separated names of elements to be tokenized and tagged. Default value: seg,head
\t--sub-elements=s\tcomma separated names of elements to be tokenized and tagged (child nodes of elements). Other sub-elements are skipped. Default value: ref
\t--word-element=s\tname of word element
\t--punct-element=s\tname of punctation element
\t--sent-element=s\tname of sentence element
";
   exit;
}


#=========================== Navigation in xml nodes:

package NodeFeeder;
use XML::LibXML qw(:libxml);


sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my $self  = {};
  bless $self, $class;
  $self->{text} = shift;
  $self->{nodesptr} = shift;
  $self->{nodes} = [@_];
  $self->{textptr} = 0;
  $self->{paragraph} = undef;
  $self->{paragraph_ptr} = undef;
  $self->{sentence} = undef;
  $self->{deprel_id_number} = undef;
  $self->{deprel} = undef;
  $self->{no_token_elem_queue} = [];
  $self->{parent_stack} = []; # contains segments, sentence and tokenized subelements
  $self->{no_parse} = 0;
  $self->{no_lemma_tag} = 0;
  $self->{token_id_prefix} = 'w';
  $self->{sent_id_prefix} = 's';
  $self->{token_counter} = 0;
  $self->{sent_counter} = 0;

  return $self;
}

sub get_nodes_pointer {
  my $self = shift;
  return $self->{nodesptr};
}

sub set_no_parse {
  my $self = shift;
  $self->{no_parse} = !! shift;
}

sub set_no_lemma_tag {
  my $self = shift;
  $self->{no_lemma_tag} = !! shift;
}


sub set_token_id_prefix {
  my $self = shift;
  $self->{token_id_prefix} = shift || $self->{token_id_prefix};
}

sub set_sent_id_prefix {
  my $self = shift;
  $self->{sent_id_prefix} = shift || $self->{sent_id_prefix};
}

sub new_paragraph {
  my $self = shift;

  $self->close_paragraph() if $self->{paragraph};

  $self->{paragraph} = $self->{nodes}->[$self->{nodesptr}]->{parent};
  $self->{paragraph_ptr} = $self->{nodes}->[$self->{nodesptr}]->{parent_cnt};
  $self->{parent_stack} = [$self->{paragraph}];
  $self->{sent_counter} = 0;
  $self->set_sent_id_prefix($self->{nodes}->[$self->{nodesptr}]->{parent_id});

  $self->add_notes_and_spaces_to_queue();
  $self->print_queue();

  if($self->{paragraph_ptr} != $self->{nodes}->[$self->{nodesptr}]->{parent_cnt}){ # jump to next paragraph if this is done
    $self->new_paragraph();
  }
}

sub close_paragraph {
  my $self = shift;
  return unless $self->{paragraph};
  $self->close_sentence() if $self->{sentence};

  $self->add_notes_and_spaces_to_queue();
  $self->print_queue();

  undef $self->{paragraph};
  undef $self->{paragraph_ptr};
}


sub new_sentence {
  my $self = shift;

  $self->close_sentence() if $self->{sentence};
  $self->{sent_counter}++;
  $self->{token_counter} = 0;
  my $id = sprintf("%s.s%d",$self->{sent_id_prefix}, $self->{sent_counter});
  $self->set_token_id_prefix($id);

  $self->add_notes_and_spaces_to_queue();
  $self->print_queue();

  $self->{sentence} = XML::LibXML::Element->new( $sent_element_name );
  $self->{sentence}->setAttributeNS($xmlNS, 'id', $id);
  $self->{deprel_id_number} = {0 => $id};
  $self->{deprel} = [];
  unshift @{$self->{parent_stack}}, $self->{sentence};
  $self->{paragraph}->appendChild($self->{sentence});
}

sub close_sentence {
  my $self = shift;

  return unless $self->{sentence};

  $self->close_subelement_if_any();
  $self->print_deprel() unless $self->{no_parse};

  undef $self->{deprel_id_number};
  undef $self->{deprel};
  undef $self->{sentence};
  shift @{$self->{parent_stack}};
}

sub close_subelement_if_any {
  my $self = shift;
  if($self->{nodesptr} < scalar(@{$self->{nodes}})
    && $self->{nodes}->[$self->{nodesptr}]->{textptr_end} <= $self->{textptr}
    && $self->{nodes}->[$self->{nodesptr}]->{tokenize}
    ){
    if( $self->{nodes}->[$self->{nodesptr}]->{textptr_end} < $self->{textptr}) {
      print STDERR "moved end of node - token cross element: $self->{nodes}->[$self->{nodesptr}]->{node}\n";
    }
    shift @{$self->{parent_stack}};
    $self->{nodesptr}++;
  }
  $self->check_and_patch_cross_elements();
}

sub check_and_patch_cross_elements { # print just empty elements
  my $self = shift;
  while($self->{nodesptr} < scalar(@{$self->{nodes}})
    && $self->{nodes}->[$self->{nodesptr}]->{textptr_end} <= $self->{textptr}
    && $self->{nodes}->[$self->{nodesptr}]->{tokenize}
    ){
    print STDERR "PATCHING - token cross element: $self->{nodes}->[$self->{nodesptr}]->{node}\n";
    $self->{parent_stack}->[0]->appendChild($self->{nodes}->[$self->{nodesptr}]->{node});
    $self->{nodesptr}++;
  }
}

sub print_deprel {
  my $self = shift;
  my $linkGrp = XML::LibXML::Element->new( 'linkGrp' );
  $self->{sentence}->appendChild($linkGrp);
  $linkGrp->setAttribute('targFunc', 'head argument');
  $linkGrp->setAttribute('type', 'UD-SYN');
  for my $rel (@{$self->{deprel}}) {
    my $link = XML::LibXML::Element->new( 'link' );
    $linkGrp->appendChild($link);
    $link->setAttribute('ana', 'ud-syn:'.($rel->{deprel}));
    $link->setAttribute('target', '#'.($self->{deprel_id_number}->{$rel->{head}}).' #'.($self->{deprel_id_number}->{$rel->{src}}));
  }
}

sub print_queue {
  my $self = shift;
  while(my $item = shift @{$self->{no_token_elem_queue}}){
    unless($self->{parent_stack}->[0]) { # this should not happen !!!
      $ParCzech::PipeLine::FileManager::logger->log_line("ERROR(line ",__LINE__,", sentence ",$self->{token_id_prefix},") no parent node is defined,", scalar(@{$self->{no_token_elem_queue}}) + 1, "'no token' ITEMs should be appended");
      $ParCzech::PipeLine::FileManager::logger->log_line("ITEM: '$_'") for ($item,@{$self->{no_token_elem_queue}});
      if($try2continue_on_error) {
        $ParCzech::PipeLine::FileManager::logger->log_line("WARNING try2continue-on-error option is set !!!");
        $ParCzech::PipeLine::FileManager::logger->log_line("WARNING cleaning no_token_elem_queue !!!");
        $self->{no_token_elem_queue} = [];
        return;
      }
    }
    if(ref $item) {
      # adding element
      $self->{parent_stack}->[0]->appendChild($item);
    } else {
      # adding text (spaces)
      $self->{parent_stack}->[0]->appendText($item);
    }
  }
}

sub add_sentence_text {
  my $self = shift;
  my $text = shift;
  return unless $text;
  $self->{current_text} = [1, $text];
}

sub add_line_text {
  my $self = shift;
  my $line = shift;
  return unless $line;
  $self->{current_line} = [1, $line];
}

sub logger {
  my $self = shift;
  my $text = shift;
  if(defined $self->{current_text} && $self->{current_text}->[0]){
    $self->{current_text}->[0] = 0;
    $ParCzech::PipeLine::FileManager::logger->log_line($self->{current_text}->[1]);
  }
  if(defined $self->{current_line} && $self->{current_line}->[0]){
    $self->{current_line}->[0] = 0;
    $ParCzech::PipeLine::FileManager::logger->log_line($self->{current_line}->[1]);
  }
  $ParCzech::PipeLine::FileManager::logger->log_line($text) if defined $text;
}

sub add_xml_comment {
  my $self = shift;
  my $comment = shift;
  return unless $comment;
  $comment =~ s/--+/-/g; # fix double hyphene validity error
  $self->{parent_stack}->[0]->appendChild(XML::LibXML::Comment->new(" $comment ")) if $self->{parent_stack}->[0];
}

sub add_notes_and_spaces_to_queue {
  my $self = shift;
  # add non tokenized elements that are in the same paragraph: spaces, notes
  my $changed = 1;

  while($changed && $self->{nodesptr} < scalar(@{$self->{nodes}})) { # test if moved in text
    undef $changed;

    # skip endlines at the beginning of paragraf
    if( substr($self->{text},$self->{textptr},4) eq "\r\n\r\n"
        && $self->{nodes}->[$self->{nodesptr}]->{textptr} > $self->{textptr}) {# I am before beggining of new paragraph
      $self->{textptr}+=4;
    }

    # adding spaces
    my $spaces = '';
    my $chr = substr($self->{text},$self->{textptr},1);
    while( $chr =~ /^[\s\n]$/
        && $self->{nodes}->[$self->{nodesptr}]->{textptr_end} > $self->{textptr}) {
      $spaces .= $chr;
      $changed = 1;
      $self->{textptr}++;
      $chr = substr($self->{text},$self->{textptr},1);
    }
    if($spaces) {
      push @{$self->{no_token_elem_queue}}, $spaces ;
    }
    # jump to next node it current is text node and pointer is at the end
    if( $self->{nodes}->[$self->{nodesptr}]->{textptr_end} == $self->{textptr}
      && $self->{nodes}->[$self->{nodesptr}]->{node}->nodeType == XML_TEXT_NODE ) {
      $self->{nodesptr}++;
    }

    # adding elements without tokenization
    while( $self->{nodesptr} < scalar(@{$self->{nodes}})
      && $self->{nodes}->[$self->{nodesptr}]->{textptr_end} == $self->{textptr} + ($try2fix_spaces?1:0)
      && not($self->{nodes}->[$self->{nodesptr}]->{tokenize})
      && $self->{nodes}->[$self->{nodesptr}]->{parent_cnt} == $self->{paragraph_ptr} # current parent !!! elements without tokenization has zero length
      && $self->{nodes}->[$self->{nodesptr}]->{node}->nodeType != XML_TEXT_NODE # node is not text
      ) {
      $changed = 1;
      push @{$self->{no_token_elem_queue}}, $self->{nodes}->[$self->{nodesptr}]->{node};
      $self->{nodesptr}++;
      $self->{textptr}+=($try2fix_spaces?1:0)
    }
  }
}


sub add_token {
  my $self = shift;
  my %opts = @_;
  warn "Not in sentence!!! $opts{forn}\n" unless $self->{sentence};
  $self->add_line_text($opts{line}) if $opts{line};

  my $token = XML::LibXML::Element->new(($opts{upos}//'') eq 'PUNCT' ? $punct_element_name : $word_element_name );

  $self->{token_counter}++;
  my $id = sprintf("%s.w%d",$self->{token_id_prefix}, $self->{token_counter});
  $token->setAttributeNS($xmlNS, 'id', $id);

  if(defined($opts{head}) and !$self->{no_parse}){
    $self->{deprel_id_number}->{$opts{i}} = $id;
    if($opts{deprel} eq 'root' && $opts{head} != 0) {
      $self->logger("ERROR: root deprel inside tree (replacing with dep) $id");
      $opts{deprel} = 'dep';
    }
    if($opts{deprel} ne 'root' && $opts{head} == 0) {
      $self->logger("ERROR: missing root deprel in tree root (replacing $opts{deprel} with root) $id");
      $opts{deprel} = 'root';
    }
    if($opts{deprel} =~ m/[^a-zA-Z_:]/) {
      $self->logger("ERROR: invalid character in deprel '$opts{deprel}' (replacing with dep) $id");
      $opts{deprel} = 'dep';
    }
    push @{$self->{deprel}}, {src => $opts{i}, head => $opts{head}, deprel => $opts{deprel}};

  }

  $token->setAttribute('lemma', $opts{lemma}) if(defined($opts{lemma}) and !$self->{no_lemma_tag});
  #$token->setAttribute('tag', $opts{xpos}) if(defined($opts{xpos}));
  $token->setAttribute('pos', $opts{upos}) if(defined($opts{upos}) and !$self->{no_lemma_tag});
  if(defined($opts{upos}) and defined($opts{feat}) and !$self->{no_lemma_tag}) {
    $opts{msd} = "UPosTag=$opts{upos}|$opts{feat}";
    $opts{msd} =~ s/\|\_$//;
    $token->setAttribute('msd', $opts{msd});
  }

  if(defined($opts{xpos}) and !$self->{no_lemma_tag}) {
    $token->setAttribute('ana', 'pdt:'.$opts{xpos});
  }
  $token->setAttribute('join', 'right') if ($opts{spacing} // '') =~ /SpaceAfter=No/;

  if(defined($opts{parent_token})) { # contracted token parts
    $token->setAttribute('norm', $opts{form});
    # $token->setAttribute('orig', '');
    $opts{parent_token}->appendChild($token);

  } else {
    $token->appendText($opts{form});
    $self->close_subelement_if_any();
    $self->add_notes_and_spaces_to_queue();
    $self->print_queue();
    # $self->check_text_ptr($opts{spacing});

    # moving into tokenizable subelement
    if($self->{nodesptr} < scalar(@{$self->{nodes}})
      && $self->{nodes}->[$self->{nodesptr}]->{textptr} == $self->{textptr}
      && $self->{nodes}->[$self->{nodesptr}]->{tokenize} # always true !
      ){
      $self->{parent_stack}->[0]->appendChild($self->{nodes}->[$self->{nodesptr}]->{node});
      unshift @{$self->{parent_stack}}, $self->{nodes}->[$self->{nodesptr}]->{node};
    }

    $self->{parent_stack}->[0]->appendChild($token);
    $self->{textptr} += length($opts{form});
  }
  return $token;
}


sub check_text_ptr {
  my $self = shift;
  my $spacing = shift;
  my ($range_start) = $spacing =~ m/TokenRange=(\d*):/;
  if(defined($range_start) && $range_start != $self->{textptr}){
    print STDERR "ERROR!!! |||||$spacing||||| = $range_start != ",$self->{textptr},"\n";
    $self->print_text_with_pointer();
    print STDERR $self->{paragraph},"\n";
  }
}


sub print_text_with_pointer {
  my $self = shift;
  my $pointer = shift // '#';
  my $begin = substr($self->{text},0,$self->{textptr});
  my $end = substr($self->{text},$self->{textptr}, length($self->{text})-$self->{textptr});
  print STDERR "[BEGIN]",
               $begin,
               '[',$pointer.']',
               $end,
               "[END]\n"
}
