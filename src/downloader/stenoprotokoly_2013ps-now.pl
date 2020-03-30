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

=description
This scrapping script works only for terms from 2013
=cut



my $URL = 'https://www.psp.cz';
my $URL_start = "$URL/eknih/";

my $tei_dir = 'out_tei';
my $yaml_dir = 'out_tei';
my $run_date = ScrapperUfal::get_timestamp('%Y%m%dT%H%M%S');
my $prune_regex = undef;

Getopt::Long::GetOptions(
  'tei=s' => \$tei_dir,
  'yaml=s' => \$yaml_dir,
  'id=s' => \$run_date,
  'prune=s' => \$prune_regex
  );

my $yaml_file_path = File::Spec->catfile( $yaml_dir,"$run_date.yml");

my $tei_out_dir = File::Spec->catdir( $tei_dir,$run_date);
File::Path::mkpath($tei_out_dir) unless -d $tei_out_dir;

File::Path::mkpath($yaml_dir) unless -d $yaml_dir;
ScrapperUfal::set_export_output($yaml_file_path);



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

my $re_schuze = qr/\([^\(\)]*(?:Schůze|Jednání)\s*/;
my $re_zacatek = qr/(?:začal[ao]|zahájen[ao]|pokračoval[ao]|pokračuje)\s*/;
my $re_konec = qr/(?:skončil|skončen|ukončen)[ao]\s*/;
my $re_prerus = qr/přerušen[ao]\s*/;
my $re_cas = qr/\s*(?:v|ve|do)?\s*(\d+)[\.:]\s*(\d+)?\s*(?:hodin|hod\.|h\.|do|\.|min|\))/;


