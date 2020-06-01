use warnings;
use strict;
use open qw(:std :utf8);
use Encode qw(decode encode);
use XML::LibXML;
use Getopt::Long;
use POSIX qw(strftime);

use Ufal::MorphoDiTa;
use Lingua::Interset::Converter;

my $scriptname = $0;

my ($debug, $test, $filename, $filelist, $mdita_model, $elements_names, $sentsplit, $mtagger);

my$xmlNS = 'http://www.w3.org/XML/1998/namespace';

$elements_names = "u,seg,head";
my $word_element_name = 'w';
my $punct_element_name = 'pc';
my $sent_element_name = 's';

my @tags;

my %known_tag_fixes=(
  'msd mul::uposf' => sub {my $tag=shift; $tag =~ s/^(.*?)\t/UposTag=$1|/; $tag =~ s/\|_$//; $tag},
  'pos mul::uposf' => sub {my $tag=shift; $tag =~ s/\t.*//; $tag},
  'ana cs::pdt'    => sub {my $tag=shift; "pdt:$tag"},
  );

$sentsplit = 1;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # tokenize, tag and lemmatize to string, do not change the database
            'filename=s' => \$filename, # input file
            'filelist=s' => \$filelist, # file that contains files (it increase speed of script - MorphoDiTa model is inicialized single time)
            'model=s' => \$mtagger, # morphodita tagger
            'elements=s' => \$elements_names,
            'sent=i' => \$sentsplit, # split into sentences
            'word-element=s' => \$word_element_name,
            'punct-element=s' => \$punct_element_name,
            'sent-element=s' => \$sent_element_name,
            'tags=s' => \@tags, # tag attribute name|format (pos cs::pdt)
            );

@tags = ('tag cs::pdt') unless @tags;


my %tag_converter = map {
                      my ($attr,$format) = split(' ',$_);
                      $attr => [
                        $format,
                        ( $format eq 'cs::pdt' ? undef : new Lingua::Interset::Converter("from" => "cs::pdt", "to" => $format))
                        ]
                      } @tags;

usage_exit() unless ( $filename  || $filelist );

usage_exit() unless $mtagger;
file_does_not_exist($mtagger) unless -e $mtagger;


my @input_files;

if ( $filename ) {
  push @input_files, $filename
}

if ( $elements_names =~ m/[\s"']/ ){
  usage_exit();
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
my $tagger = Ufal::MorphoDiTa::Tagger::load($mtagger);
$tagger or die "Cannot load tagger from file '$mtagger'\n";
print STDERR "done\n" if $debug;


my $tokenizer = Ufal::MorphoDiTa::Tokenizer::newCzechTokenizer();
my $forms = Ufal::MorphoDiTa::Forms->new();
my $lemmas = Ufal::MorphoDiTa::TaggedLemmas->new();


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
  if ( $rawxml =~ /<\/${word_element_name}>/ ) {
    print " -- file is already tokenized - $filename\n";
    next;
  }
  my $parser = XML::LibXML->new();
  my $doc = "";
  eval { $doc = $parser->load_xml(string => $rawxml); };
  if ( !$doc ) {
    print "Invalid XML in $filename";
    next;
  }

  my @parents = $doc->findnodes('//text//*[contains(" '.join(' ',split(',',$elements_names)).' ", concat(" ",name()," "))]');
  while(my $parent = shift @parents) {
    my @childnodes = $parent->childNodes(); # find all child tokens
    $_->unbindNode() for @childnodes;
    #$parent->removeChildNodes();
#    my @stack = ($parent);
#    my $newxml = '';

    while(my $chnode = shift @childnodes) {
      my $sentNode = $parent;
      if ( $chnode->nodeType != XML_TEXT_NODE ) { # not text node
        $parent->appendChild($chnode);
      } else { # text node
        my $text = $chnode->textContent();
        $text =~ s/^\s*//;
        $tokenizer->setText($text);
        my $ti = 0;
        while($tokenizer->nextSentence($forms, undef)){
          if($sentsplit){
            $sentNode = XML::LibXML::Element->new( $sent_element_name );
            $sentNode->setAttributeNS($xmlNS, 'id', "s-$sid");
            $parent->appendChild($sentNode);
            $sid++;
          }
          $tagger->tag($forms, $lemmas);

          for (my $i = 0; $i < $lemmas->size(); $i++) {
            my $form = $forms->get($i);
            my $lemma = $lemmas->get($i);
            $ti += length($form);
            my $tokenNode = XML::LibXML::Element->new( $lemma->{tag} =~ /^Z/ ? $punct_element_name : $word_element_name );
            $tokenNode->setAttributeNS($xmlNS, 'id', "w-$wid");
            $tokenNode->setAttribute('lemma', $lemma->{lemma});
            for my $attr (keys %tag_converter){
              my ($format,$converter) = @{$tag_converter{$attr}};
              my $value = ! $converter ? $lemma->{tag} : $converter->convert($lemma->{tag});
              $value = $known_tag_fixes{"$attr $format"}->($value) if exists $known_tag_fixes{"$attr $format"};
              $tokenNode->setAttribute($attr, $value);
            }
            # $tokenNode->setAttribute('form', $form);
            $tokenNode->appendText($form);
            $sentNode->appendChild($tokenNode);

            if(substr($text, $ti, 1) =~ m/\s/){ # skip first space and append space to node

              $sentNode->appendText(' ');
              $ti++;
            } else {
              $tokenNode->setAttribute('join', 'right');
            }
            $ti++ while substr($text, $ti, 1) =~ m/\s/; # skip next spaces

            $wid++;
          }
        }
      }
    } # end of element
  } # end of file
  # Add a revisionDesc to indicate the file was tagged with NameTag
  my $revnode = makenode($doc, "/TEI/teiHeader/revisionDesc/change[\@who=\"xmlmorphodita\"]");
  my $when = strftime "%Y-%m-%d", localtime;
  $revnode->setAttribute("when", $when);
  $revnode->appendText("tokenized, tagged and lemmatized using xmlmorphodita.pl");

  my $xmlfile = $doc->toString;

  if ( $test ) {
    binmode STDOUT;
    print  $xmlfile;
  } else {

    # Make a backup of the file
    my $buname;
    ( $buname = $filename ) =~ s/xmlfiles.*\//backups\//;
    my $date = strftime "%Y%m%d", localtime;
    $buname =~ s/\.xml/-$date.nmorph.xml/;
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
   print " -- usage: xmlmorphodita.pl --model=[fn] (--filename=[fn] | --filelist=[fn]) --elements=[list]\n\nelements should contain names of elements to be tokenized and tagged separated with comma";
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


