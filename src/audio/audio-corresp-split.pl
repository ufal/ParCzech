use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use File::Basename;
use File::Spec;
use File::Path;


my $scriptname = $0;
my $dirname = dirname($scriptname);
my $dirOut = shift @ARGV;

my ($nFile,$oFile);
my $OUT;

while(my $line = <STDIN>){
  $line =~ s/\n//;
  ($nFile) = $line =~ m/^.*AUDIO.*\/\/(.*).mp3/;
  print STDERR "WARN: missing audio on page - should be closed and not overflow to next page\n" if $line =~ m/^#.*AUDIO/ && $line !~ m/^#.*mp3/;
  if($nFile && $nFile ne $oFile){
    close $OUT if $oFile;
    $oFile = $nFile;
    my $file = File::Spec->catfile($dirOut,"$oFile.tsv");
    my $dir = dirname($file);
    File::Path::mkpath($dir) unless -d $dir;
    open $OUT, ">$file";
  } elsif ($line && $line !~ m/^#.*AUDIO/)  {
    print $OUT "$line\n";
  }
}
close $OUT if $oFile;
