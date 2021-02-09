use warnings;
use strict;
use open qw(:std :utf8);
use utf8;
use XML::LibXML qw(:libxml);
use Getopt::Long;
use File::Basename;
use File::Spec;


use ParCzech::PipeLine::FileManager;
use ParCzech::NoteClassifier;

my $scriptname = $0;
my $dirname = dirname($scriptname);

my $metadata_file = File::Spec->catfile($dirname,'tei_parczech.xml');

my ($debug, $test, $metadata_name, $vars,$rename, $vars_logfile);
my %variables = ();

my $xpc = ParCzech::PipeLine::FileManager::TeiFile::new_XPathContext();


GetOptions ( ## Command line options
            'debug' => \$debug, # debugging mode
            'test' => \$test, # do not change the database
            ParCzech::PipeLine::FileManager::opts()
            );

usage_exit() unless ParCzech::PipeLine::FileManager::process_opts();

my $current_file;
my $classifier = ParCzech::NoteClassifier->new();

while($current_file = ParCzech::PipeLine::FileManager::next_file('tei', xpc => $xpc)) {
  next unless defined($current_file->{dom});
  my ($text) = $xpc->findnodes('/tei:TEI/tei:text/tei:body',$current_file->get_doc());
  for my $note ($xpc->findnodes('.//tei:note[@type="comment"]',$text)) {
    my $notetext = $note->textContent;
    my $class = $classifier->classify($notetext);
    if(defined $class){
      $note->setNodeName($class->[0]);
      $note->removeAttribute('type');
      $note->setAttribute($class->[1],$class->[2]);
      $note->removeChildNodes();
      $note->appendTextChild('desc', $notetext);
    }
  }

  if($test) {
    $current_file->print();
  } else {
    my $result = $current_file->save();
  }
}

sub usage_exit {
   my ($fm_args,$fm_desc) =  @{ParCzech::PipeLine::FileManager::usage('tei')};
   print
"Usage: incidents.pl  $fm_args [--test]

$fm_desc

\t--test\tprint result to stdout - don't change any file
";
   exit;
}
