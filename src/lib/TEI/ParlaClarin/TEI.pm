package TEI::ParlaClarin::TEI;

use strict;
use warnings;

use File::Spec;
use File::Basename;
use File::Path;

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
  $self->{output}->{dir} = $params{output_dir} // '.';
  $self->{DOM} = XML::LibXML::Document->new("1.0", "UTF8");
  my $root_node =  XML::LibXML::Element->new("TEI");
  $self->{ROOT} = $root_node;
  $self->{PERSON_IDS} = {};
  $self->{THIS_TEI_PERSON_IDS} = {};
  $self->{QUEUE} = [];
  $self->{activeUtterance} = undef;
  my $personlistfilename = 'person.xml';
  my $personlistfilepath = File::Spec->catfile($self->{output}->{dir},$personlistfilename);
  $self->{personlistfile} = {name => $personlistfilename, path=> $personlistfilepath};
  $self->{DOM}->setDocumentElement($root_node);
  $self->{HEADER} = XML::LibXML::Element->new("teiHeader");
  $root_node->appendChild($self->{HEADER});

  bless($self,$class);
  $self->{PERSONLIST} = $self->getPersonlistDOM($personlistfilepath);
  $self->{METADATA} = _get_child_node_or_create($self->{HEADER},'notesStmt');
  $self->addMetadata('authorized','yes');
  $self->addNamespaces($root_node, tei => 'http://www.tei-c.org/ns/1.0', xml => 'http://www.w3.org/XML/1998/namespace');
  if(exists $params{id}) {
  	$self->{ID} = $params{id};
  	$root_node->setAttributeNS($self->{NS}->{xml}, 'id', 'doc-'.$params{id});
  }
  return $self;
}


