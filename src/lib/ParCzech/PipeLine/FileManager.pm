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
  print "file ". shift . "does not exist";exit;
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


  open FILE, $self->{inpath};
  binmode ( FILE, ":utf8" );
  my $rawxml = <FILE>;
  close FILE;

  if ( $rawxml eq '' ) {
    print " -- empty file ".$self->{inpath}."\n";
  } else {
    my $parser = XML::LibXML->new();
    my $doc = "";
    eval { $doc = $parser->load_xml(string => $rawxml); };
    if ( !$doc ) {
      print " -- invalid XML in ".$self->{inpath}."\n";
      print STDERR $rawxml;

    } else {
      $self->{raw} = $rawxml;
      $self->{dom} = $doc;
    }
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
    ParCzech::PipeLine::FileManager::XML::makenode(
      $application,
      "./tei:ref",
      $self->{xpc})->setAttribute('target', $metadata{ref}) if $metadata{ref};
    $application->appendTextChild('label', $metadata{label}) if $metadata{label};
    $application->appendTextChild('desc', $metadata{desc}) if $metadata{desc};
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



sub save {
  my $self = shift;
  ParCzech::PipeLine::FileManager::XML::save_to_file($self->{dom}, $self->{outpath});
}

sub print {
  my $self = shift;
  ParCzech::PipeLine::FileManager::XML::print($self->{dom});
}






package ParCzech::PipeLine::FileManager::XML;
use XML::LibXML::PrettyPrint;

use File::Basename;
use File::Path;

sub to_string {
  my $doc = shift;
  my $pp = XML::LibXML::PrettyPrint->new(
    indent_string => "  ",
    element => {
        inline   => [qw//], # note
        #block    => [qw//],
        #compact  => [qw//],
        preserves_whitespace => [qw/s/],
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
  my ( $xml, $xquery, $xpc ) = @_;
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
      my $parnode = makenode($xml, $parxp, $xpc);
      my $thisatts = "";
      if ( $thisname =~ /^(.*)\[(.*?)\]$/ ) {
        $thisname = $1; $thisatts = $2;
      };
#      if ( $debug ) { print "Creating node: $xquery (",($nsUri ? "$nsUri:":""),"$thisname)\n"; };
      my $newchild = $parnode->addNewChild($nsUri, $thisname); #XML::LibXML::Element->new( $thisname );

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