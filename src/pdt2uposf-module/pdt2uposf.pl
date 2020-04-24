
use warnings;
use strict;
use open qw(:std :utf8);
use Encode qw(decode encode);
use XML::LibXML;
use Getopt::Long;
use POSIX qw(strftime);

use Lingua::Interset::Converter;

my $scriptname = $0;

my ($debug, $test, $filename, $filelist, $keepinputattribute, $fixlemma);

my $inputattr='pos';
my @outputattrs=qw/pos feat/;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # process to string, do not change the database
            'fixlemma' => \$fixlemma, # remove tails from lemmas
            'keepinputattribute' => \$keepinputattribute,
            'filename=s' => \$filename, # input file
            'filelist=s' => \$filelist, # file that contains files (it increase speed of script - MorphoDiTa model is inicialized single time)
            );

my $tag_converter = new Lingua::Interset::Converter("from" => "cs::pdt", "to" => "mul::uposf");
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
  my $sid = 1;
  my $wid = 1;
  if ( $rawxml eq '' ) {
    print " -- empty file $filename\n";
    next;
  }
  my $parser = XML::LibXML->new();
  my $doc = "";
  eval { $doc = $parser->load_xml(string => $rawxml); };
  if ( !$doc ) {
    print "Invalid XML in $filename";
    next;
  }
  for my $node ($doc->findnodes('//text//tok[@'.$inputattr.']')) {
    my $pos = $node->getAttribute($inputattr);
    next unless length($pos) == 15;
    $node->removeAttribute($inputattr) unless $keepinputattribute;
    my @uposf= split "\t", $tag_converter->convert($pos);
    for my $i (0..$#uposf) {
      $node->setAttribute($outputattrs[$i],$uposf[$i]) if $i < @outputattrs;
    }
  }
  if($fixlemma) {
    for my $node ($doc->findnodes('//text//tok[@lemma]')) {
      my $lemma = $node->getAttribute('lemma');
      # https://ufal.mff.cuni.cz/pdt2.0/doc/manuals/en/m-layer/html/ch02s01.html
      # A-1`ampér_:B
      # stát-2_^(něco_se_přihodilo)
      # právo_^(právo_na_něco;_také_jako_obor)
      # dva`2_,x
      $lemma =~ s/^(.+?)[-_`].*/$1/;
      $node->setAttribute('lemma',$lemma)
    }
  }
  # Add a revisionDesc to indicate the file was tagged with NameTag
  my $revnode = makenode($doc, "/TEI/teiHeader/revisionDesc/change[\@who=\"pdt2uposf\"]");
  my $when = strftime "%Y-%m-%d", localtime;
  $revnode->setAttribute("when", $when);
  $revnode->appendText("change pos style using pdt2uposf.pl");

  my $xmlfile = $doc->toString;

  if ( $test ) {
    binmode STDOUT;
    print  $xmlfile;
  } else {

    # Make a backup of the file
    my $buname;
    ( $buname = $filename ) =~ s/xmlfiles.*\//backups\//;
    my $date = strftime "%Y%m%d", localtime;
    $buname =~ s/\.xml/-$date.pdtuposf.xml/;
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





sub file_does_not_exist {
  print "file ". shift . "does not exist";exit;
}

sub usage_exit {
   print " -- usage: pdt2uposf.pl  (--filename=[fn] | --filelist=[fn])\n";
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


