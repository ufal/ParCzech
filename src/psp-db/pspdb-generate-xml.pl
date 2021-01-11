use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use Getopt::Long;
use File::Spec;
use DateTime::Format::Strptime;
use ParCzech::PipeLine::FileManager;
use DBI;
use Data::Dumper;




my ($debug, $personlist_in, $outdir, $indbdir);

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


my $strp = DateTime::Format::Strptime->new(
  pattern   => '%d.%m.%Y',
  locale    => 'cs_CZ',
  time_zone => 'Europe/Prague'
);

my %cast = (
  date => sub {my $d = shift; return $d ? join('-', reverse(split('\.',$d))) : ''}
);



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
    }
  }
);


GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'person-list=s' => \$personlist_in,
            'output-dir=s' => \$outdir,
            'input-db-dir=s' => \$indbdir
            );



usage_exit() unless $indbdir;
usage_exit() unless $personlist_in;
usage_exit() unless $outdir;

my %dbfile_structure = (
  map {($_ => File::Spec->catfile($indbdir,'poslanci',"$_.unl"))} keys %{$tabledef{poslanci}}
);



for my $k (keys %dbfile_structure) {
  usage_exit("file $dbfile_structure{$k} is expected in $indbdir") unless -s $dbfile_structure{$k};
}

my $db_file = File::Spec->catfile($outdir,'psp.db');

my $use_existing_db=( -s $db_file );

my $pspdb = DBI->connect("dbi:SQLite:dbname=${db_file}", "", "", { sqlite_unicode => 1 });


if($use_existing_db) {
  print STDERR "using existing database $db_file\n";
} else {
  # loading database from dumps
  create_table($tabledef{poslanci}->{osoby},'osoby');
  fill_table($tabledef{poslanci}->{osoby},'osoby');
}


my $personlist = ParCzech::PipeLine::FileManager::XML::open_xml($personlist_in);

usage_exit() unless $personlist;

my $xpc = ParCzech::PipeLine::FileManager::TeiFile::new_XPathContext();

for my $person ($xpc->findnodes('//tei:person',$personlist->{dom})) {
  my $id = $person->getAttributeNS($xpc->lookupNs('xml'),'id');
  if($id =~ m/-[0-9]+$/) {
    print STDERR "skipping enriching $id:\n$person\n";
  } elsif($id =~ m/([0-9]+)$/) {
    my $id_osoba = $1;
    my $sth = $pspdb->prepare(sprintf('SELECT * FROM osoby WHERE id_osoba=%s',$id_osoba));
    $sth->execute;
    if(my $row = $sth->fetchrow_hashref){
      my ($pname) = $person->getChildrenByTagName('persName');
      if($pname){
        $pname->removeChildNodes();
        $pname->appendTextChild('surname',$row->{prijmeni});
        $pname->appendTextChild('forename',$row->{jmeno});
      }
      if($row->{pohlavi}){
        my $sex = $person->addNewChild( undef, 'sex');
        $sex->appendTextNode($row->{pohlavi} eq 'M' ? 'mužské' : 'ženské');
        $sex->setAttribute('value',$row->{pohlavi} eq 'M' ? 'M' : 'F') ;
      }

    }
  } else {
    print STDERR "invalid id $id:\n$person\n";
  }
}

ParCzech::PipeLine::FileManager::XML::save_to_file($personlist->{dom}, File::Spec->catfile($outdir,'person.xml'));







sub create_table {
  my $tabledef = shift;
  my $tablename = shift;
  my $dbstring = sprintf('CREATE TABLE %s (%s)',
                         $tablename,
                         join(", ", map {sprintf("%s %s", $_->{name}, $_->{type})} @{$tabledef->{def}} ));
  print STDERR "$dbstring\n" if $debug;
  $pspdb->do($dbstring);
  for my $idx (@{$tabledef->{index}//[]}) {
    my ($f,$un) = split('\|',"$idx|");
    $dbstring =sprintf("CREATE %s INDEX i_%s_%s ON %s (%s)",$un,$tablename,$f,$tablename,$f);
    print STDERR "$dbstring\n" if $debug;
    $pspdb->do($dbstring);
  }
}

sub fill_table {
  my $tabledef = shift;
  my $tablename = shift;
  open(my $fh,'<:encoding(Windows-1250)',  $dbfile_structure{$tablename}) or die "Cannot open:$!\n";
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
      if($fields[$i]){
        push @dbname, $name;
        push @dbval,($tabledef->{def}->[$i]->{type} eq 'INTEGER') ? $fields[$i] : "'$fields[$i]'";
      }
    }
    my $dbstring = sprintf("INSERT INTO %s (%s) VALUES (%s)", $tablename, join(',',@dbname),join(',',@dbval));
    print STDERR "$dbstring\n" if $debug;
    $pspdb->do($dbstring);
  }
}

sub usage_exit {
  my $pref = shift // '';
  print
"$pref

Usage: pspdb-generate-xml.pl  --person-list <STRING> --output-dir <STRING> --input-db-dir <STRING> [--debug]

\t--person-list=s\tfile containing list of persons that should be enriched and linked
\t--output-dir=s\tfolder where will be result stored (person.xml, org.xml) and database file psp.db
\t--input-db-dir=s\tdirectory with downloaded and unpacked database dump files
";
   exit;
}