package ParCzech::NER::CNEC;

use warnings;
use strict;
use ParCzech::PipeLine::FileManager;

my $namedEntities = {
  valuesname => 'class',
  categories => {
    a => {
      name  => 'numbers in addresses',
      valuesname => 'subclass',
      categories => {
        ah => { name  => 'street numbers'},
        at => { name  => 'phone/fax numbers'},
        az => { name  => 'zip codes'},
      },
    },
    g => {
      name  => 'geographical names',
      valuesname => 'subclass',
      categories => {
        g_ =>  { name  => 'geographical names - underspecified'},
        gc =>  { name  => 'geographical names - states'},
        gh =>  { name  => 'geographical names - hydronyms'},
        gl =>  { name  => 'geographical names - nature areas / objects'},
        gq =>  { name  => 'geographical names - urban parts'},
        gr => { name  => 'territorial names'},
        gs => { name  => 'streets, squares'},
        gt => { name  => 'continents'},
        gu => { name  => 'cities/towns'},
      },
    },
    i => {
      name  => 'institutions',
      valuesname => 'subclass',
      categories => {
        i_ => { name  => 'underspecified'},
        ia => { name  => 'conferences/contests'},
        ic => { name  => 'cult./educ./scient. inst.'},
        if => { name  => 'companies, concerns...'},
        io => { name  => 'government/political inst.'},
      },
    },
    m => {
      name  => 'media names',
      valuesname => 'subclass',
      categories => {
        me => { name  => 'email address'},
        mi => { name  => 'internet links'},
        mn => { name  => 'periodical'},
        ms => { name  => 'radio and tv stations'},
      },
    },
    n => {
      name  => 'number expressions',
      valuesname => 'subclass',
      categories => {
        n_ => { name  => 'underspecified'},
        na => { name  => 'age'},
        nb => { name  => 'vol./page/chap./sec./fig. numbers'},
        nc => { name  => 'cardinal numbers'},
        ni => { name  => 'itemizer'},
        no => { name  => 'ordinal numbers'},
        ns => { name  => 'sport score'},
      },
    },
    o => {
      name  => 'artifact names',
      valuesname => 'subclass',
      categories => {
        o_ => { name  => 'underspecified'},
        oa => { name  => 'cultural artifacts (books, movies)'},
        oe => { name  => 'measure units'},
        om => { name  => 'currency units'},
        op => { name  => 'products'},
        or => { name  => 'directives, norms'},
      },
    },
    p => {
      name  => 'personal names',
      valuesname => 'subclass',
      categories => {
        p_ => { name  => 'underspecified'},
        pc => { name  => 'inhabitant names'},
        pd => { name  => '(academic) titles'},
        pf => { name  => 'first names'},
        pm => { name  => 'second names'},
        pp => { name  => 'relig./myth persons'},
        ps => { name  => 'surnames'},
      },
    },
    t => {
      name  => 'time expressions',
      valuesname => 'subclass',
      categories => {
        td => { name  => 'days'},
        tf => { name  => 'feasts'},
        th => { name  => 'hours'},
        tm => { name  => 'months'},
        ty => { name  => 'years'}
      },
    },
  }
};

sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my $self  = {};
  bless $self, $class;
  $self->{taxonomy} = XML::LibXML::Element->new('taxonomy');
  $self->{taxonomy}->setNamespace($self->get_NS_from_prefix('xml'),'xml',0);
  $self->{taxonomy}->setAttributeNS($self->get_NS_from_prefix('xml'), 'id', 'NER.cnec2.0');
  my $desc = $self->{taxonomy}->addNewChild(undef, 'desc');
  $desc->setAttributeNS($self->get_NS_from_prefix('xml'), 'lang', 'en');
  $desc->appendText('Named entities');
  $self->addCategories($self->{taxonomy}, $namedEntities->{categories});
  return $self;
}

sub addCategories {
  my $self = shift;
  my ($node, $cats) = @_;
  return unless $cats;
  for my $cat (keys %$cats) {
  	my $catnode = $node->addNewChild(undef, 'category');
    $catnode->setAttributeNS($self->get_NS_from_prefix('xml'), 'id', $cat);
    my $desc = $catnode->addNewChild(undef, 'catDesc');
    $desc->appendText($cats->{$cat}->{name});
    $desc->setAttributeNS($self->get_NS_from_prefix('xml'), 'lang', 'en');
  	$self->addCategories($catnode, $cats->{$cat}->{categories});
  }
}

sub get_NS_from_prefix {
  my $self = shift;
  my $ns = ParCzech::PipeLine::FileManager::TeiFile::get_NS_from_prefix(shift);
  return $ns;
}

sub to_string {
  my $self = shift;
  return ParCzech::PipeLine::FileManager::XML::to_string($self->{taxonomy});
}