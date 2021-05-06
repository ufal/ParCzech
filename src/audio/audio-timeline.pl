use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use XML::LibXML qw(:libxml);
use Getopt::Long;
use File::Basename;
use File::Spec;
use Text::CSV;


use ParCzech::PipeLine::FileManager "audio-timeline";

my $scriptname = $0;
my $dirname = dirname($scriptname);

my %filename_template = (
  words => 'words_%s.tsv',
  stats => 'stats_%s.tsv',
  );
my $cert_column = 'normalized_dist_with_gaps_75';
my %cert = ( # normalized character mismatch is lower than
    high => 0.3,
    medium => 0.75,
    low => 1,
  );
my @cert_order = sort {$cert{$a} <=> $cert{$b}} keys %cert;

my ($debug, $test, $sync_dir);
my %variables = ();

my $xpc = ParCzech::PipeLine::FileManager::TeiFile::new_XPathContext();


GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # do not change the database
            'sync-dir=s' => \$sync_dir,
            ParCzech::PipeLine::FileManager::opts()
            );

usage_exit() unless ParCzech::PipeLine::FileManager::process_opts();
usage_exit() unless $sync_dir;

$ParCzech::PipeLine::FileManager::logger->log_line("aligned vertical data: $sync_dir");
my $current_file;
my $tsv = Text::CSV->new ({ binary => 1, auto_diag => 1, sep_char=> "\t"});

while($current_file = ParCzech::PipeLine::FileManager::next_file('tei', xpc => $xpc)) {
  next unless defined($current_file->{dom});

  my ($body) = $xpc->findnodes('//tei:body',$current_file->{dom});
  my $w_synced = 0;
  for my $audio ($xpc->findnodes('.//tei:media[@mimeType="audio/mp3"]',$current_file->{dom})) {
    my $audio_id = $audio->getAttributeNS(ParCzech::PipeLine::FileManager::TeiFile::get_NS_from_prefix('xml'),'id');
    my ($audio_date) = ($audio->getAttribute('url')//'') =~ m/(\d+)\.mp3/;
    unless ($audio_date) {
      $ParCzech::PipeLine::FileManager::logger->log_line("Wrong or missing audio url $audio_id:",($audio->getAttribute('url')//''));
      next;
    }
    my $words_file = get_sync_file_path('words',$audio_date);
    unless (-r $words_file) {
      $ParCzech::PipeLine::FileManager::logger->log_line("Missing or not readable word file $audio_id: $words_file");
      next;
    }
    open my $fh, "<:encoding(utf8)", "$words_file" or next;

    # initialize timeline
    my $origin_id = "$audio_id.origin";
    my $timeline = XML::LibXML::Element->new('timeline');
    $timeline->setAttribute('unit','ms');
    $timeline->setAttribute('origin',"#$origin_id");
    $timeline->setAttribute('corresp',"#$audio_id");
    my $cert_val = get_cert($audio_date);
    $timeline->setAttribute('cert',"$cert_val") if defined $cert_val;
    $body->appendChild($timeline);
    # origin
    my $origin = XML::LibXML::Element->new('when');
    $origin->setAttributeNS(ParCzech::PipeLine::FileManager::TeiFile::get_NS_from_prefix('xml'),'id',$origin_id);
    my $origin_date = $audio_date;
    $origin_date =~ s/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})\d{4}$/$1-$2-$3T$4:$5:00/;
    $ParCzech::PipeLine::FileManager::logger->log_line("origin time: $audio_date -> $origin_date");
    $origin->setAttribute('absolute',$origin_date);
    $timeline->appendChild($origin);
    my @header = $tsv->header ($fh); # read header
    my $cntr = 0;
    while (my $row = $tsv->getline_hr($fh)) {
      next if $row->{recognized} eq 'False';
      my ($node) = $xpc->findnodes('//tei:*[@xml:id="'.$row->{id}.'"]',$current_file->{dom});
      next unless $node;
      my ($wb_id,$we_id) = map {"$row->{id}.a$_"} qw/b e/;
      my $anchor = add_timeline_point($timeline,$origin_id,$wb_id,$row->{start});
      $node->parentNode->insertBefore($anchor, $node);
      $anchor = add_timeline_point($timeline,$origin_id,$we_id,$row->{end});
      $node->parentNode->insertAfter($anchor, $node);
      $cntr += 2;
      $w_synced++;
    }
    $ParCzech::PipeLine::FileManager::logger->log_line("$cntr anchors added ($origin_date) source: $words_file");

    close $fh;
  }
  $ParCzech::PipeLine::FileManager::logger->log_line("$w_synced words synchronized");
  $ParCzech::PipeLine::FileManager::logger->log_line(($xpc->findvalue('count(//tei:w[not(./w)])',$current_file->{dom}) - $w_synced)." words not synchronized");

  if($test) {
    $current_file->print();
  } else {
    my $result = $current_file->save();
  }
}

sub add_timeline_point {
  my ($timeline,$origin,$id,$since) = @_;
  my $when = XML::LibXML::Element->new('when');
  $when->setAttributeNS(ParCzech::PipeLine::FileManager::TeiFile::get_NS_from_prefix('xml'),'id',$id);
  $when->setAttribute('since',$since);
  $when->setAttribute('origin',"#$origin");
  $timeline->appendChild($when);
  my $anchor = XML::LibXML::Element->new('anchor');
  $anchor->setAttribute('synch',"#$id");
  return $anchor;
}

sub get_sync_file_path {
  my ($type,$date) = @_;
  return File::Spec->catfile($sync_dir,sprintf($filename_template{$type},$date));
}

sub get_cert {
  my $date = shift;
  my $stats_file = File::Spec->catfile($sync_dir,sprintf($filename_template{stats},$date));
  unless (-r $stats_file) {
    $ParCzech::PipeLine::FileManager::logger->log_line("Missing or not readable word file $date: $stats_file");
    return;
  }
  open my $statfh, "<:encoding(utf8)", "$stats_file" or return;
  my @header = $tsv->header ($statfh); # read header
  my $row = $tsv->getline_hr($statfh);
  close $statfh;
  if ($row){
    for my $c (@cert_order){
      return $c if $row->{$cert_column} <= $cert{$c};
    }
  }
}

sub usage_exit {
   my ($fm_args,$fm_desc) =  @{ParCzech::PipeLine::FileManager::usage('tei')};
   print
"Usage: audio-timeline.pl  $fm_args --sync-dir <DIRPATH> [--test]

$fm_desc
\t--sync-dir=DIRPATH\tdirectory with synchronized data in vertical format
\t--test\tprint result to stdout - don't change any file
";
   exit;
}
