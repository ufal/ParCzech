use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use Getopt::Long;
use File::Spec;
use DateTime::Format::Strptime;
use ParCzech::PipeLine::FileManager "psp-db";
use ParCzech::Translation;
use DBI;
use Unicode::Diacritic::Strip;
use Data::Dumper;
use List::Util;




my ($debug, $personlist_in, $outdir, $indbdir, $govdir,$translations,$patches, $roles_patches, $org_ana, $flat, $merge_to_events, $term_list, $allterm_person_filepath);

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
my %uniqueOrgRoles = map {($_ => 1)} qw/parliament senate nationalCouncil republic politicalParty/;
my %skip_orgs  = map {($_ => 1)} qw/Nezařazení/;

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
    osoba_extra => {
      def => [
        map {my ($n,$t) = split('\|', $_);{name => $n, type => $t} }
            qw/id_osoba|INTEGER id_org|INTEGER typ|INTEGER obvod|INTEGER strana|CHAR(100) id_external|INTEGER/
      ],
      index => [qw/id_osoba id_org typ id_external/],
      invalid_values => {},
      cast => {},
    },

  }
);

GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'flat' => \$flat,
            'merge-to-events' => \$merge_to_events,
            'term-list=s' => \$term_list,
            'allterm-person-outfile=s' => \$allterm_person_filepath,
            'person-list=s' => \$personlist_in,
            'output-dir=s' => \$outdir,
            'gov-input-dir=s' => \$govdir,
            'input-db-dir=s' => \$indbdir,
            'translations=s' => \$translations,
            'patches=s' => \$patches,
            'roles-patches=s' => \$roles_patches,
            'org-ana=s' => \$org_ana,
            );



usage_exit() unless $indbdir;
usage_exit() unless $personlist_in;
usage_exit() unless $outdir;

$flat = 1 if $merge_to_events;

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
  create_and_fill_table($tabledef{poslanci}->{osoba_extra},'osoba_extra');
}


my $regex_translations = [
  [qr/ministr/i,'Minister'],
  [qr/místopředseda/i,'Deputy Head'],
  [qr/^.+$/,'Member'],
];
my $regex_patches = [
  [qr/^Czech Republic\s*-?\s*(.*?) Inter-Parliamentary Group$/i,'%s'],
];

my %comparison_ignore_words = map {$_ => 1} qw/podvýbor subcommittee výbor committee pro on for of the a and poslanecký political klub group/;


my $personlist = ParCzech::PipeLine::FileManager::XML::open_xml($personlist_in);
my $patcher = ParCzech::Translation->new(single_direction => 1, keep_if_no_match => 1 ,$patches ? (tran_files => $patches) : (),tran_regex => $regex_patches);
my $translator = ParCzech::Translation->new($translations ? (tran_files => $translations) : (),
                                            tran_regex => $regex_translations);
my $roles_patcher = ParCzech::Translation->new(single_direction => 1, keep_if_no_match => 1 ,$roles_patches ? (tran_files => $roles_patches) : ());
my $org_annotator = ParCzech::Translation->new(single_direction => 1,$org_ana ? (tran_files => $org_ana) : ());

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

  print STDERR "ADDING ALL PERSONS FROM TERM $term\n";
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
  print STDERR "\tPERSON $forename $surname " ,join(' ',values %data)," = $person_id\n";
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
  print STDERR "filling table: $prefix$tablename\n";
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
        push @dbval,($tabledef->{def}->[$i]->{type} eq 'INTEGER') ? $fields[$i] : "'".escape($fields[$i])."'";
      }
    }
    my $dbstring = sprintf("INSERT INTO %s (%s) VALUES (%s)", "$prefix$tablename", join(',',@dbname),join(',',@dbval));
    print STDERR "$dbstring\n" if $debug;

    print STDERR "ERROR: $dbstring\n" unless $pspdb->do($dbstring);
  }
  $pspdb->commit;
}

