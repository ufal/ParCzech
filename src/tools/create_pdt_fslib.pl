use warnings;
use strict;
use utf8;

use lib './downloader/lib';

use ScrapperUfal;
use Getopt::Long;
use XML::LibXML::PrettyPrint;
use XML::LibXML;
use Lingua::Interset;


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