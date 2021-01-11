package ParCzech::PipeLine::FileManager;

use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use File::Spec;

my ($lock_result,$input_file,$output_file,$filelist);
my $input_dir = './';
my $output_dir = './';


my @files;

sub opts {(
    'lock-result' => \$lock_result,
  # single file input
    'input-file=s' => \$input_file,
    'output-file=s' => \$output_file,
  # filelist input
    'filelist=s' => \$filelist,
    'input-dir=s' => \$input_dir,
    'output-dir=s' => \$output_dir,
  );
}


sub usage_exit {
  print "TODO usage ParCzech::PipeLine::FileManager\n";
  exit 1;
}

sub usage {
  return [
"{(--input-file <FILEPATH> [--output-file <FILEPATH>]) | (--filelist <FILEPATH> [--input-dir <DIRPATH>] [--output-dir <DIRPATH>])} [--lock-result]",
"\t--lock-result\tresult files will be readonly

\tsingle file processing options:
\t--input-file=FILEPATH\tpath to input file
\t--output-file=FILEPATH\tpath to output file, if not set input-file inplace editation is done

\tmultiple files processing options:
\t--filelist=FILEPATH\tfile containing newline separated list of files to process
\t--input-dir=DIRPATH\tbase input files directory (files in filelist are relative to this path). Default value: ./
\t--output-dir=DIRPATH\tbase output files directory (files in filelist are relative to this path). Default value: ./ "
  ]
}

sub process_opts {
  return unless ( $input_file  || $filelist );

  if ( $input_file ) {
  	$output_file //= $input_file;
    push @files, {inpath => $input_file, outpath => $output_file}
  }

  if ( $filelist ) {
    open my $fl, $filelist or die "Could not open $filelist: $!";
    while(my $fn = <$fl>) {
      $fn =~ s/\n$//;
      push @files, {inpath => File::Spec->catfile($input_dir,$fn), outpath => File::Spec->catfile($output_dir,$fn)} if $fn ;
    }
    close $fl;
  }

  for my $f (@files) {
    file_does_not_exist($f->{inpath}) unless -e $f->{inpath}
  }
  return 1;
}

sub file_does_not_exist {
  print "file ". shift . " does not exist\n";
}

# returns hash {inpath=>..., outpath=> ..., raw => ..., dom => } path to files
sub next_file {
  my $filetype = shift;
  my %opts = @_;
  my $current_file = shift @files;
  return unless $current_file;
  $/ = undef;
  if($filetype eq 'tei'){
    return ParCzech::PipeLine::FileManager::TeiFile->new(inpath=>$current_file->{inpath}, outpath=>$current_file->{outpath},%opts)
  }
  return $current_file;
}



package ParCzech::PipeLine::FileManager::TeiFile;
use POSIX qw(strftime);
use XML::LibXML qw(:libxml);

my %xmlNs = (
  'xml' => 'http://www.w3.org/XML/1998/namespace',
  'tei' => 'http://www.tei-c.org/ns/1.0',
  'pcz' => 'http://ufal.mff.cuni.cz/parczech/ns/1.0'
  );
my %metadata = ();
my %variables = (
  TODAY => strftime("%Y-%m-%d", localtime),
  );
my %appendConditions = (
  # parent => [[childname regex, xpathCondition for searching node before it should be added],...]
  fileDesc => [
      [qr/^.*$/, './*[local-name() = "sourceDesc"]'], # all nodes should be before sourceDesc
    ]
  );

sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my %opts = @_;
  my $self  = {};
  bless $self, $class;
  $self->{inpath} = $opts{inpath};
  $self->{outpath} = $opts{outpath};
  $self->{xpc} = $opts{xpc};
  $self->{raw} = undef;
  $self->{dom} = undef;
  $self->{metadata_visited} = {};
  my $xml = ParCzech::PipeLine::FileManager::XML::open_xml($self->{inpath});
  if($xml) {
    $self->{raw} = $xml->{raw};
    $self->{dom} = $xml->{dom};
  }

  return $self
}

sub get_doc {
  my $self = shift;
  return $self->{dom};
}

sub get_doc_id {
  my $self = shift;
  return $self->{dom}->documentElement()->getAttributeNS('http://www.w3.org/XML/1998/namespace','id');
}

sub init_metadata_visited_detector {
  my $self = shift;
  $self->{metadata_visited} = {};
}

sub metadata_visited_detector {
  my $self = shift;
  my $name = shift;
  return 1 if defined($self->{metadata_visited}->{$name});
  $self->{metadata_visited}->{$name} = 1;
  return;
}

