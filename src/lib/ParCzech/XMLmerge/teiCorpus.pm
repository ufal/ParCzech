package ParCzech::XMLmerge::teiCorpus;

use warnings;
use strict;
use utf8;
use File::Spec;
use File::Copy;
use XML::LibXML qw(:libxml);
use Data::Dumper;


my $XMLNS = 'http://www.w3.org/XML/1998/namespace';
my %config = (
      # parent => {
      #   node_names => {
      #     first => [first, second]
      #     unknown sort alphabetically
      #     last => [penultimate,ultimate]
      #   },
      #   attributes => {
      #     node_name => [unique-mandatory-attributes]
      #   },
      #   text => [node_name...] # if everythink else fails(is equal) compare texts, if different, sort...
      # }
      org => {
        node_names => {
          first => [qw/orgName event listEvent/],
        },
        attributes => {
          orgName => [qw/full=yes full=init lang=cs lang=en/]
        }
      },
      person => {
        node_names => {
          first => [qw/persName sex birth death idno figure/],
          last => [qw/affiliation/]
        },
        attributes => {
          idno => [qw/type=URI/]
        },
        text => [qw/idno/]
      },
      titleStmt => {
        node_names => {
          first => [qw/title meeting respStmt funder/],
        },
        attributes => {
          title => [qw/type=main type=sub lang=cs lang=en/]
        }
      },
      bibl => {
        node_names => {
          first => [qw/title idno date/],
        },
        attributes => {
          title => [qw/type=main type=sub lang=cs lang=en/]
        }
      },

    );

