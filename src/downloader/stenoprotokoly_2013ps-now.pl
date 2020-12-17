use warnings;
use strict;
use ScrapperUfal;
use utf8;
use URI::QueryParam;
use File::Spec;
use File::Path;
use TEI::ParlaClarin::TEI;
use Getopt::Long;
use Data::Dumper;

use XML::LibXML qw(:libxml);

=description
This scrapping script works only for terms from 2013
=cut



my $URL = 'https://www.psp.cz';
my $URL_start = "$URL/eknih/";

my $tei_dir = 'out_tei';
my $yaml_dir = 'out_tei';
my $cache_dir;
my $run_date = ScrapperUfal::get_timestamp('%Y%m%dT%H%M%S');
my $prune_regex = undef;
my $debug_level = 0;

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
my %day_audio_links; # stores audio links - page -> audio_link

my $unauthorized = JSON::from_json(ScrapperUfal::get_note('unauthorized')||'{}');
my $new_unauthorized = {};

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
    my @sittings_links = xpath_string('./following-sibling::a[contains(@href,"'.$meeting_id.'schuz")]/@href',$meeting_node);
=sittings
    (<a href="001schuz/1-1.html">25.</a>, <a href="001schuz/1-2.html">27.&nbsp;listopadu&nbsp;2013</a>)
=cut
    for my $sitting_link (@sittings_links) {
      $sitting_link = URI->new_abs($sitting_link,$sch_link);
      my ($sitting_id) = $sitting_link =~ m/-(\d+)\.htm/;
      $sitting_id = sprintf("%02d",$sitting_id);
      debug_print( "\tnew sitting ".join('-', $term_id, $meeting_id, $sitting_id)."\t$sitting_link", __LINE__);
      push @steno_sittings, [$sitting_link, $term_id, $meeting_id, $sitting_id] if is_new($sitting_link,1) || exists $unauthorized->{$term_id}->{$meeting_id}->{$sitting_id};
    }
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
  push @steno_topic_anchor,[URI->new_abs($topic_anchor_link,$sitting_link),$term_id, $meeting_id, $sitting_id, '', 0];

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
my $last_sitting_date;
my %seen_topics;
my $teiCorpus;


