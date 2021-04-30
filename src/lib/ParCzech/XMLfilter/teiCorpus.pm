package ParCzech::XMLfilter::teiCorpus;

use base 'ParCzech::XMLfilter';
use strict;
use warnings;
use utf8;
use ParCzech::PipeLine::FileManager __PACKAGE__;
use ParCzech::Common;
use Data::Dumper;



sub new {
  my ($class, %params) = @_;
  my $self = $class->SUPER::new(%params);
  bless($self,$class);
  $self->{xpc} = ParCzech::PipeLine::FileManager::TeiFile::new_XPathContext();
  $self->{included_meta} = {
    #term_n => {ids=>{id=>occurences},files=>{path=>1},interval=>{from=>[atribute_value,text_value],to=>[]},uri=>...,measures=>{...},tagUsage=>{...} }
  };
  return $self;
}

sub add_term_filtering {
  my $self = shift;
  my %opts = @_;
  my $template = $opts{template};

  for my $val ($self->get_term_org()){
    my ($term,$org) = @$val;
    my ($fill_template) = $org =~ m/([^\.]*)$/;
    $fill_template =~ s/^PSP/PS/;
    my $file = sprintf($template,$fill_template);
    my ($id) = $file =~ m/^.*\/(.*?)\.xml/;
    $self->add_target_filter(file => $file, org => $org, id => $id, term => $term, interfix => $fill_template);
  }
  return $self;
}

sub get_term_org {
  my $self = shift;
  return unless defined $self->{source};
  my @result;
  for my $node ($self->{xpc}->findnodes('//tei:titleStmt/tei:meeting[contains(@ana, "#parla.term")]',$self->{source}->{dom})){
    my $term = $node->getAttribute('n');
    my $org = $node->getAttribute('ana');
    $org =~ s/ *#parla\.([a-zA-Z]*) *//g;
    $org =~ s/#//g;
    unless($org =~ m/ /){
      push @result,[$term,$org]
    }
  }
  @result;
}




