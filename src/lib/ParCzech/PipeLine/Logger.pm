package ParCzech::PipeLine::Logger;

use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use DateTime;


sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my %opts = @_;
  my $self  = {};
  bless $self, $class;
  $self->{prefix} = $opts{prefix} if defined $opts{prefix};
  $self->{tz} = DateTime::TimeZone->new( name => 'local' ) // DateTime::TimeZone->new( name => 'floating' ) // DateTime::TimeZone->new( name => 'UTC' );
  return $self
}


sub log_line {
  my $self = shift;
  my $date =   DateTime->now(time_zone => $self->{tz})->strftime('%Y-%m-%d %T');
  print STDERR "$date\t",$self->get_prefix,join(' ',@_),"\n";
}

sub get_prefix {
  my $self = shift;
  return '' unless defined $self->{prefix};
  return "($self->{prefix}) ";
}


1;