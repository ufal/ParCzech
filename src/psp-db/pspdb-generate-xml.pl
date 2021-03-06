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




my ($debug, $personlist_in, $outdir, $indbdir, $govdir,$translations,$patches, $flat, $term_list, $allterm_person_filepath);

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
            'term-list=s' => \$term_list,
            'allterm-person-outfile=s' => \$allterm_person_filepath,
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
my $patcher = ParCzech::Translation->new(single_direction => 1, keep_if_no_match => 1 ,$patches ? (tran_files => $patches) : ());
my $translator = ParCzech::Translation->new($translations ? (tran_files => $translations) : (),
                                            tran_regex => $regex_translations);

my $org_translator = ParCzech::Translation->new($translations ? (tran_files => $translations) : ());
my $orglist = listOrg->new(db => $pspdb, translator => $org_translator,
                                         patcher => $patcher);

usage_exit() unless $personlist;
my $xpc = ParCzech::PipeLine::FileManager::TeiFile::new_XPathContext();

my $new_personlist = listPerson->new(org_list => $orglist, db => $pspdb);
my %allterm_persons;


# firstly add all persons for given term to $new_personlist
for my $term (split(/,/,$term_list//'')){
  # find corresponding Chamber of Deputies organization id (id_organ)

  print STDERR "$term\n";
  my $sth = $pspdb->prepare(sprintf(
         'SELECT
            posl.id_osoba AS id_osoba,
            obd.zkratka AS obd_zkratka
          FROM poslanec AS posl
            JOIN organy AS obd ON posl.id_obdobi = obd.id_organ
          WHERE substr(obd.od_organ,1,4)="%s"',$term));
  $sth->execute;
  while(my $pm = $sth->fetchrow_hashref ) {
    my $person_id = $new_personlist->addPerson(psp_id => $pm->{id_osoba});
    $allterm_persons{$person_id} = 1;
    print STDERR "\tMATCH $person_id \n";
  }
}


# print "allterm" persons to file
if($allterm_person_filepath) {
  my $dom = XML::LibXML::Document->new("1.0", "utf-8");
  my $root_node =  XML::LibXML::Element->new('listPerson');
  $root_node->setNamespace('http://www.tei-c.org/ns/1.0');
  $root_node->setNamespace('http://www.w3.org/XML/1998/namespace', 'xml', 0);
  $dom->setDocumentElement($root_node);
  for my $id (sort keys %allterm_persons) {
    my $person = $root_node->addNewChild( undef, 'person');
    $person->setAttributeNS($XMLNS,'id',"mp-$id");
    $person->setAttribute('corresp',"person.xml#$id");
  }
  print STDERR "adding ",scalar(keys %allterm_persons)," persons to $allterm_person_filepath\n";
  ParCzech::PipeLine::FileManager::XML::save_to_file($dom, $allterm_person_filepath);
}



# loop over persons in $personlist and add them to $new_personlist

for my $person_node ($xpc->findnodes('//tei:person',$personlist->{dom})) {
  my $id = $person_node->getAttributeNS($xpc->lookupNs('xml'),'id');
  my $forename = trim($xpc->findvalue('./tei:persName/tei:forename/text()',$person_node));
  my $surname = trim($xpc->findvalue('./tei:persName/tei:surname/text()',$person_node));
  my %data = ();

  if( my ($gov_id) = $id =~ m/-([0-9]+)$/){
    $data{gov_id} = $gov_id;
  } elsif (my ($psp_id) = $id =~ m/[^-]([0-9]+)$/) {
    $data{psp_id} = $psp_id;
  } else {
    $data{guest_id} = $id;
  }

  my $person_id = $new_personlist->addPerson(
                                    forename => $forename,
                                    surname  => $surname,
                                    %data
                                    );
  print STDERR "PERSON $forename $surname " ,join(' ',values %data)," = $person_id\n";
  my $person = $new_personlist->findPerson(id => $person_id);
  for my $link (grep {$_} $xpc->findvalue('normalize-space(./tei:idno[@type="URI"]/text())',$person_node)) {
    my $type = 'guest';
    $type = 'gov' if $link =~ m/vlada.cz/;
    $type = 'psp' if $link =~ m/psp.cz/;
    $person->addLink($link,$type);
  }
  $new_personlist->addPersonXMLID($id,$person_id);
}



#ParCzech::PipeLine::FileManager::XML::save_to_file($personlist->{dom}, File::Spec->catfile($outdir,'person.xml'));
ParCzech::PipeLine::FileManager::XML::save_to_file($new_personlist->getXML_DOM(), File::Spec->catfile($outdir,'person.xml'));
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
    $line =~ s/\N{U+00A0}/ /g;
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


package listPerson;
use Data::Dumper;


sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my %opts = @_;
  my $self  = {};
  bless $self, $class;
  $self->{org_list} = $opts{org_list};
  $self->{listPerson} = {};
  $self->{ids_in_xml} = {};

  #   gov:gov_id   -> id
  #   psp:psp_id   -> id
  #   guest:guest_id -> id
  $self->{ids_to_main_id} = {};


  return $self;
}

sub addPerson { # create new person or use existing based on passed data
  my $self = shift;
  my %opts = @_;
  my $person = $self->findPerson(%opts);
  print STDERR join(' ',@_),"\n";
  my $sth;
  unless ($person){
    if(defined $opts{guest_id}){ # try to find id in government persons
      print STDERR "looking for $opts{forename} $opts{surname} in gov_osoby\n";
      $sth = $pspdb->prepare(sprintf('SELECT * FROM gov_osoby WHERE jmeno="%s" AND prijmeni="%s"', $opts{forename}//'', $opts{surname}//''));
      $sth->execute;
      if(my $idpers = $sth->fetchrow_hashref){
        print STDERR "\tFOUND (GOV:$idpers->{id_osoba})\n";
        $opts{gov_id} = $idpers->{id_osoba};
      } else {
        print STDERR "\tperson not found in any database: $opts{guest_id}\n";
      }
    }
    if(defined $opts{gov_id}){
      $sth = $pspdb->prepare(sprintf('SELECT * FROM gov_osoby WHERE id_osoba=%s', $opts{gov_id}));
      $sth->execute;
      if(my $gov_pers = $sth->fetchrow_hashref) {
        # match based on name and birthdate:
        print STDERR "found GOV:$gov_pers->{id_osoba} '$gov_pers->{jmeno} $gov_pers->{prijmeni} (",($gov_pers->{narozeni}//'???'),")'\n";
        $sth = $pspdb->prepare(sprintf('SELECT * FROM osoby WHERE jmeno="%s" AND prijmeni="%s" AND narozeni="%s"', $gov_pers->{jmeno}, $gov_pers->{prijmeni}, $gov_pers->{narozeni}//''));
        $sth->execute;
        if(my $psp_pers = $sth->fetchrow_hashref) {
          print STDERR "MATCHING (REG:$psp_pers->{id_osoba} <=> GOV:$gov_pers->{id_osoba}) '$psp_pers->{jmeno} $psp_pers->{prijmeni} nar. ",($psp_pers->{narozeni}//'???'),"'\n";
          $opts{psp_id} = $psp_pers->{id_osoba};
        } else {
          print STDERR "No match for '$gov_pers->{jmeno} $gov_pers->{prijmeni} nar. ",($gov_pers->{narozeni}//'???'),"' ($gov_pers->{id_osoba}) in psp database\n";
          # match based on name:
          $sth = $pspdb->prepare(sprintf('SELECT * FROM osoby WHERE jmeno="%s" AND prijmeni="%s"', $gov_pers->{jmeno}, $gov_pers->{prijmeni}));
          $sth->execute;
          if(my $psp_pers = $sth->fetchrow_hashref) {
            print STDERR "MATCHING (REG:$psp_pers->{id_osoba} <=> GOV:$gov_pers->{id_osoba}) '$psp_pers->{jmeno} $psp_pers->{prijmeni}'\n";
            $opts{psp_id} = $psp_pers->{id_osoba};
          } else {
            print STDERR "No match for '$gov_pers->{jmeno} $gov_pers->{prijmeni}' (GOV:$gov_pers->{id_osoba}) in psp database\n";
          }
        }
      } else {
        print STDERR "INVALID DATA: No record in GOV database for $opts{gov_id}\n";
      }
    }

    if(defined $opts{psp_id}){
      $sth = $pspdb->prepare(sprintf('SELECT * FROM osoby WHERE id_osoba=%s', $opts{psp_id}));
      $sth->execute;
      if(my $psp_pers = $sth->fetchrow_hashref) {
        print STDERR "found REG:$psp_pers->{id_osoba} '$psp_pers->{jmeno} $psp_pers->{prijmeni} (",($psp_pers->{narozeni}//'???'),")'\n";
      } else {
        print STDERR "INVALID DATA: No record in PSP database for $opts{psp_id}\n";
      }
    }

    $person = $self->createPerson(%opts);

  } else {
    print STDERR "person already exists: ", $person->toString(),"\n";
  }

  # add links to ids_to_main_id
  for my $type (qw/psp gov guest/){
    if(defined $opts{"${type}_id"}){
      my $prefixed_id = $type.':'.$opts{"${type}_id"};
      $self->{ids_to_main_id}->{$prefixed_id} = $person->id;
    }
  }
  $person->id
}


sub findPerson {
  my $self = shift;
  my %opts = @_;
  return $self->{listPerson}->{$opts{id}} if defined $opts{id};
  for my $type (qw/psp gov guest/){
    if(defined $opts{"${type}_id"}){
      my $prefixed_id = $type.':'.$opts{"${type}_id"};
      print STDERR "LOOKING FOR $prefixed_id -> ",($self->{ids_to_main_id}->{$prefixed_id}//''),"\n";
      return $self->{listPerson}->{$self->{ids_to_main_id}->{$prefixed_id}} if defined $self->{ids_to_main_id}->{$prefixed_id};
    }
  }
}

sub createPerson {
  my $self = shift;
  my %opts = @_;
  # create person
  my $pers;
  my $sth;
  if($opts{psp_id}){
    my $sth = $pspdb->prepare(sprintf('SELECT * FROM osoby WHERE id_osoba=%s', $opts{psp_id}));
    $sth->execute;
    $pers = $sth->fetchrow_hashref;
    $opts{psp_link} = "https://www.psp.cz/sqw/detail.sqw?id=$opts{psp_id}" if $pers;

  }
  if(!$pers && $opts{gov_id}){
    my $sth = $pspdb->prepare(sprintf('SELECT * FROM gov_osoby WHERE id_osoba=%s', $opts{gov_id}));
    $sth->execute;
    $pers = $sth->fetchrow_hashref;
  }
  if($pers) {
    $opts{forename} = $pers->{jmeno} if $pers->{jmeno};
    $opts{surname} = $pers->{prijmeni} if $pers->{prijmeni};
    $opts{birth} = $pers->{narozeni} if $pers->{narozeni};
    $opts{death} = $pers->{umrti} if $pers->{umrti};
    $opts{sex} = $pers->{pohlavi} eq 'M' ? 'M' : 'F' if $pers->{pohlavi};
  }

  my $person = listPerson::person->new(%opts);
  my $person_id = $person->id;
  if(defined $self->{listPerson}->{$person_id}){ # test if person exists
    undef $person;
    return $self->{listPerson}->{$person_id};
  }

  # add affiliations
  if($person->isInPSP){
    ###########
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

    while(my $pm = $sth->fetchrow_hashref ) {
      # addAffiliation($person,$pm->{obd_id_organ}, 'MP', $pm->{od_obd}, $pm->{do_obd}); # duplicite
      $self->addAffiliation($person,$pm->{kand_id_organ}, 'candidateMP', $pm->{od_obd}, $pm->{do_obd});
    }

    ###########
    # functions
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
      $self->addAffiliation($person,$func->{id_organ}, $func->{typ_funkce_en}//$translator->translate_static($func->{typ_funkce_cz}), $func->{od_o}, $func->{do_o});
    }
    ###########
    # members
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
      $self->addAffiliation($person,$incl->{id_organ}, 'member', $incl->{od_o}, $incl->{do_o});
    }
  }
  $self->{listPerson}->{$person->id} = $person;
  return $person;
}

sub addAffiliation {
  my $self = shift;
  my ($person,$org_db_id,$role,$from,$to) = @_;
  my $org = $self->{org_list}->addOrg($org_db_id);
  $role='MP' if $org->role() eq 'parliament' && ($role//'') eq 'member';
  $role = listOrg::create_ID($patcher->translate_static($role)) if $role;
  $from =~ s/ /T/ if $from;
  $to =~ s/ /T/ if $to;
  $person->affiliate(ref => '#'.$org->id(), role => $role, from => $from, to => $to);
}

sub addPersonXMLID {
  my $self = shift;
  my ($xml_id,$person_id) = @_;
  return if $person_id eq $xml_id;
  $self->{ids_in_xml}->{$xml_id} = $person_id;
}

sub getXML_DOM {
  my $self = shift;
  my $dom = XML::LibXML::Document->new("1.0", "utf-8");
  my $root_node =  XML::LibXML::Element->new('listPerson');
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
  for my $pers_id (sort keys %{$self->{listPerson}} ){
    $self->{listPerson}->{$pers_id}->addToXML($parent);
  }
  for my $xml_id (sort keys %{$self->{ids_in_xml}}) {
    my $person = $parent->addNewChild( undef, 'person');
    $person->setAttributeNS($XMLNS,'id',$xml_id);
    $person->setAttribute('corresp',"#".$self->{ids_in_xml}->{$xml_id});
  }
}


package listPerson::person;
use Data::Dumper;

sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my %opts = @_;
  my $self  = {};
  bless $self, $class;
  $self->{alternative_ids} = {}; # type => value
  $self->{idno} = {};
  $self->{affiliation} = [];
  $self->init(%opts);
  return $self;
}

sub id {
  my $self = shift;
  my $type = shift;
  return $self->{id} unless $type;
  return $self->{alternative_ids}->{$type};
}

sub isInPSP {
  my $self = shift;
  return !!$self->{alternative_ids}->{psp};
}

sub init {
  my $self = shift;
  my %opts = @_;
  for my $type (qw/psp gov guest/){
    if(defined $opts{"${type}_id"}){
      $self->{alternative_ids}->{$type} = $opts{"${type}_id"}
    }
    if(defined $opts{"${type}_link"}){
      $self->addLink($opts{"${type}_link"},$type);
    }
  }
  for my $key (qw/forename surname birth death sex/){
    if(defined $opts{$key} and $opts{$key}){
      $self->{$key} = $opts{$key}
    }
  }
  if(defined $self->{forename} and defined $self->{surname}){
    my $year = '';
    if(defined $self->{birth}){
      ($year) = $self->{birth} =~ m/^(\d\d\d\d)/;
      $year = ".$year" if $year;
    }

    $self->{id} = $self->{forename}.$self->{surname}.$year;
    $self->{id} =~ s/ //g;
    $self->{id} = Unicode::Diacritic::Strip::strip_diacritics($self->{id})
  }
}

sub addLink {
  my $self = shift;
  my ($link,$type) = (@_,'guest');
  $self->{idno}->{$type}->{$link} = 1;
}

sub affiliate {
  my $self = shift;
  my %opts = @_;
  my $aff = {};
  for $a (qw/ref role from to/){
    $aff->{$a} = $opts{$a} if $opts{$a}
  }
  push @{$self->{affiliation}},$aff;
}

sub toString {
  my $self = shift;
  return $self->id;
}

sub addToXML {
  my $self = shift;
  my $parent = shift;
  return unless $parent;
  my $pers = $parent->addNewChild( undef, 'person');
  $pers->setAttributeNS($XMLNS, 'id', $self->id);
  # personal data
  my $pname = $pers->addNewChild( undef, 'persName');
  $pname->appendTextChild($_,$self->{$_}) for qw/surname forename/;
  if($self->{sex}){
    my $sex = $pers->addNewChild( undef, 'sex');
    $sex->appendTextNode($self->{sex} eq 'M' ? 'mužské' : 'ženské');
    $sex->setAttribute('value',$self->{sex} eq 'M' ? 'M' : 'F') ;
  }
  for my $life_event (qw/birth death/) {
    if($self->{$life_event}){
      my $event = $pers->addNewChild( undef, $life_event);
      $event->setAttribute('when',$self->{$life_event}) ;
    }
  }
  # links
  for my $type (qw/psp gov guest/){
    if(defined $self->{idno}->{$type}){
      for my $link (keys %{$self->{idno}->{$type}}){
        my $idno = $pers->addNewChild( undef, 'idno');
        $idno->setAttribute('type','URI');
        $idno->appendText($link);
      }
    }
  }
  # affiliations
  for my $pers_aff (sort { $b->{from} cmp $a->{from} } @{$self->{affiliation} // []}){
    my $aff = $pers->addNewChild( undef, 'affiliation');
    for my $a (qw/ref role from to/){
      $aff->setAttribute($a,$pers_aff->{$a}) if $pers_aff->{$a};
    }
  }
}


###############################################################

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
        id => create_ID($self->{patcher}->translate_static($r->{name_en} // $self->{translator}->translate_static($r->{name_cz}) // 'institution'))
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

sub role {
  return shift->{role}
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
