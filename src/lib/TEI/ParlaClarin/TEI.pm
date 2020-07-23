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
  $self->{PAGECOUNTER} = 0;
  $self->{STATS}->{u} = 0;
  $self->{output}->{dir} = $params{output_dir} // '.';
  $self->{DOM} = XML::LibXML::Document->new("1.0", "utf-8");
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
  $self->addNamespaces($root_node, tei => 'http://www.tei-c.org/ns/1.0', xml => 'http://www.w3.org/XML/1998/namespace');

  $self->{PERSONLIST} = $self->getPersonlistDOM($personlistfilepath);
  $self->{TITLESTMT} = _get_child_node_or_create($self->{HEADER},'fileDesc', 'titleStmt');
  if($params{'title'}) {
    $self->{TITLESTMT}->appendTextChild('title', $_) for (  ! ref($params{title}) eq 'ARRAY' ? $params{title} : @{$params{title}} );
  }
  if($params{'edition'}) {
    $self->{TITLESTMT}->parentNode->addNewChild(undef,'editionStmt')->appendTextChild('edition', $params{'edition'});
  }
  $self->{TITLESTMT}->parentNode->addNewChild(undef,'publicationStmt')->addNewChild(undef,'p');
  $self->{TITLESTMT}->parentNode->addNewChild(undef,'sourceDesc')->addNewChild(undef,'p');
  $self->addMeetingData('authorized','yes');
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
    $self->{TITLESTMT} = _get_child_node_or_create($self->{HEADER},'fileDesc', 'titleStmt');
    $self->{PERSON_IDS} = {};
    $self->{THIS_TEI_PERSON_IDS} = {};
    $self->{activeUtterance} = undef;
    bless($self,$class);
    $self->{PERSONLIST} = $self->getPersonlistDOM($params{person_list}) if $params{person_list};
    # TODO -> add namespaces !!!
    $self->{ID} = $self->{ROOT}->getAttributeNS('http://www.w3.org/XML/1998/namespace','id');
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
  $self->appendQueue(1); # append queue  to <text><body><div>

  my $filename = $params{outputfile} // File::Spec->catfile($self->{output}->{dir},join("-",@id_parts[0,1]),$self->{ID});
  my $dir = dirname($filename);
  File::Path::mkpath($dir) unless -d $dir;

  $self->addMeetingData('term',$id_parts[0],1);
  $self->addMeetingData('meeting',join('/',@id_parts[0,1]),1);
  $self->addMeetingData('agenda',join('/',map {s/[^0-9]*//g;$_} @id_parts[0,1,3]),1);

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
  	_get_child_node_or_create($self->{ROOT},'teiHeader', 'profileDesc', 'particDesc')->appendChild($listPerson);
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
  $self->appendQueue(0); # appending to <text><body><div>
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
    $u->setAttribute('ana', '#'.$params{author}->{role}) if $params{author}->{role};
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
  my $no_endprint = shift // 0; # if zero - no printing at closing tei (audio and pb)
  push @{$self->{QUEUE}},[$element, $no_endprint];
}
sub addToUtterance {
  my $self = shift;
  my $element = shift;
  my $segment = shift;

  if(!defined($segment) && scalar @{$self->{QUEUE}} ) { # print queue if segment is not defined
    $self->{activeUtterance}->appendText("\n") if $self->{activeUtterance}->hasChildNodes(); #just formating
    $self->appendQueue(0,$self->{activeUtterance})
  }
  # adding element to queue and than append whole queue to utterance
  push @{$self->{QUEUE}},[$element,0];
  $self->{activeUtterance}->appendText("\n") if $self->{activeUtterance}->hasChildNodes(); # just formating
  $segment = $self->{activeUtterance}->addNewChild(undef, 'seg') unless $segment;
  return $self->appendQueue(0, $segment);
}
sub appendQueue {
  my $self = shift;
  my $isend = shift;
  my $element = shift // _get_child_node_or_create($self->{ROOT},'text', 'body', 'div');
  while ( my $elem = shift @{$self->{QUEUE}}) {
    my ($t, $noendprint) = @$elem;
    next if $isend && $noendprint;
    if(ref $t) {
      $element->appendChild($t);
    } else {
      $element->appendText($t);
    }
  }
  ## retturn segment if not closed
  return $element;
}

sub addPageBreak {
  my $self = shift;
  my %params = @_;
  my $pbNode =  XML::LibXML::Element->new("pb");
  $pbNode->setAttribute('source', $params{source}) if defined $params{source};
  $self->{PAGECOUNTER}++;
  $pbNode->setAttribute('n', $self->{PAGECOUNTER});
  $pbNode->setAttributeNS($self->{NS}->{xml}, 'id', sprintf("pb-%03d",$self->{PAGECOUNTER}));
  $self->addToElemsQueue($pbNode,1);
  return $self;
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
  return unless $text;
  my ($node) = $self->{TITLESTMT}->findnodes('./title[last()]');
  my $titlenode = XML::LibXML::Element->new("title");
  $titlenode->appendText($text);
  if($node) { # titlenodes should be at the begining !!!
    $self->{TITLESTMT}->insertAfter($titlenode,$node)
  } elsif ($self->{TITLESTMT}->firstChild()) {
    $self->{TITLESTMT}->insertBefore($titlenode, $self->{TITLESTMT}->firstChild());
  } else {
    $self->{TITLESTMT}->appendChild($titlenode);
  }
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
  my $note = $self->createTimeNoteNode(%params);
  $self->addToElemsQueue($note);
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
  return unless $date;
  my $node = _get_child_node_or_create($self->{HEADER},qw/profileDesc settingDesc setting date/);
  unless($node->textContent()) {
    $node->appendText($date->strftime('%Y-%m-%d'));
    $node->setAttribute('when', $date->strftime('%Y-%m-%d'));
    $node->setAttribute('ana', '#parla.sitting');
  }

  #$self->addMeetingData('sittingdate',$date->strftime('%Y-%m-%d')) if $date;
}

sub addAudioNote {
  my $self = shift;
  my %params = @_;
  # my $tei_text = _get_child_node_or_create($self->{ROOT},'text', 'body', 'div');
  my $note = XML::LibXML::Element->new("note");
  $note->setAttribute('type','media');
  my $media = XML::LibXML::Element->new("media");
  $media->setAttribute('mimeType',$params{mimeType} // 'audio/mp3');
  $media->setAttribute('url',$params{url}) if exists $params{url};
  $note->appendChild($media);
  # $tei_text->appendChild($note);
  $self->addToElemsQueue($note);
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

sub addMeetingData {
  my $self = shift;
  my ($key, $value, $force) = @_; # force means overwrite if key exists
  my $meetingNode;
  my $ana = "#parla.$key";
  ($meetingNode) = $self->{TITLESTMT}->findnodes('./meeting[@ana="'.$ana.'"]');
  return undef if !$force && $meetingNode;
  unless($meetingNode){
    $meetingNode = $self->{TITLESTMT}->addNewChild(undef,'meeting');
    $meetingNode->setAttribute('ana',"$ana");
  } else {
    $meetingNode->removeChildNodes(); # remove possibly existing text
  }
  $meetingNode->setAttribute('n',"$value");
  $meetingNode->appendText($value);
  return $meetingNode;
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