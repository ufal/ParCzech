package TEI::ParlaClarin;

use strict;
use warnings;

use File::Spec;
use File::Basename;

use XML::LibXML;
use XML::LibXML::PrettyPrint;
use Unicode::Diacritic::Strip;

binmode STDOUT, ":utf8";
#binmode STDERR, ":utf8";
use open OUT => ':utf8';

sub new {
  my ($class, %params) = @_;
  my $self;
  $self->{STATS}->{u} = 0;
  $self->{STATS}->{tei} = 0;
  $self->{output}->{dir} = $params{output_dir} // '.';
  $self->{DOM} = XML::LibXML::Document->new("1.0", "UTF8");
  my $root_node =  XML::LibXML::Element->new("teiCorpus");
  $self->{ROOT} = $root_node;
  $self->{TEI} = []; # list of TEI documents included in teiCorpus
  $self->{PERSON_IDS} = {};
  $self->{THIS_TEI_PERSON_IDS} = {};
  $self->{activeTEI} = undef;
  $self->{activeUtterance} = undef;
  my $personlistfilename = 'person.xml';
  my $personlistfilepath = File::Spec->catfile($self->{output}->{dir},$personlistfilename);
  $self->{personlistfile} = {name => $personlistfilename, path=> $personlistfilepath};



  $self->{DOM}->setDocumentElement($root_node);
  #$root_node->setNamespace('http://www.tei-c.org/ns/1.0');
  $self->{HEADER} = XML::LibXML::Element->new("teiHeader");
  $root_node->appendChild($self->{HEADER});
  bless($self,$class);
  $self->{PERSONLIST} = $self->getPersonlistDOM($personlistfilepath);
  # $self->addNamespaces($root_node, tei => 'http://www.tei-c.org/ns/1.0', xml => 'http://www.w3.org/XML/1998/namespace');
  if(exists $params{id}) {
  	$self->{ID} = $params{id};
  	#$root_node->setAttributeNS($self->{NS}->{xml}, 'id', $params{id});
  	$root_node->setAttribute('id', $params{id});
  }
  return $self;
}

sub load_tei {
  my ($class, %params) = @_;
  my $self;
  if($params{file}) {
    open my $fh, '<', $params{file};
    binmode $fh;
    my $dom = XML::LibXML->load_xml(IO => $fh)
    # close $fh;
    unless($dom->documentElement()->nodeName eq 'TEI') {
      print STDERR "Unsupported root element"
      return undef;
    }

  } else {
    return undef;
  }
}

sub toString {
  my $self = shift;
  return $self->{DOM}->toString();
}

sub toFile {
  my $self = shift;
  my $filename = shift // File::Spec->catfile($self->{output}->{dir},$self->{ID});
  my $suffix = '';
  my $authorized = $self->{authorized} ? '' : 'u';
  while(-f "$filename$authorized$suffix.xml"){
    $suffix = 'a' unless $suffix;
    $suffix = chr(ord($suffix)+1);
  }
  if($suffix || $authorized){
  	$self->updateIds($self->{ID},$self->{ID}.$authorized.$suffix)
  }

  my $listPerson;

=fix
  if(%{$self->{PERSON_IDS}}){ # FIX THIS !!!
  	$listPerson = XML::LibXML::Element->new("listPerson");
  	$self->{HEADER}->appendChild($listPerson);
    for my $pid (sort keys %{$self->{PERSON_IDS}}) {
      $listPerson->appendChild($self->{PERSON_IDS}->{$pid});
    }
  }
=cut

  $filename = "$filename$authorized$suffix.xml";

  my $pp = XML::LibXML::PrettyPrint->new(
  	indent_string => "  ",
    element => {
        inline   => [qw/note/],
        #block    => [qw//],
        #compact  => [qw//],
        preserves_whitespace => [qw/u/],
        }
    );
  $pp->pretty_print($self->{DOM});
  $self->{DOM}->toFile($filename);
  $listPerson->unbindNode() if $listPerson;
  return $filename;
}

