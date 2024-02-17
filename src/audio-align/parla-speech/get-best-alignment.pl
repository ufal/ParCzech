#!/usr/bin/env perl
use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use Getopt::Long;
use File::Basename;
use File::Spec;

use JSON::Lines;
use List::Util;

use constant {
  WHOLE => 0,
  BORDER => 1,
  SPLIT => 2
};

use Data::Dumper;

# get sentence alignment
# alignment is (acording to percentage Levenstein distance?)
#    - good: print to output
#    - bad: try to split to multiple segments (find the worst token??? or longest space between tokens?)


# calculation of error rate:
# SUM(dist // length(true_w) //length(trans_w))/SUM(length(true_w))


sub usage {
    print STDERR ("Usage:\n");
    print STDERR ("$0 -help\n");
    print STDERR ("$0 ");
    print STDERR (" \n");
}

my ($help, $error_rate, $input_dir, $shortest_partial_sentence, $tokens_ranges_file, $output_file);

GetOptions
    (
     'help'       => \$help,
     'error-rate=s'    => \$error_rate,
     'shortest-partial-sentence=s'    => \$shortest_partial_sentence,
     'input-dir=s'   => \$input_dir,
     'tokens-ranges=s'     => \$tokens_ranges_file,
     'output=s'  => \$output_file,
);

if ($help) {
    &usage;
    exit;
}

my $jsonl = JSON::Lines->new();
open my $OUTPUT, ">", $output_file or die "$output_file: $!";
open my $RANGES, "<", $tokens_ranges_file or die "$tokens_ranges_file: $!";


my $report = {
  pages => 0,
  processed => 0,
  result_sent => 0,
  result_part => 0
};

