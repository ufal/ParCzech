use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use XML::LibXML qw(:libxml);
use Getopt::Long;
use File::Basename;
use File::Spec;


use ParCzech::PipeLine::FileManager "metadater";

my $scriptname = $0;
my $dirname = dirname($scriptname);

my $metadata_file = File::Spec->catfile($dirname,'tei_parczech.xml');

my ($debug, $test, $metadata_name, $vars,$rename, $vars_logfile);
my %variables = ();

my $xpc = ParCzech::PipeLine::FileManager::TeiFile::new_XPathContext();


GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # do not change the database
            'metadata-file=s' => \$metadata_file, #
            'metadata-name=s' => \$metadata_name, #
            'variables=s'     => \$vars,
            'rename=s'        => \$rename,
            'variables-log=s' => \$vars_logfile,
            ParCzech::PipeLine::FileManager::opts()
            );

usage_exit() unless ParCzech::PipeLine::FileManager::process_opts();

usage_exit() unless $metadata_file and $metadata_name;

my $current_file;

if($vars) {
  for my $record (split('\|', $vars)) {
    my ($key,$val) = $record =~ m/^(XPATH:..*?:XPATH)=(.*)$/;
    unless (defined $key) {
      ($key,$val) = $record =~ m/^(..*?)=(.*)$/;
    }
    if($key) {
      if($val =~ m/\[\[|\]\]|[<>]/) {
        print STDERR "not safe value $val\n";
        usage_exit();
      }
      $variables{$key}=$val;
    } else {
      print STDERR "wrong variables format '$vars', record '$record'\n";
      usage_exit();
    }
  }
}
my @used_vars;

while($current_file = ParCzech::PipeLine::FileManager::next_file('tei', xpc => $xpc)) {
  next unless defined($current_file->{dom});
  $current_file->add_static_data($metadata_name, $metadata_file, %variables);

  if($test) {
    $current_file->print();
  } else {
    $current_file->rename(split('\|',$rename)) if $rename;
    my $result = $current_file->save();
    push @used_vars,$_ for (@{ $result // [] });
  }
}

if($vars_logfile){
  local $/;
  my $dir = dirname($vars_logfile);
  File::Path::mkpath($dir) unless -d $dir;
  open FILE, ">$vars_logfile";
  binmode FILE;
  my %cumulative;
  for my $v (@used_vars) {
    print FILE "$v->[0]|$v->[1]=$v->[2]\n";
    $cumulative{$v->[1]} = ($cumulative{$v->[1]} // 0) + $v->[2] if $v->[1] =~ m/^ELEMCNT:|XPATH:count/;
  }
  for my $var (keys %cumulative) {
    print FILE "AGGREGATED|$var=$cumulative{$var}\n";
  }
  close FILE;
}

sub usage_exit {
   my ($fm_args,$fm_desc) =  @{ParCzech::PipeLine::FileManager::usage('tei')};
   print
"Usage: metadater.pl  $fm_args --metadata-file <STRING> --metadata-name <STRING> [--test]

$fm_desc

\t--metadata-file=s\txml file containing metadata
\t--metadata-name=s\tname of metadata (/ParCzech/meta/\@name)
\t--test\tprint result to stdout - don't change any file
\t--variables\tpipe '|' separated list of assignments to variables in metadata-file \"TODAY=2021-01-05#EDITION=2.0\"
\t           \tYou can use special variable for counting elements
\t           \t(ie [[ELEMCNT:u]] for counting). If it is not set in param,
\t           \tvalue (ie count(//u)) is used for each file
\t--rename=s\tpipe '|' separated renamming regex. ie \".xml\$|.ana.xml\" will add interfix '.ana'
\t--variables-log=s\tlist of files and variables with values in format: filepath|variable=value
";
   exit;
}
