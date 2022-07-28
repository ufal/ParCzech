package ParCzech::Translation;

use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use File::Spec;


sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my %opts = @_;
  my $self  = {};
  bless $self, $class;

  $self->{static_dict} = {};
  $self->load_files(! defined $opts{single_direction}, ref($opts{tran_files}) eq 'ARRAY' ? (@{$opts{tran_files}}) : ($opts{tran_files})) if $opts{tran_files};
  $self->{regex_dict} = $opts{tran_regex} // [];
  $self->{keep_if_no_match} = defined $opts{keep_if_no_match};
  return $self
}

sub load_files {
  my $self = shift;
  my $bothdirections = shift;
  my @files = @_;
  while(my $file = shift @files) {
    open(my $fh,"<:encoding(utf-8)",  $file) or die "Cannot open:$!\n";
    while(my $line = <$fh>) {
      my ($from, $to) = map {s/^\s*$//; s/^\s*//; s/\s*$//; $_} split('\|',$line);
      $self->add_translation($from,$to);
      $self->add_translation($to, $from) if $bothdirections;
    }
    close($fh);
  }
}

sub translate_static {
  my $self = shift;
  my $str = shift;
  return undef unless $str;
  $str =~ s/^\s*|\s*$//g;
  $str =~ s/  */ /g;
  return $self->{static_dict}->{$str} if defined $self->{static_dict}->{$str};
  return $self->{static_dict}->{lc $str} if defined $self->{static_dict}->{lc $str};
  for my $tr (@{$self->{regex_dict}}) {
    my ($r,$t,$templ) = @$tr;
    return $templ ? sprintf($templ,$str =~ m/$r/) : $t if $str =~ m/$r/;
  }
  return "$str" if $self->{keep_if_no_match}; # keep no translation
  return undef;
}

sub add_translation {
  my $self = shift;
  my ($from, $to) = @_;
  $self->{static_dict}->{$from} = $to unless defined $self->{static_dict}->{$from};
  $self->{static_dict}->{lc $from} = lc $to unless defined $self->{static_dict}->{lc $from};
}






1;