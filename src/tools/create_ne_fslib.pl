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