sub process_filters {
  my $self = shift;

  $self->process_included_files();

  for my $target (values %{$self->{targets}}) {
    my $term_n = $target->{params}->{term};
    # remove unrelated meetings
    $_->unbindNode() for $self->{xpc}->findnodes('//tei:titleStmt/tei:meeting[not(@n = "'.$term_n.'")]',$target->{dom});
    my ($term_event_id,@err) = map {s/^#//;$_} grep {not(m/^#parla\./) && $_} split(' ',$self->{xpc}->findvalue('//tei:titleStmt/tei:meeting[@n = "'.$term_n.'"]/@ana',$target->{dom}));
    $ParCzech::PipeLine::FileManager::logger->log_line('unexpected ana value in //tei:titleStmt/tei:meeting', $self->{xpc}->findvalue('//tei:titleStmt/tei:meeting[@n = "'.$term_n.'"]/@ana',$target->{dom})) if @err;
    $ParCzech::PipeLine::FileManager::logger->log_line('missing organization value in //tei:titleStmt/tei:meeting/@ana', $self->{xpc}->findvalue('//tei:titleStmt/tei:meeting[@n = "'.$term_n.'"]/@ana',$target->{dom})) unless $term_event_id;
    # update title
    for my $title_text_node ($self->{xpc}->findnodes('//tei:titleStmt/tei:title[@type="main"]/text()',$target->{dom})) {
      $title_text_node->replaceDataRegEx('\]$','-'.$target->{params}->{interfix}.']');
    }
    # update id
    $target->{dom}->documentElement()->setAttributeNS($self->{xpc}->lookupNs('xml'),'id',$target->{params}->{id});

    # update date and url
    my ($bibl) = $self->{xpc}->findnodes('//tei:bibl[tei:idno[@type="URI"]]',$target->{dom});
    unless($bibl) {
      $ParCzech::PipeLine::FileManager::logger->log_line('missing bibliography');
    } else {
      my ($date_node) = $self->{xpc}->findnodes('./tei:date',$bibl);
      ParCzech::Common::set_date_node($date_node, $self->{included_meta}->{$term_n}->{interval}) if $date_node;
      my ($idno_node) = $self->{xpc}->findnodes('./tei:idno[@type="URI"]',$bibl);
      $idno_node->removeChildNodes();
      $idno_node->appendText($self->{included_meta}->{$term_n}->{uri});
    }
    # update tagUsage
    for my $tag_node ($self->{xpc}->findnodes('//tei:namespace/tei:tagUsage',$target->{dom})){
      $tag_node->setAttribute('occurs',$self->{included_meta}->{$term_n}->{tagUsage}->{$tag_node->getAttribute('gi')} // 0);
    }
    # update measures
    for my $measure_node ($self->{xpc}->findnodes('//tei:extent/tei:measure',$target->{dom})){
      my $old = $measure_node->getAttribute('quantity');
      $measure_node->setAttribute('quantity',$self->{included_meta}->{$term_n}->{measures}->{$measure_node->getAttribute('unit')} // 0);
      $measure_node->firstChild->replaceDataString($old,$self->{included_meta}->{$term_n}->{measures}->{$measure_node->getAttribute('unit')} // 0);
    }
    # add related persons to ids list
    if($term_event_id) {
      for my $pers_node ($self->{xpc}->findnodes('//tei:person[./tei:affiliation/@ref = "#'.$term_event_id.'"]',$target->{dom})){
        $self->{included_meta}->{$term_n}->{ids}->{$pers_node->getAttributeNS($self->{xpc}->lookupNs('xml'),'id')} //= 0;
      }
    }

    # clean persons not seen or related to term and add affiliation ids to include_meta
    for my $pers_node ($self->{xpc}->findnodes('//tei:listPerson/tei:person',$target->{dom})){
      if($self->is_id_referenced($pers_node,$term_n)) {
        for my $org_id (map {s/^#//;$_} map {$_->getAttribute('ref')} $self->{xpc}->findnodes('./tei:affiliation[@ref]',$pers_node)){
          $self->{included_meta}->{$term_n}->{ids}->{$org_id} //= 0;
          $self->{included_meta}->{$term_n}->{ids}->{$org_id} += 1;
        }
      } else {
        $pers_node->unbindNode();
      }
    }

    # remove orgs without affiliation (orgs, not events !!!)
    for my $org_node ($self->{xpc}->findnodes('//tei:listOrg/tei:org',$target->{dom})){
      if($self->is_id_referenced($org_node,$term_n)) {
        # keeping organization
      } else {
        $org_node->unbindNode();
      }
    }

    # remove not related included TEI files links
    for my $include ($self->{xpc}->findnodes('/tei:teiCorpus/xi:include',$target->{dom})) {
      my $included_file = $include->getAttribute('href');
      $include->unbindNode() unless defined $self->{included_meta}->{$term_n}->{files}->{$included_file};
    }


  }
  return $self;
}

sub process_included_files {
  my $self = shift;
  for my $include ($self->{xpc}->findnodes('/tei:teiCorpus/xi:include',$self->{source}->{dom})) {
    my $included_file = $include->getAttribute('href');
    my $xml = ParCzech::PipeLine::FileManager::XML::open_xml($self->get_abs_path($included_file));
    if($xml){
      my $dom = $xml->{dom};
      my @terms = map {$_->getAttribute('n')} $self->{xpc}->findnodes('//tei:titleStmt/tei:meeting[contains(@ana, "#parla.term") and @n]',$dom);
      my %speakers;
      $speakers{$_} = ( $speakers{$_} // 0) + 1 for map {s/^#//;$_} map {$_->getAttribute('who')} $self->{xpc}->findnodes('//tei:u[@who]',$dom);
      my ($bibl) = $self->{xpc}->findnodes('//tei:bibl[tei:idno[@type="URI"]]',$dom);
      my ($interval,$url);
      if($bibl) {
        $interval = ParCzech::Common::date_node_to_interval($self->{xpc}->findnodes('./tei:date',$bibl));
        ($url) = map {$_->textContent()} $self->{xpc}->findnodes('./tei:idno[@type="URI"]',$bibl);
      }
      my %measures = map {$_->getAttribute('unit')=>$_->getAttribute('quantity')} $self->{xpc}->findnodes('//tei:extent/tei:measure',$dom);
      my %tagUsage = map {$_->getAttribute('gi')=>$_->getAttribute('occurs')} $self->{xpc}->findnodes('//tei:namespace/tei:tagUsage',$dom);

      for my $term (@terms) {
        $self->{included_meta}->{$term} //= {
                                              ids =>{},
                                              files =>{},
                                              interval => $interval,
                                              uri => $url,
                                              measures => {},
                                              tagUsage => {},
                                            };
        for my $sp_id (keys %speakers){
          $self->{included_meta}->{$term}->{ids}->{$sp_id} //= 0;
          $self->{included_meta}->{$term}->{ids}->{$sp_id} += $speakers{$sp_id};
        }
        $self->{included_meta}->{$term}->{files}->{$included_file} = 1;
        $self->{included_meta}->{$term}->{uri} = ParCzech::Common::common_uri_part($self->{included_meta}->{$term}->{uri},$url);
        $self->{included_meta}->{$term}->{interval} = ParCzech::Common::merge_interval($self->{included_meta}->{$term}->{interval},$interval);

        for my $unit (keys %measures) {
          $self->{included_meta}->{$term}->{measures}->{$unit} //= 0;
          $self->{included_meta}->{$term}->{measures}->{$unit} += $measures{$unit};
        }

        for my $tg (keys %tagUsage) {
          $self->{included_meta}->{$term}->{tagUsage}->{$tg} //= 0;
          $self->{included_meta}->{$term}->{tagUsage}->{$tg} += $tagUsage{$tg};
        }
      }
    }
  }
}



sub is_id_referenced {
  my $self = shift;
  my $node = shift;
  my @terms = @_;
  for my $term_n (@terms) {
    my $id = $node->getAttributeNS($self->{xpc}->lookupNs('xml'),'id');
    return 1 if $id and defined $self->{included_meta}->{$term_n}->{ids}->{$id};
    for my $id (map {$_->getAttributeNS($self->{xpc}->lookupNs('xml'),'id')} $self->{xpc}->findnodes('.//*[@xml:id]',$node)){
      return 1 if defined $self->{included_meta}->{$term_n}->{ids}->{$id};
    }
  }
}






sub cli {
  my $self = shift;
  my $source = shift;
  my $target = shift;
  my $filter = ParCzech::XMLfilter::teiCorpus->new(file => $source);
  $filter->add_term_filtering(template => $target);
  $filter->process_filters();
  $filter->save_to_file();
}

__PACKAGE__->cli(@ARGV) unless caller;

1;