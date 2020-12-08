use warnings::unused;
use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use XML::LibXML qw(:libxml);
use Getopt::Long;
use LWP::Simple;
use LWP::UserAgent;
use JSON;

use ParCzech::PipeLine::FileManager;

my $scriptname = $0;

my ($debug, $test, $model);

my$xmlNS = 'http://www.w3.org/XML/1998/namespace';

my $xpc = XML::LibXML::XPathContext->new;
$xpc->registerNs('xml', $xmlNS);
$xpc->registerNs('tei', 'http://www.tei-c.org/ns/1.0');

my $url = 'http://lindat.mff.cuni.cz/services/nametag/api/recognize';
my $word_element_name = 'w';
my $punct_element_name = 'pc';
my $sent_element_name = 's';

my $max_sent_cnt = 60;


GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # tokenize, tag and lemmatize and parse to stdout, do not change the database
            'model=s' => \$model, # udpipe model tagger
            'word-element=s' => \$word_element_name,
            'punct-element=s' => \$punct_element_name,
            'sent-element=s' => \$sent_element_name,
            ParCzech::PipeLine::FileManager::opts()
#            'tags=s' => \@tags, # tag attribute name|format (pos cs::pdt)
            );

usage_exit() unless ParCzech::PipeLine::FileManager::process_opts();


usage_exit() unless $model;

my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });
my $current_file;

while($current_file = ParCzech::PipeLine::FileManager::next_file('tei', xpc => $xpc)) {
  next unless defined($current_file->{dom});

  my $doc = $current_file->get_doc();
  my $name_id_prefix = $current_file->get_doc_id().'.ne';

  my @sentences = $xpc->findnodes('//tei:text//tei:'.$sent_element_name,$doc);
  my $id_counter = 0;
  while(@sentences) {
    my @nodes = (); # {parent: ..., node: ..., text: ..., tokenize: boolean}
    my $text = '';
    my $sent_cnt = 0;
    while(my $sent = shift @sentences) {
      $sent_cnt++;
      # find tokens in sentence
      for my $token ($xpc->findnodes('.//tei:*[contains(" '.$word_element_name.' '.$punct_element_name.' ",concat(" ",name()," ")) and not(normalize-space(.)="")]',$sent)) {
        $text .= trim($token->textContent());
        $text .= "\n";
        push @nodes,$token;
      }
      # newlines between sentences
      $text .= "\n";
      push @nodes, undef;
      last if $sent_cnt >= $max_sent_cnt;
    }
#    print STDERR "TOKENS: ", scalar(@nodes),"========================================================\n";
    my $vertical = run_nametag($text);
    $id_counter = fill_vertical_data_doc($vertical, $id_counter, $name_id_prefix, @nodes);
  }
  $current_file->add_metadata('application',
        app => 'NameTag',
        version=>'2',
        source=>'http://lindat.mff.cuni.cz/services/nametag/',
        ref=>'http://ufal.mff.cuni.cz/nametag/2',
        label => "NameTag 2 with $model model",
        desc => 'Name entity recognition'
      );

  #print STDERR $xpc->findnodes('//tei:text',$doc);
  if($test) {
    $current_file->print();
  } else {
    $current_file->save();
  }
}

sub trim {
  my $t = shift;
  $t =~ s/^\s*//;
  $t =~ s/\s*$//;
  return $t;
}

sub run_nametag {
  my $data = shift;
  my %form = (
    "input" => "vertical",
    "output" => "vertical",
    "model" => $model,
    "data" => $data
  );
  my $res = $ua->post( $url, \%form );
  my $json = decode_json($res->decoded_content);
  return $json->{'result'};
};


