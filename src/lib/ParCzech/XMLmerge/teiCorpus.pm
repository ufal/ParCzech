package ParCzech::XMLmerge::teiCorpus;

use warnings;
use strict;
use utf8;
use File::Spec;
use File::Copy;
use XML::LibXML qw(:libxml);

my $XMLNS = 'http://www.w3.org/XML/1998/namespace';

sub compare_attribute_n { # compare
  my ($path,@nodes) = @_;
  for my $i (0, 1){
    return unless $nodes[$i]->nodeType == XML_ELEMENT_NODE;
    return unless $nodes[$i]->hasAttribute('n');
  }
  return unless $nodes[0]->nodeName eq $nodes[1]->nodeName;
  return $nodes[0]->getAttribute('n') cmp $nodes[1]->getAttribute('n');
}

sub compare_affiliation { # compare
  my ($path,@nodes) = @_;
  return unless $path =~ m/\/person\/$/;
  for my $i (0, 1){
    return unless $nodes[$i]->nodeType == XML_ELEMENT_NODE;
    return unless $nodes[$i]->nodeName eq 'affiliation';
  }
  #print STDERR "compare_affiliation: ",join("\t",@nodes),"\n";
  for my $a (qw/ref role from to/){
    my @v = map {$_->getAttribute($a)//''} @nodes;
    my $cmp = $v[0] cmp $v[1];
    return $cmp if $cmp;
  }
  return;
}

sub compare_idno { # compare
  my ($path,@nodes) = @_;
  for my $i (0, 1){
    return unless $nodes[$i]->nodeType == XML_ELEMENT_NODE;
    return unless $nodes[$i]->nodeName eq 'idno';
  }
  my @v = map {$_->textContent()} @nodes;
  return $v[0] cmp $v[1];
}

sub merge_intervals_date {
  my ($path,@nodes) = @_;
  return unless
         $path =~ m/\/settingDesc\/setting\/date\//
      || $path =~ m/\/sourceDesc\/bibl\/date\//;
  my ($from,$to);
  my ($from_text,$to_text);

  for my $i (0, 1){
    for my $a (qw/from when to/) {
      if($nodes[$i]->hasAttribute($a)){
        $from = $nodes[$i]->getAttribute($a) unless defined $from;
        $to = $nodes[$i]->getAttribute($a) unless defined $to;
        if(($from cmp $nodes[$i]->getAttribute($a)) >= 0){
          $from = $nodes[$i]->getAttribute($a);
          ($from_text) = ($nodes[$i]->textContent()) =~ m/^\s*(.*)\s*(?: - )?/;
        }
        $to = $nodes[$i]->getAttribute($a) if ($to cmp $nodes[$i]->getAttribute($a)) <= 0;
        ($to_text) = ($nodes[$i]->textContent()) =~ m/(?: - )?\s*(.*)\s*$/;
      }
    }
  }
  $nodes[0]->removeAttribute($_) for (qw/from when to/);
  $nodes[0]->removeChildNodes();
  if($from eq $to) {
    $nodes[0]->setAttribute('when', $from);
    $nodes[0]->appendText($from);
  } else {
    $nodes[0]->setAttribute('from', $from);
    $nodes[0]->setAttribute('to', $to);
    $nodes[0]->appendText($from_text
                    . ' - '
                    . $to_text);
  }
  print STDERR "merging date: $path\t$nodes[0]\n";

  return 1;
}

sub merge_tagsDecl_namespace_tagUsage {
  my ($path,@nodes) = @_;
  return unless $path =~ m/\/tagsDecl\/namespace\/tagUsage\//;
  return unless $nodes[0]->getAttribute('gi') eq $nodes[1]->getAttribute('gi');

  my $sum = 0;
  $sum += $nodes[$_]->getAttribute('occurs')//0 for (0,1);
  $nodes[0]->setAttribute('occurs', $sum);
  return 1;
}


sub merge_bibl_idno {
  my ($path,@nodes) = @_;
  return unless $path =~ m/\/sourceDesc\/bibl\/idno\//;
  my @uri;
  push @uri, $nodes[$_]->textContent() for (0,1);
  my $i=0;
  while(    $i < length($uri[1])
         && $i < length($uri[0])
         && substr($uri[1], $i, 1) eq substr($uri[0], $i, 1)){
    $i++;
  }
  if ($i < length($uri[0]) || $i < length($uri[0])) {
    $uri[0] = substr($uri[0], 0, $i);
    $uri[0] =~ s/[^\/]*$//;
  }
  $nodes[0]->removeChildNodes();
  $nodes[0]->appendText($uri[0]);

  return 1;
}


sub add_settings_to_merger {
  my $merger = shift;

  $merger->add_comparator(
                    terminate => 1,
                    func => \&compare_attribute_n
                    );

  $merger->add_merger(\&merge_intervals_date);
  $merger->add_merger(\&merge_tagsDecl_namespace_tagUsage);
  $merger->add_merger(\&merge_bibl_idno);
  $merger->add_comparator(
                    func => \&compare_affiliation,
                    );
  $merger->add_comparator(
                    terminate => 1,
                    func => \&compare_idno,
                    );
  return $merger
}


1;