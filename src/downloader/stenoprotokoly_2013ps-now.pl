use warnings;
use strict;
use ScrapperUfal;
use utf8;
use URI::QueryParam;
use File::Spec;
use File::Path;
use TEI::ParlaClarin::TEI;
use TEI::ParlaClarin::teiCorpus;
use ParCzech::WebTools::Audio;
use Getopt::Long;
use Data::Dumper;

use XML::LibXML qw(:libxml);

=description
This scrapping script works only for terms from 2013
=cut



my $URL = 'https://www.psp.cz';
my $URL_start = "$URL/eknih/index.htm";

my $tei_dir = 'out_tei';
my $yaml_dir = 'out_tei';
my $cache_dir;
my $run_date = ScrapperUfal::get_timestamp('%Y%m%dT%H%M%S');
my $prune_regex = undef;
my $debug_level = 0;
my $GuessAudioLink = ParCzech::WebTools::Audio->new(debug => 1);

my $config = {
  title => [
    {
      type => 'main',
      text => {
        cs => 'Český parlamentní korpus, Poslanecká sněmovna',
        en => 'Czech parliamentary corpus, Chamber of Deputies'
      }
    },
    {
      type => 'sub',
      text => {
        cs => 'Parlament České republiky, Poslanecká sněmovna',
        en => 'Parliament of the Czech Republic, Chamber of Deputies'
      }
    }
  ],
  titleSuffix => '[ParCzech]',
  place => [
    {
      text => 'Parlament České republiky - Poslanecká sněmovna',
      attr => {
        type => 'org',
      }
    },
    {
      text => 'Sněmovní 176/4',
      attr => {
        type => 'address',
      }
    },
    {
      text => 'Praha',
      attr => {
        type => 'city',
      }
    },
    {
      text => 'Czech Republic',
      attr => {
        type => 'country',
        key => 'CZ'
      }
    }
  ],
  anaExtend => {
    map {("#parla.$_" => "#parla.lower")} qw/term meeting sitting agenda/
  }
};


Getopt::Long::GetOptions(
  'tei=s' => \$tei_dir,
  'yaml=s' => \$yaml_dir,
  'cache=s' => \$cache_dir,
  'id=s' => \$run_date,
  'prune=s' => \$prune_regex,
  'debug=i' => \$debug_level
  );

my $yaml_file_path = File::Spec->catfile( $yaml_dir,"$run_date.yml");

my $tei_out_dir = File::Spec->catdir( $tei_dir,$run_date);
File::Path::mkpath($tei_out_dir) unless -d $tei_out_dir;

File::Path::mkpath($yaml_dir) unless -d $yaml_dir;
ScrapperUfal::set_export_output($yaml_file_path);

if ($cache_dir) {
  my $cache_out_dir = File::Spec->catdir( $cache_dir,$run_date);
  File::Path::mkpath($cache_out_dir) unless -d $cache_out_dir;
  $ENV{SCRAPPER_CACHE} = 1;
  $ScrapperUfal::Browser::cache_dir=$cache_out_dir;
  ScrapperUfal::Browser::use_devel_cache();
}


sub DEBUG {
  print STDERR "\n\t",join("\n\t",map {ref($_) ? (ref($_) eq 'ARRAY' ? join(' ',@$_):$_) : $_} @_),"\n";
}

my $tz = 'Europe/Prague';
my $strp = DateTime::Format::Strptime->new(
  pattern   => '%e. %B %Y %H:%M',
  locale    => 'cs_CZ',
  time_zone => 'Europe/Prague'
);

my $strp_act = DateTime::Format::Strptime->new(
  pattern   => '%e. %m. %Y v %H:%M',
  locale    => 'cs_CZ',
  time_zone => 'Europe/Prague'
);

my $strp_sit = DateTime::Format::Strptime->new(
  pattern   => '%e. %B %Y',
  locale    => 'cs_CZ',
  time_zone => 'Europe/Prague'
);

my $re_schuze = qr/\([^\(\)]*(?:Schůze|Jednání)\s*/;
my $re_zacatek = qr/(?:začal[ao]|zahájen[ao]|pokračoval[ao]|pokračuje)\s*/;
my $re_konec = qr/(?:skončil|skončen|ukončen)[ao]\s*/;
my $re_prerus = qr/přerušen[ao]\s*/;
my $re_cas = qr/\s*(?:v|ve|do|od)?\s*(\d+)[\.:]\s*(\d+)?\s*(?:hodin|hod\.|h\.|do|\.|min|\))/;


my @URLs_parlament;
my @steno_voleb_obd;
my @steno_sittings;
my @steno_topic_anchor;
my @steno_topic_links;
my @day_audio_page_links; # list of urls that contain audio_links
my %day_audio_links = (); # stores audio links - page -> audio_link


