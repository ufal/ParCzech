use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use Encode qw(decode encode);
use XML::LibXML::PrettyPrint;
use XML::LibXML qw(:libxml);
use Getopt::Long;
use POSIX qw(strftime);
use LWP::Simple;
use LWP::UserAgent;
use JSON;

use ParCzech::PipeLine::FileManager;

my $scriptname = $0;

my ($debug, $test, $filename, $filelist, $model, $elements_names, $no_backup_file, $sub_elements_names);

my$xmlNS = 'http://www.w3.org/XML/1998/namespace';

my $xpc = XML::LibXML::XPathContext->new;
$xpc->registerNs('xml', $xmlNS);
$xpc->registerNs('tei', 'http://www.tei-c.org/ns/1.0');

my $url = 'http://lindat.mff.cuni.cz/services/udpipe/api/process';
$elements_names = "seg,head";
$sub_elements_names = "ref";
my $word_element_name = 'w';
my $punct_element_name = 'pc';
my $sent_element_name = 's';
my $full_lemma = undef;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # tokenize, tag and lemmatize to string, do not change the database
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

  my $sid = 1;
  my $wid = 1;
  my $doc = $current_file->get_doc();

  my @parents = $xpc->findnodes('//tei:text//tei:*[contains(" '.join(' ',split(',',$elements_names)).' ", concat(" ",name()," "))]',$doc);
  my @nodes = (); # {parent: ..., node: ..., text: ..., tokenize: boolean}
  my $text = '';
  my $parent_cnt = 0;
  while(my $parent = shift @parents) {
    # test if parent contains any text to be tokenized !!!
    $parent_cnt++;
    for my $chnode ($parent->childNodes()) {
      $chnode->unbindNode();
      my $child = {
        parent => $parent,
        parent_cnt => $parent_cnt,
        node => $chnode,
        text => '',
        len => 0,
        textptr => length($text),
        tokenize => 0
      };
      if ( $chnode->nodeType == XML_TEXT_NODE || exists $sub_elements_names_filter{$chnode->nodeName}) {
        $child->{text} = $chnode->textContent();
        $child->{len} = length($child->{text});
        if($chnode->nodeType != XML_TEXT_NODE) {
          $child->{tokenize} = 1;
          }
        $chnode->removeChildNodes()
        # TODO test if it does not contain element_node -> warn !!!
      }
      $text .= $child->{text};
      $child->{textptr_end} = length($text);
      push @nodes,$child;
    }
    # newline between segments !!!
    $text .= "\n\n";
  }
  my $conll = run_udpipe($text);
  my $metadata = fill_conllu_data_doc($conll, $text, @nodes);
  $current_file->add_metadata(%$metadata, who => 'udpipe2');
  #print STDERR $xpc->findnodes('//tei:text',$doc);
  print STDERR $doc;
  $current_file->save();

  print STDERR "TODO WRITE TO FILE\n";
}



sub run_udpipe {
  my ($_text, $_model, $_url) = (@_, $model, $url);
  my %form = (
    "tokenizer" => "ranges",
    "tagger" => "1",
    "parser" => "1",
    "model" => $_model,
    "data" => $_text
  );

  my $res = $ua->post( $_url, \%form );
  my $json = decode_json($res->decoded_content);
  return $json->{'result'};
};


