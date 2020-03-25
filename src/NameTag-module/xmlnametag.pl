use warnings;
use strict;
use open qw(:std :utf8);
use Encode qw(decode encode);
use XML::LibXML;
use Getopt::Long;
use POSIX qw(strftime);

use Ufal::NameTag;

# Runs NameTag on tokenized TEI file

my $scriptname = $0;

my ($debug, $test, $filename, $filelist, $neotag_model);


# id stores last used value
# prefixid prefix for id
my %namedEntities = (
  #generate_common_entities({},qw//),
  G  => { placeName => { prefixid => 'place', id => 0 } },
  gc  => { region => { prefixid => 'gc', id => 0, type => 'state' } },
  gh  => { geogName => { prefixid => 'gh', id => 0, type => 'hydronym' } },
  gl  => { geogName => { prefixid => 'gl', id => 0, type => 'nature' } },
  gp  => { placeName => { prefixid => 'gp', id => 0, type => 'urbanpart' } },
  gr  => { country => { prefixid => 'gr', id => 0 } },
  gs  => { placeName => { prefixid => 'gs', id => 0, type => 'street' } },
  gt  => { bloc => { prefixid => 'gt', id => 0, type => 'continent' } },
  gu  => { settlement => { prefixid => 'gu', id => 0, type => 'city' } },
  g_  => { placeName => { prefixid => 'g_', id => 0, type => 'underspecified' } },


  I  => { orgName => { prefixid => 'org', id => 0 } },
  ia => { orgName => { prefixid => 'ia', id => 0, type => 'conference/contest' } }, # not in TEI
  ic => { orgName => { prefixid => 'ia', id => 0, type => 'cult/educ/scient' } }, # not in TEI
  if => { orgName => { prefixid => 'if', id => 0, type => 'company' } }, # not in TEI
  io => { orgName => { prefixid => 'io', id => 0, type => 'government/political' } }, # not in TEI
  i_ => { orgName => { prefixid => 'o_', id => 0, type => 'underspecified' } }, # not in TEI

  P  => { persName => { prefixid => 'pers', id => 0 } },
  pf => { forename => { prefixid => 'pf', id => 0 } },
  pm => { forename => { prefixid => 'pf', id => 0, type => 'second'} }, # not in TEI
  ps => { surname => { prefixid => 'ps', id => 0 } },
  pd => { roleName => { prefixid => 'pd', id => 0, type => 'honorific' } }, # possible attribute: full
  pc => { roleName => { prefixid => 'pc', id => 0, type => 'inhabitant' } }, # not in TEI
  pp => { persName => { prefixid => 'pp', id => 0, type => 'religious/mythological' } },
  p_ => { persName => { prefixid => 'p_', id => 0, type => 'underspecified' } }, # not in TEI

  O  => { name => { prefixid => 'o', id => 0, type => 'artifact' } },
  oa => { name => { prefixid => 'oa', id => 0, type => 'culturalartifact' } }, # not in TEI
  oe => { unit => { prefixid => 'oe', id => 0, type => 'measure' } },
  om => { unit => { prefixid => 'om', id => 0, type => 'currency' } },
  op => { name => { prefixid => 'op', id => 0, type => 'product' } },# not in TEI
  or => { name => { prefixid => 'or', id => 0, type => 'norm/directive' } },# not in TEI
  o_ => { name => { prefixid => 'o_', id => 0, type => 'underspecified' } }, # not in TEI

);

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # tag to string, do not change the database
            'filename=s' => \$filename, # input file
            'filelist=s' => \$filelist, # file that contains files to be nametagged (it increase speed of script - NameTag model is inicialized single time)
            'model=s' => \$neotag_model # neotag model
            );


usage_exit() unless ( $filename  || $filelist );

usage_exit() unless $neotag_model;
file_does_not_exist($neotag_model) unless -e $neotag_model;

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