sub teiToFile { # exports only tei document and use header, namespaces and id from teiCorpus
  my $self = shift;
  my %params = @_;
  my @id_parts = split '-', $self->{ID};
  my $filename = $params{outputfile} // File::Spec->catfile($self->{output}->{dir},join("-",@id_parts[0,1]),$self->{ID});
  my $dir = dirname($filename);
  File::Path::mkpath($dir) unless -d $dir;
  my $suffix = '';
  my $authorized = $self->{authorized} ? '' : 'u';
  while(-f "$filename$authorized$suffix.xml"){
    $suffix = 'a' unless $suffix;
    $suffix = chr(ord($suffix)+1);
  }
  my $teiDoc = XML::LibXML::Document->new("1.0", "UTF8");
  my $teiClone = $self->_getTei()->cloneNode(1);
  #$teiClone->setNamespace('http://www.tei-c.org/ns/1.0');
  #$teiClone->setNamespace($self->{NS}->{$_},$_,0) for keys %{$self->{NS}};
  #$teiClone->setAttributeNS($self->{NS}->{xml}, 'id', $self->{ID});
  $teiClone->setAttribute('id', $self->{ID});
  $teiDoc->setDocumentElement($teiClone);
  if($suffix || $authorized){
  	#updateIds({DOM => $teiDoc, NS => $self->{NS}},$self->{ID},$self->{ID}.$authorized.$suffix)
  	updateIds({DOM => $teiDoc},$self->{ID},$self->{ID}.$authorized.$suffix)
  }
  my $listPerson;
  if(%{$self->{THIS_TEI_PERSON_IDS}}){
  	$listPerson = XML::LibXML::Element->new("listPerson");
  	_get_child_node_or_create($teiClone,'teiHeader')->appendChild($listPerson);
    for my $pid (sort keys %{$self->{THIS_TEI_PERSON_IDS}}) {
      my $pers = XML::LibXML::Element->new("person");
      #$pers->setAttributeNS($self->{NS}->{xml}, 'id', $pid);
      $pers->setAttribute('id', $pid);
      $pers->setAttribute('corresp', $self->{personlistfile}->{name}."#".$pid);
      $listPerson->appendChild($pers);
    }
  }
  $filename = "$filename$authorized$suffix.xml";

  my $pp = XML::LibXML::PrettyPrint->new(
  	indent_string => "  ",
    element => {
        inline   => [qw/note/],
        #block    => [qw//],
        #compact  => [qw//],
        preserves_whitespace => [qw/u/],
        }
    );
  $pp->pretty_print($teiDoc);
  $teiDoc->toFile($filename);

  # save personlist
  if($self->{PERSONLIST}) {
    $pp->pretty_print($self->{PERSONLIST});
    $self->{PERSONLIST}->toFile($self->{personlistfile}->{path});
  }
  return $filename;
}

sub addNamespaces {
  my $self = shift;
  my $elem = shift;
  $self->{NS}={} unless exists $self->{NS};
  my %ns = @_;
  while( my ($prefix, $uri) = each %ns) {
  	$elem->setNamespace($uri,$prefix,0);
  	$self->{NS}->{$prefix} = $uri;
  }
  return $self;
}


sub updateIds {
  my $self = shift;
  my $old = shift;
  my $new = shift;
  foreach my $node ($self->{DOM}->findnodes('//*[@xml:id]')) {
    #my $attr = $node->getAttributeNS($self->{NS}->{xml}, 'id');
    my $attr = $node->getAttribute('id');
    $attr =~ s/^$old/$new/;
    #$node->setAttributeNS($self->{NS}->{xml}, 'id', $attr);
    $node->setAttribute('id', $attr);
  }
  return $self;
}