sub escape {
  my $str = shift;
  $str =~ s/(['])/$1$1/g;
  return $str;
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

Usage: pspdb-generate-xml.pl  --person-list <STRING> --output-dir <STRING> --input-db-dir <STRING> [--debug] [--flat] [--merge-to-events]

\t--person-list=s\tfile containing list of persons that should be enriched and linked
\t--output-dir=s\tfolder where will be result stored (person.xml, org.xml) and database file psp.db
\t--input-db-dir=s\tdirectory with downloaded and unpacked database dump files
\t--flat\tprint flat organization structure (no sub organization)
\t--merge-to-events\tmerges organizations with same prefix into one organization (produce flat structure)
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

sub getPhotoUrl {
  my $self = shift;
  my ($pers_id,$dt,$obd) = @_;
  return unless $obd =~ m/^PSP/;
  $dt =~ s/-.*$//;
  my $url = "https://www.psp.cz/eknih/cdrom/${dt}ps/eknih/${dt}ps/poslanci/i${pers_id}.jpg";
  return $url;
}

sub addPerson { # create new person or use existing based on passed data
  my $self = shift;
  my %opts = @_;
  my $person = $self->findPerson(%opts);
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
          print STDERR  "TODO: add  testing affiliation with government \n";
          $sth = $pspdb->prepare(sprintf('SELECT * FROM osoby WHERE jmeno="%s" AND prijmeni="%s"', $gov_pers->{jmeno}, $gov_pers->{prijmeni}));
          $sth->execute;
          my $result = $sth->fetchall_hashref('id_osoba');
          print STDERR "Multiple persons matched - using older one\n" if(keys %$result > 1);
          if(my $psp_pers = [reverse sort {($a->{narozeni}//'') cmp ($b->{narozeni}//'')} values %$result]->[0]) {
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
        print STDERR "found REG:$psp_pers->{id_osoba} '$psp_pers->{jmeno} $psp_pers->{prijmeni} (",($psp_pers->{narozeni}//'???'),")'";
      } else {
        print STDERR "INVALID DATA: No record in PSP database for $opts{psp_id}\n";
      }
    }

    $person = $self->createPerson(%opts);

  } else {
    print STDERR "person already exists: ", $person->toString(),"";
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
      print STDERR "LOOKING FOR $prefixed_id -> ",($self->{ids_to_main_id}->{$prefixed_id}//''),"\t";
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

  if($person->isInPSP){ # add aditional personal info (web, facebook, photo(from newest period))
    $sth = $pspdb->prepare(sprintf(
         'SELECT
            posl.id_osoba AS id_osoba,
            kand.id_organ AS kand_id_organ,
            kand.zkratka AS kand_zkratka,
            obd.id_organ AS obd_id_organ,
            obd.zkratka AS obd_zkratka,
            obd.od_organ AS od_obd,
            obd.do_organ AS do_obd,
            posl.foto AS foto,
            posl.web AS web,
            posl.facebook AS facebook
          FROM poslanec AS posl
            JOIN organy AS obd ON posl.id_obdobi = obd.id_organ
            JOIN organy AS kand ON posl.id_kandidatka = kand.id_organ
          WHERE posl.id_osoba=%s',$pers->{id_osoba}));
    $sth->execute;
    while(my $pm = $sth->fetchrow_hashref ) {
      $person->addLink($pm->{facebook}, 'facebook') if defined $pm->{facebook};
      $person->addLink($pm->{web}, 'personal') if defined $pm->{web};
      $person->addPhoto($self->getPhotoUrl($pm->{id_osoba},$pm->{od_obd},$pm->{obd_zkratka}), $pm->{od_obd})  if defined $pm->{foto};
    }

    # try to add senat url
    $sth = $pspdb->prepare(sprintf(
           'SELECT
             extra.id_external AS id_external,
             org.od_organ AS od_organ
            FROM
              osoba_extra AS extra
              JOIN organy as org ON org.id_organ = extra.id_org
            WHERE
              extra.id_osoba=%s
              AND extra.typ=1
              AND org.od_organ IS NOT NULL',$pers->{id_osoba}));
    $sth->execute;
    while(my $pm = $sth->fetchrow_hashref ) {
      $person->addLink(
                 sprintf('https://www.senat.cz/senatori/index.php?ke_dni=%d.%d.%d&par_3=%s',
                         (reverse split('-',$pm->{od_organ})),
                         $pm->{id_external}), 'senat');
    }
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
      $self->addAffiliation($person,$pm->{kand_id_organ}, 'representative', $pm->{od_obd}, $pm->{do_obd}, "Reprezentant", "Representative");
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
                AND zaraz.cl_funkce = 1
                AND funk.id_typ_funkce > 0',$pers->{id_osoba}));
    $sth->execute;
    while(my $func = $sth->fetchrow_hashref ) {
      $self->addAffiliation($person,
                            $func->{id_organ},
                            $roles_patcher->translate_static( $translator->translate_static($func->{typ_funkce_cz})
                                                              // $func->{typ_funkce_en}),
                            $func->{od_o},
                            $func->{do_o},
                            $func->{typ_funkce_cz},
                            $translator->translate_static($func->{typ_funkce_cz})
                              //$func->{typ_funkce_en}
                            );
    }
    # patched functions
    $sth = $pspdb->prepare(sprintf(
         'SELECT
            org.id_organ AS id_organ,
            org.zkratka AS zkratka,
            zaraz.od_o AS od_o,
            zaraz.do_o AS do_o,
            funk.nazev_funkce_cz AS nazev_funkce
          FROM zarazeni AS zaraz
            JOIN funkce AS funk ON funk.id_funkce = zaraz.id_of
            JOIN organy as org ON org.id_organ = funk.id_organ
          WHERE zaraz.id_osoba=%s
                AND zaraz.cl_funkce = 1
                AND funk.id_typ_funkce < 0',$pers->{id_osoba}));
    $sth->execute;
    while(my $func = $sth->fetchrow_hashref ) {
      $self->addAffiliation($person,$func->{id_organ}, $roles_patcher->translate_static($func->{nazev_funkce}), $func->{od_o}, $func->{do_o}, $func->{nazev_funkce}, $translator->translate_static($func->{nazev_funkce}));
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
      $self->addAffiliation($person,$incl->{id_organ}, 'member', $incl->{od_o}, $incl->{do_o}, "Člen", "Member");
    }
  }
  $self->{listPerson}->{$person->id} = $person;
  return $person;
}

sub addAffiliation {
  my $self = shift;
  my ($person,$org_db_id,$role,$from,$to,$roleNameCZ,$roleNameEN) = @_;
  my $org = $self->{org_list}->addOrg($org_db_id);
  return unless $org;
  if(($org->{name_cz}//'') =~ /Poslanecká Sněmovna/ && ($role//'') eq 'member'){
    $roleNameCZ = ($person->{sex} eq 'F') ? "Poslankyně" : "Poslanec";
    $roleNameEN = "Member of Parliament";
  }
  $role=$patcher->translate_static($role);
  $role = listOrg::create_ID($role) if $role;
  $from =~ s/ /T/ if $from;
  $to =~ s/ /T/ if $to;
  $person->affiliate(
               ($merge_to_events && $self->{org_list}->isEvent($org))
                   ? (ref => '#'.$org->prefix(), ana => '#'.$org->id())
                   : (ref => '#'.$org->id()),
               role => $role,
               from => $from,
               to => $to,
               lang_cs => $roleNameCZ,
               lang_en => $roleNameEN
               );
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
  $self->{affiliation} = {};
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

sub addPhoto {
  my $self = shift;
  my ($url,$date) = @_;
  $self->{photo}->{$date} = $url;
}

sub getNewestPhoto {
  my $self = shift;
  my ($date) = sort {$b cmp $a} keys %{$self->{photo} // {} };
  return unless $date;
  return $self->{photo}->{$date};
}

sub addLink {
  my $self = shift;
  my ($link,$type) = (@_,'guest');
  return unless $link;
  $link = "https://$link" unless $link =~ m{https?://};
  $self->{idno}->{$type}->{$link} = 1;
}

sub affiliate {
  my $self = shift;
  my %opts = @_;
  my $aff = {};
  my $aff_key = join("\t",map {$opts{$_}//''} qw/from ref role lang_cs lang_en to/);
  $self->{affiliation}->{$aff_key} //= {};
  for $a (qw/ref role from to lang_cs lang_en/){
    $self->{affiliation}->{$aff_key}->{$a} = $opts{$a} if $opts{$a}
  }
  $self->{affiliation}->{$aff_key}->{ana} //= '';
  $self->{affiliation}->{$aff_key}->{ana} .= ' '.$opts{ana} if $opts{ana};
  $self->{affiliation}->{$aff_key}->{ana} =~ s/^ *//;
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
    # $sex->appendTextNode($self->{sex} eq 'M' ? 'mužské' : 'ženské');
    $sex->setAttribute('value',$self->{sex} eq 'M' ? 'M' : 'F') ;
  }
  for my $life_event (qw/birth death/) {
    if($self->{$life_event}){
      my $event = $pers->addNewChild( undef, $life_event);
      $event->setAttribute('when',$self->{$life_event}) ;
    }
  }
  # links
  my %subtypes = map {$_=>1} qw/facebook twitter personal/;
  for my $type (sort qw/psp gov senat guest/, keys %subtypes){
    if(defined $self->{idno}->{$type}){
      for my $link (sort keys %{$self->{idno}->{$type}}){
        my $idno = $pers->addNewChild( undef, 'idno');
        $idno->setAttribute('type','URI');
        $idno->setAttribute('subtype',$type) if defined $subtypes{$type};
        $idno->setAttribute('subtype','parliament') if $type eq 'psp';
        $idno->setAttribute('subtype','parliament') if $type eq 'senat';
        $idno->setAttribute('subtype','government') if $type eq 'gov';
        $idno->appendText($link);
      }
    }
  }
  my $photo = $self->getNewestPhoto();
  if(defined $photo) {
    my $figure = $pers->addNewChild( undef, 'figure');
    my $graphic = $figure->addNewChild( undef, 'graphic');
    $graphic->setAttribute('url',$photo);
  }
  # affiliations
  for my $pers_aff (map {$self->{affiliation}->{$_}} reverse sort keys %{$self->{affiliation} // {}}){
    my $aff = $pers->addNewChild( undef, 'affiliation');
    for my $a (qw/ref role from to/){
      $aff->setAttribute($a,$pers_aff->{$a}) if $pers_aff->{$a};
    }
    if ($pers_aff->{ana}){
      $aff->setAttribute('ana',
                          join(" ",
                               do {
                                  my %seen;
                                  grep {!$seen{$_}++} split(" ", $pers_aff->{ana})
                                }
                              )
                        )
    }
    for my $a (qw/lang_cs lang_en/){
      if($pers_aff->{$a}){
        my $roleName = $aff->addNewChild(undef,'roleName');
        $roleName->setAttributeNS($XMLNS,'lang',$a =~ m/lang_(.*)/);
        $roleName->appendText($pers_aff->{$a});
      }
    }
  }
}


###############################################################

package listOrg;
use Data::Dumper;


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
  $self->{org_prefix} = {}; # list of orgs by prefix
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
  if($merge_to_events){
      print STDERR "TOTAL PREF: ",scalar(keys %{$self->{org_prefix}}),"\n";

    for my $prefix (sort {sort_org($a,$b,$self->{org_prefix})} keys %{$self->{org_prefix}}){
      my @orgs = values %{$self->{org_prefix}->{$prefix}};
      print STDERR "SAVING $prefix: ",scalar(@orgs),"\n";
      if (@orgs == 1){
        for my $org (values %{$self->{org_prefix}->{$prefix}}){
          $org->addToXML($parent);
        }
      } else {
        listOrg::org->new_from_list($prefix,@orgs)->addToXML($parent);
      }
    }
  } else {
    for my $ch_id (keys %{$self->{child}}){
      $self->{child}->{$ch_id}->addToXML($parent);
    }
  }
}
sub sort_org {
  my ($a,$b,$l) = @_;
  my $a_role=listOrg::org::_oldest_text(map {[$_->{role},$_->{from}]} values %{$l->{$a}});
  my $b_role=listOrg::org::_oldest_text(map {[$_->{role},$_->{from}]} values %{$l->{$b}});
  return -1 if $a_role eq 'government' and !($b_role eq 'government');
  return 1 if !($a_role eq 'government') and $b_role eq 'government';
  return -1 if $a_role eq 'parliament' and !($b_role eq 'parliament');
  return 1 if !($a_role eq 'parliament') and $b_role eq 'parliament';
  if($a_role eq $b_role){
    return (listOrg::org::_oldest_text(map {[$_->{from},$_->{from}]} values %{$l->{$a}}) cmp listOrg::org::_oldest_text(map {[$_->{from},$_->{from}]} values %{$l->{$b}}))
          ||
          ($a cmp $b);
  }
  return $a cmp $b;
}
sub isEvent {
  my $self = shift;
  my $org = shift;
  return (scalar(keys %{$self->{org_prefix}->{$org->prefix()}}) > 1)
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
  my $prefix = shift;
  my $identicalDistance = shift//0;
  $self->{tmp_prefix} = {} if $identicalDistance == 0;
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
      return undef if $skip_orgs{$orgrow->{name_cz}};
      my $role = $self->getRole($orgrow->{type});
      my $parent;
      $parent = $self->addOrg($orgrow->{parent}) unless $flat;
      $orgrow->{name_en} ||= $self->{translator}->translate_static($orgrow->{name_cz});
      $orgrow->{name_en} = $self->{patcher}->translate_static($orgrow->{name_en});
      my $org = listOrg::org->new(%$orgrow, prefix=>$prefix, abbr_sd => create_ID($orgrow->{abbr},keep_case => 1, keep_dash => 1), role => $role,  $parent ? (parent_org_id => $parent->id()):() );
      $self->{org}->{$dbid} = $org;
      if($merge_to_events){# add all organizations with same prefix
        $self->addIdenticalOrgs($dbid, $org->prefix(),$identicalDistance+1);

        $self->{tmp_prefix}->{$dbid} = $org;
        if($identicalDistance == 0){
          if(defined $self->{org_prefix}->{$org->prefix()}){
            new_prefixes($self->{org_prefix},values %{$self->{tmp_prefix}});
          }
          print STDERR "ADDING NEW PREFIX:",$org->prefix(),"\n";

          $self->{org_prefix}->{$org->prefix()} = $self->{tmp_prefix};
          $self->{tmp_prefix} = {};
        }
      }
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

sub addIdenticalOrgs{
  my $self = shift;
  my $dbid = shift;
  my $prefix = shift;
  my $identicalDistance = shift;
  return unless $dbid;
  my $sth = $pspdb->prepare(sprintf(
         'SELECT
            org.id_organ AS id_organ,
            org.nazev_organu_cz as name_cz,
            org.nazev_organu_en as name_en,
            org.zkratka as abbr,
            org.od_organ AS `from`,
            org.do_organ AS `to`,
            org_ref.nazev_organu_cz as name_cz_ref,
            org_ref.nazev_organu_en as name_en_ref,
            org_ref.zkratka as abbr_ref,
            org_ref.od_organ AS `from_ref`,
            org_ref.do_organ AS `to_ref`
          FROM organy AS org
          JOIN organy AS org_ref
            ON
             (
               org.zkratka = org_ref.zkratka
               OR org.nazev_organu_cz = org_ref.nazev_organu_cz
               OR org.nazev_organu_en = org_ref.nazev_organu_en
              )
              -- this is not working:
              -- AND org.id_typ_org = org_ref.id_typ_org -- labels need to be compared
          JOIN typ_organu AS type
            ON org.id_typ_org = type.id_typ_org
          JOIN typ_organu AS type_ref
            ON org_ref.id_typ_org = type_ref.id_typ_org
          WHERE
            org_ref.id_organ=%s
            AND org_ref.id_organ != org.id_organ
            --AND max(org.od_organ, org_ref.od_organ)
            --    >=
            --    min( COALESCE(org.do_organ,"1000-01-01"), COALESCE(org_ref.do_organ,"9999-12-12" ))
            AND (
                  type.nazev_typ_org_cz = type_ref.nazev_typ_org_cz
                  OR
                  type.nazev_typ_org_en = type_ref.nazev_typ_org_en
                )
          ',$dbid));
  $sth->execute;

  while(my $orgrow = $sth->fetchrow_hashref){
    $orgrow->{name_en} //= $self->{patcher}->translate_static($orgrow->{name_cz});
    $orgrow->{name_en_ref} //= $self->{patcher}->translate_static($orgrow->{name_cz_ref});
    $orgrow->{name_en} = $self->{patcher}->translate_static($orgrow->{name_en});
    $orgrow->{name_en_ref} = $self->{patcher}->translate_static($orgrow->{name_en_ref});
    my %identityLevel = map
                        {$_ => _compare($orgrow->{$_}, $orgrow->{$_.'_ref'})}
                        qw/abbr name_cz name_en/;
    my $identityLevelSum = List::Util::sum(values %identityLevel);

    next unless $identityLevelSum >= 1.5;
    next if defined $self->{org}->{$orgrow->{id_organ}};

    $self->addOrg($orgrow->{id_organ}, $prefix, $identicalDistance+1);
  }
}

sub _compare {
  my ($a,$b) = map {s/^\s*//;s/\s*$//;s/\s\s/ /g;lc $_} @_;

  return 0 unless $a;
  return 0 unless $b;
  return 1 if $a eq $b;
  return 0.6 if index($a,$b) == 0;
  return 0.6 if index($b,$a) == 0;
  return 0.5 if index($a,$b) != -1;
  return 0.5 if index($b,$a) != -1;
  my $acnt=_word_freq($a);
  my $bcnt=_word_freq($b);
  my $avg = (List::Util::sum(values %$acnt) + List::Util::sum(values %$bcnt)) / 2;
  my $common_percent = List::Util::sum(map {List::Util::min($acnt->{$_},$bcnt->{$_}||0)} keys %$acnt) / $avg;

  return $common_percent;
}

sub _word_freq {
  my $str=shift // '';
  my $cnt={};
  for my $w (split(" ",$str)){
    next if defined $comparison_ignore_words{$w};
    $cnt->{$w}//=0;
    $cnt->{$w}++;
  }
  return $cnt;
}



sub new_prefixes{
  my $seen = shift;
  my @orgs = @_;
  my $name_en = listOrg::org::_newest_text(map {[$_->{name_en},$_->{from}]} @orgs);
  my ($prefix) = listOrg::org::_newest_text(map {[$_->{id},$_->{from}]} @orgs) =~ m/^([^\.]*)\..*?$/;
  $prefix .= ".".create_ID($name_en);
  while(defined $seen->{$prefix}){
    $prefix =~ s/(_?I*)$/$1I/;
  }
  for my $o (@orgs){
    $o->fix_prefix($prefix);
  }
}

package listOrg::org;

sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my %opts = @_;
  my $self  = { map { $_ => $opts{$_} } qw/abbr name_cz name_en from to role abbr_sd id_organ prefix/ };
  bless $self, $class;
  $self->{iddb} = {
    id => $opts{id_organ},
    parent => $opts{parent},
    type => $opts{type}
  };
  $self->buildID();

  $self->{role} = $roles_patcher->translate_static($self->{role}) if $self->{role};

  my $prefix = $self->{id};
  $prefix =~ s/\.[0-9]*$//;
  $prefix =~ s/[0-9]*$// if $self->{role} eq 'parliament';
  $self->{prefix} = $prefix unless $self->{prefix};

  $self->annotate($org_annotator->translate_static(join('@',$self->{id},$self->{name_cz},$self->{name_en})));
  $self->{child} = {};
  $self->{events} = {};
  print STDERR "ORG:",$self->id(),"(".$self->{ana}.")\t",$self->{name_cz},"\t",$self->prefix(),"\n";
  return $self;
}

sub new_from_list{
  my $this  = shift;
  my $class = ref($this) || $this;
  my $prefix = shift;
  my @orgs = @_;
  my $abbr = _newest_text(map {[$_->{abbr},$_->{from}]} @orgs);
  #($prefix) = _newest_text(map {[$_->{id},$_->{from}]} @orgs) =~ m/^(.*)\..*?$/;

  my $role = $orgs[0]->{role};
  $abbr =~ s/[0-9]*$// if $role eq 'parliament';
  #$prefix =~ s/[0-9]*$// if $role eq 'parliament';
  my $self  = $class->new(
                         abbr => $abbr,
                         abbr_sd => $orgs[0]->{abbr_sd},
                         role => $role,
                         name_cz => _newest_text(map {[$_->{name_cz},$_->{from}]} @orgs),
                         name_en => _newest_text(map {[$_->{name_en},$_->{from}]} @orgs),
                      );
  $self->{id} = $prefix;
  bless $self, $class;
  $self->annotate($org_annotator->translate_static(join('@',$self->{id},$self->{name_cz},$self->{name_en})));
  for my $org (@orgs){
    $self->{events} //= {};
    $self->{events}->{$org->id()} = event->new(org=>$org);
  }

  return $self
}

sub annotate {
  my $self = shift;
  my $ana = shift;
  $self->{ana} //= '';
  $self->{ana} .= ' '.$ana if $ana;
  $self->{ana} =~ s/^ *//;
}

sub _newest_text{
  return [reverse grep {$_} map {$_->[0]} sort { $a->[1] cmp $b->[1] } @_]->[0]
}
sub _oldest_text{
  return [grep {$_} map {$_->[0]} sort { $a->[1] cmp $b->[1] } @_]->[0]
}

sub buildID {
  my $self = shift;
  my @parts;
  push @parts, $self->{role} if $self->{role};
  push @parts, $self->{abbr_sd};
  unless(defined $uniqueOrgRoles{$self->{role} // ''}){
    push @parts, $self->{id_organ} if defined $self->{id_organ};
  }
  $self->{id} = join('.', @parts);
}

sub id {
  return shift->{id}
}

sub role {
  return shift->{role}
}

sub prefix {
  return shift->{prefix}
}

sub fix_prefix {
  my $self = shift;
  my $pref = shift;
  $self->{prefix} = $pref if $pref;
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
  if ($self->{ana}){
    $org->setAttribute('ana',
                        join(" ",
                             do {
                                my %seen;
                                grep {!$seen{$_}++} split(" ", $self->{ana})
                              }
                            )
                      )
  }
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
  $name->setAttribute('full', 'abb');
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
  if(%{$self->{events}}) {
    my $list = $org->addNewChild( undef, 'listEvent');
    for my $ch_id (sort {($self->{events}->{$a}->{from} cmp $self->{events}->{$b}->{from})||($self->{events}->{$a}->{to} cmp $self->{events}->{$b}->{to})} keys %{$self->{events}}){
      $self->{events}->{$ch_id}->addToXML($list);
    }
  }
}


package event;

sub new {
  my $this  = shift;
  my $class = ref($this) || $this;
  my %opts = @_;
  my $org = $opts{org};
  my $self  = { map { $_ => $opts{$_} } qw/abbr name_cz name_en from to role abbr_sd id_organ/ };
  $self->{id} = $org->id();
  $self->{from} = $org->{from} if $org->{from};
  $self->{to} = $org->{to} if $org->{to};
  $self->{label} = {};
  for my $n ([qw/name_cz cs/],[qw/name_en en/])  {
    if(defined $org->{$n->[0]}) {
      $self->{label}->{$n->[1]} = sprintf("%s (%s - %s)",$org->{$n->[0]}, $self->{from}//'', $self->{to}//'')
    }
  }
  bless $self, $class;

  return $self;
}

sub id {
  return shift->{id}
}

sub addToXML {
  my $self = shift;
  my $parent = shift;
  return unless $parent;
  my $XMLNS='http://www.w3.org/XML/1998/namespace';
  my $event = $parent->addNewChild( undef, 'event');
  $event->setAttributeNS($XMLNS, 'id', $self->id);
  for my $dt (qw/from to/) {
    if(defined $self->{$dt}){
      $event->setAttribute($dt,$self->{$dt});
    }
  }

  for my $lang (sort keys %{$self->{label}})  {
    my $label = $event->addNewChild(undef,'label');
    $label->appendText($self->{label}->{$lang});
    $label->setAttributeNS($XMLNS, 'lang', $lang);
  }
}