my %date_to_patch = (
  '2017ps 002' => {
    text => 'Úterý 28. listopadu 2017',
    from => 2, # inclusive
    to => 26 # exclusive
  },
  '2017ps 005' => {
    text => 'Středa 10. ledna 2018',
    from => 2, # inclusive
    to => 44 # exclusive
  },
  '2017ps 012' => {
    text => 'Úterý 10. dubna 2018',
    from => 2, # inclusive
    to => 31 # exclusive
  },
  '2017ps 031' => {
    text => 'Středa 29. května 2019',
    from => 3, # inclusive
    to => 31 # exclusive
  },
  '2017ps 035' => {
    text => 'Úterý 15. října 2019',
    from => 2, # inclusive
    to => 40 # exclusive
  },
  '2017ps 049' => {
    text => 'Úterý 26. května 2020',
    from => 6, # inclusive
    to => 48 # exclusive
  },
);

my %link_patcher_data = (
  #'start_sitting|https://www.psp.cz/eknih/2017ps/stenprot/002schuz/s002002.htm' => 'https://www.psp.cz/eknih/2017ps/stenprot/002schuz/s002026.htm',
  #'start_sitting|https://www.psp.cz/eknih/2017ps/stenprot/005schuz/s005002.htm' => 'https://www.psp.cz/eknih/2017ps/stenprot/005schuz/s005044.htm',
  #'start_sitting|https://www.psp.cz/eknih/2017ps/stenprot/012schuz/s012002.htm' => 'https://www.psp.cz/eknih/2017ps/stenprot/012schuz/s012031.htm',
  #'start_sitting|https://www.psp.cz/eknih/2017ps/stenprot/031schuz/s031003.htm' => 'https://www.psp.cz/eknih/2017ps/stenprot/031schuz/s031032.htm',
  #'start_sitting|https://www.psp.cz/eknih/2017ps/stenprot/035schuz/s035002.htm' => 'https://www.psp.cz/eknih/2017ps/stenprot/035schuz/s035040.htm',
  #'start_sitting|https://www.psp.cz/eknih/2017ps/stenprot/049schuz/s049006.htm' => 'https://www.psp.cz/eknih/2017ps/stenprot/049schuz/s049048.htm',
  );

my $unauthorized = JSON::from_json(ScrapperUfal::get_note('unauthorized')||'{}');
my $new_unauthorized = {};


my $teiCorpus = TEI::ParlaClarin::teiCorpus->new(
                                                  id => "ParCzech-$run_date",
                                                  output_dir => $tei_out_dir,
                                                  title => $config->{title},
                                                  place => $config->{place},
                                                  anaExtend => $config->{anaExtend}
                                                );

# loop through terms
for my $row (xpath_node('//*[@id="main-content"]/table/tr',$URL_start)) {
  my $link = xpath_string('./td[2]/a/@href',$row);
  my $header = xpath_string('./td[2]/a',$row);
  my ($from, $notequal,$to) = xpath_string('./td[1]',$row) =~ m/(\d{4})\s*(-?)\s*(\d*)/;
  $to = $from unless $notequal;
  $link = $URL.$link;
  push @URLs_parlament, $link if $from >= 2013 and $link =~ m/\/\d{4}ps\//;
}

# get stenoprotocols link for each terms
for my $ps_link (@URLs_parlament) {
  make_request($ps_link);
  next unless doc_loaded;
  push @steno_voleb_obd,URI->new_abs($_,$ps_link) for (xpath_string('//*[@id="main-content"]/b/a[text() = "Stenoprotokoly"]/@href'));
}