my @URLs_parlament;
my @steno_voleb_obd;
my @steno_sittings;
my @steno_topic_anchor;
my @steno_topic_links;

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
for my $sch_link (@steno_voleb_obd) {
  make_request($sch_link);
  my ($term_id) = $sch_link =~ m/(\d{4})ps/;
  next unless doc_loaded;
  for my $meeting_node (xpath_node('//*[@id="main-content"]/a[./b]')) {
    my $meeting_link = URI->new_abs($meeting_node->getAttribute('href'),$sch_link);
    my ($meeting_id) = $meeting_link =~ m/(\d\d\d)schuz/;
    $meeting_id .= 'psse' if $meeting_link =~ m/psse/;
    my @sittings_links = xpath_string('./following-sibling::a[contains(@href,"'.$meeting_id.'schuz")]/@href',$meeting_node);
    for my $sitting_link (@sittings_links) {
      $sitting_link = URI->new_abs($sitting_link,$sch_link);
      my ($sitting_id) = $sitting_link =~ m/-(\d+)\.htm/;
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

  # get opening speeches link
  my ($topic_anchor_link,$anchor) = xpath_string('//*[@id="main-content"]/a[starts-with(./@href,"s")][1]/@href') =~ m/(.*)#(.*)/;
  my $is_topic_page = 1;
  my $is_new_topic = 1;
  push @steno_topic_anchor,[URI->new_abs($topic_anchor_link,$sitting_link),'',$is_topic_page, $is_new_topic,$term_id, $meeting_id, $sitting_id, '000'];

  # get topic links
  $is_topic_page = 0;
  my %seen;
  for my $l (xpath_string('//*[@id="main-content"]/a[@name]/following-sibling::b[1]/following-sibling::a[1]/@href')){
  	next if exists $seen{$l}; # add non topic page only onetimes !!!
  	$seen{$l} = 1;
  	($topic_anchor_link,$anchor) = $l =~ m/(.*)#(.*)/;
    push @steno_topic_anchor,[URI->new_abs($topic_anchor_link,$sitting_link),$anchor,$is_topic_page, $is_new_topic,$term_id, $meeting_id, $sitting_id];
  }
}

my $previeous_link = '';
my $author = {};
my $post = {};
my %seen_topics;
my $teiCorpus;

while(my $steno_top = shift @steno_topic_anchor) { # order is important !!!
  my ($topic_anchor_link,$anchor,$is_topic_page,$is_new_topic,$term_id, $meeting_id, $sitting_id, $topic_id) = @$steno_top;
  # načíst stránku
  unless($previeous_link eq $topic_anchor_link){ # test whether is document loaded from previeous iteration
    make_request($topic_anchor_link);
    $previeous_link = $topic_anchor_link;
    next unless doc_loaded;
  }

  if($is_topic_page){
    if($is_new_topic){
  	  export_steno_record(\$author,\$post);
  	  export_TEI();
  	  init_TEI($term_id, $meeting_id, $sitting_id, $topic_id);
    }
    $post->{link} = $topic_anchor_link;
    $post->{id}->{term} = $term_id;
    $post->{id}->{meeting} = $meeting_id;
    $post->{id}->{sitting} = $sitting_id;
    $post->{id}->{topic} = $topic_id;


    # get whole page
    my $get_next_page = record_exporter($topic_anchor_link, \$author,\$post,$anchor);

    # add next page if exists
    # push @steno_topic_anchor,[$link,'',1,0,$term_id, $meeting_id, $sitting_id, $topic_id];
    if($get_next_page){
      my $url_next = xpath_string('//*[@id="main-content"]/*[has(@class,"document-nav")]//a[@class="next"]/@href');
      if($url_next) {
        unshift @steno_topic_anchor,[URI->new_abs($url_next,$topic_anchor_link),'',1,0,$term_id, $meeting_id, $sitting_id, $topic_id];
      } else {
        my $number;
        ($url_next,$number) = $topic_anchor_link =~ m/(.*schuz\/s.*)(\d\d\d).htm$/;
        if($url_next) {
          $number = int($number) + 1;
          unshift @steno_topic_anchor,[URI->new_abs($url_next.sprintf("%03d.htm",$number),$topic_anchor_link),'',1,0,$term_id, $meeting_id, $sitting_id, $topic_id];
        }
      }
    }
  } else {
  	# jenom najdu odkaz na stránku a přidám ho na začátek @steno_topic_anchor
  	# zapamatuji si předchozího autora !!! (bude to autor titulku), pokud se dodrží pořadí stahování, tak už je v paměti...

  	# get whole topic link
  	my $anchor_node = xpath_node('//p[./b/a/@id = "'.$anchor.'"]') // xpath_node('//a[@id = "'.$anchor.'"]') ;
    my @link = (xpath_string('./preceding-sibling::p[@align="center"][1]/preceding-sibling::div[1][@class="media-links"]/a[@class="bqbs"]/@href',$anchor_node));
    if(
    	xpath_node('./following-sibling::p[@align="center"][1][./preceding-sibling::p[./b/a/@id][1]/b/a/@id = "'.$anchor.'"]',$anchor_node) # anchor node is followed by title (no anchor between)
    	&&
    	xpath_node('./following-sibling::p[@align="center"][2][./preceding-sibling::p[./b/a/@id][1]/b/a/@id = "'.$anchor.'"]',$anchor_node) # no speaker between two following titles
      ){ # if there is only Předsedající speech, then wrong or no topic has been set in $link. Evample: https://www.psp.cz/eknih/2017ps/stenprot/001schuz/s001015.htm#r3
      # following topic title that does not have speaker
      #$link = xpath_string('./following-sibling::p[@align="center"][1]/preceding-sibling::div[1][@class="media-links"]/a[@class="bqbs"]/@href',$anchor_node);
      @link = xpath_string('./following-sibling::p[@align="center"]/preceding-sibling::div[1][@class="media-links"][preceding-sibling::p[./b/a/@id][1]/b/a/@id = "'.$anchor.'"]/a[@class="bqbs"]/@href',$anchor_node);
      # do not add last caption if it is followed by author anchor ($anchor_node is not the last author anchor on page)
      if(xpath_node('./following-sibling::p/b/a[@id]',$anchor_node)){
      	pop @link
      	} else {
      		#print STDERR "TITLE CAN BE ON NEXT PAGE !!! $topic_anchor_link\n";
      	}
    }
  	if(@link) {
  	  for my $l (@link) {
        ($topic_id) = $l =~ m/b\d{3}(\d{3})\d{2}\.htm/;
        $l = URI->new_abs($l,$topic_anchor_link);
        #next unless exists $seen_topics{$l};
        #$seen_topics{$l} = 1;
        unshift @steno_topic_anchor,[$l,'',1,1,$term_id, $meeting_id, $sitting_id, $topic_id];
      }
    } else {
  			# TODO bod nemá vlastní stránku !!!
  			# nebo kotva nasměrovala na následující stránku !!!
  			my $previeous_page = xpath_string('//*[@id="main-content"]/*[has(@class,"document-nav")]//a[@class="prev"]/@href');
            push @steno_topic_anchor,[URI->new_abs($previeous_page,$topic_anchor_link),'_d',0, 1,$term_id, $meeting_id, $sitting_id] if $previeous_page;
 			# print STDERR "This topic is glued with previeous one or topic is on previeous_page: \n\t$topic_anchor_link#$anchor -> $previeous_page\n";
  	}

  	# remember current author

  }
  ScrapperUfal::set_note('unauthorized',JSON::to_json($new_unauthorized));
}


ScrapperUfal::set_note('unauthorized',JSON::to_json($new_unauthorized));

####################################################################################################

sub record_exporter {
  my ($link, $ref_author, $ref_post,$anchor) = @_;
  my $get_next_page = 1;
  my $datetime;
  my $jumb_to_anchor = '';
  my $act_date;
  if($anchor){
  	# TODO skip begining to anchor
  }

  if($act_date=xpath_string('//*[@id="main-content"]/p[@class = "status"]')) {
  	$act_date =~ s/^[^\d]*//;
  	$act_date =~ s/[^\d]*$//;
  	$act_date = $strp_act->parse_datetime(trim $act_date);
  	unless(set_document_date($act_date)) {
  	  return 0; # if not new - do not export and do not follow next page !!!
  	}
  }

  if(my $page_mp3_url = xpath_string('//div[@class="aside"]//ul[@class="link-list"]/li[contains(text(),"MP3")]/a/@href')){
    $teiCorpus->addAudioNote(url => URI->new_abs($page_mp3_url, $link));
  }

  my $date = trim xpath_string('//*[@id="main-content"]/*[has(@class,"document-nav")]/p[@class="date"]/a');
  if($date){
    $date =~ s/^[^ ]* //;
    $teiCorpus->addSittingDate($strp->parse_datetime("$date 00:00"));
  }

  for my $cnt (xpath_node('//*[@id="main-content"]/'.$jumb_to_anchor.'*[not(has(@class,"document-nav"))] | //*[@id="main-content"]/'.$jumb_to_anchor.'text()')) {
  	my $cnt_html = trim dump_html($cnt);
    my $cnt_text =trim ScrapperUfal::html2text($cnt);
    if(xpath_node('./a[../@class="media-links" and @class="bqbs"]',$cnt)){ # end condition, record will be exported within next make_request iteration
      $get_next_page = 0;
      # export previeous utterance
      export_steno_record($ref_author,$ref_post);
      last;
    }
    if(xpath_node('.//strong[contains(text(), "eautorizováno !" )]',$cnt) ) { # Neautorizováno or neautorizováno
      set_current_tei_unauthorized($act_date);
    } elsif (my $s = xpath_string('./@class',$cnt) eq "status") {
      next;
    } elsif (my $mp3 = xpath_string('./a[@class = "audio"]/@href',$cnt)) {
      $teiCorpus->addAudioNote(url => URI->new_abs($mp3,$ link));
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
      push@{$$ref_post->{content}}, $noteNode;
      $$ref_post->{date} = $datetime;
      next;
    } elsif ($cnt_html =~ m/${re_schuze}.*${re_prerus}${re_cas}\)?/) {
      my $texttime = $&;
      my $time = "$1:".($2//'00');
      $datetime = $strp->parse_datetime("$date $time");
      $teiCorpus->addTimeNote(to=>$datetime, texttime=>$texttime);
      next;
    } elsif ($cnt_html =~ m/${re_schuze}.*${re_konec}${re_cas}\)?/) {
      my $texttime = $&;
      my $time = "$1:".($2//'00');

      # export previeous utterance
      export_steno_record($ref_author,$ref_post);

      $datetime = $strp->parse_datetime("$date $time");
      $teiCorpus->addTimeNote(to=>$datetime, texttime=>$texttime);
    } elsif ($cnt_html =~ m/${re_schuze}.*${re_zacatek}${re_cas}\)?/) {
      my $texttime = $&;
      my $time = "$1:".($2//'00');

      $datetime = $strp->parse_datetime("$date $time");
      $teiCorpus->addTimeNote(from=>$datetime, texttime=>$texttime);
      next;
    } elsif(my $a = xpath_node('./b[not(../@align = "center" or ../@align = "CENTER" ) and (.//a or starts-with(text(),"Poslan"))]',$cnt)) { # new utterance
      # export previeous utterance
      export_steno_record($ref_author,$ref_post);
      # fill new utterance
      my $auth;
      my $auth_id;
      my $post_id;

      if ($a) {
        $auth =  trim xpath_string('.//* | ./text()',$a);
        ($auth_id) = (xpath_string('.//@href',$a)||'') =~ m/id=(\d+)/;
        $post_id = xpath_string('.//@id',$a);
        $a->unbindNode();
        $cnt_text = ScrapperUfal::html2text($cnt);
      }
      $cnt_text =~ s/\s*:?\s*//; # remove initial : and spaces

      ($$ref_author->{authorname}) = $auth =~ m/([^ ]*\s+[^ ]+?):?$/;
      $$ref_author->{author} = $auth;
      $$ref_author->{author_id} = $auth_id;
      ($$ref_post->{speechnote}) = grep {m/^###.*|\@\@$/} xpath_string('./comment()',$cnt);
      $$ref_post->{id}->{post} = $post_id;
      push @{$$ref_post->{content}}, $cnt_text;
    } elsif($cnt_text) {
      if($cnt->nodeType == XML::LibXML::XML_ELEMENT_NODE && lc($cnt->getAttribute('align')//'') eq 'center'){
        $teiCorpus->addHead($cnt_text);
      }
      push @{$$ref_post->{content}}, $cnt_text;
    }
  }
  return $get_next_page;
}

sub init_TEI {
  my ($term_id, $meeting_id, $sitting_id, $topic_id) = @_;
  $teiCorpus = TEI::ParlaClarin::TEI->new(id => "$term_id-$meeting_id-$sitting_id-$topic_id", output_dir => $tei_out_dir);
}

sub export_TEI {
  if($teiCorpus && !$teiCorpus->isEmpty()) {
    my $filepath = $teiCorpus->toFile();

   # print STDERR "otestovat jestli se soubor změnil -> md5\n";
   # print STDERR "vyřešit verzování -> když se změní jen některý soubor z jednání -> problém se suffixem, který se automaticky upravuje\n";
   # print STDERR "skript, který bude přesouvat aktualizované a oanotované soubory jinam. Vůči nim se bude provádět kontrola na existenci??? Jak zaznamenávat změny - více verzí ";


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

sub export_steno_record {
  my ($ref_author, $ref_post) = @_;
  unless($teiCorpus) {
  	$teiCorpus = init_TEI(map {$$ref_post->{id}->{$_} // ''} qw/term meeting sitting topic/) ;
  }
  my %post = %{$$ref_post};
  $$ref_post->{id}->{post} = 'r0' unless exists $$ref_post->{id}->{post};
  my $id = join("-",map {$$ref_post->{id}->{$_} // ''} qw/term meeting sitting topic post/);
  my $textcontent = trim join(' ',@{$$ref_post->{content} //[]}) ;
  unless($textcontent) {
  	return;
  }

  $teiCorpus->addUtterance(
    id => $id,
    author => { author_full => $$ref_author->{author}, name => $$ref_author->{authorname}, id => $$ref_author->{author_id}},
    text => $$ref_post->{content},
    link =>  $$ref_post->{link}.'#'.($$ref_post->{id}->{post}//'')
    );
  export_record_yaml(
    id => $id,
    url => $$ref_post->{link}.'#'.($$ref_post->{id}->{post}//''),
    type => 'speech',
    content => $textcontent,
    #ord => $speakerno,
    author => $$ref_author->{author} // undef,
    author_name => $$ref_author->{authorname} // undef,
    author_id => $$ref_author->{author_id} // undef,
    topic_id => join("-",map {$$ref_post->{id}->{$_} // ''} qw/term meeting sitting topic/) // undef,
    speech_note => $post{speechnote} // undef,
    date => $$ref_post->{date},
    #scalar @hlas ?(voting => \@hlas) : (),
    #scalar @tisk ?(prints => \@tisk) : (),
    #authorized => $args{authorized},
    #interpelation => $post{interpelation} // undef,
    #mp3 => $args{mp3},
    );

  delete $$ref_post->{id}->{post};
  $$ref_post->{content} = []; # clean content (keep datetime !!!)
}