sub add_metadata {
  my $self = shift;
  my $type = shift;
  my %metadata = @_;
  if($type eq 'application') {
    my $application = ParCzech::PipeLine::FileManager::XML::makenode(
      $self->{dom},
      "/tei:TEI/tei:teiHeader/tei:encodingDesc/tei:appInfo/tei:application[\@ident=\"".$metadata{app}."\"]",
      $self->{xpc});
    $application->setAttribute('version', $metadata{version}) if defined($metadata{version});
    $application->setAttribute('source', $metadata{source}) if defined($metadata{source});
    $application->appendTextChild('label', $metadata{label}) if $metadata{label};
    $application->appendTextChild('desc', $metadata{desc}) if $metadata{desc};
    ParCzech::PipeLine::FileManager::XML::makenode(
      $application,
      "./tei:ref",
      $self->{xpc})->setAttribute('target', $metadata{ref}) if $metadata{ref};
  } elsif ($type eq 'prefix') {
    my $prefix = ParCzech::PipeLine::FileManager::XML::makenode(
      $self->{dom},
      "//tei:teiHeader/tei:encodingDesc/tei:listPrefixDef/tei:prefixDef[\@ident=\"$metadata{ident}\"]",
      $self->{xpc});
    for my $n (qw/matchPattern replacementPattern/) {
      $prefix->setAttribute($n, $metadata{$n}) if defined($metadata{$n});
    }
    $prefix->appendTextChild('p',$metadata{p}) if defined($metadata{p});
  } else {
    print STDERR "Unknown metadata type: $type\n";
  }

#  my $revnode = ParCzech::PipeLine::FileManager::XML::makenode(
#  	  $self->{dom},
#  	  "/tei:TEI/tei:teiHeader/tei:revisionDesc/tei:change[\@who=\"".$metadata{who}."\"]",
#  	  $self->{xpc});
#  my $when = strftime "%Y-%m-%d", localtime;
#  $revnode->setAttribute("when", $when);
  return $self;
}


sub add_static_data {
  my $self = shift;
  my ($name, $file) = (shift,shift);
  my %opts = @_;
  $self->init_metadata_visited_detector();
  my $dom = get_metadata_dom($file,%variables,%opts);
  if($dom) {
  	$self->_add_static_data_items($name,$dom);
  }
}

sub _add_static_data_items {
  my $self = shift;
  my ($name,$dom) = @_;
  return if $self->metadata_visited_detector($name);
  my @targets = $self->{xpc}->findnodes('//pcz:ParCzech/pcz:meta[@pcz:name="'.$name.'"]',$dom);
  if (scalar @targets == 0) {
    print STDERR "No meta with target name $name found\n";
    return;
  } elsif (scalar @targets > 1) {
    print STDERR "Multiple targets with similar name name $name found. Using first one!!!\n";
  }
  for my $item ($self->{xpc}->findnodes('./pcz:item',$targets[0])) {
    my $xpath = $item->getAttributeNS($xmlNs{pcz}, 'xpath');
    my $dep_name = $item->getAttributeNS($xmlNs{pcz}, 'dep');

    next unless $self->_static_data_items_test($self->{xpc}->findnodes('./pcz:test', $item));

    if($xpath) {
      my $appendPlace = ParCzech::PipeLine::FileManager::XML::makenode( $self->{dom}, $xpath, $self->{xpc}, \&nodeConditionalAppender);
      my ($teiNodes) = $self->{xpc}->findnodes('./pcz:tei', $item);
      if (defined $teiNodes) {
        for my $content ($teiNodes->childNodes()) {
          $appendPlace->appendChild($content->cloneNode(1));
        }
      }
    } elsif ($dep_name) {
      $self->_add_static_data_items($dep_name,$dom);
    }
  }
}

sub _static_data_items_test {
  my $self = shift;
  my $testnode = shift;
  return 1 unless $testnode; # no test done - item can be added
  for my $cond ($testnode->childNodes()) {
    next if $cond->nodeType() == XML_TEXT_NODE;
    my $xpath = $cond->getAttributeNS($xmlNs{pcz}, 'xpath');
    next unless $xpath;
    if($cond->nodeName() =~ /^[^:]*:?true$/) {
      return undef unless scalar($self->{xpc}->findnodes($xpath, $self->{dom}));
    } elsif ($cond->nodeName() =~ /^[^:]*:?false$/) {
      return undef if scalar($self->{xpc}->findnodes($xpath, $self->{dom}));
    } else {
      print STDERR "unknown element $cond\n";
    }
  }

  return 1
}

sub get_metadata_dom {
  my $file = shift;
  my %vars = @_;
  return $metadata{$file} if defined($metadata{$file});
  my $xml = ParCzech::PipeLine::FileManager::XML::open_xml($file,%vars);
  if($xml) {
    $metadata{$file} = $xml->{dom};
    return $metadata{$file};
  }
}

sub save {
  my $self = shift;
  ParCzech::PipeLine::FileManager::XML::save_to_file($self->{dom}, $self->{outpath});
}

sub print {
  my $self = shift;
  ParCzech::PipeLine::FileManager::XML::print($self->{dom});
}

sub new_XPathContext {
  my $xpc = XML::LibXML::XPathContext->new;
  $xpc->registerNs($_, $xmlNs{$_}) for keys %xmlNs ;
  return $xpc;
}

