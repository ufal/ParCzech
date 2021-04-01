package ParCzech::XMLmerge;

use warnings;
use strict;
# use open qw/:std :encoding(UTF-8)/;
use utf8;
use File::Spec;
use File::Copy;
use XML::LibXML qw(:libxml);
use ParCzech::PipeLine::FileManager __PACKAGE__;
use ParCzech::XMLmerge::teiCorpus;
use sort 'stable';          # guarantee stability

my $XMLNS = 'http://www.w3.org/XML/1998/namespace';

sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my %opts = @_;
  my $self  = {};
  bless $self, $class;
  $self->{comparators} = [];
  $self->{mergers} = [];
  $self->{constants} = {%opts};
  return $self
}

sub merge {
  my $self = shift;
  my ($base,$in) = @_;
  my $res = XML::LibXML::Document->new("1.0", "utf-8");
  $res->setDocumentElement($base->documentElement()->cloneNode(1));
  $self->{constants}->{doc} = $res->documentElement();
  $self->merge_node(path=>'/', res=>$self->{constants}->{doc}, in=>$in->documentElement());
  undef $self->{constants}->{doc};
  return $res;
}

sub merge_node {
  my $self = shift;
  my %opts = @_;
  if ($opts{res}->nodeType == XML_TEXT_NODE) {
    $opts{res}->setData($opts{in}->data);
    return;
  }

  # nodes $res and $ins corresponds, only attributes and childnodes colisious should be solved
  my $path = $opts{path}.$opts{res}->nodeName.'/';

  return if $self->try_merge($path,$opts{res},$opts{in});

  # solve attributes
  $self->merge_attributes(path => $path, res=>$opts{res}, in=>$opts{in});

  # solve childnodes
  my @res_chn = $opts{res}->nonBlankChildNodes;
  my @in_chn = $opts{in}->nonBlankChildNodes;
  @res_chn = $self->sort($path,@res_chn);
  @in_chn = $self->sort($path,@in_chn);
  my ($res_i, $in_i) = (0, 0);
  #$_->unbindNode() for @res_chn;
  $opts{res}->removeChildNodes();

  while($res_i < scalar(@res_chn) or $in_i < scalar(@in_chn)) {
    my $cmp = $self->compare($path, $res_chn[$res_i]//undef, $in_chn[$in_i]//undef);
    if($cmp < 0) {
      $opts{res}->appendChild($self->sortNode($path,$res_chn[$res_i]));
      $res_i++;
    } elsif ($cmp > 0) {
      $opts{res}->appendChild($self->sortNode($path,$in_chn[$in_i]->cloneNode(1)));
      $in_i++;
    } else {
      # merge node into res
      $self->merge_node(path => $path, res => $res_chn[$res_i], in => $in_chn[$in_i]);
      $opts{res}->appendChild($res_chn[$res_i]);
      $res_i++;
      $in_i++;
    }
  }
}

sub sortNode {
  my $self = shift;
  my $path = shift;
  my $node = shift;

  return $node unless $node->nodeType == XML_ELEMENT_NODE;
  $path = $path.$node->nodeName.'/';

  my @chnodes = $node->nonBlankChildNodes;
  @chnodes = $self->sort($path, @chnodes);
  $node->removeChildNodes();
  for my $ch (@chnodes) {
    $node->appendChild($self->sortNode($path,$ch));
  }
  return $node
}


sub sort {
  my $self = shift;
  my $path = shift;
  my @array = @_;
  @array = sort sort_id_nodes @array;
  for my $comp (grep {!$_->{no_sort}} $self->comparators) {
    @array = sort {return $comp->{func}($path,$a,$b)//0} @array;
  }
  @array;
}

sub sort_id_nodes {
  my $a_id = get_id($a)//'';
  my $b_id = get_id($b)//'';
  return $a_id cmp $b_id;
}

sub get_id {
  my $n = shift;
  return unless $n->nodeType == XML_ELEMENT_NODE;
  return unless $n->hasAttributeNS($XMLNS,'id');
  return $n->getAttributeNS($XMLNS,'id');
}

sub compare {
  my $self = shift;
  my ($path,@nodes) = @_;
  my $cmp;
  return -1 unless defined $nodes[1];
  return  1 unless defined $nodes[0];
  if ($nodes[0]->nodeType == XML_TEXT_NODE && $nodes[1]->nodeType == XML_TEXT_NODE) {
    #return trim($nodes[0]->data) cmp trim($nodes[1]->data);
    return 0; # texts should be equal
  } elsif ($nodes[0]->nodeType == XML_TEXT_NODE || $nodes[1]->nodeType == XML_TEXT_NODE) {
    return -1;
  }


  ##  print STDERR "Comparing nodes\t",$nodes[0]->cloneNode(),"\n             \t",$nodes[1]->cloneNode(),"\n";
  my @nodes_ids = map {$_->hasAttributeNS($XMLNS, 'id') ? $_->getAttributeNS($XMLNS, 'id') : undef } @nodes;

  # if both have xml:id - compare (nodename,xml:id)
  if($nodes[0]->nodeName eq $nodes[1]->nodeName
    && $nodes_ids[0] && $nodes_ids[1]) {
    return $nodes_ids[0] cmp $nodes_ids[1];
  }

  # if one have id - dont return 0 !!! - point node without id
  return -1 if  !$nodes_ids[0] and !!$nodes_ids[1];
  return  1 if !!$nodes_ids[0] and  !$nodes_ids[1];

  # try using custom comparator
  ###$cmp = $self->compare_custom($path,@nodes);
  ###  return $cmp if defined $cmp;


  # equal nodenames, compare @corresp and then then attributes in given order (parametrize this !!!)
  # print STDERR "TODO - equal nodeNames: $path",$nodes[0]->nodeName,"\n";#, "\n\t",$nodes[0]->cloneNode(),"\n\t",$nodes[1]->cloneNode(),"\n";

  return 0 if $nodes[0]->nodeName eq $nodes[1]->nodeName && $self->is_unique($path,$nodes[0]->nodeName);

  $cmp = $self->compare_custom($path,@nodes);

  return $cmp if defined $cmp;

 # keep order if different nodenames (this can break thinks !!!)
  return $nodes[0]->nodeName cmp $nodes[1]->nodeName unless $nodes[0]->nodeName eq $nodes[1]->nodeName;

}


sub trim {
  my $str = shift;
  $str =~ s/^\s*|\s*$//g;
  return $str;
}

sub add_comparator {
  my $self = shift;
  my %opts = @_;
  push @{$self->{comparators}}, {terminate=> !!$opts{terminate},no_sort=> !!$opts{no_sort}, func => $opts{func}};
  return $self;
}

sub add_merger {
  my $self = shift;
  my $f = shift;
  push @{$self->{mergers}}, $f;
  return $self;
}

sub compare_custom {
  my $self = shift;
  my ($path,@nodes) = @_;
  for my $comp ($self->comparators) {
    my $cmp = $comp->{func}($path,@nodes);
    return $cmp if defined($cmp) and $comp->{terminate};
    return $cmp if defined($cmp) and $cmp; # not equal
  }
}
sub comparators {
  my $self = shift;
  @{$self->{comparators}//[]};
}

sub try_merge {
  my $self = shift;
  my ($path,@nodes) = @_;
  for my $merger ($self->mergers) {
    return 1 if $merger->($path,$self->{constants},@nodes);
  }
}
sub mergers {
  my $self = shift;
  @{$self->{mergers}//[]};
}

sub merge_attributes {
  my $self = shift;
  my %opts = @_;
  tie my %res_attr, 'XML::LibXML::AttributeHash', $opts{res};
  tie my %in_attr, 'XML::LibXML::AttributeHash', $opts{in};
  for my $attr_name (keys %in_attr) {
    if (defined $res_attr{$attr_name}) {
      $res_attr{$attr_name} = $self->solve_conflict(
                                        type => 'attribute',
                                        path => $opts{path},
                                        res => $opts{res},
                                        in => $opts{in},
                                        name => $attr_name,
                                        res_val => $res_attr{$attr_name},
                                        in_val=>$in_attr{$attr_name}
                                      );
    } else { # adding new attribute
      print STDERR "Adding attribute $opts{path}\@$attr_name = $in_attr{$attr_name}\n";
      $res_attr{$attr_name} = $in_attr{$attr_name};
    }
  }
}

sub is_unique {
  my $self = shift;
  my ($path,$name) = @_;
  #print STDERR "TODO add all nodes in header, parametrize it !!! $path$name \n";
  my %unique = map {$_ => 1} qw/teiHeader persName birth death sex/;
  return 1 if defined $unique{$name};
  return 1 if $path =~ m/teiHeader\/[^\/]*$/;
}

sub solve_conflict {
  my $self = shift;
  my %opts = @_;
  if( $opts{'type'}//'' eq 'attribute') {
    print STDERR "Attribue conflict $opts{path}/".'@'."$opts{name} :  $opts{res_val} <> $opts{in_val}\n" unless $opts{res_val} eq $opts{in_val};
    return $opts{res_val} if $opts{name} =~ m/\}id$/ and $opts{path} =~ m/^\/[^\/]*\/$/; # keep document id
    my $ret = $opts{in_val};
    return $ret;
  } else {
    print STDERR "TODO - node conflicts !!! allow return list !!!";
    return "TODO"
  }

}

sub cli {
  my $self = shift;
  my $old = shift;
  my $new = shift;
  my $result = shift;
  my ($id) = $result =~ m/([^\/]*)\.xml$/;
  my ($backup_suff) = $new =~ m/([T\d]+)(\.ana)?\.xml$/;
  my ($base) = $result =~ m/^(.*\/)/;
  $base = "" unless $base;

  my $merger = ParCzech::XMLmerge->new( id => $id, backup_suff => ".$backup_suff", base => $base);

  ParCzech::XMLmerge::teiCorpus::add_settings_to_merger($merger);
  my $old_xml = ParCzech::PipeLine::FileManager::XML::open_xml($old);
  my $new_xml = ParCzech::PipeLine::FileManager::XML::open_xml($new);
  exit 0 unless $old_xml && $new_xml;

  my $result_dom = $merger->merge($old_xml->{dom}, $new_xml->{dom});
  ParCzech::PipeLine::FileManager::XML::save_to_file($result_dom, $result);

  print STDERR "TODO
  * sorter for different parents
  * tagUsage (recount at the end - postprocess, based on <xi:include>)
  * extent (similar as tagUsage)
  * sort xi:include based on date in files ???
  ";
}

__PACKAGE__->cli(@ARGV) unless caller;

1;