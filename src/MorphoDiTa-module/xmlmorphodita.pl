use warnings;
use strict;
use open qw(:std :utf8);
use Encode qw(decode encode);
use XML::LibXML::PrettyPrint;
use XML::LibXML;
use Getopt::Long;
use POSIX qw(strftime);

use Ufal::MorphoDiTa;
use Lingua::Interset::Converter;

my $scriptname = $0;

my ($debug, $test, $filename, $filelist, $mdita_model, $elements_names, $sentsplit, $mtagger, $no_backup_file, $sub_elements_names);

my$xmlNS = 'http://www.w3.org/XML/1998/namespace';

$elements_names = "seg,head";
$sub_elements_names = "ref";
my $word_element_name = 'w';
my $punct_element_name = 'pc';
my $sent_element_name = 's';
my $full_lemma = undef;

my @tags;

my %known_tag_fixes=(
  'msd mul::uposf' => sub {my $tag=shift; $tag =~ s/^(.*?)\t/UposTag=$1|/; $tag =~ s/\|_$//; $tag},
  'pos mul::uposf' => sub {my $tag=shift; $tag =~ s/\t.*//; $tag},
  'ana cs::pdt'    => sub {
    my $tag=shift;
    while($tag =~ m/^(.*)([^-_a-zA-Z0-9])(.*)$/) {
      $tag = $1.sprintf('_%X_', ord($2)).$3;
    }
    "pdt:$tag"
  },
  'ana cs::multext'=> sub {my $tag=shift; "mte:$tag"},
           # there exists morphosyntactic specs in tei http://nl.ijs.si/ME/V6/msd/tables/msd-fslib-cs.xml (for Czech)
  );

my %run_once_for_every_file = (
  'ana cs::multext'=> sub { # add encoding info tp teiHeader
    # teiHeader/encodingDesc/listPrefixDef/<prefixDef ident="mte" matchPattern="(.+)" replacementPattern="http://nl.ijs.si/ME/V6/msd/tables/msd-fslib-cs.xml#$1" />
    my $xml = shift;
    my $node = makenode($xml,'//teiHeader/encodingDesc/listPrefixDef/prefixDef[@ident="mte"]');
    $node->setAttribute('ident', 'mte');
    $node->setAttribute('matchPattern', '(.+)');
    $node->setAttribute('replacementPattern', 'http://nl.ijs.si/ME/V6/msd/tables/msd-fslib-cs.xml#$1');
    $node->appendTextChild('p','Feature-structure elements definition of the Czech MULTEXT-East Version 6 MSDs');
  },
  'ana cs::pdt'=> sub {
    my $xml = shift;
    my $node = makenode($xml,'//teiHeader/encodingDesc/listPrefixDef/prefixDef[@ident="pdt"]');
    $node->setAttribute('ident', 'pdt');
    $node->setAttribute('matchPattern', '(.+)');
    $node->setAttribute('replacementPattern', 'pdt-fslib.xml#$1');
    $node->appendTextChild('p','Feature-structure elements definition of the Czech Positional Tags');
  },
);

$sentsplit = 1;

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # tokenize, tag and lemmatize to string, do not change the database
            'full-lemma' => \$full_lemma,
            'no-backup-file' => \$no_backup_file,
            'filename=s' => \$filename, # input file
            'filelist=s' => \$filelist, # file that contains files (it increase speed of script - MorphoDiTa model is inicialized single time)
            'model=s' => \$mtagger, # morphodita tagger
            'elements=s' => \$elements_names,
            'sub-elements=s' => \$sub_elements_names, # child elements that are also tokenized
            'sent=i' => \$sentsplit, # split into sentences
            'word-element=s' => \$word_element_name,
            'punct-element=s' => \$punct_element_name,
            'sent-element=s' => \$sent_element_name,
            'tags=s' => \@tags, # tag attribute name|format (pos cs::pdt)
            );

@tags = ('tag cs::pdt') unless @tags;
my %sub_elements_names_filter = map {$_ => 1} split(',', $sub_elements_names);

my %tag_converter = map {
                      my ($attr,$format) = split(' ',$_);
                      "$attr $format" => [
                        $attr,
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
  for my $tag (@tags){
    $run_once_for_every_file{$tag}->($doc) if exists $run_once_for_every_file{$tag};
  }
  my @parents = $doc->findnodes('//text//*[contains(" '.join(' ',split(',',$elements_names)).' ", concat(" ",name()," "))]');
  while(my $parent = shift @parents) {
    my $text = '';
    my @childnodes = ();
    for my $chnode ($parent->childNodes()) { # loop and unbind all child nodes
      $chnode->unbindNode();
      my $chtext='';
      my $chtextsize=0;
      if ( $chnode->nodeType == XML_TEXT_NODE || exists $sub_elements_names_filter{$chnode->nodeName}) {
        $chtext = $chnode->textContent();
        $chtextsize = length($chtext);
      }
print STDERR $chnode->nodeType,"\t\t",$chnode,"\n";
      $text .= $chtext;
      push @childnodes,{node => $chnode, text => $chtext, size => $chtextsize};
    }
print STDERR "TEXT:=========================\n", $text,"\n$parent\n=============================\n";

    #$parent->removeChildNodes();
#    my @stack = ($parent);
#    my $newxml = '';
    my $sentNode = $parent;
    my $space = '';
    if($space) {
      $parent->appendText($space);
      undef $space;
    }

    $tokenizer->setText($text);
    my $ti = 0; # nodetext index
    my $cti = 0; # current childnode text index
    my $chi = 0; # childnode index
    while($tokenizer->nextSentence($forms, undef)){ ### sentences loop
      while (@childnodes < $chi
           && $childnodes[$chi]->{size} == 0) { ### copy if no content should be tokenized
        $parent->appendChild($childnodes[$chi]->{node});
        $chi += 1;
        $cti = 0;
      }

      if($sentsplit){
        $sentNode = XML::LibXML::Element->new( $sent_element_name );
        $sentNode->setAttributeNS($xmlNS, 'id', "s-$sid");
        if($space) {
          $parent->appendText($space);
          undef $space;
        }
        $parent->appendChild($sentNode);
        $sid++;
      }
      $tagger->tag($forms, $lemmas);

      for (my $i = 0; $i < $lemmas->size(); $i++) { ### tokens loop
        my $form = $forms->get($i);
        my $lemma = $lemmas->get($i);
        $ti += length($form);
        while ( $chi < @childnodes
             && $childnodes[$chi]->{size} == 0) { ### copy if no content should be tokenized
          $sentNode->appendChild($childnodes[$chi]->{node}->cloneNode(1));
          $chi += 1;
          $cti = 0;
        }
        if( $childnodes[$chi]->{node}->nodeType != XML_TEXT_NODE
            && $cti == 0) { ### is it first token?
          my $newchild = $childnodes[$chi]->{node}->cloneNode(0); # Expecting only text child nodes - no deep copy
          $sentNode->appendChild($newchild);
          $sentNode = $newchild; ## TODO use stack ???
        }

        $cti += length($form);
        my $tokenNode = XML::LibXML::Element->new( $lemma->{tag} =~ /^Z/ ? $punct_element_name : $word_element_name );
        $tokenNode->setAttributeNS($xmlNS, 'id', "w-$wid");
        $lemma->{lemma} =~ s/^(.+?)[-_`].*/$1/ unless $full_lemma;
        $tokenNode->setAttribute('lemma', $lemma->{lemma});

        for my $key (keys %tag_converter){
          my ($attr, $format,$converter) = @{$tag_converter{$key}};
          my $value = ! $converter ? $lemma->{tag} : $converter->convert($lemma->{tag});
          $value = $known_tag_fixes{"$attr $format"}->($value) if exists $known_tag_fixes{"$attr $format"};

          $tokenNode->setAttribute($attr, ($tokenNode->hasAttribute($attr) ? $tokenNode->getAttribute($attr).' ' : '').$value);
        }
        # $tokenNode->setAttribute('form', $form);
        $tokenNode->appendText($form);
        if($space){
          $sentNode->appendText($space);
          undef $space;
        }

        $sentNode->appendChild($tokenNode);

        if(substr($text, $ti, 1) =~ m/\s/){ # skip first space and append space to node
          $space = " ";
          $ti++;
          $cti++; #
        } else {
          $tokenNode->setAttribute('join', 'right');
        }
        $ti++ while substr($text, $ti, 1) =~ m/\s/; # skip next spaces ???? this should not happen !!!

        $wid++;
        if($childnodes[$chi]->{size} <= $cti){
          $sentNode = $sentNode->parentNode() if $childnodes[$chi]->{node}->nodeType != XML_TEXT_NODE;
          $chi++;
          $cti = 0;
        }
      } # end tokens loop
    } # end sentences loop
    while ( $chi < @childnodes
           && $childnodes[$chi]->{size} == 0) { ### copy if no content should be tokenized
      $sentNode->appendChild($childnodes[$chi]->{node}->cloneNode(1));
      $chi += 1;
      $cti = 0;
    }

  } # end of file
  # Add a revisionDesc to indicate the file was tagged with NameTag
  my $revnode = makenode($doc, "/TEI/teiHeader/revisionDesc/change[\@who=\"xmlmorphodita\"]");
  my $when = strftime "%Y-%m-%d", localtime;
  $revnode->setAttribute("when", $when);
  $revnode->appendText("tokenized, tagged and lemmatized using xmlmorphodita.pl");
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

  my $xmlfile = $doc->toString;

  if ( $test ) {
    binmode STDOUT;
    print  $xmlfile;
  } else {

    unless(defined $no_backup_file) { # Make a backup of the file
      my $buname;
      ( $buname = $filename ) =~ s/xmlfiles.*\//backups\//;
      my $date = strftime "%Y%m%d", localtime;
      $buname =~ s/\.xml/-$date.nmorph.xml/;
      my $cmd = "/bin/cp $filename $buname";
      `$cmd`;
    }

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