while(my $steno_top = shift @steno_topic_anchor) { # order is important !!!
  my ($page_link,$term_id, $meeting_id, $sitting_id, $topic_id) = @$steno_top;
  make_request($page_link);
  debug_print( " -> LOADING \t$page_link", __LINE__, -1);
  next unless doc_loaded;
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

  if($act_date=xpath_string('//*[@id="main-content"]/p[@class = "status"]')) {
  	$act_date =~ s/^[^\d]*//;
  	$act_date =~ s/[^\d]*$//;
  	$act_date = $strp_act->parse_datetime(trim $act_date);
  	unless(set_document_date($act_date)) {
  	  return 0; # if not new - do not export and do not follow next page !!!
  	}
  }

  add_pagebreak_to_teiCorpus($link);
  add_audio_to_teiCorpus($link); # add audio if possible
  my ($link_id) = $link =~ m/s(\d*)\.htm$/;

  my $date = trim xpath_string('//*[@id="main-content"]/*[has(@class,"document-nav")]/p[@class="date"]/a');
  if($date){
    $date =~ s/^[^ ]* //;
    $datetime = $strp->parse_datetime("$date 00:00");
    $teiCorpus->addSittingDate($datetime);
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
      add_pagebreak_to_teiCorpus($link);
      add_audio_to_teiCorpus($link); # add audio if possible
      $teiCorpus->addSittingDate($datetime) if $datetime;
      debug_print( "  UTTERANCE " .($$ref_author->{authorname}), __LINE__, 5);
      my $id = $teiCorpus->addUtterance(
        author => {
          author_full => $$ref_author->{author},
          name => $$ref_author->{authorname},
          id => $$ref_author->{author_id},
          govern_id => $$ref_author->{auth_govern_id},
          role => $$ref_author->{role},
        },

       # link =>  $$ref_post->{link}.'#'.($$ref_post->{id}->{post}//'')
      );

    }
    if(xpath_node('.//strong[contains(text(), "eautorizováno !" )]',$cnt) ) { # Neautorizováno or neautorizováno
      set_current_tei_unauthorized($act_date);
    } elsif (my $s = xpath_string('./@class',$cnt) eq "status") {
      next;
    } elsif (my $mp3 = xpath_string('./a[@class = "audio"]/@href',$cnt)) {
      $teiCorpus->addAudioNote(url => URI->new_abs($mp3,$link));
      next;
    } elsif (xpath_string('./text()',$cnt) eq '***') {
      next;
    } elsif ($cnt_html =~ m/\s*<br\s*\/?>\s*$/) {
      next;
    } elsif ($cnt_html =~ m/\([Pp]okračuje\s+\b.*?\b\)/) {
      next;
    } elsif ($cnt_html =~ m/\(${re_cas}\)/) { # speaker continue
      my $texttime = $&;
      my $time = "$1:".($2//'00');
      $datetime = $strp->parse_datetime("$date $time");
      my $noteNode = $teiCorpus->createTimeNoteNode(from=>$datetime, texttime=>$texttime);
      $teiCorpus->addToElemsQueue($noteNode);
      $$ref_post->{date} = $datetime;
      next;
    } elsif ($cnt_html =~ m/${re_schuze}.*${re_prerus}${re_cas}.*\)/) {
      my $texttime = $&;
      my $time = "$1:".($2//'00');

      $datetime = $strp->parse_datetime("$date $time");
      $teiCorpus->addTimeNote(to=>$datetime, texttime=>$texttime);
      next;
    } elsif ($cnt_html =~ m/${re_schuze}.*${re_konec}${re_cas}.*\)/) {
      my $texttime = $&;
      my $time = "$1:".($2//'00');


      $datetime = $strp->parse_datetime("$date $time");
      $teiCorpus->addTimeNote(to=>$datetime, texttime=>$texttime);
    } elsif ($cnt_html =~ m/${re_schuze}.*${re_zacatek}${re_cas}.*\)/) {
      my $texttime = $&;
      my $time = "$1:".($2//'00');

      $datetime = $strp->parse_datetime("$date $time");
      $teiCorpus->addTimeNote(from=>$datetime, texttime=>$texttime);
      next;
    } elsif(my $a = xpath_node('./b[not(../@align = "center" or ../@align = "CENTER" ) and (.//a or starts-with(text(),"Poslan"))]',$cnt)) { # new utterance

      # fill new utterance
      my $auth;
      my $auth_id;
      my $govern_id;
      my $post_id;

      if ($a) {
        $auth =  trim xpath_string('.//* | ./text()',$a);
        ($auth_id) = (xpath_string('.//@href',$a)||'') =~ m/id=(\d+)/;
        ($govern_id) = (xpath_string('.//@href',$a)||'') =~ m/clenove-vlady\/(.*?)\//;
        $post_id = xpath_string('.//@id',$a);
        $a->unbindNode();
        $cnt_text = ScrapperUfal::html2text($cnt);
      }
      $cnt_text =~ s/\s*:?\s*//; # remove initial : and spaces

      ($$ref_author->{authorname}) = $auth =~ m/([^ ]*\s+[^ ]+?):?$/;
      $$ref_author->{author} = $auth;
      $$ref_author->{author_id} = $auth_id;
      $$ref_author->{auth_govern_id} = $govern_id;
      $$ref_author->{role} = get_role($$ref_author->{author});
      ### ($$ref_post->{speechnote}) = grep {m/^###.*|\@\@$/} xpath_string('./comment()',$cnt); # not at this page
      $$ref_post->{id}->{post} = $post_id;
      $$ref_post->{id}->{post} = 'r0' unless exists $$ref_post->{id}->{post};
      debug_print( "  UTTERANCE " .($$ref_author->{authorname}), __LINE__, 5);
      my $id = $teiCorpus->addUtterance(
        author => {
          author_full => $$ref_author->{author},
          name => $$ref_author->{authorname},
          id => $$ref_author->{author_id},
          govern_id => $$ref_author->{auth_govern_id},
          role => $$ref_author->{role},
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
      if($cnt->nodeType == XML::LibXML::XML_ELEMENT_NODE && lc($cnt->getAttribute('align')//'') eq 'center'){
        $teiCorpus->addHead($cnt_text);
        $cnt = xpath_node('./b', $cnt) // $cnt;
      }
      export_text($cnt, 1);
    }
  }
  return $topic_id;
}

sub add_pagebreak_to_teiCorpus {
  my $link = shift;
  $teiCorpus->addPageBreak(source => $link)
}

sub add_audio_to_teiCorpus {
  my $link = shift;
  if(my $page_mp3_url = xpath_string('//div[@class="aside"]//ul[@class="link-list"]/li[contains(text(),"MP3")]/a/@href')){
    $teiCorpus->addAudioNote(url => URI->new_abs($page_mp3_url, $link));
  } else { # get mp3 link from mp3file list page
    $teiCorpus->addAudioNote(url => $day_audio_links{$link->as_string}) if $day_audio_links{$link};
  }
}

sub init_TEI {
  my ($term_id, $meeting_id, $sitting_id, $topic_id) = @_;
  my $new_doc_id = sprintf('ps%d-%03d-%02d-%03d-%03d',$term_id, $meeting_id, $sitting_id, $topic_cntr, $topic_id );
  debug_print( "NEW DOCUMENT $new_doc_id " .join('-', $term_id, $meeting_id, $sitting_id, $topic_id), __LINE__, -1);
  $teiCorpus = TEI::ParlaClarin::TEI->new(id => $new_doc_id, output_dir => $tei_out_dir,
                                          title => ["Parliament of the Czech Republic, Chamber of Deputies"],
                                          );
}

sub export_TEI {
  if($teiCorpus && !$teiCorpus->isEmpty()) {
    my $filepath = $teiCorpus->toFile();
    debug_print( "SAVING DOCUMENT TO $filepath", __LINE__, -1);
    $topic_cntr++;

   # print STDERR "otestovat jestli se soubor změnil -> md5\n";
   # print STDERR "vyřešit verzování -> když se změní jen některý soubor z jednání -> problém se suffixem, který se automaticky upravuje\n";
   # print STDERR "skript, který bude přesouvat aktualizované a oanotované soubory jinam. Vůči nim se bude provádět kontrola na existenci??? Jak zaznamenávat změny - více verzí ";
  } else {
    debug_print( "EMPTY DOCUMENT - NOT SAVING", __LINE__, -1)
  }
}

sub set_current_tei_unauthorized {
  my $date = shift;
  my $id = $teiCorpus->teiID();
  $teiCorpus->setUnauthorizedFlag();
  $teiCorpus->setRevisionDate($date,'unauthorized');
  my $h = $new_unauthorized;
  for my $p (split("-", $id)) {
  	$h = $h->{$p} = {};
  }
}

sub set_document_date {
  my $date = shift;
  my $id = $teiCorpus->teiID();
  return unless is_new($id, $date);
  $teiCorpus->setActDate($date);
}

sub export_text {
  my $cnt = shift;
  my $is_first = shift; # remove initial : if true
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
      $segm = $teiCorpus->addToUtterance(create_ref_node($childnode),$segm);
    } else { # text or text in node that is not converted
      my $text = ScrapperUfal::html2text($childnode);
      $text =~ s/\s*:?\s*// if $is_first; # remove initial : and spaces
      $text =~ s/\s\s+/ /g ; # squeeze spaces
      while($text){
        if($text =~ s/^\s+//) {
          $teiCorpus->addToElemsQueue($&);
        } elsif($text =~ s/^[^\(]*[^\(\s]//){ # text without last space
          $segm = $teiCorpus->addToUtterance($&,$segm);
        } elsif ($text =~ s/^\(.*?\)//) {
          $teiCorpus->addToElemsQueue($teiCorpus->createNoteNode(type => 'comment', text => $&));
        } elsif ($text =~ s/^.*//) {
        $segm = $teiCorpus->addToUtterance($&, $segm); # this should not  happen but we don't wont loose some text
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
  $ref->setAttribute('source',$href) if $href;

  $ref->appendText($text);
  return $ref;
}

sub get_role {
  my $text = shift;
  return 'chair' if $text =~ m/ PSP /; # Předseda / Místopředseda
  return 'regular' if $text =~ m/^Poslan/i;
  return 'guest' if $text =~ m/^Senátor/i;
  return 'regular';
}

sub debug_print {
  my $msg = shift;
  my $line = shift;
  my $min_level = shift // 1;
  return unless $debug_level >= $min_level;
  print STDERR "$line : $msg\n";
}


