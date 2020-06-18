use warnings;
use strict;
use open qw(:std :utf8);
use Encode qw(decode encode);
use XML::LibXML::PrettyPrint;
use XML::LibXML;
use Getopt::Long;
use POSIX qw(strftime);

use Ufal::NameTag;

# Runs NameTag on tokenized TEI file

my $scriptname = $0;

my ($debug, $test, $filename, $filelist, $neotag_model, $no_backup_file);

my$xmlNS = 'http://www.w3.org/XML/1998/namespace';




# id stores last used value
# prefixid prefix for id
my $default_ne_conf = ['unknown', 'name', {}];
# [ ParCzech_category, ParlaClarinElement, {ParlaClarinAttribute => ParlaClarinValue}]

my $namedEntities = {
  valuesname => 'class',
  values => {
    a => {
      symbol => 'numbers in addresses',
      valuesname => 'subclass',
      values => {
        ah => { symbol => 'street numbers'},
        at => { symbol => 'phone/fax numbers'},
        az => { symbol => 'zip codes'},
      },
    },
    g => {
      symbol => 'geographical names',
      valuesname => 'subclass',
      values => {
        g_ =>  { symbol => 'geographical names - underspecified'},
        gc =>  { symbol => 'geographical names - states'},
        gh =>  { symbol => 'geographical names - hydronyms'},
        gl =>  { symbol => 'geographical names - nature areas / objects'},
        gq =>  { symbol => 'geographical names - urban parts'},
        gr => { symbol => 'territorial names'},
        gs => { symbol => 'streets, squares'},
        gt => { symbol => 'continents'},
        gu => { symbol => 'cities/towns'},
      },
    },
    i => {
      symbol => 'institutions',
      valuesname => 'subclass',
      values => {
        i_ => { symbol => 'underspecified'},
        ia => { symbol => 'conferences/contests'},
        ic => { symbol => 'cult./educ./scient. inst.'},
        if => { symbol => 'companies, concerns...'},
        io => { symbol => 'government/political inst.'},
      },
    },
    m => {
      symbol => 'media names',
      valuesname => 'subclass',
      values => {
        me => { symbol => 'email address'},
        mi => { symbol => 'internet links'},
        mn => { symbol => 'periodical'},
        ms => { symbol => 'radio and tv stations'},
      },
    },
    n => {
      symbol => 'number expressions',
      valuesname => 'subclass',
      values => {
        n_ => { symbol => 'underspecified'},
        na => { symbol => 'age'},
        nb => { symbol => 'vol./page/chap./sec./fig. numbers'},
        nc => { symbol => 'cardinal numbers'},
        ni => { symbol => 'itemizer'},
        no => { symbol => 'ordinal numbers'},
        ns => { symbol => 'sport score'},
      },
    },
    o => {
      symbol => 'artifact names',
      valuesname => 'subclass',
      values => {
        o_ => { symbol => 'underspecified'},
        oa => { symbol => 'cultural artifacts (books, movies)'},
        oe => { symbol => 'measure units'},
        om => { symbol => 'currency units'},
        op => { symbol => 'products'},
        or => { symbol => 'directives, norms'},
      },
    },
    p => {
      symbol => 'personal names',
      valuesname => 'subclass',
      values => {
        p_ => { symbol => 'underspecified'},
        pc => { symbol => 'inhabitant names'},
        pd => { symbol => '(academic) titles'},
        pf => { symbol => 'first names'},
        pm => { symbol => 'second names'},
        pp => { symbol => 'relig./myth persons'},
        ps => { symbol => 'surnames'},
      },
    },
    t => {
      symbol => 'time expressions',
      valuesname => 'subclass',
      values => {
        td => { symbol => 'days'},
        tf => { symbol => 'feasts'},
        th => { symbol => 'hours'},
        tm => { symbol => 'months'},
        ty => { symbol => 'years'}
      },
    },
  }
};