# get sittings
# example input https://www.psp.cz/eknih/2013ps/stenprot/index.htm
my @meetings_with_wrong_sitting_link;
for my $sch_link (@steno_voleb_obd) {
  make_request($sch_link);
  debug_print( "Getting sittings from $sch_link", __LINE__);
  my ($term_id) = $sch_link =~ m/(\d{4})ps/;
  next unless doc_loaded;
  for my $meeting_node (xpath_node('//*[@id="main-content"]/a[./b]')) {
=node
    <a href="001schuz/index.htm"><b>1. schůze</b></a>
=cut
    my $meeting_link = URI->new_abs($meeting_node->getAttribute('href'),$sch_link);
    my ($meeting_id) = $meeting_link =~ m/(\d\d\d)schuz/;
    $meeting_id .= 'psse' if $meeting_link =~ m/psse/;
    my @sittings_links = grep {m/-(\d+)\.htm/} xpath_string('./following-sibling::a[contains(@href,"'.$meeting_id.'schuz")]/@href',$meeting_node);
=sittings
    (<a href="001schuz/1-1.html">25.</a>, <a href="001schuz/1-2.html">27.&nbsp;listopadu&nbsp;2013</a>)
=cut
    unless (@sittings_links) {
      debug_print( "Missing sitting links for $term_id-$meeting_id -> getting links from $meeting_link", __LINE__);
      push @meetings_with_wrong_sitting_link, [$meeting_link, $term_id, $meeting_id]
    }
    for my $sitting_link (@sittings_links) {
      $sitting_link = URI->new_abs($sitting_link,$sch_link);
      my ($sitting_id) = $sitting_link =~ m/-(\d+)\.htm/;
      $sitting_id = sprintf("%02d",$sitting_id);
      debug_print( "\tnew sitting ".join('-', $term_id, $meeting_id, $sitting_id)."\t$sitting_link", __LINE__);

      push @steno_sittings, [$sitting_link, $term_id, $meeting_id, $sitting_id] if defined($prune_regex) || is_new($sitting_link,1) || exists $unauthorized->{$term_id}->{$meeting_id}->{$sitting_id};
    }
=special_sittings
get all "strange" lings following meeting and preceding next meeting
<a href="025schuz/index.htm"><b>25. schůze</b></a> (<a href="025schuz/25-1.html">31.&nbsp;května</a>, <a href="025schuz/25-2.html">1.</a>, <a href="025schuz/25-3.html">2.</a>, <a href="025schuz/25-4.html">3.</a>, <a href="025schuz/25-5.html">14.</a>, <a href="025schuz/25-6.html">15.</a>, <a href="025schuz/25-7.html">16.</a>, <a href="025schuz/25-8.html">17.&nbsp;června&nbsp;2022</a>)
<br>
&nbsp;&nbsp;&nbsp;<a href="220615/">Vystoupení prezidenta Ukrajiny Volodymyra Zelenského před oběma komorami Parlamentu České republiky</a>
<br>
=cut
    my @spec_sittings_links = grep {m/^\d{6}\/$/} xpath_string('./following-sibling::br[1]/following-sibling::a[contains(./preceding-sibling::a[contains(@href,"schuz")][1]/@href,"'.$meeting_id.'schuz")]/@href',$meeting_node);
    for my $spec_sitting_link (@spec_sittings_links) {
      $spec_sitting_link = URI->new_abs($spec_sitting_link,$sch_link);
      my ($sitting_id) = $spec_sitting_link =~ m/(\d{6})\//;
      $sitting_id = sprintf("%06d",$sitting_id);
      debug_print( "\tnew sitting ".join('-', $term_id, '000', $sitting_id)."\t$spec_sitting_link", __LINE__);

      push @meetings_with_wrong_sitting_link, [$spec_sitting_link, $term_id, '000', $sitting_id] if defined($prune_regex) || is_new($spec_sitting_link,1) || exists $unauthorized->{$term_id}->{'000'}->{$sitting_id};
    }
  }
}


# loop through meetings with wrong sitting link
for my $meeting (@meetings_with_wrong_sitting_link){
  my ($meeting_link, $term_id, $meeting_id) = @$meeting;
  make_request($meeting_link);
  next unless doc_loaded;
  my @sittings_links = grep {m/\d+-\d+\.html?/} xpath_string('//div[@id="main-content"]/div[@class="page-title"]/following-sibling::br[1]/preceding-sibling::a/@href');
  for my $sitting_link (@sittings_links) {
    $sitting_link = URI->new_abs($sitting_link,$meeting_link);
    my ($sitting_id) = $sitting_link =~ m/-(\d+)\.htm/;
    $sitting_id = sprintf("%02d",$sitting_id);
    debug_print( "\tnew sitting ".join('-', $term_id, $meeting_id, $sitting_id)."\t$sitting_link", __LINE__);

    push @steno_sittings, [$sitting_link, $term_id, $meeting_id, $sitting_id] if defined($prune_regex) || is_new($sitting_link,1) || exists $unauthorized->{$term_id}->{$meeting_id}->{$sitting_id};
  }
}