sub fill_vertical_data_doc {
  my ($vertical_text, $name_cnt, $name_id_prefix, @node_list) = @_;
#  print STDERR "\n\n================================ fill_vertical_data_doc\n";
  my $nodeTagger = NodeTagger->new(@node_list);
  $nodeTagger->set_id_prefix($name_id_prefix);
  my @lines = split /\n/, $vertical_text;
  while(my $line = shift @lines){
    $name_cnt++;
#    print STDERR "LINE:$line\n";
    my ($range, $type, $text) = split(/\t/, $line);
    my @linenumbers = split(",",$range);
    my $nm = $nodeTagger->add_name_entity($type, $linenumbers[0], $linenumbers[$#linenumbers], $name_cnt);
    $nm->setAttribute('LABEL',$text) if $nm and $debug;
  }
  return $name_cnt;
}



sub usage_exit {
   my ($fm_args,$fm_desc) =  @{ParCzech::PipeLine::FileManager::usage('tei')};
   print
"Usage: nametag2.pl  $fm_args --model <STRING> [--test] [OPTIONAL]

$fm_desc

\t--model=s\tspecific UDPipe model
\t--test\tprint result to stdout - don't change any file

OPTIONAL:
\t--word-element=s\tname of word element
\t--punct-element=s\tname of punctation element
\t--sent-element=s\tname of sentence element
";
   exit;
}


#=========================== Navigation in xml nodes:

package NodeTagger;
use XML::LibXML qw(:libxml);
use Data::Dumper;


sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my $self  = {};
  bless $self, $class;
  $self->{nodes} = [@_];
  $self->{id_prefix} = 'ne';

  return $self;
}

sub set_id_prefix {
  my $self = shift;
  $self->{id_prefix} = shift || $self->{id_prefix};
}


sub add_name_entity {
  my $self = shift;
  my ($type, $start, $end, $id) = @_;
  $start--;
  $end--;

  return undef unless $start < @{$self->{nodes}} and $start < @{$self->{nodes}} and $start <= $end and $start >= 0;
  return $self->cover_tokens_with_name($type,$self->{nodes}->[$start], $self->{nodes}->[$end], $id)
}

sub cover_tokens_with_name {
  my $self = shift;
  my ($type, $start, $end, $id) = @_;
  # anc contains: {ancestor, first_child, last_child, depth}
  my $anc = get_common_ancestor($start, $end);

  unless($anc){
    print STDERR "Unable to add Named Entity (possible crossing elements)", $start->toString()," ... ", $end->toString(),"\n";
    return;
  }

  my $name_elem = XML::LibXML::Element->new('name');
  $name_elem->setAttribute('ana',"ne:$type");
  $name_elem->setAttributeNS($xmlNS, 'id', sprintf("%s%03d",$self->{id_prefix},$id));
  # append <name> element to ancestor before first_child
  $anc->{ancestor}->insertBefore($name_elem, $anc->{first_child});
  # unbind all children between first and last child (included) and append them to <name>
  my $ptr = $anc->{first_child};
  my $next = $ptr->nextSibling();
  while($ptr && $ptr != $anc->{last_child}){
    $ptr->unbindNode();
    $name_elem->appendChild($ptr);
    $ptr = $next;
    $next = $ptr->nextSibling();
  }
  # append last child
  $ptr->unbindNode();
  $name_elem->appendChild($ptr);
  return  $name_elem;
}

sub get_common_ancestor {
  my ($start,$end,$maxdepth) = @_;
  $maxdepth //= 10;
  return undef if $maxdepth < 0;
  return undef unless defined($start) and defined($end);
  $maxdepth--;
  if($start->parentNode()->isSameNode($end->parentNode())){
    return {
      ancestor => $start->parentNode(),
      first_child => $start,
      last_child => $end,
      depth => 10 - $maxdepth
    }
  }
  my ($result1,$result2);
  for my $i (0..1) {
    if($maxdepth % 2 eq $i) { # swapping order of exploring ancestors (closer are explored firstly)
      my $parent = $start->parentNode();
      if($parent && $parent->firstChild()->isSameNode($start)) {
        $result1 = get_common_ancestor($parent,$end,$maxdepth) ;
      }
    } else {
      my $parent = $end->parentNode();
      if($parent && $parent->lastChild()->isSameNode($end)) {
        $result2 = get_common_ancestor($start,$parent,$maxdepth) ;
      }
    }
  }
  if(defined($result1) && defined($result2)) {
    return $result1->{depth} < $result2->{depth} ? $result1 : $result2 ;
  } elsif (defined($result1)) {
    return $result1;
  } else {
    return $result2;
  }
}