sub newTEI {
  my $self = shift;
  my %params = @_;
  my $tei = XML::LibXML::Element->new("TEI");
  $self->{authorized} = 1;
  push @{$self->{TEI}}, $tei;
  $self->{activeTEI} = $tei;
  $self->{ROOT}->appendChild($tei);
  if(exists $params{id} && defined $params{id}) {
  	#$tei->setAttributeNS($self->{NS}->{xml}, 'id', $params{id});
  	$tei->setAttribute('id', $params{id});
  	$self->{ID} = $params{id};
  }
  $tei->appendChild(XML::LibXML::Element->new("teiHeader"));
  $self->{ROOT}->appendChild($tei);
  $self->{STATS}->{tei}++;
  return $self;
}

sub addUtterance { # don't change actTEI
  my $self = shift;
  my %params = @_;
  my $tei_text = _get_child_node_or_create($self->_getTei(%params),'text');
  my $u = XML::LibXML::Element->new("u");
  if(exists $params{author}) {
    my $author_xml_id = $self->addAuthor(%{$params{author}});
    $author_xml_id = "#$author_xml_id" if $author_xml_id;
    $u->setAttribute('who',$author_xml_id // $params{author}->{author_full});
    if($params{author}->{author_full}) {
      my $note = XML::LibXML::Element->new("note");
      $note->setAttribute('type','speaker');
      $note->appendText($params{author}->{author_full});
      $tei_text->appendChild($note);
    }
  }
  #$u->setAttributeNS($self->{NS}->{xml}, 'id', $params{id}) if exists $params{id};
  $u->setAttribute('id', $params{id}) if exists $params{id};
  if(exists $params{link}) {
    my $url_note = XML::LibXML::Element->new("note");
    my $url_idno = XML::LibXML::Element->new("idno");
    $url_idno->setAttribute('type','URI');
    $url_idno->appendText($params{link});

    $url_note->appendChild($url_idno);
    $u->appendChild($url_note);
  }
  $u->appendText($params{text}//'');
  $u->appendChild($_) for (@{$params{html}//[]});

  $tei_text->appendChild($u);
  $self->{activeUtterance} = $u;
  $self->{STATS}->{u}++;
  return $self;
}

sub addAuthor {
  my $self = shift;
  my %params = @_;
  return unless $params{id};
  my $xmlid = _to_xmlid($params{name},$params{id});
  return unless $xmlid;
  return $xmlid if exists $self->{THIS_TEI_PERSON_IDS}->{$xmlid};
  if(exists $self->{PERSON_IDS}->{$xmlid}) {
    $self->{THIS_TEI_PERSON_IDS}->{$xmlid} = $self->{PERSON_IDS}->{$xmlid};
    return $xmlid;
  }

  my $person = XML::LibXML::Element->new("person");
  #$person->setAttributeNS($self->{NS}->{xml}, 'id', $xmlid);
  $person->setAttribute('id', $xmlid);
  my $persname = XML::LibXML::Element->new("persName");
  $person->appendChild($persname);
  $persname->appendText($params{name});
  my $idno =  XML::LibXML::Element->new("idno");
  $person->appendChild($idno);
  $idno->appendText('https://www.psp.cz/sqw/detail.sqw?id='.$params{id});
  $idno->setAttribute('type', 'URI');
  $self->{PERSON_IDS}->{$xmlid} = $person;
  $self->{THIS_TEI_PERSON_IDS}->{$xmlid} = 1;
  $self->{PERSONLIST}->documentElement()->appendChild($person) if $self->{PERSONLIST};
  return $xmlid;
}

sub addHead {
  my $self = shift;
  my $text = shift;
  my $tei_text = _get_child_node_or_create($self->_getTei(),'text');
  my $head = XML::LibXML::Element->new("head");
  $head->appendText($text//'');
  $tei_text->appendChild($head);
  return $self;
}

sub setUnauthorizedFlag {
  my $self = shift;
  $self->{authorized} = 0;
  return $self;
}

sub addTimeNote {
  my $self = shift;
  my %params = @_;
  my $tei_text = _get_child_node_or_create($self->_getTei(%params),'text');
  my $note = XML::LibXML::Element->new("note");
  $note->setAttribute('type','time');
  $note->appendText($params{before}//'');
  my $time = XML::LibXML::Element->new("time");
  $time->setAttribute('from',$params{from}) if exists $params{from};
  $time->setAttribute('to',$params{to}) if exists $params{to};
  $time->appendText($params{texttime}//'');
  $note->appendChild($time);
  $note->appendText($params{before}//'');
  $tei_text->appendChild($note);
  return $self;
}

sub addAudioNote {
  my $self = shift;
  my %params = @_;
  my $tei_text = _get_child_node_or_create($self->_getTei(%params),'text');
  my $note = XML::LibXML::Element->new("note");
  $note->setAttribute('type','media');
  my $media = XML::LibXML::Element->new("media");
  $media->setAttribute('mimeType',$params{mimeType} // 'audio/mp3');
  $media->setAttribute('url',$params{url}) if exists $params{url};
  $note->appendChild($media);
  $tei_text->appendChild($note);
  return $self;
}


sub isEmpty {
  my $self = shift;
  my $el = shift // 'u';
  return !defined($self->{STATS}->{u}) || $self->{STATS}->{u} == 0;
}

sub size {
  my $self = shift;
  my $el = shift // 'u';
  return $self->{STATS}->{u} // 0;
}

sub corpusID {
  my $self = shift;
  return $self->{ID};
}

sub getTeiAt {
  my ($self,$idx) = @_;
  return undef unless defined $idx;
  return $self->{TEI}->[$idx];
}

sub _getTei {
  my $self = shift;
  my %params = @_;
  return $params{tei}//$self->getTeiAt($params{tei})//$self->{activeTEI};
}


sub setActDate {
  my $self = shift;
  my $date = shift;
  my $profileDesc = _get_child_node_or_create($self->{HEADER}, "profileDesc");
  my $creation = XML::LibXML::Element->new("creation");
  my $date_node = XML::LibXML::Element->new("date");
  $date_node->setAttribute('when',$date);
  $creation->appendChild($date_node);
  $profileDesc->appendChild($creation)
}
sub setRevisionDate {
  my $self = shift;
  my $date = shift;
  my $status = shift;
  my $revisionDesc = _get_child_node_or_create(_get_child_node_or_create($self->{activeTEI}, "teiHeader"), "revisionDesc");
  $revisionDesc->setAttribute('status',$status) if $status;
  if($date){
    my $date_node = XML::LibXML::Element->new("change");
    $date_node->setAttribute('when',$date);
    $revisionDesc->appendChild($date_node);
  }
}


sub getPersonlistDOM {
  my $self = shift;
  my $filepath = shift;
  my $DOM;
  if(-f $filepath) {
    $DOM = XML::LibXML->load_xml(location => $filepath);
    #$self->{PERSON_IDS}->{$_->getAttributeNS($self->{NS}->{xml}, 'id')} = $_ for $DOM->documentElement()->findnodes(".//person"); ###########
    $self->{PERSON_IDS}->{$_->getAttribute('id')} = $_ for $DOM->documentElement()->findnodes(".//person"); ###########
  } else {
    $DOM = XML::LibXML::Document->new("1.0", "UTF8");
    my $root =  XML::LibXML::Element->new("personList");
    $DOM->setDocumentElement($root);
  }
  return $DOM;
}

# ===========================

sub _get_child_node_or_create {
  my $node = shift;
  my $newName = shift;
  return $_ for (reverse $node->findnodes("./$newName")); # get last valid child
  my $child = XML::LibXML::Element->new($newName);
  $node->appendChild($child);
  return $child;

}

sub _to_xmlid {
  return join('',map {my $p = $_; $p =~ s/\s*//g; Unicode::Diacritic::Strip::strip_diacritics($p)} @_);
}




1;