# loop through sittings
# example input link: https://www.psp.cz/eknih/2013ps/stenprot/012schuz/12-1.html
for my $steno_s (@steno_sittings) {
  my ($sitting_link, $term_id, $meeting_id, $sitting_id) = @$steno_s;
  if(defined $prune_regex){
    unless(join('-',$term_id, $meeting_id, $sitting_id) =~ m/^$prune_regex/) {
      print STDERR "prunning: ",join('-',$term_id, $meeting_id, $sitting_id),"\n";
      next;
    }
  }
  make_request($sitting_link);
  next unless doc_loaded;
  debug_print( "Getting sitting page " .join('-', $term_id, $meeting_id, $sitting_id)."\t$sitting_link", __LINE__);

  # get opening speeches link
  my ($topic_anchor_link,$anchor) = xpath_string('//*[@id="main-content"]/a[starts-with(./@href,"s")][1]/@href') =~ m/(.*)#(.*)/;
  debug_print( "\topening " .join('-', $term_id, $meeting_id, $sitting_id, ''), __LINE__);
  my $first_sitting_speech_link = URI->new_abs($topic_anchor_link,$sitting_link);
  link_patcher('start_sitting|',\$first_sitting_speech_link);

  push @steno_topic_anchor,[$first_sitting_speech_link,$term_id, $meeting_id, $sitting_id, '', 0];

  my $date = trim xpath_string('//h1[@class="page-title-x"]');
  if($date) {
    $date =~ s/^.*,\s*//;
    $date = $strp_sit->parse_datetime($date);
    my ($audio_link_prefix) = $sitting_link =~ m/^(.*)\/stenprot.*/;
    push @day_audio_page_links, "$audio_link_prefix/audio/". $date->strftime('%Y/%m/%d') .'/index.htm';
  }
}

for my $day_audio_page_link (@day_audio_page_links) {
  make_request($day_audio_page_link);
  next unless doc_loaded;
  for my $item (xpath_node('//tr/td[last()][./a/@href]')){
    my $text_link = xpath_string('./a/@href',$item);
    next unless $text_link =~ m/s\d{6}.htm/;
    my $mp3_link = xpath_string('./preceding-sibling::td[1]/a/@href',$item);
    next unless $mp3_link =~ m/mp3$/;
    $day_audio_links{URI->new_abs($text_link, $day_audio_page_link)->as_string} = URI->new_abs($mp3_link, $day_audio_page_link)->as_string;
  }
}

my $author = {};
my $post = {};
my $topic_cntr = 0;
my $akt_sitting = '';
my $last_sitting_date;
my %seen_topics;
my $teiFile;


while(my $steno_top = shift @steno_topic_anchor) { # order is important !!!
  my ($page_link,$term_id, $meeting_id, $sitting_id, $topic_id) = @$steno_top;
  make_request($page_link);
  debug_print( " -> LOADING \t$page_link", __LINE__, -1);
  next unless doc_loaded;
  next if(xpath_node('//*[@id="main-content"]/h3[contains(./text(),"nebyl dosud přepsán.")]'));
  html_patcher($page_link);
  my $sitting_date = trim xpath_string('//*[@id="main-content"]/*[has(@class,"document-nav")]/p[@class="date"]');

  if($sitting_date){
    $sitting_date =~ s/^[^ ]* //;
    $sitting_date = $strp->parse_datetime("$sitting_date 00:00");
  }
  if($topic_id eq ''){
    $topic_id = '000';
    debug_print( "downloading new sitting " .join('-', $term_id, $meeting_id, $sitting_id, $topic_id), __LINE__);
    export_TEI();
    $author = {};
    debug_print( "NEW TEI, cleaning author", __LINE__, 5);
    init_TEI($term_id, $meeting_id, $sitting_id, $topic_id);
  } elsif (defined($last_sitting_date) && $sitting_date != $last_sitting_date) {
    next;
  }
  $last_sitting_date = $sitting_date;
  $post->{link} = $page_link;
  $post->{id}->{term} = $term_id;
  $post->{id}->{meeting} = $meeting_id;
  $post->{id}->{sitting} = $sitting_id;
  $post->{id}->{topic} = $topic_id;


  # get whole page
  $topic_id = record_exporter($page_link, \$author,\$post) // $topic_id;

  # add next page if exists
  # push @steno_topic_anchor,[$link,'',1,0,$term_id, $meeting_id, $sitting_id, $topic_id];
  my $url_next = xpath_string('//*[@id="main-content"]/*[has(@class,"document-nav")]//a[@class="next"]/@href');
  if($url_next) {
    debug_print( "\tadding page (link):\t" .join('-', $term_id, $meeting_id, $sitting_id, $topic_id)."\t$page_link", __LINE__);
    unshift @steno_topic_anchor,[URI->new_abs($url_next,$page_link),$term_id, $meeting_id, $sitting_id, $topic_id];
  } else { # guessing next page
    my $number;
    ($url_next,$number) = $page_link =~ m/(.*schuz\/s.*)(\d\d\d).htm$/;
    if($url_next) {
      $number = int($number) + 1;
      debug_print( "\tadding page (guess):\t" .join('-', $term_id, $meeting_id, $sitting_id, $topic_id)."\t$number", __LINE__);
      unshift @steno_topic_anchor,[URI->new_abs($url_next.sprintf("%03d.htm",$number),$page_link), $term_id, $meeting_id, $sitting_id, $topic_id];
    }
  }
  ScrapperUfal::set_note('unauthorized',JSON::to_json($new_unauthorized));
}
ScrapperUfal::set_note('unauthorized',JSON::to_json($new_unauthorized));