=old2
my %namedEntities = (
    A => [ 'numbers in addresses', '',{} ],
    ah => [ 'numbers in addresses - street numbers', '',{} ],
    at => [ 'numbers in addresses - phone/fax numbers', '',{} ],
    az => [ 'numbers in addresses - zip codes', '',{} ],
    G => [ 'geographical names', '',{} ],
    g_ => [ 'geographical names - underspecified', '',{} ],
    gc => [ 'geographical names - states', '',{} ],
    gh => [ 'geographical names - hydronyms', '',{} ],
    gl => [ 'geographical names - nature areas / objects', '',{} ],
    gq => [ 'geographical names - urban parts', '',{} ],
    gr => [ 'geographical names - territorial names', '',{} ],
    gs => [ 'geographical names - streets, squares', '',{} ],
    gt => [ 'geographical names - continents', '',{} ],
    gu => [ 'geographical names - cities/towns', '',{} ],
    I => [ 'institutions', '',{} ],
    i_ => [ 'institutions - underspecified', '',{} ],
    ia => [ 'institutions - conferences/contests', '',{} ],
    ic => [ 'institutions - cult./educ./scient. inst.', '',{} ],
    if => [ 'institutions - companies, concerns...', '',{} ],
    io => [ 'institutions - government/political inst.', '',{} ],
    M => [ 'media names', '',{} ],
    me => [ 'media names - email address', '',{} ],
    mi => [ 'media names - internet links', '',{} ],
    mn => [ 'media names - periodical', '',{} ],
    ms => [ 'media names - radio and tv stations', '',{} ],
    N => [ 'number expressions', '',{} ],
    n_ => [ 'number expressions - underspecified', '',{} ],
    na => [ 'number expressions - age', '',{} ],
    nb => [ 'number expressions - vol./page/chap./sec./fig. numbers', '',{} ],
    nc => [ 'number expressions - cardinal numbers', '',{} ],
    ni => [ 'number expressions - itemizer', '',{} ],
    no => [ 'number expressions - ordinal numbers', '',{} ],
    ns => [ 'number expressions - sport score', '',{} ],
    O => [ 'artifact names', '',{} ],
    o_ => [ 'artifact names - underspecified', '',{} ],
    oa => [ 'artifact names - cultural artifacts (books, movies)', '',{} ],
    oe => [ 'artifact names - measure units', '',{} ],
    om => [ 'artifact names - currency units', '',{} ],
    op => [ 'artifact names - products', '',{} ],
    or => [ 'artifact names - directives, norms', '',{} ],
    P => [ 'personal names', '',{} ],
    p_ => [ 'personal names - underspecified', '',{} ],
    pc => [ 'personal names - inhabitant names', '',{} ],
    pd => [ 'personal names - (academic) titles', '',{} ],
    pf => [ 'personal names - first names', '',{} ],
    pm => [ 'personal names - second names', '',{} ],
    pp => [ 'personal names - relig./myth persons', '',{} ],
    ps => [ 'personal names - surnames', '',{} ],
    T => [ 'time expressions', '',{} ],
    td => [ 'time expressions - days', '',{} ],
    tf => [ 'time expressions - feasts', '',{} ],
    th => [ 'time expressions - hours', '',{} ],
    tm => [ 'time expressions - months', '',{} ],
    ty => [ 'time expressions - years', '',{} ]
  );

=old
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
=cut

my @token_names;
my $tei_fslib_file;
my $tei_fslib_url = 'ne-fslib.xml';

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # tag to string, do not change the database
            'no-backup-file' => \$no_backup_file,
            'filename=s' => \$filename, # input file
            'filelist=s' => \$filelist, # file that contains files to be nametagged (it increase speed of script - NameTag model is inicialized single time)
            'model=s' => \$neotag_model, # neotag model
            'token-name=s' => \@token_names, #
            'tei-fslib=s' => \$tei_fslib_file,
            'tei-fslib-url=s' => \$tei_fslib_url,
            );

