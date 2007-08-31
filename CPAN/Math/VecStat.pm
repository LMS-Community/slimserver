
require Exporter;
package Math::VecStat;
@Math::VecStat::ISA=qw(Exporter);
@EXPORT_OK=qw(max min maxabs minabs sum average
	vecprod ordered convolute
	sumbyelement diffbyelement
	allequal median);
$Math::VecStat::VERSION = '0.08';

use strict;

sub max {
  my $v=ref($_[0]) ? $_[0] : \@_;
  my $i=$#{$v};
  my $j=$i;
  my $m=$v->[$i];
  while (--$i >= 0) { if ($v->[$i] > $m) { $m=$v->[$i]; $j=$i; }}
  return wantarray ? ($m,$j): $m;
}

sub min {
  my $v=ref($_[0]) ? $_[0] : \@_;
  my $i=$#{$v};
  my $j=$i;
  my $m=$v->[$i];
  while (--$i >= 0) { if ($v->[$i] < $m) { $m=$v->[$i]; $j=$i; }}
  return wantarray ? ($m,$j): $m;
}

sub maxabs {
  my $v=ref($_[0]) ? $_[0] : \@_;
  my $i=$#{$v};
  my $j=$i;
  my $m=abs($v->[$i]);
  while (--$i >= 0) { if (abs($v->[$i]) > $m) { $m=abs($v->[$i]); $j=$i}}
  return (wantarray ? ($m,$j) : $m);
}

sub minabs {
   my $v=ref($_[0]) ? $_[0] : \@_;
   my $i=$#{$v};
   my $j=$i;
   my $m=abs($v->[$i]);
   while (--$i >= 0) { if (abs($v->[$i]) < $m) { $m=abs($v->[$i]); $j=$i}}
   return (wantarray ? ($m,$j) : $m);
}

sub sum {
  my $v=ref($_[0]) ? $_[0] : \@_;
  my $s=0;
  foreach(@{$v}) { $s+=$_; }
  return $s;
}

# spinellia@acm.org, handle the empty array case
sub average {
  my $v=ref($_[0]) ? $_[0] : \@_;
  return undef unless $#{$v} >= 0;
  return $#{$v}==-1 ? 0 : sum($v)/(1+$#{$v});
}

sub vecprod {
  my $c = shift;
  my $v=ref($_[0]) ? $_[0] : \@_;
  return undef unless $#{$v} >= 0;
  my @result = map( $_ * $c, @{$v} );
  return \@result;
}

sub ordered
{
	my $v=ref($_[0]) ? $_[0] : \@_;
	if( scalar( @{$v} ) < 2 ){ return 1; }
	for(my $i=0; $i<$#{$v}; $i++ ){
		return 0 if $v->[$i] > $v->[$i+1];
	}
	return 1;
}

