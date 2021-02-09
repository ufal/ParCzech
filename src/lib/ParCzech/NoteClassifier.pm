package ParCzech::NoteClassifier;

use warnings;
use strict;
use open qw(:std :utf8);
use utf8;

my %full_match = (
  ano => [qw/vocal speaking/],
  ne => [qw/vocal speaking/],
  slibuji => [qw/vocal speaking/],
);

my @reg_match = (
  [qr/(ne)?souhlas/i, qw/vocal speaking/],
  [qr/potlesk/i, qw/kinesic applause/],
  [qr/bouchání|bouchnutí/i, qw/incident break/],
  [qr/gong/i, qw/kinesic signal/],
  [qr/odchází/i, qw/incident leaving/],
  [qr/\bhlásí\b/i, qw/kinesic gesture/],
  [qr/\bgest/i, qw/kinesic gesture/],
  [qr/^hlasy?\b/i, qw/vocal speaking/],
  [qr/hlučno|hluk|rušno|ruch|neklid/i, qw/vocal noise/],
  [qr/šum/i, qw/kinesic noise/],
  [qr/k řečni/i, qw/kinesic kinesic/],
  [qr/ukazuje/i, qw/kinesic gesture/],
  [qr/směje|smích|úsměv/i, qw/vocal laughter/],
  [qr/\bnesroz/i, qw/gap inaudible/],
  [qr/[aA]no/, qw/vocal speaking/],
  [qr/zvonění/i, qw/incident sound/],
  [qr/^hlasit[áýé]\b/i, qw/vocal speaking/],
  [qr/\bbaví\b/i, qw/vocal noise/],
  [qr/^aha\b/i, qw/vocal speaking/],
  [qr/dohad/i, qw/vocal speaking/],
  [qr/\bčas[,\.!]/i, qw/vocal speaking/],
  [qr/mimo mikrofon/i, qw/vocal speaking/],
  [qr/domluva s/i, qw/vocal speaking/],
  [qr/děkuji/i, qw/vocal speaking/],
  [qr/dotazy?\b/i, qw/vocal speaking/],
  [qr/^do sálu/i, qw/incident entering/],
  [qr/^k mikrofonu/i, qw/incident entering/],
  [qr/^dává přednost/i, qw/kinesic gesture/],
  [qr/hledá|hledí/i, qw/kinesic kinesic/],
  [qr/pobavení|vesel|oživení/i, qw/vocal noise/],
  [qr/poznámka z/i, qw/vocal noise/],
  [qr/(upozornění|upozorňuje) na čas/i, qw/kinesic gesture/],
);

sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my %opts = @_;
  my $self  = {};
  bless $self, $class;

  return $self;
}

sub classify {
  my $self = shift;
  my $string = shift;
  $string =~ s/^\((.*)\)$/$1/;
  $string =~ s/^\s*|\.?\s*$//g;
  return $full_match{lc $string} if defined($full_match{lc $string});
  for my $pattern (@reg_match) {
    my $reg = $pattern->[0];
    return [$pattern->[1], ($pattern->[1] eq 'gap' ? 'reason' : 'type'), $pattern->[2]] if $string =~ /$reg/;
  }
  return undef;
}


sub test {
  my $classifier = ParCzech::NoteClassifier->new();
  while(my $line = <>){
    my $cls = $classifier->classify($line);
    if(defined $cls){
        print "$cls->[0]\t$cls->[1]";
      } else {
        print "?\t?";
      }
    print "\t$line";
  }
}

__PACKAGE__->test(@ARGV) unless caller;

1;