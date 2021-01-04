package TEI::ParlaClarin::TEI;

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
#binmode STDERR, ":utf8";
use open OUT => ':utf8';

sub new {
  my ($class, %params) = @_;
  my $self = $class->SUPER::new('TEI',%params);
  bless($self,$class);
  $self->{PAGECOUNTER} = 0;
  $self->{UTT_COUNTER} = 0;
  $self->{UTT_ID} = ''; # current utterance ID
  $self->{SEG_COUNTER} = 0;
  $self->{STATS}->{u} = 0;
  
  $self->{PERSON_IDS} = {};
  $self->{THIS_TEI_PERSON_IDS} = {};
  $self->{QUEUE} = [];
  $self->{activeUtterance} = undef;
  my $personlistfilename = 'person.xml';
  my $personlistfilepath = File::Spec->catfile($self->{output}->{dir},$personlistfilename);
  $self->{personlistfile} = {name => $personlistfilename, path=> $personlistfilepath};
  
  
  $self->{PERSONLIST} = $self->getPersonlistDOM($personlistfilepath);
  $self->addMeetingData('authorized','yes');

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
    $self->{XPC} = XML::LibXML::XPathContext->new;
    $self->setXPC('' => 'http://www.tei-c.org/ns/1.0', xml => 'http://www.w3.org/XML/1998/namespace');
    $self->{HEADER} = _get_child_node_or_create($self->{XPC},$self->{ROOT},'teiHeader');
    $self->{TITLESTMT} = _get_child_node_or_create($self->{XPC},$self->{HEADER},'fileDesc', 'titleStmt');
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



sub toFile {
  my $self = shift;
  my %params = @_;
  my @id_parts = split '-', $self->{ID};
  $self->appendQueue(1); # append queue  to <text><body><div>



  $self->addMeetingData('term',$id_parts[0],1);
  $self->addMeetingData('meeting',join('/',@id_parts[0,1]),1);
  $self->addMeetingData('sitting',join('/',@id_parts[0,1,2]),1);
  $self->addMeetingData('agenda',join('/', @id_parts[0,1,4]),1);


  my $filename = $params{outputfile} // File::Spec->catfile(join("-",@id_parts[0,1]),$self->{ID}.'.xml');
  $self->SUPER::toFile(%params,($params{outputfile} ? () : (outputfile => File::Spec->catfile($self->{output}->{dir},$filename))));
  # save personlist
  my $pp = XML::LibXML::PrettyPrint->new(
    indent_string => "  ",
    element => {
        inline   => [qw/note/],
        #block    => [qw//],
        #compact  => [qw//],
        preserves_whitespace => [qw/u/],
        }
    );
  
  if($self->{PERSONLIST}) {
    $pp->pretty_print($self->{PERSONLIST});
    $self->{PERSONLIST}->toFile($self->{personlistfile}->{path});
  }
  return $filename;
}

sub getPersonIdsList {
  my $self = shift;
  return [keys %{$self->{THIS_TEI_PERSON_IDS}}];
}

sub getPersonListFileName {
  my $self = shift;
  return $self->{personlistfile};
}

sub getAudioUrls {
  my $self = shift;
  my %seen;
  return [ sort grep {!$seen{$_}++} map {$_->getAttribute('url')} $self->{XPC}->findnodes('.//tei:media[@url][@mimeType="audio/mp3"]', $self->{ROOT}) ];
}

sub hideAudioUrls {
  my $self = shift;
  for my $node ($self->{XPC}->findnodes('.//tei:note[@type="media"][./tei:media[@url][@mimeType="audio/mp3"]]', $self->{ROOT})){
    my $url = $self->{XPC}->findnodes('.//tei:media/@url', $node);
    $node->replaceNode(XML::LibXML::Comment->new("AUDIO:$url"));
  }
}


sub addAudioFile {
  my $self = shift;
  my $file = shift;
  my $rec = _get_child_node_or_create($self->{XPC},$self->{HEADER},'recordingStmt')->addNewChild(undef,'recording');
  $rec->setAttribute('type', 'audio');
  my $media = $rec->addNewChild(undef,"media");
  $media->setAttribute('mimeType', 'audio/mp3');
  $media->setAttribute('url', $file);

  return $self;
}


sub updateIds {
  my $self = shift;
  my $old = shift;
  my $new = shift;
  foreach my $node ($self->{XPC}->findnodes('//tei:*[@id]', $self->{DOM})) {
    my $attr = $node->getAttributeNS($self->{NS}->{xml}, 'id');
    $attr =~ s/$old/$new/;
    $node->setAttributeNS($self->{NS}->{xml}, 'id', $attr);
  }
  return $self;
}




sub addUtterance { # don't change actTEI
  my $self = shift;
  $self->appendQueue(0); # appending to <text><body><div>
  $self->{UTT_COUNTER}++;
  $self->{SEG_COUNTER} = 0;
  my %params = @_;
  my $tei_text = _get_child_node_or_create($self->{XPC},$self->{ROOT},'text', 'body', 'div');
  my $u = XML::LibXML::Element->new("u");
  if(exists $params{author}) {
    my $author_xml_id = $self->addAuthor(%{$params{author}});
    $author_xml_id = "#$author_xml_id" if $author_xml_id;
    $u->setAttribute('who',$author_xml_id // $params{author}->{author_full});
    if($params{author}->{author_full}) {
      my $note = XML::LibXML::Element->new("note");
      $note->setAttribute('type','speaker');
      $note->appendText($params{author}->{author_full});
      $note->setAttribute('target',$author_xml_id) if $author_xml_id;
      $tei_text->appendChild($note);
    }
    $u->setAttribute('ana', '#'.$params{author}->{role}) if $params{author}->{role};
  }
  $self->{UTT_ID} = sprintf('%s.u%d',$self->{ID},$self->{UTT_COUNTER});
  $u->setAttributeNS($self->{NS}->{xml}, 'id', $self->{UTT_ID}); # if exists $params{id};
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
  return $self->{UTT_ID};
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
  $self->addUtterance() unless $self->{activeUtterance}; # DEFINE NO SPEAKER UTTERANCE
  if(!defined($segment) && scalar @{$self->{QUEUE}}) { # print queue if segment is not defined
    $self->{activeUtterance}->appendText("\n") if $self->{activeUtterance}->hasChildNodes(); #just formating
    $self->appendQueue(0,$self->{activeUtterance})
  }
  # adding element to queue and than append whole queue to utterance
  push @{$self->{QUEUE}},[$element,0];
  $self->{activeUtterance}->appendText("\n") if $self->{activeUtterance}->hasChildNodes(); # just formating
  unless($segment) {
    $segment = $self->{activeUtterance}->addNewChild(undef, 'seg');
    $self->{SEG_COUNTER}++;
    $segment->setAttributeNS($self->{NS}->{xml}, 'id', sprintf('%s.p%d',$self->{UTT_ID},$self->{SEG_COUNTER}));
  }
  return $self->appendQueue(0, $segment);
}
sub appendQueue {
  my $self = shift;
  my $isend = shift;
  my $element = shift // _get_child_node_or_create($self->{XPC},$self->{ROOT},'text', 'body', 'div');
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
  $pbNode->setAttributeNS($self->{NS}->{xml}, 'id', sprintf("%s.pb%d",$self->{ID}, $self->{PAGECOUNTER}));
  $self->addToElemsQueue($pbNode,1);
  return $self;
}

sub addAuthor {
  my $self = shift;
  my %params = @_;
  return unless $params{id} or $params{govern_id};
  my $xmlid = _to_xmlid($params{id} ? ('pers-', $params{name}, $params{id}) : ('pers-gov-',$params{govern_id}));
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
  for my $link (
      ['https://www.psp.cz/sqw/detail.sqw?id=',$params{id}],
      ['https://www.vlada.cz/cz/clenove-vlady/',$params{govern_id},'/'],
      ) {
    next unless $link->[1];
    my $idno =  XML::LibXML::Element->new("idno");
    $person->appendChild($idno);
    $idno->appendText( join('', @$link));
    $idno->setAttribute('type', 'URI');
  }
  $self->{PERSON_IDS}->{$xmlid} = $person;
  $self->{THIS_TEI_PERSON_IDS}->{$xmlid} = 1;
  $self->{PERSONLIST}->documentElement()->appendChild($person) if $self->{PERSONLIST};
  return $xmlid;
}

sub addHead {
  my $self = shift;
  my $text = shift;
  return unless $text;
  my ($node) = $self->{XPC}->findnodes('./title[last()]', $self->{TITLESTMT});
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
  # $self->addMetadata('authorized','no',1); # subrutine is missing
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
  my $node = _get_child_node_or_create($self->{XPC},$self->{HEADER},qw/profileDesc settingDesc setting date/);
  unless($node->textContent()) {
    $self->logDate($date);
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
  if(exists $params{url}) {
    my $url = $params{url};
    $media->setAttribute('source',$url);
    $url =~ s{^https?://}{};
    $url =~ s{^.*?eknih/}{};
    $media->setAttribute('url',$url);
  }
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
  my $profileDesc = _get_child_node_or_create($self->{XPC},$self->{HEADER}, "profileDesc");
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
  my $revisionDesc = _get_child_node_or_create($self->{XPC},$self->{HEADER}, "revisionDesc");
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
    my $XMLNS=$DOM->documentElement()->lookupNamespaceURI( 'xml' );
    $self->{PERSON_IDS}->{$_->getAttributeNS($XMLNS, 'id')} = $_ for $self->{XPC}->findnodes(".//tei:person",$DOM->documentElement()); ###########
  } else {
    $DOM = XML::LibXML::Document->new("1.0", "utf-8");
    my $root =  XML::LibXML::Element->new("personList");
    $DOM->setDocumentElement($root);
    $self->addNamespaces($root, xml => 'http://www.w3.org/XML/1998/namespace');
    $self->addNamespaces($root, '' => 'http://www.tei-c.org/ns/1.0');
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
  return TEI::ParlaClarin::_get_child_node_or_create(@_);
}


sub _to_xmlid {
  return TEI::ParlaClarin::_to_xmlid(@_);
}




1;