print STDERR "Loading ner: " if $debug;
my $ner = Ufal::NameTag::Ner::load($neotag_model);
$ner or die "Cannot load recognizer from file '$neotag_model'\n";
print STDERR "done\n" if $debug;
my $entities = Ufal::NameTag::NamedEntities->new();


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
  unless ( $rawxml =~ /<\/tok>/ ) {
    print " -- file is not tokenized $filename\n";
    next;
  }
  my $parser = XML::LibXML->new();
  my $doc = "";
  eval { $doc = $parser->load_xml(string => $rawxml); };
  if ( !$doc ) {
    print "Invalid XML in $filename";
    next;
  }

  my @parents = $doc->findnodes('//*[./tok]'); # all parent nodes that contain tokens
  while(my $parent = shift @parents) {
    my @childnodes = $parent->childNodes(); # find all child tokens
    $_->unbindNode() for @childnodes;
    #$parent->removeChildNodes();
    my @stack = ($parent);
#    my $newxml = '';

    while(@childnodes) {
      my @sentence_nodes;
      my $forms = Ufal::NameTag::Forms->new();
      my @sentence_tokens;
      my $prev_num = 0;

      while(my $chnode = shift @childnodes){
        push @sentence_nodes, $chnode;
        my $text = $chnode->nodeName eq 'tok'
                   ? join('',map {$_->textContent()} grep {$_->nodeType == XML_TEXT_NODE} $chnode->childNodes())
                   : undef;
        push @sentence_tokens, $text;
        if(defined $text) { # definde for tokens
          $forms->push($text);
          unless($parent->nodeName() eq 's') { # detect end of sentence unless sentence is defined:
            last if not($prev_num) && $text eq '.'; # possible ordinal number
            last if $text =~ m/[\?\!]/;
            $prev_num = $text =~ /^[0-9]+$/ ? 1 : 0;
          }
        }
      }

      print STDERR "SENTENCE:",join(' ', map {$_//''} @sentence_tokens),"\n" if $debug;
      $ner->recognize($forms, $entities);
      my @sorted_entities = sort_entities($entities);
      my @open_entities;
      my $e=0;
      my $skipped=0;
      for( my $i=0; $i < @sentence_nodes; $i++) {
        while($i < @sentence_nodes && not defined $sentence_tokens[$i]){ # print nodes != 'tok'
#          $newxml .= $sentence_nodes[$i];
          $stack[$#stack]->appendChild($sentence_nodes[$i]);
          $i++;
          $skipped++;
        }
        last unless $i < @sentence_nodes;
        my $node = $sentence_nodes[$i];
        for (; $e < @sorted_entities && $sorted_entities[$e]->{start} == $i - $skipped; $e++) {
#          $newxml .= sprintf '<ne type="%s">', encode_entities($sorted_entities[$e]->{type});
          my $newnode = new_nametag_element($sorted_entities[$e]->{type});
          $stack[$#stack]->appendChild($newnode);
          push @stack, $newnode;
          push @open_entities, $sorted_entities[$e]->{start} + $sorted_entities[$e]->{length} - 1;
        }
#        $newxml .= $node;
        $stack[$#stack]->appendChild($node);
        while (@open_entities && $open_entities[-1] == $i - $skipped) {
#          $newxml .= '</ne>';
          pop @stack;
          pop @open_entities;
        }
      }


    } # end of utterance
  } # end of file
  # Add a revisionDesc to indicate the file was tagged with NameTag
  my $revnode = makenode($doc, "/TEI/teiHeader/revisionDesc/change[\@who=\"xmlnametag\"]");
  my $when = strftime "%Y-%m-%d", localtime;
  $revnode->setAttribute("when", $when);
  $revnode->appendText("tagged using xmlnametag.pl");

  my $xmlfile = $doc->toString;

  if ( $test ) {
    binmode STDOUT;
    print  $xmlfile;
  } else {

    # Make a backup of the file
    my $buname;
    ( $buname = $filename ) =~ s/xmlfiles.*\//backups\//;
    my $date = strftime "%Y%m%d", localtime;
    $buname =~ s/\.xml/-$date.nntg.xml/;
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

sub new_nametag_element {
  my $tag = shift;
  unless(exists $namedEntities{$tag}){
    $namedEntities{$tag} = {
      name => {
        prefixid => $tag,
        id =>0,
        type => $tag
        }
      };
  }
  my ($name) = keys %{$namedEntities{$tag}};
  my $entSpec = $namedEntities{$tag}->{$name};
  my $node = XML::LibXML::Element->new($name);
  $node->setAttribute('id',($entSpec->{prefixid}//'NE') . $entSpec->{id});
  $entSpec->{id}++;
  $node->setAttribute($_,encode_entities($entSpec->{$_})) for (grep {not($_ eq 'id' || $_ eq 'prefixid')} keys %$entSpec);
  return $node;
}



sub file_does_not_exist {
  print "file ". shift . "does not exist";exit;
}

sub usage_exit {
   print " -- usage: xmlnametag.pl --model=[fn] (--filename=[fn] | --filelist=[fn])"; exit;
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