my %config_ord = (
    map {
      my $parent = $_;
      $parent => {
        node_names => {
          first => array_to_index($config{$parent}->{node_names}->{first}),
          last  => array_to_index($config{$parent}->{node_names}->{last})
        },
        attributes => {
          map {
            $_ => array_to_index($config{$parent}->{attributes}->{$_})
          } keys %{$config{$parent}->{attributes}//{}}
        },
        text => {
          map {
            $_ => 1
          } @{$config{$parent}->{text}//[]}
        },
      }
    } keys %config
  );

sub array_to_index {
  my @arr = @{shift//[]};
  my %hash;
  @hash{@arr} = 0..$#arr;
  return {%hash};
}

sub compare_node_names {
  my ($path,@nodes) = @_;
  my ($parent) = $path =~ m/([^\/]*)\/$/;
  return unless defined $config_ord{$parent};
  for my $i (0, 1){
    return unless $nodes[$i]->nodeType == XML_ELEMENT_NODE;
  }
  my $cmp;
  unless ($nodes[0]->nodeName eq $nodes[1]->nodeName) {
    $cmp = compare_idx($config_ord{$parent}->{node_names}->{first},1000,map {$_->nodeName} @nodes);
    return $cmp if $cmp;
    $cmp = compare_idx($config_ord{$parent}->{node_names}->{last},-1000,map {$_->nodeName} @nodes);
    return $cmp if $cmp;
    return $nodes[0]->nodeName cmp $nodes[1]->nodeName
  }

  my ($a,$b) = map {
      my $n=$_;
      [sort map {
          my ($a,$v)=($_,$n->{$_});
          $a=~s/^.*}//;
          $config_ord{$parent}->{attributes}->{$n->nodeName}->{"$a=$v"}//1000
          } keys %$n]
      } map {$nodes[$_]} (0,1);

  my $i=0;
  while($i < scalar(@$a)
    && $i < scalar(@$b)
    && $a->[$i] == $b->[$i]){
    $i++
  }
  $cmp = ($a->[$i]//1000) <=> ($b->[$i]//1000);
  return $cmp if $cmp;
  if(defined $config_ord{$parent}->{text}->{$nodes[0]->nodeName}){
    return $nodes[0]->textContent cmp $nodes[1]->textContent;
  }

  return 0;
}

sub compare_idx {
  my ($conf,$def,$a,$b) = @_;
  return ($conf->{$a}//$def) <=> ($conf->{$b}//$def);
}

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
  for my $a (qw/ref role from/){
    my @v = map {$_->getAttribute($a)//''} @nodes;
    my $cmp = $v[0] cmp $v[1];
    return $cmp if $cmp;
  }
  return 0;
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

sub compare_include { # compare
  my ($path,@nodes) = @_;
  for my $i (0, 1){
    return unless $nodes[$i]->nodeType == XML_ELEMENT_NODE;
    return unless $nodes[$i]->nodeName =~ m/^(.*:)?include$/;
  }
  my @v = map {$_->getAttribute('href')} @nodes;
  print STDERR "COMPARING INCLUDE: $v[0] (",($v[0] cmp $v[1]),") $v[1]\n";
  return $v[0] eq $v[1] ? 0 : -1; # return 0 if equal, else keep order (-1)
}

sub merge_intervals_date {
  my ($path,$config,@nodes) = @_;
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
          ($from_text) = ($nodes[$i]->textContent()) =~ m/^\s*([^-]*)\s*(?: - )?[^-]*?$/;
        }
        if(($to cmp $nodes[$i]->getAttribute($a)) <= 0){
          $to = $nodes[$i]->getAttribute($a);
          ($to_text) = ($nodes[$i]->textContent()) =~ m/^[^-]*?(?: - )?\s*([^-]*)\s*$/;
        }
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
    print STDERR "FROM: '$from_text'\nTO:   '$to_text'\n";
    $nodes[0]->appendText($from_text
                    . ' - '
                    . $to_text);
  }
  print STDERR "merging date: $path\t$nodes[0]\n";

  return 1;
}

sub merge_tagsDecl_namespace_tagUsage {
  my ($path,$config,@nodes) = @_;
  return unless $path =~ m/\/tagsDecl\/namespace\/tagUsage\//;
  return unless $nodes[0]->getAttribute('gi') eq $nodes[1]->getAttribute('gi');

  my $sum = 0;
  $sum += $nodes[$_]->getAttribute('occurs')//0 for (0,1);
  $nodes[0]->setAttribute('occurs', $sum);
  return 1;
}

sub merge_extent_measure {
  my ($path,$config,@nodes) = @_;
  return unless $path =~ m/\/extent\/measure\//;
  return unless $nodes[0]->getAttribute('unit') eq $nodes[1]->getAttribute('unit');
  return unless $nodes[0]->getAttributeNS($XMLNS,'lang') eq $nodes[1]->getAttributeNS($XMLNS,'lang');

  my $sum = 0;
  $sum += $nodes[$_]->getAttribute('quantity')//0 for (0,1);
  my $text = $nodes[0]->textContent();
  $nodes[0]->removeChildNodes;
  $text =~ s/\s*[0-9]* /$sum /;
  $nodes[0]->appendText($text);
  $nodes[0]->setAttribute('quantity', $sum);

  return 1;
}

sub merge_include {
  my ($path,$config,@nodes) = @_;
  return unless $path =~ m/include\//;
  my $file_path = $nodes[0]->getAttribute('href');
  my $old_file_path = "$config->{base}/$file_path$config->{backup_suff}";
  print STDERR "updating measures for $file_path\n";
  # newly added data are counted - measures of removed files should be added(removed):
  my $xml = ParCzech::PipeLine::FileManager::XML::open_xml("$old_file_path");
  if ($xml) {
    for my $pattern ({elem=>'tagUsage', compare=>'gi', value=>'occurs'},{elem=>'measure', compare=>'unit', value=>'quantity', text=>1}){
      my %seen_pair;
      my $xpath = '//*[local-name(.) = "'.$pattern->{elem}.'" and @'.$pattern->{compare}.' and @'.$pattern->{value}.']';
      for my $old_node ($xml->{dom}->findnodes($xpath)){
        my $comp = $old_node->getAttribute($pattern->{compare});
        next if defined $seen_pair{$old_node->nodeName.' '.$comp};
        $seen_pair{$old_node->nodeName.' '.$comp} = 1;
        my $decrement_val = $old_node->getAttribute($pattern->{value});
        for my $node ($config->{doc}->findnodes($xpath.'[ @'.$pattern->{compare}.' = "'.$comp.'"]')){
          my $old_val = $node->getAttribute($pattern->{value});
          my $new_val = $old_val - $decrement_val;
          $node->setAttribute($pattern->{value}, $new_val);
          print STDERR "\t//",$node->nodeName,"/@",$pattern->{compare}," = '$comp'\t$new_val = $old_val - $decrement_val\n";
          if(defined $pattern->{text}){
            my $text = $node->textContent;
            print STDERR "pattern not found in $node" unless $text =~ s/$old_val/$new_val/;
            $node->removeChildNodes();
            $node->appendText($text);
          }
        }

      }
    }

  } else {
    print STDERR "File does not exist or is not xml: $old_file_path\n";
  }

  return 1;
}

sub merge_bibl_idno {
  my ($path,$config,@nodes) = @_;
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
  $merger->add_merger(\&merge_extent_measure);
  $merger->add_merger(\&merge_include);
  $merger->add_comparator(
                    func => \&compare_affiliation,
                    );
  $merger->add_comparator(
                    terminate => 1,
                    func => \&compare_node_names,
                    );
  $merger->add_comparator(
                    terminate => 1,
                    func => \&compare_idno,
                    );
  $merger->add_comparator(
                    terminate => 1,
                    no_sort => 1,
                    func => \&compare_include,
                    );
  return $merger
}


1;