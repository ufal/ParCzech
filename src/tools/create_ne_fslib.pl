use warnings;
use strict;
use utf8;

use Getopt::Long;
use XML::LibXML::PrettyPrint;
use XML::LibXML;



 my $scriptname = $0;

my ($debug, $test, $outfile);

my $xmlNS = 'http://www.w3.org/XML/1998/namespace';
my $teiNS = 'http://www.tei-c.org/ns/1.0';
my $xpc = XML::LibXML::XPathContext->new;
$xpc->registerNs('xml', $xmlNS);
$xpc->registerNs('tei', $teiNS);


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

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # tag to string, do not change the database
            'filename=s' => \$outfile,
            );


my $fslibDOM = create_fslib($namedEntities);
if($fslibDOM){
  my $pp = XML::LibXML::PrettyPrint->new(
    indent_string => "  ",
    element => {
      inline   => [qw//],
      block    => [qw//],
      compact  => [qw/string symbol f/],
      preserves_whitespace => [qw//],
    }
  );
  $pp->pretty_print($fslibDOM);
  my $str = $fslibDOM->toString();
  if ( $test ) {
    binmode STDOUT;
    print  $str;
  } else {
    open FILE, ">$outfile";
    binmode FILE;
    print FILE $str;
    close FILE;
  };
}



sub create_fslib {
  my $ents = shift;
  my $dom = XML::LibXML::Document->new("1.0", "utf-8");
  my $root_node =  XML::LibXML::Element->new("div");
  $dom->setDocumentElement($root_node);
  $root_node->setNamespace($teiNS,'',1);
  $root_node->setNamespace($xmlNS,'xml',0);
  $root_node->setAttributeNS($xmlNS,'id','ne');
  $root_node->setAttribute('type','part');
  my $fLib = $root_node->addNewChild($teiNS, 'fLib');
  my $fvLib = $root_node->addNewChild($teiNS, 'fvLib');
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
    my $f = $fLib->addNewChild($teiNS, 'f');
    $f->setAttribute('name', $opts{'category'});
    $f->setAttributeNS($xmlNS,'id', "f-$key");
    $f->appendTextChild('string', $opts{'values'}->{$key}->{'symbol'});

    my @feats = (@{$opts{'feats'}//[]},"#f-$key");
    my $fs = $fvLib->addNewChild($teiNS, 'fs');
    $fs->setAttributeNS($xmlNS,'id', "$key");
    $fs->setAttribute('feats', join(' ',@feats));

    fill_lib($fLib, $fvLib, feats => [@feats], category => $opts{'values'}->{$key}->{'valuesname'}, values => $opts{'values'}->{$key}->{'values'});
  }
}






















=ccc

my $url = 'http://ufal.mff.cuni.cz/pdt/Morphology_and_Tagging/Doc/hmptagqr.html';
my$xmlNS = 'http://www.w3.org/XML/1998/namespace';

make_request($url, {encoding => 'iso-8859-2'});
exit 1 unless doc_loaded;

my $features = {};

# list of possible values

# getting positional categories
# getting values

for my $pos_item (xpath_node('//table/tr[position() > 1 and count(td) = 3]')) {
  my $pos_num = trim xpath_string('./td[1]', $pos_item);
  my $pos_name = xpath_string('./td[2]/a', $pos_item);
  my $pos_id = xpath_string('./td[2]/a/@href', $pos_item);
  $pos_id =~ s/^#//;
  my $pos_desc = xpath_string('./td[3]', $pos_item);
  $features->{$pos_num} = {
  	id => $pos_id,
    position => $pos_num,
    name => $pos_name,
    desc => $pos_desc,
    values => {}
  };
  my $values = $features->{$pos_num}->{values};
  for my $val_item (xpath_node('//h3[a/@name="'.$pos_id.'"]/following-sibling::table[1]/tr[position() > 1]')) {
  	my $val = xpath_string('./td[1]', $val_item);
  	my $val_desc = xpath_string('./td[2]', $val_item);
    $values->{$val} = {desc => $val_desc};
  }
}

my $dom = XML::LibXML::Document->new("1.0", "utf-8");
my $root_node =  XML::LibXML::Element->new("div");
$dom->setDocumentElement($root_node);
$root_node->setNamespace('http://www.tei-c.org/ns/1.0','',1);
$root_node->setNamespace($xmlNS,'xml',0);
$root_node->setAttributeNS($xmlNS,'id','pdt');
$root_node->setAttribute('type','part');
my $fLib = $root_node->addNewChild(undef, 'fLib');
my $fvLib = $root_node->addNewChild(undef, 'fvLib');



my @positions = sort { $a <=> $b } keys %$features;

for my $pos_num (@positions) {
  for my $val_id (sort keys %{$features->{$pos_num}->{values}}) {
    my $f = $fLib->addNewChild(undef, 'f');
    $f->setAttribute('name', $features->{$pos_num}->{name});
    $f->setAttributeNS($xmlNS,'id', encode_id(sprintf('p%02dv%s', $pos_num, $val_id)));
    $f->addNewChild(undef,'string')->appendText($features->{$pos_num}->{values}->{$val_id}->{desc});
  }
}

for my $tag (@{Lingua::Interset::list('cs::pdt')}) {
  my $fs = $fvLib->addNewChild(undef, 'fs');
  $fs->setAttributeNS($xmlNS,'id', encode_id($tag));
  $fs->setAttribute('feats', join(' ', map {sprintf('#p%02dv%s',$_,encode_id(substr($tag,$_-1,1)))} grep {not(substr($tag,$_-1,1) eq '-') } @positions));
  my $f = $fs->addNewChild(undef,'f');
  $f->setAttribute('name','pdt');
  $f->addNewChild(undef,'symbol')->setAttribute('value',"$tag");
}

my $pp = XML::LibXML::PrettyPrint->new(
  indent_string => "  ",
  element => {
      inline   => [qw//],
      block    => [qw//],
      compact  => [qw/string symbol f/],
      preserves_whitespace => [qw//],
      }
  );
$pp->pretty_print($dom);
my $str = $dom->toString();
binmode STDOUT;
print  $str;


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