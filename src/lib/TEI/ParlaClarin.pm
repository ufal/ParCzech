package TEI::ParlaClarin;




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
  my ($class, $rootname, %params) = @_;
  my $self = {};
  bless($self,$class);
  
  $self->{DOM} = XML::LibXML::Document->new("1.0", "utf-8");
  my $root_node =  XML::LibXML::Element->new($rootname);
  $self->{ROOT} = $root_node;
  $self->{DOM}->setDocumentElement($root_node);
  $self->{HEADER} = XML::LibXML::Element->new("teiHeader");
  $root_node->appendChild($self->{HEADER});
  $self->{XPC} = XML::LibXML::XPathContext->new; # xpath context - easier finding nodes with namespace (including default namespace)
  $self->addNamespaces($root_node, '' => 'http://www.tei-c.org/ns/1.0', xml => 'http://www.w3.org/XML/1998/namespace');
  if(exists $params{id}) {
    $self->{ID} = $params{id};
    $root_node->setAttributeNS($self->{NS}->{xml}, 'id', $self->{ID});
  }
  $self->{TITLESTMT} = _get_child_node_or_create($self->{XPC},$self->{HEADER},'fileDesc', 'titleStmt');
  if($params{'title'}) {
    $self->{TITLESTMT}->appendTextChild('title', $_) for (  ! ref($params{title}) eq 'ARRAY' ? $params{title} : @{$params{title}} );
  }
  $self->{DATE}={FROM => undef, TO => undef};
  return $self
}



sub logDate {
  my $self = shift;
  my $date = shift;
  return unless $date;
  $self->{DATE}->{FROM} = $date unless defined($self->{DATE}->{FROM});
  $self->{DATE}->{TO}   = $date unless defined($self->{DATE}->{TO});

  $self->{DATE}->{FROM} = $date if $self->{DATE}->{FROM} > $date;
  $self->{DATE}->{TO}   = $date if $self->{DATE}->{TO}   < $date;
  return $date;
}

sub getFromDate {
  return shift->{DATE}->{FROM};
}

sub getToDate {
  return shift->{DATE}->{TO};
}


sub addNamespaces {
  my $self = shift;
  my $elem = shift;
  $self->{NS}={} unless exists $self->{NS};
  my %ns = @_;
  while( my ($prefix, $uri) = each %ns) {
    $elem->setNamespace($uri,$prefix,$prefix eq '' ? 1 : 0);
    $self->{NS}->{$prefix} = $uri;
  }
  $self->setXPC($elem, %ns);
  return $self;
}

sub setXPC {
  my $self = shift;
  my $elem = shift;
  my %nslist = @_;
  $self->{XPC} = XML::LibXML::XPathContext->new unless $self->{XPC};
  while(my ($prefix, $uri) = each %nslist) {
    $self->{XPC}->registerNs($prefix||'tei', $uri); # use tei if no prefix !!!, it can be used while searched with $self->{XPC}
  }
}





# ========================
sub _get_child_node_or_create { # allow create multiple tree ancestors
  my $XPC = shift;
  my $node = shift;
  my $newName = shift;
  return $node unless $newName;
  my ($child) = reverse $XPC->findnodes("./$newName", $node); # get last valid child
  $child = $node->addNewChild(undef,$newName) unless $child;
  return _get_child_node_or_create($XPC,$child, @_);
}


sub _to_xmlid {
  my $self = shift;
  return join('',map {my $p = $_; $p =~ s/\s*//g; Unicode::Diacritic::Strip::strip_diacritics($p)} @_);
}
1;