sub allequal
{
	my($v,$u) = @_;
	return undef unless (defined($v) and defined($u)); # this is controversial
	return undef unless ($#{$v} == $#{$u});
	my $i= @{$v};
	while (--$i >= 0) { return 0 unless( $v->[$i] == $u->[$i]); }
	return 1;
}

sub sumbyelement
{
	my($v,$u) = @_;

	return undef unless ($#{$v} == $#{$u});
	my @summed;
	my $i= @{$v};
	while (--$i >= 0) { $summed[$i] = $v->[$i] + $u->[$i]; }
	return \@summed;
}

sub diffbyelement
{
	my($v,$u) = @_;

	return undef unless ($#{$v} == $#{$u});
	my @summed;
	my $i= @{$v};
	while (--$i >= 0) { $summed[$i] = $v->[$i] - $u->[$i]; }
	return \@summed;
}

sub convolute
{
	my($v,$u) = @_;

	return undef unless ($#{$v} == $#{$u});
	my @conv;
	my $i= @{$v};
	while (--$i >= 0) { $conv[$i] = $v->[$i]*$u->[$i]; }
	return \@conv;
}

sub _justToAvoidWarnings
{
	my $a = $Math::VecStat::VERSION;
}

sub median
{
	my $v=ref($_[0]) ? $_[0] : \@_;
	my $n = scalar @{$v};

# generate a list of [value,index] pairs
	my @tras =	map( [$v->[$_],$_], 0..$#{$v} );
# sort by ascending value, then by original position
# suggested by david@jamesgang.com
	my @sorted = sort { ($a->[0] <=> $b->[0])
		or ($a->[1] <=> $b->[1]) } @tras;
# find the middle ordinal
	my $med = int( $n / 2 );

# when there are several identical median values
# we arbitrarily (but consistently) choose the first one
# in the original array

	while( ($med >= 1) && ($sorted[$med]->[0] == $sorted[$med-1]->[0]) ){
		$med--;
	}

	return $sorted[$med];
}


1;

__END__

# $Id: VecStat.pm,v 1.5 1997/02/26 17:20:37 willijar Exp $

=head1 NAME

    Math::VecStat - Some basic numeric stats on vectors

=head1 SYNOPSIS

    use Math::VecStat qw(max min maxabs minabs sum average);
    $max=max(@vector);
    $max=max(\@vector);
    ($max,$imax)=max(@vector);
    ($max,$imax)=max(\@vector);
    $min=min(@vector);
    $min=min(\@vector);
    ($max,$imin)=min(@vector);
    ($max,$imin)=min(\@vector);
    $max=maxabs(@vector);
    $max=maxabs(\@vector);
    ($max,$imax)=maxabs(@vector);
    ($max,$imax)=maxabs(\@vector);
    $min=minabs(@vector);
    $min=minabs(\@vector);
    ($max,$imin)=minabs(@vector);
    ($max,$imin)=minabs(\@vector);
    $sum=sum($v1,$v2,...);
    $sum=sum(@vector);
    $sum=sum(\@vector);
    $average=average($v1,$v2,...);
    $av=average(@vector);
    $av=average(\@vector);
    $ref=vecprod($scalar,\@vector);
    $ok=ordered(@vector);
    $ok=ordered(\@vector);
    $ref=sumbyelement(\@vector1,\@vector2);
    $ref=diffbyelement(\@vector1,\@vector2);
    $ok=allequal(\@vector1,\@vector2);
    $ref=convolute(\@vector1,\@vector2);

=head1 DESCRIPTION

This package provides some basic statistics on numerical
vectors. All the subroutines can take
a reference to the vector to be operated
on. In some cases a copy of the vector is acceptable,
but is not recommended for efficiency.

=over 5

=item  max(@vector), max(\@vector)

return the maximum value of given values or vector. In an array
context returns the value and the index in the array where it
occurs.

=item min(@vector), min(\@vector)

return the minimum value of given values or vector, In an array
context returns the value and the index in the array where it
occurs.


=item maxabs(@vector), maxabs(\@vector)

return the maximum value of absolute of the given values or vector. In
an array context returns the value and the index in the array where it
occurs.

=item minabs(@vector), minabs(\@vector)

return the minimum value of the absolute of the given values or
vector. In an array context returns the value and the index in the
array where it occurs.

=item sum($v1,$v2,...), sum(@vector), sum(\@vector)

return the sum of the given values or vector

=item average($v1,$v2,..), average(@vector), average(\@vector)

return the average of the given values or vector

=item vecprod($a,$v1,$v2,..), vecprod($a,@vector), vecprod( $a, \@vector )

return a vector built by multiplying the scalar $a by each element of the
@vector.

=item ordered($v1,$v2,..), ordered(@vector), ordered(\@vector)

return nonzero iff the vector is nondecreasing with respect to its index.
To be used like

  if( ordered( $lowBound, $value, $highBound ) ){

instead of the (slightly) more clumsy

  if( ($lowBound <= $value) && ($value <= $highBound) ) {

=item sumbyelement( \@array1, \@array2 ), diffbyelement(\@array1,\@array2)

return the element-by-element sum or difference of two
identically-sized vectors. Given

  $s = sumbyelement( [10,20,30], [1,2,3] );
  $d = diffbyelement( [10,20,30], [1,2,3] );

C<$s> will be C<[11,22,33]>, C<$d> will be C<[9,18,27]>.

=item allequal( \@array1, \@array2 )

returns true if and only if the two arrays are numerically identical.

=item convolute( \@array1, \@array2 )

return a reference to an array containing the element-by-element
product of the two input arrays. I.e.,

  $r = convolute( [1,2,3], [-1,2,1] );

returns a reference to

  [-1,4,3]

=item median

evaluates the median, i.e. an element which separates the population
in two halves.  It returns a reference to a list whose first element
is the median value and the second element is the index of the
median element in the original vector.

  $a = Math::VecStat::median( [9,8,7,6,5,4,3,2,1] );

returns the list reference

  [ 5, 4 ]

i.e. the median value is 5 and it is found at position 4 of the
original array.

If there are several elements of the array
having the median value, e.g. [1,3,3,3,5].  In this case
we choose always the first element in the original vector
which is a median. In the example, we return [3,1].

=head1 HISTORY

 $Log: VecStat.pm,v $
 Revision 1.9  2003/04/20 00:49:00 spinellia@acm.org
 Perl 5.8 broke test 36, exposing inconsistency in C<median>.  Fixed, thanks to david@jamesgang.com.

 Revision 1.8  2001/01/26 11:10:00 spinellia@acm.org
 Added function median.
 Fixed test, thanks to Andreas Marcel Riechert <riechert@pobox.com>

 Revision 1.7  2000/10/24 15:28:00  spinellia@acm.org
 Added functions allequal diffbyelement
 Created a reasonable test suite.

 Revision 1.6  2000/06/29 16:06:37  spinellia@acm.org
 Added functions vecprod, convolute, sumbyelement

 Revision 1.5  1997/02/26 17:20:37  willijar
 Added line before pod header so pod2man installs man page correctly

 Revision 1.4  1996/02/20 07:53:10  willijar
 Added ability to return index in array contex to max and min
 functions. Added minabs and maxabs functions.
 Thanks to Mark Borges <mdb@cdc.noaa.gov> for these suggestions.

 Revision 1.3  1996/01/06 11:03:30  willijar
 Fixed stupid bug that crept into looping in min and max functions

 Revision 1.2  1995/12/26 09:56:38  willijar
 Oops - removed xy data functions.

 Revision 1.1  1995/12/26 09:39:07  willijar
 Initial revision

=head1 BUGS

Let me know. I welcome any appropriate additions for this package.

=head1 AUTHORS

John A.R. Williams <J.A.R.Williams@aston.ac.uk>
Andrea Spinelli <spinellia@acm.org>

=cut

