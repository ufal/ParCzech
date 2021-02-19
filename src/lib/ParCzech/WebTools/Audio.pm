package ParCzech::WebTools::Audio;

use warnings;
use strict;
use utf8;
use DateTime;
use DateTime::Format::Strptime;

use LWP::Simple;
use LWP::UserAgent;


sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my %opts = @_;
  my $self  = {};
  bless $self, $class;
  $self->{debug} = 1 if defined $opts{debug};
  $self->{ua} = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });
  $self->{tested_links} = {};
  return $self;
}

sub set_term_id {
  my $self = shift;
  $self->{term} = shift;
  return $self;
}

sub test_link {
  my $self = shift;
  my $link = shift;
  my $res = $self->{ua}->head( $link );

  if ($res->is_success) {
    print STDERR "VALID LINK: $link\n" if $self->{debug};
    return 1;
  } else {
    print STDERR $res->status_line," $link\n" if $self->{debug};
    return;
  }
}

sub create_audio_link {
  my $self = shift;
  my $date = shift;
  print STDERR "TEST IF DATETIME OBJECT !!!";
  my $start = $date->clone()->subtract( minutes => ($date->minute % 10) + 2);
  my $end = $start->clone()->add(minutes => 14);
  my $link = 'https://www.psp.cz/eknih/'.$self->{term}.'/audio/'
             .$start->strftime('%Y/%m/%d/%Y%m%d%H%M')
             .$end->strftime('%H%M')
             .'.mp3';
  print STDERR "AUDIO LINK for ($self->{term},$date) \t$link\n" if $self->{debug};
  return $link;
}

sub get_audio_link {
  my $self = shift;
  my $date = shift;
  my $link = $self->create_audio_link($date);
  return $link if defined $self->{tested_links}->{$link};
  if($self->test_link($link)){
    $self->{tested_links}->{$link} = 1;
    return $link;
  }
}


sub test {
  my $audio = ParCzech::WebTools::Audio->new();#debug => 1);
  $audio->set_term_id('2017ps');
  my $strp = DateTime::Format::Strptime->new(
    pattern   => '%Y%m%d-%H%M',
    locale    => 'cs_CZ',
    time_zone => 'Europe/Prague'
  );
  while(my $line = <>){
    my $d = $strp->parse_datetime($line);
    print STDERR $audio->get_audio_link($d),"\n";
  }
}

__PACKAGE__->test(@ARGV) unless caller;

1;