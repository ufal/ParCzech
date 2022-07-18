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
  $self->{TEXTCLASS} = _get_child_node_or_create($self->{XPC},$self->{HEADER},qw/profileDesc textClass/);
  $self->{tei_file_list} = [];
  $self->{seen_person_id} = {};
  $self->{TERMS} = {};
  return $self;
}


sub addTeiFile {
  my $self = shift;
  my $teiFileName = shift;
  my $topic_cnt = shift;
  my $tei = shift;

  my $persfile = $tei->getPersonListFileName();
  $self->{seen_person_id}->{$_}=$persfile for (@{$tei->getPersonIdsList()});

  $self->logDate($_) for @{$tei->getPeriodDate()};
  $self->logMeeting('#parla.term',$_) for @{$tei->getMeetings('#parla.term')};
  my $srcURI = $tei->getSourceURI();
  if(defined $self->{sourceURI}) {
    my $i=0;
    while(    $i < length($srcURI)
           && $i < length($self->{sourceURI})
           && substr($srcURI, $i, 1) eq substr($self->{sourceURI}, $i, 1)){
      $i++;
    }
    if ($i < length($srcURI) || $i < length($self->{sourceURI})) {
      $self->{sourceURI} = substr($srcURI, 0, $i);
      $self->{sourceURI} =~ s/[^\/]*$//;
    }
  } else {
    $self->{sourceURI} = $srcURI
  }

  push @{$self->{tei_file_list}}, {file => $teiFileName, ord => {date => $tei->getFromDate(), epoch => $tei->getFromDate()->epoch, topic_cnt => $topic_cnt }};
}

sub toFile {
  my $self = shift;
  my %params = @_;

  if(%{$self->{seen_person_id}}){
    my $listPerson = _get_child_node_or_create($self->{XPC},$self->{ROOT},'teiHeader', 'profileDesc', 'particDesc', 'listPerson');
    for my $pid (sort keys %{$self->{seen_person_id}}) {
      my $pers = XML::LibXML::Element->new("person");
      $pers->setAttributeNS($self->{NS}->{xml}, 'id', $pid);
      $pers->setAttribute('corresp', $self->{seen_person_id}->{$pid}->{name}."#".$pid);
      $listPerson->appendChild($pers);
    }
  }
  for my $term (sort @{$self->getMeetings('#parla.term') // []}){
    $self->addMeetingData('term',$term);
  }

  my $nsUri = $self->{XPC}->lookupNs('xi');
  for my $tf (sort  {   $a->{ord}->{epoch} <=> $b->{ord}->{epoch}
                     || $a->{ord}->{topic_cnt} <=> $b->{ord}->{topic_cnt}}
                    @{$self->{tei_file_list}}) {
    my $child = $self->{ROOT}->addNewChild($nsUri, 'include');
    $child->setAttribute('href', $tf->{file})
  }

  my $dt = $self->getPeriodDateNode(attr => '%Y-%m-%d',text => '%d.%m.%Y');
  $self->{SETTING}->appendChild($dt) if $dt;
  return $self->SUPER::toFile(%params, outputfile => File::Spec->catfile($self->{output}->{dir},$self->{ID}.'.xml'));
}

sub getSourceURI {
  return shift->{sourceURI};
}

# ===========================

sub _get_child_node_or_create { # allow create multiple tree ancestors
  return TEI::ParlaClarin::_get_child_node_or_create(@_);
}


sub _to_xmlid {
  return TEI::ParlaClarin::_to_xmlid(@_);
}
1;