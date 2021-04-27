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



1;