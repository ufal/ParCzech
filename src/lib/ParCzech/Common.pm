package ParCzech::Common;




sub common_uri_part {
  my @uri = (shift,shift);
  my @rest_uri = @_;
  return $uri[0] unless defined $uri[1];

  my $i=0;
  while(    $i < length($uri[1])
         && $i < length($uri[0])
         && substr($uri[1], $i, 1) eq substr($uri[0], $i, 1)){
    $i++;
  }
  my $res = $uri[0];
  if ($i < length($res)) {
    $res = substr($res, 0, $i);
    $res =~ s/[^\/]*$//;
  }
  return common_uri_part($res,@rest_uri);
}


sub date_node_to_interval {
  my $date_node = shift;
  my ($from,$to);
  my ($from_text,$to_text);

  for my $a (qw/from when to/) {
    if($date_node->hasAttribute($a)){
      $from = $date_node->getAttribute($a) unless defined $from;
      $to = $date_node->getAttribute($a) unless defined $to;
      if(($from cmp $date_node->getAttribute($a)) >= 0){
        $from = $date_node->getAttribute($a);
        ($from_text) = ($date_node->textContent()) =~ m/^\s*([^-]*)\s*(?: - )?[^-]*?$/;
      }
      if(($to cmp $date_node->getAttribute($a)) <= 0){
        $to = $date_node->getAttribute($a);
        ($to_text) = ($date_node->textContent()) =~ m/^[^-]*?(?: - )?\s*([^-]*)\s*$/;
      }
    }
  }
  return {from=>[$from, $from_text],to=>[$to, $to_text]};
}

sub set_date_node {
  my $date_node = shift;
  my $interval = shift;
  $date_node->removeAttribute($_) for (qw/from when to/);
  $date_node->removeChildNodes();
  if($interval->{from}->[0] eq $interval->{to}->[0]) {
    $date_node->setAttribute('when', $interval->{from}->[0]);
    $date_node->appendText($interval->{from}->[1]);
  } else {
    $date_node->setAttribute('from', $interval->{from}->[0]);
    $date_node->setAttribute('to', $interval->{to}->[0]);
    $date_node->appendText($interval->{from}->[1]
                    . ' - '
                    . $interval->{to}->[1]);
  }
}

sub merge_interval {
  my @intervals = (shift,shift);
  my @rest_intervals = @_;
  return $intervals[0] unless defined $intervals[1];

  my ($from,$to);
  my ($from_text,$to_text);

  for my $i (0, 1){
    for my $a (qw/from when to/) {
      if(defined $intervals[$i]->{$a}){
        $from = $intervals[$i]->{$a}->[0] unless defined $from;
        $to = $intervals[$i]->{$a}->[0] unless defined $to;
        if(($from cmp $intervals[$i]->{$a}->[0]) >= 0){
          $from = $intervals[$i]->{$a}->[0];
          $from_text = $intervals[$i]->{$a}->[1];
        }
        if(($to cmp $intervals[$i]->{$a}->[0]) <= 0){
          $to = $intervals[$i]->{$a}->[0];
          $to_text = $intervals[$i]->{$a}->[1];
        }
      }
    }
  }
  return merge_interval({from=>[$from, $from_text],to=>[$to, $to_text]}, @rest_intervals);
}



1;