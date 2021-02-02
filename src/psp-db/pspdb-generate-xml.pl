use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use Getopt::Long;
use File::Spec;
use DateTime::Format::Strptime;
use ParCzech::PipeLine::FileManager;
use ParCzech::Translation;
use DBI;
use Unicode::Diacritic::Strip;
use Data::Dumper;




my ($debug, $personlist_in, $outdir, $indbdir, $govdir,$translations,$patches, $flat);

=note

  poslanci/zarazeni.unl
  poslanci/pkgps.unl
  poslanci/organy.unl
  poslanci/funkce.unl
  poslanci/poslanec.unl
  poslanci/osoby.unl
  poslanci/typ_organu.unl
  poslanci/osoba_extra.unl
  poslanci/typ_funkce.unl
=cut

my $XMLNS = 'http://www.w3.org/XML/1998/namespace';
my $strp = DateTime::Format::Strptime->new(
  pattern   => '%d.%m.%Y',
  locale    => 'cs_CZ',
  time_zone => 'Europe/Prague'
);

my %cast = (
  date => sub {my $d = shift; return $d ? join('-', reverse(split('\.',$d))) : ''},
  datehour => sub {my $d = shift; return $d ? "$d:00:00" : ''},
  unescape_patch => sub {my $s = shift; $s =~ s/\\ / /g; $s =~ s/^\s+|\s+$//g; return $s},
);
my %uniqueOrgRoles = map {($_ => 1)} qw/parliament senate nationalCouncil president/;


my %data_links = ();
my %mapper = ();

my %tabledef = (
  poslanci => {
    osoby => {
      def => [
        map {my ($n,$t) = split('\|', $_);{name => $n, type => $t} } qw/id_osoba|INTEGER pred|CHAR(20) prijmeni|CHAR(20) jmeno|CHAR(20) za|CHAR(20) narozeni|DATE pohlavi|CHAR(10) zmena|DATE umrti|DATE/
      ],
      index => [qw/id_osoba|UNIQUE/],
      invalid_values => {
        narozeni => '01.01.1900' # missing date
      },
      cast => {
        narozeni => $cast{date},
        umrti => $cast{date},
        zmena => $cast{date},
      },
    },
    organy => {
      def => [
        map {my ($n,$t) = split('\|', $_);{name => $n, type => $t} }
            qw/id_organ|INTEGER organ_id_organ|INTEGER id_typ_org|INTEGER zkratka|CHAR(20) nazev_organu_cz|CHAR(100) nazev_organu_en|CHAR(100) od_organ|DATE do_organ|DATE priorita|INTEGER cl_organ_base|INTEGER/
      ],
      index => [qw/id_organ|UNIQUE id_typ_org organ_id_organ/],
      invalid_values => {},
      cast => {
        od_organ => $cast{date},
        do_organ => $cast{date},
      },
    },
    typ_organu => {
      def => [
        map {my ($n,$t) = split('\|', $_);{name => $n, type => $t} }
            qw/id_typ_org|INTEGER typ_id_typ_org|INTEGER nazev_typ_org_cz|CHAR(100) nazev_typ_org_en|CHAR(100) typ_org_obecny|INTEGER priorita|INTEGER/
      ],
      index => [qw/id_typ_org|UNIQUE typ_id_typ_org typ_org_obecny/],
      invalid_values => {},
      cast => {},
    },
    typ_funkce => {
      def => [
        map {my ($n,$t) = split('\|', $_);{name => $n, type => $t} }
            qw/id_typ_funkce|INTEGER id_typ_org|INTEGER typ_funkce_cz|CHAR(100) typ_funkce_en|CHAR(100) priorita|INTEGER typ_funkce_obecny|INTEGER/
      ],
      index => [qw/id_typ_funkce|UNIQUE id_typ_org/],
      invalid_values => {},
      cast => {},
    },
    funkce => {
      def => [
        map {my ($n,$t) = split('\|', $_);{name => $n, type => $t} }
            qw/id_funkce|INTEGER id_organ|INTEGER id_typ_funkce|INTEGER  nazev_funkce_cz|CHAR(100) priorita|INTEGER/
      ],
      index => [qw/id_funkce|UNIQUE id_organ id_typ_funkce/],
      invalid_values => {},
      cast => {},
    },
    zarazeni => {
      def => [
        map {my ($n,$t) = split('\|', $_);{name => $n, type => $t} }
            qw/id_osoba|INTEGER id_of|INTEGER cl_funkce|INTEGER od_o|DATETIME do_o|DATETIME od_f|DATE do_f|DATE/
      ],
      index => [qw/id_osoba id_of/],
      invalid_values => {},
      cast => {
        od_f => $cast{date},
        do_f => $cast{date},
        od_o => $cast{datehour},
        do_o => $cast{datehour},
      },
    },
    poslanec => {
      def => [
        map {my ($n,$t) = split('\|', $_);{name => $n, type => $t//'CHAR(50)'} }
            qw/id_poslanec|INTEGER id_osoba|INTEGER id_kraj|INTEGER id_kandidatka|INTEGER id_obdobi|INTEGER
            web ulice obec psc email telefon fax psp_telefon facebook foto|INTEGER/

      ],
      index => [qw/id_poslanec|UNIQUE id_osoba id_kraj id_kandidatka id_obdobi/],
      invalid_values => {},
      cast => {
        map {$_ => $cast{unescape_patch} } qw/web ulice obec psc email telefon fax psp_telefon facebook/
      },
    },

  }
);

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'flat' => \$flat,
            'person-list=s' => \$personlist_in,
            'output-dir=s' => \$outdir,
            'gov-input-dir=s' => \$govdir,
            'input-db-dir=s' => \$indbdir,
            'translations=s' => \$translations,
            'patches=s' => \$patches,
            );



usage_exit() unless $indbdir;
usage_exit() unless $personlist_in;
usage_exit() unless $outdir;

my %dbfile_structure = (
  (map {($_ => File::Spec->catfile($indbdir,'poslanci',"$_.unl"))} keys %{$tabledef{poslanci}}),
  $govdir ? (map {("gov_$_" => File::Spec->catfile($govdir,"gov_$_.unl"))} qw/osoby/) : ()
);


for my $k (keys %dbfile_structure) {
  usage_exit("file $dbfile_structure{$k} is expected") unless -s $dbfile_structure{$k};
}

my $db_file = File::Spec->catfile($outdir,'psp.db');

my $use_existing_db=( -s $db_file );

my $pspdb = DBI->connect("dbi:SQLite:dbname=${db_file}", "", "", { sqlite_unicode => 1 });




if($use_existing_db) {
  print STDERR "using existing database $db_file\n";
} else {
  # loading database from dumps
  create_and_fill_table($tabledef{poslanci}->{osoby},'osoby');
  create_and_fill_table($tabledef{poslanci}->{osoby},'osoby','utf-8','gov_');
  create_and_fill_table($tabledef{poslanci}->{typ_organu},'typ_organu');
  create_and_fill_table($tabledef{poslanci}->{organy},'organy');
  create_and_fill_table($tabledef{poslanci}->{typ_funkce},'typ_funkce');
  create_and_fill_table($tabledef{poslanci}->{funkce},'funkce');
  create_and_fill_table($tabledef{poslanci}->{zarazeni},'zarazeni');
  create_and_fill_table($tabledef{poslanci}->{poslanec},'poslanec');
}


my $regex_translations = [
  [qr/ministr/i,'minister'],
  [qr/místopředseda/i,'vice chairman'],
  [qr/^.+$/,'member']
];

my $personlist = ParCzech::PipeLine::FileManager::XML::open_xml($personlist_in);
my $patcher = ParCzech::Translation->new(single_direction => 1,$patches ? (tran_files => $patches) : ());
my $translator = ParCzech::Translation->new($translations ? (tran_files => $translations) : (),
                                            tran_regex => $regex_translations);
my $orglist = listOrg->new(db => $pspdb, translator => $translator,
                                         patcher => $patcher);

usage_exit() unless $personlist;

my $xpc = ParCzech::PipeLine::FileManager::TeiFile::new_XPathContext();

for my $person ($xpc->findnodes('//tei:person',$personlist->{dom})) {
  my $id = $person->getAttributeNS($xpc->lookupNs('xml'),'id');

  unless($id =~ m/(-?)([0-9]+)$/){ # no id, try to find id in government persons
    my $forename = trim($xpc->findvalue('./tei:persName/tei:forename/text()',$person));
    my $surname = trim($xpc->findvalue('./tei:persName/tei:surname/text()',$person));
    print STDERR "looking for $forename $surname in gov_osoby\n";
    my $sth = $pspdb->prepare(sprintf('SELECT * FROM gov_osoby WHERE jmeno="%s" AND prijmeni="%s"', $forename, $surname));
    $sth->execute;
    if(my $idpers = $sth->fetchrow_hashref){
      print STDERR "\tFOUND (GOV-$idpers->{id_osoba})\n";
      $id.='-'.$idpers->{id_osoba};
    }
  }

  if($id =~ m/(-?)([0-9]+)$/) {
    my $prefix = $1 ? 'gov_' : '';
    my $id_osoba = $2;
    my $type = $prefix ? 'gov' : 'reg';
    my $sth = $pspdb->prepare(sprintf('SELECT  "%s" as TYPE,* FROM %sosoby WHERE id_osoba=%s', $type, $prefix,$id_osoba));
    $sth->execute;
    my ($gov, $pers);
    if($pers = $sth->fetchrow_hashref){
      if($prefix){ # govern person
        $gov = $pers;
        # match based on name and birthdate:
        $sth = $pspdb->prepare(sprintf('SELECT "reg" as TYPE, * FROM osoby WHERE jmeno="%s" AND prijmeni="%s" AND narozeni="%s"', $gov->{jmeno}, $gov->{prijmeni}, $gov->{narozeni}//''));
        $sth->execute;
        if(my $pers2 = $sth->fetchrow_hashref) {
          $pers = $pers2;
          print STDERR "MATCHING (REG-$pers->{id_osoba} <=> GOV-$gov->{id_osoba}) '$pers->{jmeno} $pers->{prijmeni} nar. ",($pers->{narozeni}//'???'),"'\n";
          add_data_link($pers->{id_osoba},$id,$person);
        } else {
          print STDERR "No match for '$pers->{jmeno} $pers->{prijmeni} nar. ",($pers->{narozeni}//'???'),"' ($pers->{id_osoba}) in psp database\n";

          # match based on name:
          $sth = $pspdb->prepare(sprintf('SELECT "reg" as TYPE, * FROM osoby WHERE jmeno="%s" AND prijmeni="%s"', $gov->{jmeno}, $gov->{prijmeni}));
          $sth->execute;
          if(my $pers2 = $sth->fetchrow_hashref) {
            $pers = $pers2;
            print STDERR "MATCHING (REG-$pers->{id_osoba} <=> GOV-$gov->{id_osoba}) '$pers->{jmeno} $pers->{prijmeni}'\n";
            add_data_link($pers->{id_osoba},$id,$person);
          } else {
            print STDERR "No match for '$pers->{jmeno} $pers->{prijmeni}' ($pers->{id_osoba}) in psp database\n";
          }
        }
      } else {
        mapper_set_xml_pers($pers->{id_osoba},$person,'reg');
      }

      my ($pname) = $person->getChildrenByTagName('persName');
      if($pname){
        $pname->removeChildNodes();
        $pname->appendTextChild('surname',$pers->{prijmeni});
        $pname->appendTextChild('forename',$pers->{jmeno});
      }
      if($pers->{pohlavi}){
        my $sex = $person->addNewChild( undef, 'sex');
        $sex->appendTextNode($pers->{pohlavi} eq 'M' ? 'mužské' : 'ženské');
        $sex->setAttribute('value',$pers->{pohlavi} eq 'M' ? 'M' : 'F') ;
      }

      if($pers->{narozeni}){
        my $birth = $person->addNewChild( undef, 'birth');
        $birth->setAttribute('when',$pers->{narozeni}) ;
      }
      if($pers->{umrti}){
        my $death = $person->addNewChild( undef, 'death');
        $death->setAttribute('when',$pers->{umrti}) ;
      }

      if($pers->{TYPE} eq 'reg') {
        # table poslanec
        $sth = $pspdb->prepare(sprintf(
         'SELECT
            posl.id_osoba AS id_osoba,
            kand.id_organ AS kand_id_organ,
            kand.zkratka AS kand_zkratka,
            obd.id_organ AS obd_id_organ,
            obd.zkratka AS obd_zkratka,
            obd.od_organ AS od_obd,
            obd.do_organ AS do_obd

          FROM poslanec AS posl
            JOIN organy AS obd ON posl.id_obdobi = obd.id_organ
            JOIN organy AS kand ON posl.id_kandidatka = kand.id_organ
          WHERE posl.id_osoba=%s',$pers->{id_osoba}));
        $sth->execute;

        print STDERR "MATCHING (REG-$pers->{id_osoba}) '$pers->{jmeno} $pers->{prijmeni} nar. ",($pers->{narozeni}//'???'),"'\n";
        while(my $pm = $sth->fetchrow_hashref ) {
          addAffiliation($person,$pm->{obd_id_organ}, 'MP', $pm->{od_obd}, $pm->{do_obd});
          addAffiliation($person,$pm->{kand_id_organ}, 'candidateMP', $pm->{od_obd}, $pm->{do_obd});
        }

        $sth = $pspdb->prepare(sprintf(
         'SELECT
            org.id_organ AS id_organ,
            org.zkratka AS zkratka,
            zaraz.od_o AS od_o,
            zaraz.do_o AS do_o,
            funk.nazev_funkce_cz AS nazev_funkce,
            typf.typ_funkce_en AS typ_funkce_en,
            typf.typ_funkce_cz AS typ_funkce_cz
          FROM zarazeni AS zaraz
            JOIN funkce AS funk ON funk.id_funkce = zaraz.id_of
            JOIN organy as org ON org.id_organ = funk.id_organ
            JOIN typ_funkce AS typf ON funk.id_typ_funkce = typf.id_typ_funkce
          WHERE zaraz.id_osoba=%s
                AND zaraz.cl_funkce = 1',$pers->{id_osoba}));
        $sth->execute;
        while(my $func = $sth->fetchrow_hashref ) {
          addAffiliation($person,$func->{id_organ}, $func->{typ_funkce_en}//$translator->translate_static($func->{typ_funkce_cz}), $func->{od_o}, $func->{do_o});#->appendText($func->{nazev_funkce});
        }

        $sth = $pspdb->prepare(sprintf(
         'SELECT
            org.id_organ AS id_organ,
            org.zkratka AS zkratka,
            zaraz.od_o AS od_o,
            zaraz.do_o AS do_o
          FROM zarazeni AS zaraz
            JOIN organy AS org ON org.id_organ = zaraz.id_of
          WHERE zaraz.id_osoba=%s
                AND zaraz.cl_funkce = 0',$pers->{id_osoba}));
        $sth->execute;
        while(my $incl = $sth->fetchrow_hashref ) {
          addAffiliation($person,$incl->{id_organ}, 'member', $incl->{od_o}, $incl->{do_o});
        }
      }
    }
  } else {
    print STDERR "invalid id $id:\n$person\n";
  }
}

for my $reg_dbid (keys %data_links) {
  my $reg_person = mapper_get_xml_pers($reg_dbid,'reg');
  unless($reg_person){
    my ($gov_person) = values %{$data_links{$reg_dbid}};
    if ($gov_person) {
      # clone gov person node
      $reg_person = $gov_person->cloneNode(1);
      # change id and add to mapper
      my $new_id=listOrg::create_ID($xpc->findvalue('concat(.//tei:forename,.//tei:surname)',$gov_person)."$reg_dbid",keep_case=>1);
      $reg_person->setAttributeNS($XMLNS, 'id',$new_id);
      mapper_set_xml_pers($reg_dbid,$reg_person,'reg');
      # replace idno url
      my ($idno) = $xpc->findnodes('./tei:idno[@type="URI"]',$reg_person);
      if($idno){
        $idno->removeChildNodes();
      } else {
        my ($namenode) = $xpc->findnodes('./tei:persName',$reg_person);
        $idno = XML::LibXML::Element->new('idno');
        $idno->setAttribute('type','URI');
        $reg_person->insertAfter($idno,$namenode // undef);
      }
      $idno->appendText("https://www.psp.cz/sqw/detail.sqw?id=$reg_dbid");
      # append to parent node
      $gov_person->addSibling($reg_person);
    }
  }


  if ($reg_person) {
    print STDERR "person linking ",$reg_person->getAttributeNS($XMLNS,'id'),": ";
    for my $gov_person (values %{$data_links{$reg_dbid}}) {
      print STDERR " ",$gov_person->getAttributeNS($XMLNS,'id');
      my ($idno) = $xpc->findnodes('./tei:idno[@type="URI"]',$gov_person);
      if($idno) {
        $idno->unbindNode();
        my $insert_place = $xpc->findnodes('./tei:idno',$reg_person) // $xpc->findnodes('./tei:persName',$reg_person);
        $reg_person->insertAfter($idno,$insert_place // undef);
      }
      $gov_person->removeChildNodes();
      $gov_person->setAttribute('corresp','#'.$reg_person->getAttributeNS($XMLNS,'id'));
    }
  } else {
    print STDERR "ERROR - NOT FOUND: $reg_dbid";
  }
  print STDERR "\n";
}




ParCzech::PipeLine::FileManager::XML::save_to_file($personlist->{dom}, File::Spec->catfile($outdir,'person.xml'));
ParCzech::PipeLine::FileManager::XML::save_to_file($orglist->getXML_DOM(), File::Spec->catfile($outdir,'org.xml'));




sub trim {
  my $str = shift;
  $str =~ s/^\s*//;
  $str =~ s/\s*$//;
  return $str;
}


sub create_and_fill_table {
  my $tabledef = shift;
  my $tablename = shift;
  my $encoding = shift // 'Windows-1250';
  my $prefix = shift // '';
  return unless exists $dbfile_structure{"$prefix$tablename"};

  create_table($tabledef, $tablename, $prefix);
  fill_table($tabledef, $tablename, $encoding, $prefix);
}

sub drop_table {
  my $tablename = shift;
  my $prefix = shift // '';
  return unless exists $dbfile_structure{"$prefix$tablename"};
  my $dbstring = sprintf('DROP TABLE %s', "$prefix$tablename");
  print STDERR "$dbstring\n" if $debug;
  $pspdb->do($dbstring);
}

sub create_table {
  my $tabledef = shift;
  my $tablename = shift;
  my $prefix = shift // '';
  return unless exists $dbfile_structure{"$prefix$tablename"};
  my $dbstring = sprintf('CREATE TABLE %s (%s)',
                         "$prefix$tablename",
                         join(", ", map {sprintf("%s %s", $_->{name}, $_->{type})} @{$tabledef->{def}} ));
  print STDERR "$dbstring\n" if $debug;
  $pspdb->do($dbstring);
  for my $idx (@{$tabledef->{index}//[]}) {
    my ($f,$un) = split('\|',"$idx|");
    $dbstring =sprintf("CREATE %s INDEX i_%s_%s ON %s (%s)",$un,"$prefix$tablename",$f,"$prefix$tablename",$f);
    print STDERR "$dbstring\n" if $debug;
    $pspdb->do($dbstring);
  }
}

sub fill_table {
  my $tabledef = shift;
  my $tablename = shift;
  my $encoding = shift // 'Windows-1250';
  my $prefix = shift // '';
  return unless exists $dbfile_structure{"$prefix$tablename"};
  open(my $fh,"<:encoding($encoding)",  $dbfile_structure{"$prefix$tablename"}) or die "Cannot open:$!\n";
  $pspdb->begin_work;
  while(my $line = <$fh>) {
    my @fields = map {s/^\s*$//;$_} split('\|',$line);
    my @dbname;
    my @dbval;
    for my $i (0..($#fields-1)) {
      my $name = $tabledef->{def}->[$i]->{name};
      if(exists $tabledef->{invalid_values}->{$name}){
        $fields[$i] = '' if $fields[$i] eq $tabledef->{invalid_values}->{$name};
      }
      if(exists $tabledef->{cast}->{$name}){
        $fields[$i] = $tabledef->{cast}->{$name}->($fields[$i]);
      }
      undef $fields[$i] if $fields[$i] eq '';
      if(defined $fields[$i] ){
        push @dbname, $name;
        push @dbval,($tabledef->{def}->[$i]->{type} eq 'INTEGER') ? $fields[$i] : "'$fields[$i]'";
      }
    }
    my $dbstring = sprintf("INSERT INTO %s (%s) VALUES (%s)", "$prefix$tablename", join(',',@dbname),join(',',@dbval));
    print STDERR "$dbstring\n" if $debug;
    $pspdb->do($dbstring);
  }
  $pspdb->commit;
}

sub addAffiliation {
  my ($elem,$id,$role,$from,$to) = @_;
  my $aff = $elem->addNewChild( undef, 'affiliation');
  my $ref = $orglist->addOrg($id)->id();
  $aff->setAttribute('ref',"#$ref");
  $aff->setAttribute('role',listOrg::create_ID($patcher->translate_static($role))) if $role;
  if($from) {
    $from =~ s/ /T/;
    $aff->setAttribute('from',$from);
  }
  if($to){
    $to =~ s/ /T/;
    $aff->setAttribute('to',$to);
  }
  return $aff;
}

sub add_data_link {
  my ($reg,$gov,$govperson) = @_;
  $data_links{$reg} = {} unless defined $data_links{$reg};
  $data_links{$reg}->{$gov} = $govperson;
}

sub mapper_get_xml_pers {
  my ($id,$type) = @_;
  return $mapper{"$type$id"};
}
sub mapper_set_xml_pers {
  my ($id,$pers,$type) = @_;
  $mapper{"$type$id"} = $pers;
}

sub usage_exit {
  my $pref = shift // '';
  print
"$pref

Usage: pspdb-generate-xml.pl  --person-list <STRING> --output-dir <STRING> --input-db-dir <STRING> [--debug] [--flat]

\t--person-list=s\tfile containing list of persons that should be enriched and linked
\t--output-dir=s\tfolder where will be result stored (person.xml, org.xml) and database file psp.db
\t--input-db-dir=s\tdirectory with downloaded and unpacked database dump files
\t--flat\tprint flat organization structure (no sub organization)
";
   exit;
}

package listOrg;


sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my %opts = @_;
  my $self  = {};
  bless $self, $class;
  $self->{db} = $opts{db};
  $self->{hidden} = ! defined $opts{visible};
  $self->{child} = {}; # list of child orgs
  $self->{list_org} = {}; # list of all descendant orgs
  $self->{org} = {}; # list of all orgs
  $self->{roles} = {};
  $self->{translator} = $opts{translator};
  $self->{patcher} = $opts{patcher};

  return $self;
}


sub getXML_DOM {
  my $self = shift;
  my $dom = XML::LibXML::Document->new("1.0", "utf-8");
  my $root_node =  XML::LibXML::Element->new('listOrg');
  $root_node->setNamespace('http://www.tei-c.org/ns/1.0');
  $root_node->setNamespace('http://www.w3.org/XML/1998/namespace', 'xml', 0);
  $dom->setDocumentElement($root_node);
  $self->addToXML($root_node);
  return $dom
}

sub addToXML {
  my $self = shift;
  my $parent = shift;
  return unless $parent;
  for my $ch_id (keys %{$self->{child}}){
    $self->{child}->{$ch_id}->addToXML($parent);
  }
}




sub addChild {
  my $self = shift;
  my $child = shift;
  return unless defined $child;
  $self->{child}->{$child->id} = $child;
}

sub getRole {
  my $self = shift;
  my $rid = shift;
  unless(defined $self->{roles}->{$rid}) {
    # create role from database
    my $sth = $pspdb->prepare(sprintf(
         'SELECT
            type.id_typ_org AS id_typ,
            type.nazev_typ_org_cz AS name_cz,
            type.nazev_typ_org_en AS name_en,
            type.typ_org_obecny AS gen,
            type.typ_id_typ_org AS parent
          FROM typ_organu AS type
          WHERE type.id_typ_org=%s',$rid));
    $sth->execute;
    if(my $r = $sth->fetchrow_hashref){
      $self->{roles}->{$rid} = {
        parent => "PARENT",
        name_cz => $r->{name_cz},
        name_en => $r->{name_en},
        id => create_ID($self->{patcher}->translate_static($r->{name_en} // $self->{translator}->translate_static($r->{name_cz})))
      };
    } else {
      print STDERR "ERROR: unknown role id_typ_org=$rid\n";
      return '';
    }
  }
  return $self->{roles}->{$rid}->{id};
}


sub addOrg {
  my $self = shift;
  my $dbid = shift;
  return unless defined $dbid;
  unless(defined $self->{org}->{$dbid}) {
    my $sth = $pspdb->prepare(sprintf(
         'SELECT
            org.id_organ AS id_organ,
            org.zkratka AS abbr,
            org.nazev_organu_cz AS name_cz,
            org.nazev_organu_en AS name_en,
            org.od_organ AS `from`,
            org.do_organ AS `to`,
            org.organ_id_organ AS parent,
            org.id_typ_org AS type
          FROM organy AS org
          WHERE org.id_organ=%s',$dbid));
    $sth->execute;
    if(my $orgrow = $sth->fetchrow_hashref ) {
      my $role = $self->getRole($orgrow->{type});
      my $parent;
      $parent = $self->addOrg($orgrow->{parent}) unless $flat;
      my $org = listOrg::org->new(%$orgrow, abbr_sd => create_ID($orgrow->{abbr},keep_case => 1, keep_dash => 1), role => $role,  $parent ? (parent_org_id => $parent->id()):() );
      $self->{org}->{$dbid} = $org;
      ($parent//$self)->addChild($org);
    } else {
      return undef;
    }
  }
  return $self->{org}->{$dbid}
}

sub create_ID {
  my $str = shift // '';
  my %opts = @_;

  $str =~s/^\s+|\s+$//g;
  $str =~ s/-/ /g unless $opts{keep_dash};
  $str =~ s/,/ /g;
  $str =~ s/\s+/ /g;
  $str = Unicode::Diacritic::Strip::strip_diacritics($str);
  if($opts{keep_case}){ # keep case in abbrevitations
    $str =~ s/ //g;
  } elsif ($str =~ m/ /) {
    $str = lc $str unless $str eq uc $str;
    $str =~ s/ (\w)/\U$1/g;
  } elsif ( !( $str eq uc $str)){
    $str =~ s/^(\w)/\l$1/; # make first letter small
  }

  return $str;
}

package listOrg::org;

sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my %opts = @_;
  my $self  = { map { $_ => $opts{$_} } qw/abbr name_cz name_en from to role abbr_sd id_organ/ };
  bless $self, $class;
  $self->{iddb} = {
    id => $opts{id_organ},
    parent => $opts{parent},
    type => $opts{type}
  };
  $self->buildID();
  $self->{child} = {};

  return $self;
}

sub buildID {
  my $self = shift;
  my @parts;
  push @parts, $self->{role} if $self->{role};
  push @parts, $self->{abbr_sd};
  unless(defined $uniqueOrgRoles{$self->{role} // ''}){
    push @parts, $self->{id_organ};
  }
  $self->{id} = join('.', @parts);
}

sub id {
  return shift->{id}
}

sub addChild {
  my $self = shift;
  my $child = shift;
  return unless defined $child;
  $self->{child}->{$child->id} = $child;
}


sub addToXML {
  my $self = shift;
  my $parent = shift;
  return unless $parent;
  my $XMLNS='http://www.w3.org/XML/1998/namespace';
  my $org = $parent->addNewChild( undef, 'org');
  $org->setAttributeNS($XMLNS, 'id', $self->id);
  $org->setAttribute('role',$self->{role}) if $self->{role};
  for my $n ([qw/name_cz cs/],[qw/name_en en/])  {
    if(defined $self->{$n->[0]}) {
      my $name = $org->addNewChild(undef,'orgName');
      $name->appendText($self->{$n->[0]});
      $name->setAttribute('full', 'yes');
      $name->setAttributeNS($XMLNS, 'lang', $n->[1]);
    }
  }
  my $name = $org->addNewChild(undef,'orgName');
  $name->appendText($self->{abbr});
  $name->setAttribute('full', 'init');
  my $existence;
  for my $dt (qw/from to/) {
    if(defined $self->{$dt}){
      unless($existence){
        $existence =$org->addNewChild(undef,'event');
        my $lab = $existence->addNewChild(undef,'label');
        $lab->setAttributeNS($XMLNS, 'lang', 'en');
        $lab->appendText('existence');
      }
      $existence->setAttribute($dt,$self->{$dt});
    }
  }
  if(%{$self->{child}}) {
    my $list = $org->addNewChild( undef, 'listOrg');
    for my $ch_id (keys %{$self->{child}}){
      $self->{child}->{$ch_id}->addToXML($list);
    }
  }
}