while(my $range = <$RANGES>){
  $range =~ s/\s*$//;
  my ($file_id,$start_token,$end_token) = split /\t/, $range;
  my $input_page_file = "$input_dir/$file_id.tsv";
  print STDERR "Processing page $file_id source file $input_page_file\n";
  open my $ALIGNMENT, "<", $input_page_file or next;
  $report->{pages} += 1;
  my $line;
  my @sentence;
  do {$line = <$ALIGNMENT>; } until ($line =~ m/\t$start_token\t/);
  my ($sent_id, $new_sent_id);
  PAGE: {
    do {
      # true_w  trans_w joined  id  recognized  dist  dist/len(true_word) start end time_len_ms time_len/len(true_word)
      my ($true_w,$trans_w,$joined,$id,undef,$dist,undef,$start_time,$end_time,$time_len_ms,undef) = map {$_ eq '-' ? undef : $_} split /\t/, $line;
      my $new_sent_id;
      if (defined $id && $id =~ m/^CONTEXT_/){
        last PAGE;
      } elsif(! defined $id ) {
        $new_sent_id = $sent_id;
      } else {
        ($new_sent_id) = $id =~ m/^(.*)w.*?$/;
      }
      if($sent_id && $sent_id ne $new_sent_id){
        proces_sentence({json_obj=>$jsonl,fh=>$OUTPUT, report => $report}, $error_rate, WHOLE, $shortest_partial_sentence, $sent_id, @sentence);
        @sentence = ();
        undef $sent_id;
      }
      $sent_id = $new_sent_id;
      push @sentence, {
        true_w => $true_w,
        trans_w => $trans_w,
        joined => ($joined eq 'True'),
        id => $id,
        dist =>  ($dist // (length($true_w//'')+ length($trans_w//''))),
        start_time => $start_time,
        end_time => $end_time,
        time_len_ms => $time_len_ms
      };
    } while ($line = <$ALIGNMENT>);
  }
  proces_sentence({json_obj=>$jsonl,fh=>$OUTPUT, report => $report}, $error_rate, WHOLE, $shortest_partial_sentence, $sent_id, @sentence);
  close $ALIGNMENT;
  print STDERR "Page $file_id done\n";
}

print "Pages processed: ",$report->{pages},"\n";
print "Sentences processed: ",$report->{processed},"\n";
print "Sentences in result: ",$report->{result_sent},"\n";
print "Parts in result: ",$report->{result_part},"\n";


print STDERR "TODO:
\tload original tsv file and insert interpunction ????
\t BETTER: and maybe insert other info from TEI file to tsv-corresp???
- nospace after
\t   insert the data before passing them to this script???\n";


sub proces_sentence {
  my $result = shift;
  my $max_error_rate = shift;
  my $crop_level = shift;
  my $partial_sentence_min_len = shift;
  my $sent_id = shift;
  my @alignment = @_;
  # remove mismatchs from the beginning
  while(@alignment && (!defined($alignment[0]->{id}) || !defined($alignment[0]->{trans_w}))) {
    $crop_level = BORDER if !defined($alignment[0]->{trans_w}) && $crop_level == WHOLE;
    shift @alignment;
  }
  # remove mismatchs from the end
  while(@alignment && (!defined($alignment[$#alignment]->{id}) || !defined($alignment[$#alignment]->{trans_w}))) {
    $crop_level = BORDER if !defined($alignment[$#alignment]->{trans_w}) && $crop_level == WHOLE;
    pop @alignment;
  }
  $result->{report}->{processed} += 1 if $crop_level == WHOLE;
  my $sent_dist = List::Util::sum(map { $_->{dist} } @alignment);
  my $sent_len_true = List::Util::sum(map { length($_->{true_w}//'') } @alignment);
  my $sent_len_all = List::Util::sum(map { length($_->{true_w}//$_->{trans_w}) } @alignment);
  return unless $sent_len_all;
  my $result_error_rate = $sent_dist / $sent_len_all;
  if(($result_error_rate <= $max_error_rate) && (($crop_level == WHOLE) || ($partial_sentence_min_len <= @alignment)) ) {
    print STDERR ($crop_level == WHOLE ? "WHOLE-":'PARTIAL-'),"SENTENCE: DIST=$sent_dist LEN=$sent_len_true ERROR-TRUE=",($sent_dist/$sent_len_true)," ERROR-ALL=$result_error_rate\n";
    print STDERR "\tTEXT: ",join(" ",map {$_->{true_w}//'-'} @alignment),"\n";
    print STDERR "\tAUDIO:",join(" ",map {$_->{trans_w}//'-'} @alignment),"\n";
    $result->{json_obj}->add_line({align=>\@alignment},$result->{fh});
    if($crop_level == WHOLE){
      $result->{report}->{result_sent} += 1;
    } else {
      $result->{report}->{result_part} += 1;
    }
  } elsif (@alignment >= 3 && @alignment >= $partial_sentence_min_len) {
    # calculate floating mismatch
    my @floating_dist = (
      $alignment[0]->{dist},
      (map {List::Util::sum(map {$alignment[$_]->{dist}} ($_-1,$_,$_+1) ) } (1..($#alignment-1))),
      $alignment[$#alignment]->{dist}
    );
    print STDERR "($crop_level)===== split sentence $result_error_rate  ($max_error_rate)\n";
    my $max_idx = List::Util::reduce { $floating_dist[$a] > $floating_dist[$b] ? $a : $b } 0..$#floating_dist;
    print STDERR "\t",join(' ',@floating_dist),"\n";
    print STDERR "\t",join(' ',@floating_dist[0..($max_idx-1)])," ## ", join(' ',@floating_dist[($max_idx+1)..$#floating_dist]),"\n";
    print STDERR "\tTEXT: ",join(" ",map {$max_idx == $_ ? '##' : $alignment[$_]->{true_w}//'-'} (0..$#alignment)),"\n";
    print STDERR "\tAUDIO:",join(" ",map {$max_idx == $_ ? '##' : $alignment[$_]->{trans_w}//'-'} (0..$#alignment)),"\n";
    proces_sentence($result, $max_error_rate, SPLIT, $partial_sentence_min_len, $sent_id, @alignment[0..($max_idx-1)]) if $max_idx > $partial_sentence_min_len;
    proces_sentence($result, $max_error_rate, SPLIT, $partial_sentence_min_len, $sent_id, @alignment[($max_idx+1)..$#floating_dist]) if $#floating_dist-$max_idx+1 > $partial_sentence_min_len;
  }
}



close $RANGES;
close $OUTPUT;