sub load_tei {
  my ($class, %params) = @_;
  my $self;
  if($params{file}) {
    open my $fh, '<', $params{file};
    binmode $fh;
    my $dom = XML::LibXML->load_xml(IO => $fh);
    close $fh;
    unless($dom->documentElement()->nodeName eq 'TEI') {
      print STDERR "Unsupported root element\n";
      return undef;
    }
    $self->{DOM} = $dom;
    $self->{ROOT} = $dom->documentElement();
    $self->{HEADER} = _get_child_node_or_create($self->{ROOT},'teiHeader');
    $self->{METADATA} = _get_child_node_or_create($self->{HEADER},'notesStmt');
    $self->{PERSON_IDS} = {};
    $self->{THIS_TEI_PERSON_IDS} = {};
    $self->{activeUtterance} = undef;
    bless($self,$class);
    $self->{PERSONLIST} = $self->getPersonlistDOM($params{person_list}) if $params{person_list};
    $self->{ID} = $self->{ROOT}->getAttribute('id');
    return $self;
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
  my %params = @_;
  my @id_parts = split '-', $self->{ID};
  $self->appendQueue(); # append queue  to <text><body><div>

  my $filename = $params{outputfile} // File::Spec->catfile($self->{output}->{dir},join("-",@id_parts[0,1]),$self->{ID});
  my $dir = dirname($filename);
  File::Path::mkpath($dir) unless -d $dir;

  $self->addMetadata('term',$id_parts[0],1);
  $self->addMetadata('meeting',join('/',@id_parts[0,1]),1);
  $self->addMetadata('topic',join('/',map {s/[^0-9]*//g;$_} @id_parts[0,1,3]),1);

  unless($params{outputfile}) {
    my $suffix = '';
    my $unauthorized = $self->{unauthorized} ? '.u' : '';
    while(-f "$filename$suffix$unauthorized.xml"){
      $suffix = 'a' unless $suffix;
      $suffix = chr(ord($suffix)+1);
    }
    if($suffix || $unauthorized){
      updateIds({DOM => $self->{DOM}, NS => $self->{NS}},$self->{ID}, $self->{ID}.$suffix.$unauthorized)
    }
    $filename = "$filename$suffix$unauthorized.xml";
  }
  my $listPerson;
  if(%{$self->{THIS_TEI_PERSON_IDS}}){
  	$listPerson = XML::LibXML::Element->new("listPerson");
  	_get_child_node_or_create($self->{ROOT},'teiHeader')->appendChild($listPerson);
    for my $pid (sort keys %{$self->{THIS_TEI_PERSON_IDS}}) {
      my $pers = XML::LibXML::Element->new("person");
      $pers->setAttributeNS($self->{NS}->{xml}, 'id', $pid);
      $pers->setAttribute('corresp', $self->{personlistfile}->{name}."#".$pid);
      $listPerson->appendChild($pers);
    }
  }

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

  # save personlist
  if($self->{PERSONLIST}) {
    $pp->pretty_print($self->{PERSONLIST});
    $self->{PERSONLIST}->toFile($self->{personlistfile}->{path});
  }
  return $filename;
}

sub getAudioUrls {
  my $self = shift;
  my %seen;
  return [ sort grep {!$seen{$_}++} map {$_->getAttribute('url')} $self->{ROOT}->findnodes('.//media[@url][@mimeType="audio/mp3"]') ];
}

sub hideAudioUrls {
  my $self = shift;
  for my $node ($self->{ROOT}->findnodes('.//note[@type="media"][./media[@url][@mimeType="audio/mp3"]]')){
    my $url = $node->findnodes('.//media/@url');
    $node->replaceNode(XML::LibXML::Comment->new("AUDIO:$url"));
  }
}


sub addAudioFile {
  my $self = shift;
  my $file = shift;
  my $rec = _get_child_node_or_create($self->{HEADER},'recordingStmt')->addNewChild(undef,'recording');
  $rec->setAttribute('type', 'audio');
  my $media = $rec->addNewChild(undef,"media");
  $media->setAttribute('mimeType', 'audio/mp3');
  $media->setAttribute('url', $file);

  return $self;
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
  foreach my $node ($self->{DOM}->findnodes('//*[@id]')) {
    my $attr = $node->getAttributeNS($self->{NS}->{xml}, 'id');
    $attr =~ s/$old/$new/;
    $node->setAttributeNS($self->{NS}->{xml}, 'id', $attr);
  }
  return $self;
}




sub addUtterance { # don't change actTEI
  my $self = shift;
  $self->appendQueue(); # appending to <text><body><div>
  my %params = @_;
  my $tei_text = _get_child_node_or_create($self->{ROOT},'text', 'body', 'div');
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
  $u->setAttributeNS($self->{NS}->{xml}, 'id', "utt-".$params{id}) if exists $params{id};
  if(exists $params{link}) {
    $u->setAttribute('source',$params{link});
  }
  for my $t (@{$params{text}//[]}) {
    if(ref $t) {
      $u->appendChild($t);
    } else {
      $u->appendText($t.' ');
    }
  }
  $u->appendChild($_) for (@{$params{html}//[]});

  $tei_text->appendChild($u);
  $self->{activeUtterance} = $u;
  $self->{STATS}->{u}++;
  return $self;
}
sub addToElemsQueue {
  my $self = shift;
  my $element = shift;
  push @{$self->{QUEUE}},$element;
}
sub addToUtterance {
  my $self = shift;
  my $element = shift;
  # adding element to queue and than append whole queue to utterance
  push @{$self->{QUEUE}},$element;
  $self->appendQueue($self->{activeUtterance});
}
sub appendQueue {
  my $self = shift;
  my $element = shift // _get_child_node_or_create($self->{ROOT},'text', 'body', 'div');
  while ( my $t = shift @{$self->{QUEUE}}) {
    if(ref $t) {
      $element->appendChild($t);
    } else {
      $element->appendText($t.' ');
    }
  }
}

sub addAuthor {
  my $self = shift;
  my %params = @_;
  return unless $params{id};
  my $xmlid = _to_xmlid('pers-', $params{name},$params{id});
  return unless $xmlid;
  return $xmlid if exists $self->{THIS_TEI_PERSON_IDS}->{$xmlid};
  if(exists $self->{PERSON_IDS}->{$xmlid}) {
    $self->{THIS_TEI_PERSON_IDS}->{$xmlid} = $self->{PERSON_IDS}->{$xmlid};
    return $xmlid;
  }

  my $person = XML::LibXML::Element->new("person");
  $person->setAttributeNS($self->{NS}->{xml}, 'id', $xmlid);
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
  _get_child_node_or_create(_get_child_node_or_create($self->{HEADER},'fileDesc'),'titleStmt')->appendTextChild('title',$text//'');
  return $self;
}

sub setUnauthorizedFlag {
  my $self = shift;
  $self->{unauthorized} = 1;
  $self->addMetadata('authorized','no',1);
  return $self;
}

sub addTimeNote {
  my $self = shift;
  my %params = @_;
  my $tei_text = _get_child_node_or_create($self->{ROOT},'text', 'body', 'div');
  my $note = $self->createTimeNoteNode(%params);
  $tei_text->appendChild($note);
  return $note;
}

sub createTimeNoteNode {
  my $self = shift;
  my %params = @_;
  my $note = XML::LibXML::Element->new("note");
  $note->setAttribute('type','time');
  $note->appendText($params{before}//'');
  my $time = XML::LibXML::Element->new("time");
  $time->setAttribute('from',$params{from}) if exists $params{from};
  $time->setAttribute('to',$params{to}) if exists $params{to};
  $time->appendText($params{texttime}//'');
  $note->appendChild($time);
  $note->appendText($params{before}//'');
  return $note;
}

sub createNoteNode {
  my $self = shift;
  my %params = @_;
  my $note = XML::LibXML::Element->new("note");
  $note->setAttribute('type',$params{type}) if exists $params{type};
  $note->appendText($params{text}//'');
  return $note;
}

sub addSittingDate {
  my $self = shift;
  my $date = shift;
  $self->addMetadata('sittingdate',$date->strftime('%Y-%m-%d')) if $date;
}

sub addAudioNote {
  my $self = shift;
  my %params = @_;
  my $tei_text = _get_child_node_or_create($self->{ROOT},'text', 'body', 'div');
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
  my $revisionDesc = _get_child_node_or_create($self->{HEADER}, "revisionDesc");
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
    $self->{PERSON_IDS}->{$_->getAttributeNS($self->{NS}->{xml}, 'id')} = $_ for $DOM->documentElement()->findnodes(".//person"); ###########
    #$self->{PERSON_IDS}->{$_->getAttribute('id')} = $_ for $DOM->documentElement()->findnodes(".//person"); ###########
  } else {
    $DOM = XML::LibXML::Document->new("1.0", "UTF8");
    my $root =  XML::LibXML::Element->new("personList");
    $DOM->setDocumentElement($root);
  }
  return $DOM;
}

sub teiID {
  my $self = shift;
  return $self->{ID};
}

sub addMetadata {
  my $self = shift;
  my ($key, $value, $force) = @_; # force means overwrite if key exists
  my $noteNode;
  ($noteNode) = $self->{METADATA}->findnodes('./note[@n="'.$key.'"]');
  return undef if !$force && $noteNode;
  unless($noteNode){
    $noteNode = $self->{METADATA}->addNewChild(undef,'note');
    $noteNode->setAttribute('n',"$key");
  } else {
    $noteNode->removeChildNodes(); # remove possibly existing text
  }
  $noteNode->appendText($value);
  return $noteNode;
}
# ===========================

sub _get_child_node_or_create { # allow create multiple tree ancestors
  my $node = shift;
  my $newName = shift;
  return $node unless $newName;
  my ($child) = reverse $node->findnodes("./$newName"); # get last valid child
  $child = $node->addNewChild(undef,$newName) unless $child;
  return _get_child_node_or_create($child, @_);
}


sub _to_xmlid {
  return join('',map {my $p = $_; $p =~ s/\s*//g; Unicode::Diacritic::Strip::strip_diacritics($p)} @_);
}




1;