sub get_NS_from_prefix {
  my $pref = shift;
  return $xmlNs{$pref};
}


sub nodeConditionalAppender {
  my ($xpc, $parent, $ns, $childname) = @_;
  my $node = XML::LibXML::Element->new($childname);
  my $firstSibling = undef;
  if(defined $appendConditions{$parent->nodeName}) {
    my @cond = @{$appendConditions{$parent->nodeName}};
    my %candidates = ();
    for my $c (@cond) {
      next unless $childname =~ $c->[0];
      my ($n) = reverse $parent->findnodes($c->[1]);
      $candidates{$n->unique_key} = 1 if $n;
    }
    for my $ch ($parent->childNodes()){ # find first matching node
      if(defined $candidates{$ch->unique_key}) {
        $firstSibling = $ch;
        last;
      }
    }
  }
  return $parent->insertBefore($node,$firstSibling // undef); # if first child does not exist, node is appended to the end (// undef avoids warning)
}

package ParCzech::PipeLine::FileManager::XML;
use XML::LibXML::PrettyPrint;

use File::Basename;
use File::Path;

sub open_xml {
  my $file = shift;
  my %vars = @_;
  my $xml;
  local $/;
  open FILE, $file;
  binmode ( FILE, ":utf8" );
  my $rawxml = <FILE>;
  close FILE;

  if ((! defined($rawxml)) || $rawxml eq '' ) {
    print " -- empty file $file\n";
  } else {
    my $parser = XML::LibXML->new();
    my $doc = "";
    $rawxml =~ s/\[\[$_\]\]/$vars{$_}/g for keys %vars;
    eval { $doc = $parser->load_xml(string => $rawxml); };
    if ( !$doc ) {
      print " -- invalid XML in $file\n";
      print "$@";

    } else {
      $xml = {raw => $rawxml, dom => $doc}
    }
  }
  return $xml
}

sub to_string {
  my $doc = shift;
  my $pp = XML::LibXML::PrettyPrint->new(
    indent_string => "  ",
    element => {
        inline   => [qw//], # note
        block    => [qw/person persName/],
        compact  => [qw/catDesc term desc label date edition title meeting idno orgName persName resp licence language sex forename surname/],
        preserves_whitespace => [qw/s seg note ref p/],
        }
    );
  $pp->pretty_print($doc);
  return $doc->toString();
}


sub print {
  my $doc = shift;
  binmode STDOUT;
  print to_string($doc);
}


sub save_to_file {
  my ($doc,$filename) = @_;
  my $dir = dirname($filename);
  File::Path::mkpath($dir) unless -d $dir;
  open FILE, ">$filename";
  binmode FILE;
  print FILE to_string($doc);
  close FILE;
}


sub makenode {
  my ( $xml, $xquery, $xpc, $nodeAppender ) = @_;
  my @tmp = $xpc->findnodes($xquery,$xml);
  if ( scalar @tmp ) {
    my $node = shift(@tmp);
#    if ( $debug ) { print "Node exists: $xquery\n"; };
    return $node;
  } else {
    if ( $xquery =~ /^(.*)\/(.*?:)?(.*?)$/ ) {
      my $parxp = $1;
      my $nsPrefix = $2;
      my $thisname = $3;
      $nsPrefix =~ s/:$// if $nsPrefix;
      my $nsUri = undef;
      $nsUri = $xpc->lookupNs($nsPrefix) if $nsPrefix;
      my $parnode = makenode($xml, $parxp, $xpc, $nodeAppender);
      my $thisatts = "";
      if ( $thisname =~ /^(.*)\[(.*?)\]$/ ) {
        $thisname = $1; $thisatts = $2;
      };
#      if ( $debug ) { print "Creating node: $xquery (",($nsUri ? "$nsUri:":""),"$thisname)\n"; };
      my $newchild = $nodeAppender ? $nodeAppender->($xpc, $parnode, $nsUri, $thisname) : $parnode->addNewChild($nsUri, $thisname); #XML::LibXML::Element->new( $thisname );

      # Set any attributes defined for this node
      if ( $thisatts ne '' ) {
#        if ( $debug ) { print "setting attributes $thisatts\n"; };
        foreach my $ap ( split ( " and ", $thisatts ) ) {
          if ( $ap =~ /\@([^ ]+) *= *"(.*?)"/ ) {
            my $an = $1;
            my $av = $2;
            $newchild->setAttribute($an, $av);
          };
        };
      };

      return $newchild

    } else {
      print "Failed to find or create node: $xquery\n";
    };
  };
};


sub encode_id {
  my $string = shift;
  while($string =~ m/^(.*)([^-_a-zA-Z0-9])(.*)$/) {
    $string = $1.replace_char($2).$3;
  }
  return $string;
}

sub replace_char {
  my $c = shift;
  return sprintf('_%X_', ord($c));
}




1;