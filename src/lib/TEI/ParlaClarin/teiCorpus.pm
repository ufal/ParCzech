package TEI::ParlaClarin::teiCorpus;

use base 'TEI::ParlaClarin';
use strict;
use warnings;

use File::Spec;
use File::Basename;
use File::Path;

use XML::LibXML;
use XML::LibXML::PrettyPrint;
use Unicode::Diacritic::Strip;

binmode STDOUT, ":utf8";
use open OUT => ':utf8';

sub new {
  my ($class, %params) = @_;
  my $self = $class->SUPER::new('teiCorpus',%params);
  bless($self,$class);
  $self->addNamespaces($self->{ROOT}, 'xi' => 'http://www.w3.org/2001/XInclude');
  $self->{tei_file_list} = [];
  return $self;
}


sub addTeiFile {
  my $self = shift;
  my $teiFileName = shift;
  my $topic_cnt = shift;
  my $tei = shift;

  push @{$self->{tei_file_list}}, {file => $teiFileName, ord => {date => $tei->getFromDate(), epoch => $tei->getFromDate()->epoch, topic_cnt => $topic_cnt }};
}

sub toFile {
  my $self = shift;
  my %params = @_;
  my $nsUri = $self->{XPC}->lookupNs('xi');
  for my $tf (sort  {   $a->{ord}->{epoch} <=> $b->{ord}->{epoch}
                     || $a->{ord}->{topic_cnt} <=> $b->{ord}->{topic_cnt}}
                    @{$self->{tei_file_list}}) {
    my $child = $self->{ROOT}->addNewChild($nsUri, 'include');
    $child->setAttribute('href', $tf->{file})
  }
  return $self->SUPER::toFile(%params, outputfile => File::Spec->catfile($self->{output}->{dir},$self->{ID}.'.xml'));
}

1;