@token_names = ('tok') unless @token_names;
my %token_names_h = map {$_ => 1} @token_names;

if($tei_fslib_file) {
  my $fslibDOM = create_fslib($namedEntities);
  if($fslibDOM){
    my $str = $fslibDOM->toString();
    if ( $test ) {
      binmode STDOUT;
      print  $str;
    } else {
      open FILE, ">$tei_fslib_file";
      binmode FILE;
      print FILE $str;
      close FILE;
    };
  }
  exit unless ( $filename  || $filelist );
}

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

  my $re_tok = '(' . join('|', @token_names) . ')';
  unless ( $rawxml =~ /<\/${re_tok}>/ ) {
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
  my $entId = 0;
  my @parents = $doc->findnodes('//*[./*[contains(" '.join(" ", @token_names).' " ,concat(" ",name()," "))]]'); # all parent nodes that contain tokens
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
        my $text = exists $token_names_h{$chnode->nodeName}
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
          my $newnode = new_nametag_element($sorted_entities[$e]->{type},$entId++);
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
  if($tei_fslib_url) {
    my $node = makenode($doc,'//teiHeader/encodingDesc/listPrefixDef/prefixDef[@ident="ne"]');
    $node->setAttribute('ident', 'ne');
    $node->setAttribute('matchPattern', '(.+)');
    $node->setAttribute('replacementPattern', $tei_fslib_url.'#$1');
    $node->appendTextChild('p','Feature-structure elements definition of the Named Entities');
  }
  my $pp = XML::LibXML::PrettyPrint->new(
    indent_string => "  ",
    element => {
        inline   => [qw//], # note
        #block    => [qw//],
        #compact  => [qw//],
        preserves_whitespace => [qw/seg/],
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
      $buname =~ s/\.xml/-$date.nntg.xml/;
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

sub new_nametag_element {
  my $tag = shift;
  my $id = shift;
  #my $ne_conf = $namedEntities{$tag} // $default_ne_conf;

  my $node = XML::LibXML::Element->new('name');

  $node->setAttributeNS($xmlNS, 'id','ne-' . $id);
  $node->setAttribute('ana', "ne:". lc $tag);
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


sub create_fslib {
  my $ents = shift;
  my $dom = XML::LibXML::Document->new("1.0", "UTF8");
  my $root_node =  XML::LibXML::Element->new("div");
  $dom->setDocumentElement($root_node);
  $root_node->setNamespace('http://www.tei-c.org/ns/1.0','tei',0);
  $root_node->setNamespace($xmlNS,'xml',0);
  $root_node->setAttributeNS($xmlNS,'id','ne');
  $root_node->setAttribute('type','part');
  my $fLib = $root_node->addNewChild(undef, 'fLib');
  my $fvLib = $root_node->addNewChild(undef, 'fvLib');
  fill_lib($fLib, $fvLib, feats => [], category => $ents->{'valuesname'}, values => $ents->{'values'});
  return $dom;
}

sub fill_lib {
  my $fLib = shift;
  my $fvLib = shift;
  my %opts = @_;
  return unless exists $opts{'category'};
  return unless exists $opts{'values'};
  for my $key (keys %{$opts{'values'}}){
    my $f = $fLib->addNewChild(undef, 'f');
    $f->setAttribute('name', $opts{'category'});
    $f->setAttributeNS($xmlNS,'id', "f-$key");
    $f->appendTextChild('string', $opts{'values'}->{$key}->{'symbol'});

    my @feats = (@{$opts{'feats'}//[]},"#f-$key");
    my $fs = $fvLib->addNewChild(undef, 'fs');
    $fs->setAttributeNS($xmlNS,'id', "$key");
    $fs->setAttribute('feats', join(' ',@feats));

    fill_lib($fLib, $fvLib, feats => [@feats], category => $opts{'values'}->{$key}->{'valuesname'}, values => $opts{'values'}->{$key}->{'values'});
  }
}

