
use warnings;
use strict;
use open qw(:std :utf8);
use Encode qw(decode encode);
use XML::LibXML;
use Getopt::Long;
use POSIX qw(strftime);

use Lingua::Interset::Converter;

my $scriptname = $0;

my ($debug, $test, $filename, $filelist, $breaklim);

$breaklim = 500;
my $cntelm='tok';
my $breakafter='u';

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # process to string, do not change the database
            'after-n-elem-break' => \$breaklim, #
            'filename=s' => \$filename, # input file
            'filelist=s' => \$filelist, # file that contains files (it increase speed of script - MorphoDiTa model is inicialized single time)
            );

usage_exit() unless ( $filename  || $filelist );


my @input_files;

if ( $filename ) {
  push @input_files, $filename
}

if ( $filelist ) {
  open my $fl, $filelist or die "Could not open $filelist: $!";
  while(my $fn = <$fl>) {
    $fn =~ s/\n$//;
    push @input_files, $fn if $fn ;
  }
  close $fl;
}

for my $f (@input_files) {
  file_does_not_exist($f) unless -e $f
}

print STDERR "Loading : " if $debug;

while($filename = shift @input_files) {
  $/ = undef;
  open FILE, $filename;
  binmode ( FILE, ":utf8" );
  my $rawxml = <FILE>;
  close FILE;
  if ( $rawxml eq '' ) {
    print " -- empty file $filename\n";
    next;
  }
  if ( $rawxml =~ m/<pb[^>\/]\/>/ ) {
    print " -- already paginated $filename\n";
    next;
  }
  if( scalar (() = $rawxml =~ /<\/$cntelm>/g) < $breaklim) {
    print " -- no pagination $filename\n";
    next;
  }

  my $parser = XML::LibXML->new();
  my $doc = "";
  eval { $doc = $parser->load_xml(string => $rawxml); };
  if ( !$doc ) {
    print "Invalid XML in $filename";
    next;
  }
  my $token_cnt = $breaklim; # force begining break
  my $pbid = 1;
  # insert first pagebreak
  my (@nodes) = $doc->findnodes('//text/*[name()="'.$breakafter.'" or name()="note"]'); # last page break can be before last node
  for my $node (@nodes) {
    my $is_time_to = ($node->nodeName eq 'note') && $node->findvalue('./time/@to');
    if($token_cnt >= $breaklim && !$is_time_to) { # dont break if current note is type of time-to
      $node->parentNode->insertBefore(new_pagebreak(\$pbid),$node); #
      $token_cnt = 0;
    }
    $token_cnt += $node->findvalue('count(.//'.$cntelm.')');

  }

  # Add a revisionDesc to indicate the file was tagged with NameTag
  my $revnode = makenode($doc, "/TEI/teiHeader/revisionDesc/change[\@who=\"paginator\"]");
  my $when = strftime "%Y-%m-%d", localtime;
  $revnode->setAttribute("when", $when);
  $revnode->appendText("add pagebreak using paginator.pl");

  my $xmlfile = $doc->toString;

  if ( $test ) {
    binmode STDOUT;
    print  $xmlfile;
  } else {

    # Make a backup of the file
    my $buname;
    ( $buname = $filename ) =~ s/xmlfiles.*\//backups\//;
    my $date = strftime "%Y%m%d", localtime;
    $buname =~ s/\.xml/-$date.nopb.xml/;
    my $cmd = "/bin/cp $filename $buname";
    `$cmd`;

    open FILE, ">$filename";
    binmode FILE;
    print FILE $xmlfile;
    close FILE;
  };
}





sub makenode {
  my ( $xml, $xquery ) = @_;
  my @tmp = $xml->findnodes($xquery);
  if ( scalar @tmp ) {
    my $node = shift(@tmp);
    if ( $debug ) { print "Node exists: $xquery"; };
    return $node;
  } else {
    if ( $xquery =~ /^(.*)\/(.*?)$/ ) {
      my $parxp = $1; my $thisname = $2;
      my $parnode = makenode($xml, $parxp);
      my $thisatts = "";
      if ( $thisname =~ /^(.*)\[(.*?)\]$/ ) {
        $thisname = $1; $thisatts = $2;
      };
      my $newchild = XML::LibXML::Element->new( $thisname );

      # Set any attributes defined for this node
      if ( $thisatts ne '' ) {
        if ( $debug ) { print "setting attributes $thisatts"; };
        foreach my $ap ( split ( " and ", $thisatts ) ) {
          if ( $ap =~ /\@([^ ]+) *= *"(.*?)"/ ) {
            my $an = $1;
            my $av = $2;
            $newchild->setAttribute($an, $av);
          };
        };
      };

      if ( $debug ) { print "Creating node: $xquery ($thisname)"; };
      $parnode->addChild($newchild);

    } else {
      print "Failed to find or create node: $xquery";
    };
  };
};


sub new_pagebreak {
  my $idcnt = shift;
  my $newnode = XML::LibXML::Element->new( 'pb' );
  $newnode->setAttribute('id', sprintf("pb%03d", $$idcnt));
  $newnode->setAttribute('n', sprintf("%03d", $$idcnt));
  $$idcnt += 1;
  return $newnode;
}


sub file_does_not_exist {
  print "file ". shift . "does not exist";exit;
}

sub usage_exit {
   print " -- usage: paginator.pl  (--filename=[fn] | --filelist=[fn]) [--after-n-elem-break=[number]]\n";
   exit;
}


sub sort_entities {
  my ($entities) = @_;
  my @entities = ();
  for (my ($i, $size) = (0, $entities->size()); $i < $size; $i++) {
    push @entities, $entities->get($i);
  }
  return sort { $a->{start} <=> $b->{start} || $b->{length} <=> $a->{length} } @entities;
}

sub encode_entities {
  my ($text) = @_;
  $text =~ s/[&<>"]/$& eq "&" ? "&amp;" : $& eq "<" ? "&lt;" : $& eq ">" ? "&gt;" : "&quot;"/ge;
  return $text;
}


