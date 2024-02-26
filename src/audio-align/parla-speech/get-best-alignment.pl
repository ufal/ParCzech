#!/usr/bin/env perl
use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use Getopt::Long;
use File::Basename;
use File::Spec;

use Text::CSV qw/csv/;

use JSON::Lines;
use List::Util;

use Text::Levenshtein;


use constant {
  WHOLE => 0,
  BORDER => 1,
  SPLIT => 2,
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

my ($help, $error_rate, $input_alignment_dir, $input_tokens_dir, $shortest_partial_sentence, $meta_file, $output_file);

$shortest_partial_sentence = 1000000; #default is not put partial sentences to result
GetOptions
    (
     'help'       => \$help,
     'error-rate=s'    => \$error_rate,
     'shortest-partial-sentence=s'    => \$shortest_partial_sentence,
     'input-alignment-dir=s'   => \$input_alignment_dir,
     'input-tokens-dir=s'   => \$input_tokens_dir,
     'meta=s'   => \$meta_file,
     #'tokens-ranges=s'     => \$tokens_ranges_file,
     'output=s'  => \$output_file,
);

if ($help) {
    &usage;
    exit;
}

unless($meta_file){
  die "Missing --meta param\n";
}

my %meta_db;
for my $m (@{csv({in => $meta_file,headers => "auto", binary => 1, auto_diag => 1, sep_char=> "\t"})}){
  $meta_db{$m->{ID}} = $m;
}

my $jsonl = JSON::Lines->new();
$JSON::Lines::JSON->ascii(1); # escape non ascii
$JSON::Lines::JSON->canonical([1]);
open my $OUTPUT, ">", $output_file or die "$output_file: $!";
# open my $RANGES, "<", $tokens_ranges_file or die "$tokens_ranges_file: $!";


my $report = {
  pages => 0,
  processed => 0,
  result_sent => 0,
  result_part => 0,
  audio_len => 0,
  audio_gaps_len => 0,
  audio_tokens_len => 0,
};


#while(my $range = <$RANGES>){
#  $range =~ s/\s*$//;

foreach my $input_align_file (sort glob "$input_alignment_dir/*.tsv" ){ # iterate over all alignment files in input_alignment_dir
  #my ($file_id,$start_token,$end_token) = split /\t/, $range;
  #my $input_page_file = "$input_alignment_dir/$file_id.tsv";
  my ($file_id) = $input_align_file =~ m/(\d*)\.tsv$/;
  print STDERR "Processing page $file_id source file $input_align_file\n";
  open my $ALIGNMENT, "<", $input_align_file or next;
  my ($YYYY,$MM,$DD) = $file_id =~ m/^(\d{4})(\d{2})(\d{2})/;
  print STDERR "$input_tokens_dir/www.psp.cz/eknih/*/audio/$YYYY/$MM/$DD/$file_id.tsv\n";
  my ($input_token_page_file) = glob "$input_tokens_dir/www.psp.cz/eknih/*/audio/$YYYY/$MM/$DD/$file_id.tsv";
  my ($audio_file) = $input_token_page_file =~ m/audio\/(.*)\.tsv$/;
  $audio_file = "audio/psp/$audio_file.mp3";
  open my $TOKENS, "<", $input_token_page_file or next;
  $report->{pages} += 1;
  my $line;
  my @sentences = load_source_files($TOKENS,$ALIGNMENT);
  while(my $sentence = shift @sentences){
    proces_sentence({json_obj=>$jsonl,fh=>$OUTPUT, report => $report}, $error_rate, WHOLE, $shortest_partial_sentence, {%$sentence,audio_file=>$audio_file},@{$sentence->{tokens}});
  }

=XXX
  #do {$line = <$ALIGNMENT>; } until ($line =~ m/\t$start_token\t/);
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
=cut
  close $ALIGNMENT;
  close $TOKENS;

  print STDERR "Page $file_id done\n";
}

print "Pages processed: ",$report->{pages},"\n";
print "Sentences processed: ",$report->{processed},"\n";
print "Sentences in result: ",$report->{result_sent},"\n";
print "Parts in result: ",$report->{result_part},"\n";
print "audio length in result: ",($report->{audio_len}/1000)," s\n";
print "tokens audio length in result: ",($report->{audio_tokens_len}/1000)," s\n";
print "gaps audio length in result: ",($report->{audio_gaps_len}/1000)," s\n";


print STDERR "TODO:
\tload original tsv file and insert interpunction ????
\t BETTER: and maybe insert other info from TEI file to tsv-corresp???
- nospace after
\t   insert the data before passing them to this script???\n";


sub load_source_files {
  my ($TOK,$ALIGN) = @_;
  my @result;
  my $tok_in = Text::CSV->new({binary => 1, auto_diag => 1, sep_char=> "\t"});
  my $align_in = Text::CSV->new({binary => 1, auto_diag => 1, sep_char=> "\t"});
  # set/load headers
  $tok_in -> column_names(qw/token wid who uid date no_space_after is_word/);
  # true_w  trans_w joined  id  recognized  dist  dist/len(true_word) start end time_len_ms time_len/len(true_word)
  $align_in->header ($ALIGN, { munge_column_names => "none" });
  # load data
  my $toks = $tok_in->getline_hr_all($TOK);
  my $align = $align_in->getline_hr_all($ALIGN);
  foreach my $row (@$align,@$toks) {
    foreach my $col (values %{$row}) {
      $col = 1 if $col && $col eq 'True';
      $col = 0 if $col && $col eq 'False';
      $col = $col eq '-' ? undef :$col if $col;
    }
  }
  my ($ti, $ai) = (0,0);
  while($ai < @$align && (!defined($align->[$ai]->{id}) ||  $toks->[$ti]->{wid} ne $align->[$ai]->{id} )) { # skipping undef and context tokens
    $ai++;
  }
  my ($sent_id, $new_sent_id);
  my $u_id;
  my $u_len = 0;
  my $sentence;
  #print STDERR Dumper($toks,$align);
  while($ti < @$toks && $ai < @$align){
    my ($move_ti,$move_ai) = (0,0);
    if($toks->[$ti]->{wid} && $align->[$ai]->{id}
        && $toks->[$ti]->{wid} eq $align->[$ai]->{id}){
      $move_ti = 1;
      $move_ai = 1;
      ($new_sent_id) = $toks->[$ti]->{wid} =~ m/^(.*)\.w.*?$/;
    } elsif (! defined($align->[$ai]->{id})) { # skip move through all unmatched aligns
      $move_ai = 1;
    } else { # move to next token (current token is not in align)
      $move_ti = 1;
      ($new_sent_id) = $toks->[$ti]->{wid} =~ m/^(.*)\.w.*?$/;
    }

    if($sent_id && $sent_id ne $new_sent_id){
      push @result, $sentence;
      undef $sentence;
      my @seg_id = ($sent_id,$new_sent_id);
      @seg_id = map {s/\.[^\.]*$//;$_} @seg_id;
      $u_len +=1 if($seg_id[0] ne $seg_id[1]); # moving to next paragraph
    }
    $sent_id = $new_sent_id;
    if($move_ti && $toks->[$ti]->{uid} ne ($u_id//'')){ # move to next utterance
      $u_len = 0;
      $u_id = $toks->[$ti]->{uid};
    }
    if(!defined($sentence) && $sent_id){ # first token in sentence from toks
      $sentence = {};
      $sentence->{sid} = $sent_id;
      $sentence->{uid} = $toks->[$ti]->{uid};
      ($sentence->{tid}) = $sentence->{uid} =~ m/^(.*)\.u[0-9]*$/;
      $sentence->{date} = $toks->[$ti]->{date};
      $sentence->{tokens} = [];
    }
    # change sentence if previous different sent_id
    # insert to current sentence
    if($sentence){ # align is skipped if not seen the first token from toks
      my $id = $move_ti ? $toks->[$ti]->{wid} : $align->[$ai]->{id};
      my $new_u_len = $u_len + ($move_ti ? length($toks->[$ti]->{token}//'') : 0);
      push @{$sentence->{tokens}},{
        id => $id,
        dist => ($move_ti && $move_ai)
                ? ($align->[$ai]->{dist} // length($align->[$ai]->{true_w}))
                : ($move_ai
                    ? length($align->[$ai]->{trans_w})
                    : 0 # punctation
                  ),
        #dist => ($move_ti && $move_ai) ? ($align->[$ai]->{dist} // length($align->[$ai]->{true_w})) : 0,
        len => $move_ai ? length($align->[$ai]->{true_w} // $align->[$ai]->{trans_w}) : 0,
        #len => $move_ai ? length($align->[$ai]->{true_w} // '') : 0,
        word => $move_ti ? $toks->[$ti]->{token} : undef,
        u_pos_start => $u_len,
        u_pos_end => $new_u_len,
        word_audio => $move_ai ? $align->[$ai]->{trans_w} : undef,
        aligned => ($move_ti + $move_ai == 2 && $align->[$ai]->{start}) ? 1 : 0,
        is_in_audio => $move_ai,
        is_in_token => $move_ti,
        no_space_after => $move_ti ? $toks->[$ti]->{no_space_after} : 1,
        start_time => $move_ai ? $align->[$ai]->{start} : undef,
        end_time => $move_ai ? $align->[$ai]->{end} : undef,
        time_len_ms => $move_ai ? $align->[$ai]->{time_len_ms} : undef,
      };
      $u_len = $new_u_len + (($move_ti && !$toks->[$ti]->{no_space_after}) ? 1 : 0);
    }
    $ai += $move_ai;;
    $ti += $move_ti;
  }
  return @result;
}

sub proces_sentence {
  my $result = shift;
  my $max_error_rate = shift;
  my $crop_level = shift;
  my $partial_sentence_min_len = shift;
  my $sentence = shift;
  my @alignment = @_;

  # remove mismatchs from the beginning
  my @beginning = ();
  while(@alignment && !$alignment[0]->{aligned}) { #ends at the first aligned token
    my $elem = shift @alignment;
    unshift @beginning, $elem if $elem->{id};
  }
  unshift @alignment, (shift @beginning) while(@beginning);

  # remove mismatchs from the end
  my @ending = ();
  while(@alignment && !$alignment[$#alignment]->{aligned}) { #ends at the last aligned token
    my $elem = pop @alignment;
    push @ending, $elem if $elem->{id}
  }
  push @alignment, pop @ending while(@ending);

  $result->{report}->{processed} += 1 if $crop_level == WHOLE;

  my $sent_dist = List::Util::sum(map { $_->{dist} } @alignment);
  my $sent_len_all = List::Util::sum(map { $_->{len} } @alignment);
  return unless $sent_len_all;
  my $result_error_rate = $sent_dist / $sent_len_all;

  if(($result_error_rate <= $max_error_rate) && (($crop_level == WHOLE) || ($partial_sentence_min_len <= @alignment)) ) {
    #print STDERR ($crop_level == WHOLE ? "WHOLE-":'PARTIAL-'),"SENTENCE: DIST=$sent_dist ERROR-ALL=$result_error_rate\n";
    #print STDERR "\tTEXT: ",join(" ",map {$_->{word}//'-'} @alignment),"\n";
    #print STDERR "\tAUDIO:",join(" ",map {$_->{word_audio}//'-'} @alignment),"\n";
    sentence_to_result($result, \@alignment,{%$sentence, token_char_error_rate => $result_error_rate},$crop_level);
    if($crop_level == WHOLE){
      $result->{report}->{result_sent} += 1;
    } else {
      $result->{report}->{result_part} += 1;
    }
  } elsif (@alignment >= 3 && @alignment >= $partial_sentence_min_len) {
    # calculate floating mismatch
    #print STDERR "DEAL WITH PUNCTATION - best space for division !!!";
    my @floating_dist = (
      $alignment[0]->{dist},
      (map {List::Util::sum(map {$alignment[$_]->{dist}} ($_-1,$_,$_+1) ) } (1..($#alignment-1))),
      $alignment[$#alignment]->{dist}
    );
    #print STDERR "($crop_level)===== split sentence $result_error_rate  ($max_error_rate)\n";
    my $max_idx = List::Util::reduce { $floating_dist[$a] > $floating_dist[$b] ? $a : $b } 0..$#floating_dist;
    #print STDERR "\t",join(' ',@floating_dist),"\n";
    #print STDERR "\t",join(' ',@floating_dist[0..($max_idx-1)])," ## ", join(' ',@floating_dist[($max_idx+1)..$#floating_dist]),"\n";
    #print STDERR "\tTEXT: ",join(" ",map {$max_idx == $_ ? '##' : $alignment[$_]->{word}//'-'} (0..$#alignment)),"\n";
    #print STDERR "\tAUDIO:",join(" ",map {$max_idx == $_ ? '##' : $alignment[$_]->{word_audio}//'-'} (0..$#alignment)),"\n";
    proces_sentence($result, $max_error_rate, SPLIT, $partial_sentence_min_len, $sentence, @alignment[0..($max_idx-1)]) if $max_idx > $partial_sentence_min_len;
    proces_sentence($result, $max_error_rate, SPLIT, $partial_sentence_min_len, $sentence, @alignment[($max_idx+1)..$#floating_dist]) if $#floating_dist-$max_idx+1 > $partial_sentence_min_len;
  }
}

sub sentence_to_result {
  my ($result,$alignment,$meta,$status) = @_;
  my $id_prefix = 'ParlaMint-CZ_'.$meta->{date}.'-';
  my $id = $id_prefix.$meta->{sid}.'_'. join('-',map {(split '\.', $_->{id})[-1] } @$alignment[0,-1]);
  my ($time_s,$time_e);
  my ($text_start,$text_end);
  my $time_len = 0;
  my $text = '';
  my $text_audio = '';
  my @words;
  for my $tok (@$alignment){
    my $word = {};
    $word->{char_s} = length($text) + 0; # force number
    $text .=  $tok->{word}//'';
    $text_audio .=  $tok->{word_audio} ? ($tok->{word_audio}.' ') : '';
    if($tok->{aligned}){
      $word->{char_e} = length($text) + 0;
      $word->{time_s} = $tok->{start_time};
      $word->{time_e} = $tok->{end_time};
      $word->{id} = $tok->{id};
      push @words, $word;
      $time_s //= $tok->{start_time};
      $time_e = $tok->{end_time};
      $time_len += $tok->{end_time} - $tok->{start_time};
    }
    $text_start //= $tok->{u_pos_start} + 0;
    $text_end = $tok->{u_pos_end} + 0;
    $text .= ' ' unless $tok->{no_space_after};
  }
  $text =~ s/ $//; # removing space after sentence (inside paragraph)
  $text_audio =~ s/ $//; # removing space after sentence (inside paragraph)

  my $audio_start = $time_s;
  my $audio_end = $time_e;
  $_->{time_s}= ($_->{time_s} - $audio_start)/1000+0 for @words;
  $_->{time_e} = ($_->{time_e} - $audio_start)/1000+0  for @words;
  my $audio_pref = $meta->{audio_file};
  $audio_pref =~ s/.mp3//;
  $result->{json_obj}->add_line(
    {
      id => $id,
      sentence_id => $id_prefix.$meta->{sid},
      words => \@words,
      audio_source => $meta->{audio_file},
      audio => sprintf('%s_%0.2f-%0.2f.flac', $audio_pref, ($audio_start / 1000), ($audio_end / 1000)),
      text_start => $text_start,
      text_end => $text_end,
      audio_start => $audio_start / 1000 + 0,
      audio_end => $audio_end / 1000 + 0,
      audio_length => ($audio_end - $audio_start)/1000 + 0,
      text => $text,
      speaker_info => $meta_db{$id_prefix.$meta->{uid}}
    }
    ,$result->{fh});

  $result->{report}->{audio_len} += $time_e-$time_s;
  $result->{report}->{audio_tokens_len} += $time_len;
  $result->{report}->{audio_gaps_len} += $time_e - $time_s - $time_len;
}

#close $RANGES;
close $OUTPUT;