####################################################################################################

sub record_exporter {
  my ($link, $ref_author, $ref_post) = @_;
  my $topic_id;
  my $datetime;
  my $act_date;
  my $pagedate;

  if($act_date=xpath_string('//*[@id="main-content"]/p[@class = "status"]')) {
  	$act_date =~ s/^[^\d]*//;
  	$act_date =~ s/[^\d]*$//;
  	$act_date = $strp_act->parse_datetime(trim $act_date);
  	unless(set_document_date($act_date)) {
  	  return 0; # if not new - do not export and do not follow next page !!!
  	}
  }

  add_pagebreak_and_audio_to_teiFile($link);  # add audio if possible
  my ($link_id) = $link =~ m/s(\d*)\.htm$/;

  my $date = trim xpath_string('//*[@id="main-content"]/*[has(@class,"document-nav")]/p[@class="date"]/a');
  if($date){
    $date =~ s/^[^ ]* //;
    $datetime = $strp->parse_datetime("$date 00:00");
    $teiFile->addSittingDate($datetime);
  }

  for my $cnt (xpath_node('//*[@id="main-content"]/*[not(has(@class,"document-nav"))] | //*[@id="main-content"]/text()')) {
  	my $cnt_html = trim dump_html($cnt);
    my $cnt_text =trim ScrapperUfal::html2text($cnt);
    if($topic_id = xpath_node('./a[../@class="media-links" and @class="bqbs"]/@href',$cnt)){ # end condition, record will be exported within next make_request iteration
      export_TEI();

      # NEW TOPIC !!!
      $topic_id =~ s/^.*b\d\d\d(\d\d\d)\d\d\.htm.*/$1/;
      ${$ref_post}->{id}->{topic} = $topic_id;
      init_TEI( map {${$ref_post}->{id}->{$_} } qw/term meeting sitting topic/ );
      add_pagebreak_and_audio_to_teiFile($link); # add audio if possible
      $teiFile->addPageTime($pagedate) if $pagedate;
      $teiFile->addSittingDate($datetime) if $datetime;
      debug_print( "  UTTERANCE " .($$ref_author->{authorname}), __LINE__, 5);
      my $id = $teiFile->addUtterance(
        author => {
          author_full => $$ref_author->{author},
          name => $$ref_author->{authorname},
          id => $$ref_author->{author_id},
          govern_id => $$ref_author->{auth_govern_id},
          role => $$ref_author->{role},
          link => $$ref_author->{link},
        },

       # link =>  $$ref_post->{link}.'#'.($$ref_post->{id}->{post}//'')
      );

    }
    if(my $status_str = xpath_string('.//strong[contains(text(), "eautorizováno !" )]',$cnt) ) { # Neautorizováno or neautorizováno
      set_current_tei_unauthorized($status_str, $act_date);
    } elsif (my $s = xpath_string('./@class',$cnt) eq "status") {
      next;
    } elsif (my $mp3 = xpath_string('./a[@class = "audio"]/@href',$cnt)) {
      print STDERR "THIS SHOULD NOT HAPPEN: AUDIO: ",URI->new_abs($mp3,$link),"\n";
      # $teiFile->addAudioNote(url => URI->new_abs($mp3,$link));
      next;
    } elsif (xpath_string('./text()',$cnt) =~ /^\s*\*\*\*\s*$/) {
      next;
    } elsif ($cnt_html =~ m/^\s*<br\s*\/?>\s*$/) {
      next;
    } elsif ($cnt_html =~ m/\([Pp]okračuje\s+\b.*?\b\)/) {
      next;
    } elsif ($cnt_html =~ m/\(${re_cas}\)/) { # speaker continue
      my $texttime = $&;
      my $time = "$1:".($2//'00');
      $datetime = $strp->parse_datetime("$date $time");
      my $noteNode = $teiFile->createTimeNoteNode(when=>$datetime, texttime=>$texttime);
      $pagedate = $datetime->clone();
      $teiFile->addToElemsQueue($noteNode);
      $$ref_post->{date} = $datetime;
      next;
    } elsif ($cnt_html =~ m/${re_schuze}.*${re_prerus}${re_cas}.*\)/) {
      my $texttime = $&;
      my $time = "$1:".($2//'00');

      $datetime = $strp->parse_datetime("$date $time");
      $teiFile->addTimeNote(when=>$datetime, texttime=>$texttime);
      next;
    } elsif ($cnt_html =~ m/${re_schuze}.*${re_konec}${re_cas}.*\)/) {
      my $texttime = $&;
      my $time = "$1:".($2//'00');


      $datetime = $strp->parse_datetime("$date $time");
      $teiFile->addTimeNote(when=>$datetime, texttime=>$texttime);
    } elsif ($cnt_html =~ m/${re_schuze}.*${re_zacatek}${re_cas}.*\)/) {
      my $texttime = $&;
      my $time = "$1:".($2//'00');

      $datetime = $strp->parse_datetime("$date $time");
      $pagedate = $datetime->clone();
      $teiFile->addTimeNote(when=>$datetime, texttime=>$texttime);
      next;
    } elsif(my $a = xpath_node('./b[not(../@align = "center" or ../@align = "CENTER" ) and (.//a or starts-with(text(),"Poslan"))]',$cnt)
                   ## patching obscure utterances (https://www.psp.cz/eknih/2013ps/stenprot/036schuz/s036311.htm)
                   // xpath_node( './a[position() = 1 and not (starts-with(@href,"/") or contains(@href,"psp.cz/") ) and following-sibling::text()[1][starts-with(., ":")]]',$cnt)) { # new utterance
      # fill new utterance
      my $auth;
      my $auth_id;
      my $govern_id;
      my $post_id;
      my $auth_link;

      if ($a) {
        $auth =  trim xpath_string('.//* | ./text()',$a);
        ($auth_id) = (xpath_string('.//@href',$a)||'') =~ m/id=(\d+)/;
        ($govern_id) = (xpath_string('.//@href',$a)||'') =~ m/clenove-vlady.*\/(.*?)\//;
        $post_id = xpath_string('.//@id',$a);
        $auth_link = xpath_string('.//@href',$a) unless $auth_id || $govern_id;
        $a->unbindNode();
        $cnt_text = ScrapperUfal::html2text($cnt);
      }
      $cnt_text =~ s/\s*:?\s*//; # remove initial : and spaces

      ($$ref_author->{authorname}) = $auth =~ m/([^ ]*\s+[^ ]+?):?$/;
      $$ref_author->{author} = $auth;
      $$ref_author->{author_id} = $auth_id;
      $$ref_author->{auth_govern_id} = $govern_id;
      $$ref_author->{link} = $auth_link;
      $$ref_author->{role} = get_role($$ref_author->{author});
      ### ($$ref_post->{speechnote}) = grep {m/^###.*|\@\@$/} xpath_string('./comment()',$cnt); # not at this page
      $$ref_post->{id}->{post} = $post_id;
      $$ref_post->{id}->{post} = 'r0' unless exists $$ref_post->{id}->{post};
      debug_print( "  UTTERANCE " .($$ref_author->{authorname}), __LINE__, 5);
      my $id = $teiFile->addUtterance(
        author => {
          author_full => $$ref_author->{author},
          name => $$ref_author->{authorname},
          id => $$ref_author->{author_id},
          govern_id => $$ref_author->{auth_govern_id},
          role => $$ref_author->{role},
          link => $$ref_author->{link},
        },
        link =>  $$ref_post->{link}.'#'.($$ref_post->{id}->{post}//'')
      );
      export_text($cnt, 1);
      export_record_yaml(
        id => $id,
        url => $$ref_post->{link}.'#'.($$ref_post->{id}->{post}//''),
        type => 'speech',
        author => $$ref_author->{author} // undef,
        author_name => $$ref_author->{authorname} // undef,
        author_id => $$ref_author->{author_id} // $$ref_author->{auth_govern_id} // undef,
        topic_id => join("-",map {$$ref_post->{id}->{$_} // ''} qw/term meeting sitting topic/) // undef,
        #speech_note => $$post->{speechnote} // undef,
        date => $datetime // undef,
        );




    } elsif($cnt_text) {
      my %header_opts = ();
      if($cnt->nodeType == XML::LibXML::XML_ELEMENT_NODE && lc($cnt->getAttribute('align')//'') eq 'center'){
        $teiFile->addHead($cnt_text);
        $cnt = xpath_node('./b', $cnt) // $cnt;
        %header_opts = (no_note => 1);
      }
      export_text($cnt, 1,%header_opts);
    }
  }
  return $topic_id;
}

export_TEI();
$teiCorpus->addSourceDesc();
$teiCorpus->addTitleSuffix(' '.$config->{titleSuffix}, type=>'main', lang=>undef);
$teiCorpus->toFile();


sub html_patcher {
  my $link = shift;
  unless (doc_loaded){
    print STDERR "document is not loaded, unable to patch: $link\n";
    return;
  }
  return if $link =~ m/\/\d{6}\//; # skipping patching special meeting links
  my ($term, $meeting, $part) = $link =~ m/(\d+ps)\/stenprot\/.*\/s(\d\d\d)(\d\d\d).htm$/;
  my $patched = date_patcher($link, $term,$meeting,$part);
  return $patched;
}

sub date_patcher {
  my ($link, $term, $meeting, $part) = @_;
  return unless defined $date_to_patch{"$term $meeting"};
  if($date_to_patch{"$term $meeting"}->{from} <= $part
    && $date_to_patch{"$term $meeting"}->{to} > $part ){
    print STDERR "PATCHING: $link\n";
    my $node = xpath_node('//*[@id="main-content"]/*[has(@class,"document-nav")]/p[@class="date"]/a');
    #my $text = "Úterý 28. listopadu 2017";
    my $text = $date_to_patch{"$term $meeting"}->{text};
    print STDERR "\t'",$node->textContent(),"' -> '$text'\n";
    $node->removeChildNodes();
    $node->appendText( $text );
    undef $day_audio_links{$link}; # removing audio link from list of known pairing
    $_->unbindNode() for (xpath_node('//div[@class="aside"]//ul[@class="link-list"]/li[contains(text(),"MP3")]/a')); # remove wrong link from DOM
    return 1;
  }
}

sub link_patcher {
  my ($type,$link_ref) = @_;
  if(defined $link_patcher_data{"$type$$link_ref"}) {
    print STDERR "PATCHING LINK: $$link_ref -> ",$link_patcher_data{"$type$$link_ref"},"\n";
    $$link_ref = $link_patcher_data{"$type$$link_ref"};
  }
}

sub add_pagebreak_and_audio_to_teiFile {
  my $link = shift;
  my $mp3link;
  if(my $page_mp3_url = xpath_string('//div[@class="aside"]//ul[@class="link-list"]/li[contains(text(),"MP3")]/a/@href')){
    $mp3link = URI->new_abs($page_mp3_url, $link);
  } else { # get mp3 link from mp3file list page
    $mp3link = $day_audio_links{$link->as_string} if $day_audio_links{$link->as_string};
  }
  $teiFile->addPageBreak(source => $link, audiolink => $mp3link);
}

sub init_TEI {
  my ($term_id, $meeting_id, $sitting_id, $topic_id) = @_;
  my $sitting_pref = sprintf('ps%d-%03d-%02d',$term_id, $meeting_id, $sitting_id );
  unless ($akt_sitting eq $sitting_pref) {
    $topic_cntr = 0;
    $akt_sitting = $sitting_pref;
  }
  my $new_doc_id = sprintf('%s-%03d-%03d',$sitting_pref, $topic_cntr, $topic_id );
  debug_print( "NEW DOCUMENT $new_doc_id " .join('-', $term_id, $meeting_id, $sitting_id, $topic_id), __LINE__, -1);
  $teiFile = TEI::ParlaClarin::TEI->new(id => $new_doc_id, output_dir => $tei_out_dir,
                                          title => $config->{title},
                                          place => $config->{place},
                                          anaExtend => $config->{anaExtend}
                                          );
}

sub export_TEI {
  if($teiFile && !$teiFile->isEmpty()) {
    my ($term) = map {s/^([a-z]*)(\d*)$/$2$1/; $_} @{$teiFile->getMeetings('#parla.term')};
    $GuessAudioLink->set_term_id($term);
    for my $page ($teiFile->getPages) {
      unless ($page->{has_audio}) {
        print STDERR "looking for audio for (".($page->{from}//'?DATE?').") $page->{link}\n";
        my $audiolink;
        if($page->{from}){
          $audiolink = $GuessAudioLink->get_audio_link($page->{from});
          if(defined $audiolink) {
            print STDERR "\taudio: $audiolink\n";
          } else {
            print STDERR "\taudio - looking to previous 10 minutes\n";
            $audiolink = $GuessAudioLink->get_audio_link($page->{from}->subtract(minutes => 10)) unless $audiolink; # look to previeous audio - can be overlap
             print STDERR "\t\taudio found $audiolink\n" if $audiolink;
          }
        }
        $teiFile->addAudio(page_number=>$page->{number}, audio_link=>$audiolink) if defined $audiolink;
      }
    }
    $teiFile->addSourceDesc();
    $teiFile->addTitleSuffix(sprintf(', %s %s %s',$teiFile->getFromDate()->strftime('%Y-%m-%d'), $teiFile->teiID(),$config->{titleSuffix}), type=>'main', lang=>undef);
    my $filepath = $teiFile->toFile();
    debug_print( "SAVING DOCUMENT TO $filepath", __LINE__, -1);
    $teiCorpus->addTeiFile($filepath, $topic_cntr,$teiFile);
    $topic_cntr++;

   # print STDERR "otestovat jestli se soubor změnil -> md5\n";
   # print STDERR "vyřešit verzování -> když se změní jen některý soubor z jednání -> problém se suffixem, který se automaticky upravuje\n";
   # print STDERR "skript, který bude přesouvat aktualizované a oanotované soubory jinam. Vůči nim se bude provádět kontrola na existenci??? Jak zaznamenávat změny - více verzí ";
  } else {
    debug_print( "EMPTY DOCUMENT OR UNDEFINED - NOT SAVING", __LINE__, -1)
  }
  undef $teiFile;
}


sub set_current_tei_unauthorized {
  my $str = shift;
  my $date = shift;
  my $id = $teiFile->teiID();
  $teiFile->setUnauthorizedFlag($str);
  my $h = $new_unauthorized;
  for my $p (split("-", $id)) {
  	$h = $h->{$p} = {};
  }
}

sub set_document_date {
  my $date = shift;
  my $id = $teiFile->teiID();
  return unless is_new($id, $date);
  $teiFile->setActDate($date);
}

sub export_text {
  my $cnt = shift;
  my $is_first = shift; # remove initial : if true
  my %opts = @_;
  # my $text = shift;
  # start <seg>
  my @child_nodes;
  my $segm = undef;
  if($cnt->nodeType() == XML_TEXT_NODE){
    push @child_nodes, $cnt;
  } else {
    @child_nodes = $cnt->childNodes();
  }
  for my $childnode (@child_nodes) {
    if(xpath_node('./self::*[name()="a"]', $childnode)) { # link that should be appended
      $segm = $teiFile->addToUtterance(create_ref_node($childnode),$segm);
    } else { # text or text in node that is not converted
      my $text = ScrapperUfal::html2text($childnode); # returns empty string if it contains only spaces !!!
      $text =~ s/\N{NO-BREAK SPACE}/ /g;
      $text = ' ' if ($text eq '') and ! ($childnode->toString() eq '');
      $text =~ s/\s*\*\*\*\s*$//; # remove triple asterisk from the end of paragraph
      $text =~ s/\s*:?\s*// if $is_first; # remove initial : and spaces
      $text =~ s/\s\s+/ /g ; # squeeze spaces
      if(defined $opts{no_note}){
        $segm = $teiFile->addToUtterance($text,$segm);
        $text = '';
      }
      debug_print("TEXT: $text",__LINE__,10);
      while($text){
        if($text =~ s/^\s+//) {
          $teiFile->addToElemsQueue($&);
        } elsif($text =~ s/^[^\(]*[^\(\s]//){ # text without last space
          $segm = $teiFile->addToUtterance($&,$segm);
        } elsif ($text =~ s/^\(.*?\)//) {
          my $nt = $&;
          if(length($nt) > 3) {
            $teiFile->addToElemsQueue($teiFile->createNoteNode(type => 'comment', text => $nt));
          } else { # note is too short - appending to regular text
            $segm = $teiFile->addToUtterance($nt,$segm);
          }
        } elsif ($text =~ s/^.*//) {
        $segm = $teiFile->addToUtterance($&, $segm); # this should not  happen but we don't wont loose some text
        }
      }
    }
    undef $is_first;
  }
  # end </seg>
}

sub create_ref_node {
  my $a = shift;
  my $href = $a->hasAttribute('href') ? $a->getAttribute('href') : '';
  $href = URI->new_abs($href,$URL) if $href;
  my $id = $a->hasAttribute('id') ? $a->getAttribute('id') : '';
  my $text = ScrapperUfal::html2text($a);
  $text =~ s/\N{NO-BREAK SPACE}/ /g;

  my $ref = XML::LibXML::Element->new("ref");
  my $type;
  my $n;
  if($href =~ m/hlasy.sqw/) {
    $type = 'voting';
    ($n) = ($href =~ m/.*G=(\d+)/);
  }
  if($href =~ m/historie.sqw/){
    $type = 'print';
    $n = $href;
    $n =~ s@.*T=(\d+).*?O=(\d+)@$2/$1@;
  }
  $ref->setAttribute('ana',"#parla.$type") if $type;
  $ref->setAttribute('n',$n) if $n;
  $ref->setAttribute('target',$href) if $href;

  $ref->appendText($text);
  return $ref;
}

sub get_role {
  my $text = shift;
  return 'chair' if $text =~ m/ PSP /; # Předseda / Místopředseda
  return 'chair' if $text =~ m/^Předsedající/; #
  return 'regular' if $text =~ m/^Poslan/i;
  return 'guest' if $text =~ m/^Senátor/i;
  return 'regular' if $text =~ m/^Ministr/i;
  return 'regular' if $text =~ m/^[^ ]*předsed[^ ]* vlády/i;
  return 'guest'; # Členka rady, Guvernér, Primátor, Člen zastupitelstva, Prezident, Hejtman
}

sub debug_print {
  my $msg = shift;
  my $line = shift;
  my $min_level = shift // 1;
  return unless $debug_level >= $min_level;
  print STDERR "$line : $msg\n";
}


