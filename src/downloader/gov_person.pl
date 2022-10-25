use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use ParCzech::PipeLine::FileManager "gov";

use ScrapperUfal;
use File::Spec;
use File::Path;
use Getopt::Long;

my $URL = 'https://www.vlada.cz';
my $URL_start = "$URL/cz/clenove-vlady/historie-minulych-vlad/prehled-vlad-cr/1993-2007-cr/";
my @gov_urls = ("$URL/cz/vlada/");
my @pers_urls = ();


###############
my $tz = 'Europe/Prague';
my @patterns =       (
                      ['%e. %B %Y','cs_CZ'], # 1. července 2014
                      ['%d.%m.%Y','cs_CZ'], # 30.6.2014
                      ['%d. %m. %Y','cs_CZ'], # 30. 6. 2014
                     );
my @strp_patterns = map {DateTime::Format::Strptime->new(
                      pattern => $_->[0],
                      locale => $_->[1],
                      time_zone =>$tz,
                      on_error => 'undef'
                     )}
               @patterns;
################

my $db_dir = 'out_gov_db';
my $cache_dir;
my $run_date = ScrapperUfal::get_timestamp('%Y%m%dT%H%M%S');
my $debug_level = 0;
my $person_list_in;

Getopt::Long::GetOptions(
  'db=s' => \$db_dir,
  'cache=s' => \$cache_dir,
  'id=s' => \$run_date,
  'debug=i' => \$debug_level,
  'person-list=s' => \$person_list_in,
  );

my $db_out_dir = File::Spec->catdir( $db_dir,$run_date);
File::Path::mkpath($db_out_dir) unless -d $db_out_dir;

if ($cache_dir) {
  my $cache_out_dir = File::Spec->catdir( $cache_dir,$run_date);
  File::Path::mkpath($cache_out_dir) unless -d $cache_out_dir;
  $ENV{SCRAPPER_CACHE} = 1;
  $ScrapperUfal::Browser::cache_dir=$cache_out_dir;
  ScrapperUfal::Browser::use_devel_cache();
}


# load existing urls from person-list
if($person_list_in){
  print STDERR "Adding seen government urls: $person_list_in\n";
  my $personlist = ParCzech::PipeLine::FileManager::XML::open_xml($person_list_in);
  my $xpc = ParCzech::PipeLine::FileManager::TeiFile::new_XPathContext();
  for my $idno ($xpc->findnodes('//tei:person/tei:idno[contains(text(),"vlada.cz")]',$personlist->{dom})) {
    my $url = trim $idno->textContent();
    push @pers_urls,
         [
           $url,
           trim($xpc->findvalue('../tei:persName/tei:surname',$idno)),
           trim($xpc->findvalue('../tei:persName/tei:forename',$idno))
         ] if is_new($url);
  }
}


make_request($URL_start);
if(doc_loaded) {
  my $first=1;
  for my $period_link (grep {m/clenove-vlady/} xpath_string('//div[has(@class,"content-main")]//ul/li/a/@href')){
    my ($pgid) = $period_link =~m/-([0-9]+)\/?$/;
    print STDERR "$period_link\n";
    push @gov_urls, "$URL$period_link" if($first || is_new($pgid));
    undef $first;
  }
}

for my $gov_url (@gov_urls) {
  make_request($gov_url);
  print STDERR "DOWNLOADING: $gov_url\n";
  next unless doc_loaded;
  for my $pers_link (grep {m/clenove-vlady.*-\d+\/?$/} xpath_string('//div[has(@class,"content-main")]//p/a/@href')) {
    push @pers_urls,["$pers_link",'',''] if is_new($pers_link);
  }
}

my $fh;
open($fh,'>:encoding(utf-8)',  File::Spec->catfile($db_out_dir,'gov_osoby.unl')) or die "Cannot open:$!\n";

for my $pers (@pers_urls) {
  my ($pers_link,$sname,$fname) = @$pers;
  $pers_link = "$URL$pers_link" unless $pers_link =~ m/^http/;
  make_request($pers_link);
  print STDERR "DOWNLOADING: $pers_link\n";
  my ($id) = $pers_link =~ m/[^\/]*-([0-9]*)\/?$/;
  next unless is_new("PERSON-$id");
  if( !doc_loaded || xpath_node('//h1[contains(text(),"Zadaná adresa není na našem webu dostupná")]')){
    print $fh "$id||$sname|$fname||||||\n" if $fname and $sname;
    next;
  }
  my $main = xpath_node('//*[has(@class,"content-main")]');
  next unless $main;
  my $persName = xpath_string('./h1[1]',$main);
  my ($before,$forename,$surname,$after) = $persName =~ m/^(.*?)\s*([^\.\s]+)\s+([^\.,]+),?\s*(.*?)$/;
  $surname = trim $surname;
  my ($pers_info) = grep {m/\d\d\d\d/} grep {$_} map {trim $_} xpath_string('.//*[contains(./text(),"Osobní údaje")]/following::p');
  ($pers_info) =  grep {m/\d\d\d\d/} grep {$_} map {trim $_} xpath_string('.//*[contains(./text(),"Osobní údaje")]/following::text()') unless $pers_info;
  my ($female,$birth_date,$birth_place) = ($pers_info//'') =~ m/(?:(?:rodil)|(?:rozen))(a*)\s*(?:se\s+)?(\d+\.\s+[^\s]+\s+\d\d\d\d)(?:\s+v.?\s+([^\.,]*))?/;
  $birth_date = guess_date($birth_date);
  unless($birth_date){
    ($female,$birth_date) = ($pers_info//'') =~ m/(?:(?:rodil)|(?:rozen))(a*)\s*(?:se\s+)?.*?(\d+\.\s+[^\s]+\s+\d\d\d\d)/;
    $birth_date = guess_date($birth_date);
  }
  ($female) = $surname =~ m/(á)$/  unless $birth_date;
  my $sex = $female ? 'F' : 'M';

  print $fh "$id|$before|$surname|$forename|$after|$birth_date|$sex|||\n";
  # save to gov_osoby.unl
}

close($fh);


sub guess_date {
  my $date = shift;
  my $format = shift // '%d.%m.%Y';
  $date = trim $date;
  return '' unless $date;
  my $ret = undef;
  for my $pattern (@strp_patterns){
    eval {$ret = $pattern->parse_datetime($date)};
    last if $ret;
  }
  return '' unless $ret;
  return $ret->strftime($format);
}
