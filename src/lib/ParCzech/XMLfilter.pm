package ParCzech::XMLfilter;

use warnings;
use strict;
# use open qw/:std :encoding(UTF-8)/;
use utf8;
use File::Spec;
use File::Copy;
use File::Basename;
use XML::LibXML qw(:libxml);
use ParCzech::PipeLine::FileManager __PACKAGE__;

my $XMLNS = 'http://www.w3.org/XML/1998/namespace';



sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my %opts = @_;
  my $self  = {};
  bless $self, $class;
  $self->{targets} = {};
  if(defined $opts{file}){
    my $xml = ParCzech::PipeLine::FileManager::XML::open_xml($opts{file});
    if($xml){
      $self->{source} = {
        path => $opts{file},
        base => dirname($opts{file}),
        dom => $xml->{dom},
      };
    }
  }
  return $self;
}


sub add_target_filter {
  my $self = shift;
  my %opts = @_;
  my $file = $opts{file};
  return unless defined $file; # target is not defined
  undef $opts{file};
  my $dom = $self->clone_source_dom();

  $self->{targets}->{$file} = {
    params => {%opts},
    file_path => $file,
    ($dom) ? (dom => $dom) : (),
  };
  return $self;
}

sub clone_source_dom {
  my $self = shift;
  if(defined $self->{source}){
    my $res = XML::LibXML::Document->new("1.0", "utf-8");
    $res->setDocumentElement($self->{source}->{dom}->documentElement()->cloneNode(1));
    return $res;
  }
}

sub process_filters {
  my $self = shift;
  print STDERR "NO FILTER PROCESSING\n";
  return $self;
}

sub save_to_file {
  my $self = shift;
  for my $target (values %{$self->{targets}}) {
    ParCzech::PipeLine::FileManager::XML::save_to_file($target->{dom}, $target->{file_path});
  }
  return $self;
}

sub get_abs_path {
  my $self = shift;
  my $file = shift;
  return unless $file;
  return unless $self->{source};
  return File::Spec->catfile($self->{source}->{base}, $file);
}

sub cli {
  my $self = shift;
  my $source = shift;
  my $target = shift;
  my $filter = ParCzech::XMLfilter->new(file => $source);
  $filter->add_target_filter(file => $target);
  $filter->process_filters();
  $filter->save_to_file();
}

__PACKAGE__->cli(@ARGV) unless caller;

1;