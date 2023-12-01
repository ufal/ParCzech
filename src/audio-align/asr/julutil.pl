#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use 5.010;

# KenLM orders tokens by latest which confuses julius
package LmSort;
sub sort_lm {
  while (<>) {
    print;
    ngrams() if /-grams:/
  }
}
sub ngrams {
  my @grams;
  while (<>) {
    last if /^$/;
    # score1 \t token1 \t token2 \t score2 => token1 \t token2 \t score2 \t score1
    chomp;
    push @grams, join(';;;', (split /\t/, $_, 2)[1, 0]);
  }
  my $sep = $_;
  say join("\t", (split /;;;/)[1, 0]) for sort @grams;
  print $sep;
}

package RecoutAggr;

use Encode qw(decode encode_utf8);
my $enc = 'iso-8859-2';

sub aggregate {
  @ARGV = sort {
    my ($sa) = $a =~ /from-([^-]+)-/;
    my ($sb) = $b =~ /from-([^-]+)-/;
    return $sa <=> $sb;
  } @ARGV;
  my $failed = 0;
  my $last_file = '';
  my $offset = 0;
  my $tokens_cnt = 0;
  my $success = 0;
  my %end2word;
  while (<>) {
    if ($ARGV ne $last_file) {
      $failed += aggr_end_print_status($tokens_cnt,$last_file,$success) if $last_file;
      $last_file = $ARGV;
      ($offset) = $ARGV =~ /from-([^-]+)-/;
      print STDERR "INFO: start $last_file\n";
      $tokens_cnt = 0;
      $success = 0;
    }
    if (/-- word alignment --/ .. /=== end forced alignment ===/) {
      my $str = decode $enc, $_;

      # cs as in centiseconds
      my ($start_cs, $end_cs, $word_uc) = $str =~ /\[\s*(\d+)\s+(\d+)\s*\]\s+\S+\s+(\S+)/ or next;
      my $start = $offset + $start_cs / 100;
      my $end = $offset + $end_cs / 100;
      my $word = lc $word_uc;

      next if $word =~ /</;

      $end2word{$end_cs} = { start => $start,  end => $end, word => encode_utf8 $word };
    }
    if (/-- phoneme alignment --/ .. /=== end forced alignment ===/) {
      my $str = decode $enc, $_;

      if (my ($start_cs, $end_cs, $triphone) = $str =~ /\[\s*(\d+)\s+(\d+)\s*\]\s+\S+\s+(\S+)/) {
        my $phone = $triphone;
        $phone =~ s/.*?-//;
        $phone =~ s/\+.*//;
        if ($end2word{$end_cs} and $phone =~ /sp|sil/) {
          $end2word{$end_cs}{end} = $offset + $start_cs / 100;
        }
      }
      if (/=== end forced alignment ===/) {
        for my $wordkey (sort {$a <=> $b} keys %end2word) {
          say join ' ', $end2word{$wordkey}{start}, $end2word{$wordkey}{end}, $end2word{$wordkey}{word};
        }
        $tokens_cnt = keys %end2word;
        $success = 1;
        %end2word = ();
      }
    }
  }
  if($last_file) {
    $failed += aggr_end_print_status($tokens_cnt,$last_file,$success);
  }
  die "ERROR: $failed fragments of audio files failed" if $failed
}

sub aggr_end_print_status {
  my ($cnt,$file,$success) = @_;
  print STDERR ($cnt?'INFO':'WARN').": seen $cnt tokens\n";
  if($success) {
    print STDERR "INFO: processed $file\n";
    return 0;
  } else {
    print STDERR "ERROR: processing failed $file\n";
    return 1;
  }
}

package main;
my $command = shift;
if ($command eq 'sort_lm') {
  LmSort::sort_lm();
}
elsif ($command eq 'aggregate-julout') {
  my $part_length_seconds = shift;
  RecoutAggr::aggregate($part_length_seconds);
}
else {
  die "unknown command '$command'";
}