sub fill_conllu_data_doc {
  my ($conll_text, $text, @node_list) = @_;
  my $nodeFeeder = NodeFeeder->new($text, @node_list);
  my @lines = split /\n/, $conll_text;
  while(@lines){
    my %parent_tokens = ();

    while (my $line = shift @lines) { ## reading until first empty line or undefined (this loop is for sentences)
      if($line =~ /^# newpar/) {
        $nodeFeeder->new_paragraph();
      } elsif ($line =~ /^# sent_id = (\d+)/) { # sentence beginning
        $nodeFeeder->new_sentence("s-$1");
      } elsif ($line =~ /^# text = (.*)/) {
        $nodeFeeder->add_xml_comment($1); # TEMPORARY !!!
      } elsif ($line =~ /^(\d+)\t([^\t]+)\t/) {
        my ($ti,$tt,$tl,$tp,$tg,$tf,$th,$tr, undef ,$tsp) = split(/\t/, $line);
        $nodeFeeder->add_token(
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
        my ($ti,$tt,undef,undef,undef,undef,undef,undef, undef ,$tsp) = split(/\t/, $line);
        my $token = $nodeFeeder->add_token(
            #i=>$ti,
            form => $tt,
            spacing => $tsp,
          );
        $parent_tokens{$_} = $token for ($1..$2);
      } else {
        print STDERR "SKIPPING: $line\n";
      }
    }
    $nodeFeeder->close_sentence();
  }
  $nodeFeeder->close_paragraph();
}



sub usage_exit {
   my ($fm_args,$fm_desc) =  @{ParCzech::PipeLine::FileManager::usage('tei')};
   print
"Usage: udpipe2.pl  $fm_args --model <STRING> [OPTIONAL]

$fm_desc

\t--model=s\tspecific UDPipe model

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
  $self->{nodes} = [@_];
  $self->{textptr} = 0;
  $self->{nodesptr} = 0;
  $self->{tokencnt} = 0;
  $self->{paragraph} = undef;
  $self->{paragraph_ptr} = undef;
  $self->{sentence} = undef;
  $self->{deprel_id_number} = undef;
  $self->{deprel} = undef;
  $self->{no_token_elem_queue} = [];
  $self->{parent_stack} = []; # contains segments, sentence and tokenized subelements

  return $self;
}

sub new_paragraph {
  my $self = shift;

  $self->close_paragraph() if $self->{paragraph};

  $self->{paragraph} = $self->{nodes}->[$self->{nodesptr}]->{parent};
  $self->{paragraph_ptr} = $self->{nodes}->[$self->{nodesptr}]->{parent_cnt};
  $self->{parent_stack} = [$self->{paragraph}];

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
  my $id = shift;

  $self->close_sentence() if $self->{sentence};

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
  $self->print_deprel();

  undef $self->{deprel_id_number};
  undef $self->{deprel};
  undef $self->{sentence};
  shift @{$self->{parent_stack}};
}

sub close_subelement_if_any {
  my $self = shift;
  if($self->{nodesptr} < scalar(@{$self->{nodes}})
    && $self->{nodes}->[$self->{nodesptr}]->{textptr_end} == $self->{textptr}
    && $self->{nodes}->[$self->{nodesptr}]->{tokenize}
    ){
    shift @{$self->{parent_stack}};
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
    if(ref $item) {
      # adding element
      $self->{parent_stack}->[0]->appendChild($item);
    } else {
      # adding text (spaces)
      $self->{parent_stack}->[0]->appendText($item);
    }
  }
}

sub add_xml_comment {
  my $self = shift;
  $self->{parent_stack}->[0]->appendChild(XML::LibXML::Comment->new(shift)) if $self->{parent_stack}->[0];
}

sub add_notes_and_spaces_to_queue {
  my $self = shift;
  # add non tokenized elements that are in the same paragraph: spaces, notes
  my $changed = 1;

  while($changed && $self->{nodesptr} < scalar(@{$self->{nodes}})) { # test if moved in text
    undef $changed;

    # skip endlines at the beginning of paragraf
    if( substr($self->{text},$self->{textptr},2) eq "\n\n"
        && $self->{nodes}->[$self->{nodesptr}]->{textptr} > $self->{textptr}) {# I am before beggining of new paragraph
      $self->{textptr}+=2;
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
      && $self->{nodes}->[$self->{nodesptr}]->{textptr_end} == $self->{textptr}
      && not($self->{nodes}->[$self->{nodesptr}]->{tokenize})
      && $self->{nodes}->[$self->{nodesptr}]->{parent_cnt} == $self->{paragraph_ptr} # current parent !!! elements without tokenization has zero length
      && $self->{nodes}->[$self->{nodesptr}]->{node}->nodeType != XML_TEXT_NODE # node is not text
      ) {
      $changed = 1;
      push @{$self->{no_token_elem_queue}}, $self->{nodes}->[$self->{nodesptr}]->{node};
      $self->{nodesptr}++;
    }
  }
}


sub add_token {
  my $self = shift;
  my %opts = @_;
  warn "Not in sentence!!! $opts{forn}\n" unless $self->{sentence};

  my $token = XML::LibXML::Element->new(($opts{upos}//'') eq 'PUNCT' ? $punct_element_name : $word_element_name );

  $self->{tokencnt}++;
  my $id = "w-".$self->{tokencnt};
  $token->setAttributeNS($xmlNS, 'id', $id);

  if(defined($opts{head})){
    $self->{deprel_id_number}->{$opts{i}} = $id;
    push @{$self->{deprel}}, {src => $opts{i}, head => $opts{head}, deprel => $opts{deprel}};
  }

  $token->setAttribute('lemma', $opts{lemma}) if(defined($opts{opts}));
  #$token->setAttribute('tag', $opts{xpos}) if(defined($opts{xpos}));
  $token->setAttribute('pos', $opts{upos}) if(defined($opts{upos}));
  if(defined($opts{upos}) and defined($opts{feat})) {
    $opts{msd} = "UposTag=$opts{upos}|$opts{feat}";
    $opts{msd} =~ s/\|\_$//;
    $token->setAttribute('msd', $opts{msd});
  }

  $token->setAttribute('join', 'right') if ($opts{spacing} // '') =~ /SpaceAfter=No/;

  if(defined($opts{parent_token})) { # contracted token parts
    $token->setAttribute('norm', $opts{form});
    $token->setAttribute('orig', '');
    $opts{parent_token}->appendChild($token);

  } else {
    $token->appendText($opts{form});
    $self->close_subelement_if_any();
    $self->add_notes_and_spaces_to_queue();
    $self->print_queue();

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
