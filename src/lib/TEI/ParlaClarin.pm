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
  $self->{output}->{dir} = $params{output_dir} // '.';

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
  $root_node->setAttributeNS($self->{NS}->{xml}, 'lang', 'cs');
  $self->{TITLESTMT} = _get_child_node_or_create($self->{XPC},$self->{HEADER},'fileDesc', 'titleStmt');
  $self->{SETTING} = _get_child_node_or_create($self->{XPC},$self->{HEADER},qw/profileDesc settingDesc setting/);
  for my $r (@{$params{place}//[]}) {
    my $n = XML::LibXML::Element->new('name');
    $n->appendText($r->{text});
    for my $a (keys %{$r->{attr} // {} }) {
      $n->setAttribute($a,$r->{attr}->{$a});
    }
    $self->{SETTING}->appendChild($n);
  }
  $self->{sourceDesc_bib} = XML::LibXML::Element->new('bibl');
  $self->{MEETING} = {};
  if($params{'title'}) {
    for my $tit (  ! ref($params{title}) eq 'ARRAY' ? $params{title} : @{$params{title}} ){
      for my $lng (keys %{$tit->{text}}) {
        my $n = XML::LibXML::Element->new('title');
        $self->{TITLESTMT}->appendChild($n);
        $n->appendText($tit->{text}->{$lng});
        $n->setAttribute('type', $tit->{type}) if exists $tit->{type};
        $n->setAttributeNS($self->{NS}->{xml}, 'lang', $lng);

        $self->{sourceDesc_bib}->appendChild($n->cloneNode(1));
      }
    }
  }
  $self->{DATE}={FROM => undef, TO => undef};
  return $self
}

sub toString {
  my $self = shift;
  return $self->{DOM}->toString();
}


sub toFile {
  my $self = shift;
  my %params = @_;
  my $filename = $params{outputfile};
  my $dir = dirname($filename);
  File::Path::mkpath($dir) unless -d $dir;
  my $pp = XML::LibXML::PrettyPrint->new(
    indent_string => "  ",
    element => {
        inline   => [qw/note/],
        #block    => [qw//],
        compact  => [qw/title idno date meeting name/],
        preserves_whitespace => [qw/u/],
        }
    );
  $pp->pretty_print($self->{DOM});
  $self->{DOM}->toFile($filename);
  return $filename;
}

sub addSourceDesc {
  my $self = shift;
  my $idno = XML::LibXML::Element->new('idno');
  if(defined $self->{unauthorized}) {
    my $ed = XML::LibXML::Element->new('edition');
    $ed->appendText($self->{unauthorized});
    $ed->setAttributeNS($self->{NS}->{xml}, 'lang', 'cs');
    $self->{sourceDesc_bib}->appendChild($ed);
  }
  $idno->setAttribute('type','URI');
  $idno->appendText($self->getSourceURI());
  $self->{sourceDesc_bib}->appendChild($idno);
  my $dt = $self->getPeriodDateNode(attr => '%Y-%m-%d',text => '%d.%m.%Y');
  $self->{sourceDesc_bib}->appendChild($dt) if $dt;

  my $sourceDesc = _get_child_node_or_create($self->{XPC},$self->{HEADER},'fileDesc', 'sourceDesc');
  $sourceDesc->appendChild($self->{sourceDesc_bib});
  $sourceDesc->appendChild($self->{sourceDesc_recording}) if defined $self->{sourceDesc_recording};
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

sub getPeriodDateNode {
  my $self = shift;
  my %opts = @_;
  return unless defined $self->{DATE}->{FROM};
  my $dt = XML::LibXML::Element->new('date');
  my $from = $self->{DATE}->{FROM}->strftime($opts{attr} // '%Y-%m-%d');
  my $to = $self->{DATE}->{TO}->strftime($opts{attr} // '%Y-%m-%d');
  if($from eq $to) {
    $dt->setAttribute('when', $from);
    $dt->appendText($self->{DATE}->{FROM}->strftime($opts{text} // '%Y-%m-%d'));
  } else {
    $dt->setAttribute('from', $from);
    $dt->setAttribute('to', $to);
    $dt->appendText($self->{DATE}->{FROM}->strftime($opts{text} // '%Y-%m-%d')
                    . ' - '
                    . $self->{DATE}->{TO}->strftime($opts{text} // '%Y-%m-%d'));

  }
  return $dt;
}

sub addMeetingData {
  my $self = shift;
  my ($key, $value, $force) = @_; # force means overwrite if key exists
  my $meetingNode;
  my $ana = "#parla.$key";
  ($meetingNode) = $self->{TITLESTMT}->findnodes('./meeting[@ana="'.$ana.'"]') if $force;
  unless($meetingNode){
    $meetingNode = $self->{TITLESTMT}->addNewChild(undef,'meeting');
    $meetingNode->setAttribute('ana',"$ana");
  } else {
    $meetingNode->removeChildNodes(); # remove possibly existing text
  }
  $meetingNode->setAttribute('n',"$value");
  $meetingNode->appendText($value);
  $self->logMeeting($ana,$value);
  return $meetingNode;
}

sub logMeeting {
  my $self = shift;
  my ($ana,$val) = @_;
  return unless $ana;
  return unless $val;
  $self->{MEETING}->{$ana} = {} unless defined $self->{MEETING}->{$ana};
  $self->{MEETING}->{$ana}->{$val} = 1;
}

sub getMeetings {
  my $self = shift;
  my $ana = shift;
  return unless $ana;
  return [keys %{$self->{MEETING}->{$ana} // {}}];
}


sub getPeriodDate {
  my $self = shift;
  return [] unless defined $self->{DATE}->{FROM};
  return [map {$self->{DATE}->{$_}} qw/FROM TO/];
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