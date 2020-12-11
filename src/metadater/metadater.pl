use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use XML::LibXML qw(:libxml);
use Getopt::Long;
use File::Basename;
use File::Spec;


use ParCzech::PipeLine::FileManager;

my $scriptname = $0;
my $dirname = dirname($scriptname);

my $metadata_file = File::Spec->catfile($dirname,'tei_parczech.xml');

my ($debug, $test, $metadata_name);

my $xpc = ParCzech::PipeLine::FileManager::TeiFile::new_XPathContext();


GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # do not change the database
            'metadata-file=s' => \$metadata_file, #
            'metadata-name=s' => \$metadata_name, #
            ParCzech::PipeLine::FileManager::opts()
            );

usage_exit() unless ParCzech::PipeLine::FileManager::process_opts();

usage_exit() unless $metadata_file and $metadata_name;

my $current_file;

while($current_file = ParCzech::PipeLine::FileManager::next_file('tei', xpc => $xpc)) {
  next unless defined($current_file->{dom});

  $current_file->add_static_data($metadata_name, $metadata_file);

  if($test) {
    $current_file->print();
  } else {
    $current_file->save();
  }
}


sub usage_exit {
   my ($fm_args,$fm_desc) =  @{ParCzech::PipeLine::FileManager::usage('tei')};
   print
"Usage: metadater.pl  $fm_args --metadata-file <STRING> --metadata-name <STRING> [--test]

$fm_desc

\t--metadata-file=s\txml file containing metadata
\t--metadata-name=s\tname of metadata (/ParCzech/meta/\@name)
\t--test\tprint result to stdout - don't change any file
";
   exit;
}
