#
# Tie/IxHash.pm
#
# Indexed hash implementation for Perl
#
# See below for documentation.
#

require 5.003;

package Tie::IxHash;
use integer;
require Tie::Hash;
@ISA = qw(Tie::Hash);

$VERSION = $VERSION = '1.21';

#
# standard tie functions
#

sub TIEHASH {
  my($c) = shift;
  my($s) = [];
  $s->[0] = {};   # hashkey index
  $s->[1] = [];   # array of keys
  $s->[2] = [];   # array of data
  $s->[3] = 0;    # iter count

  bless $s, $c;

  $s->Push(@_) if @_;

  return $s;
}

#sub DESTROY {}           # costly if there's nothing to do

sub FETCH {
  my($s, $k) = (shift, shift);
  return exists( $s->[0]{$k} ) ? $s->[2][ $s->[0]{$k} ] : undef;
}

sub STORE {
  my($s, $k, $v) = (shift, shift, shift);
  
  if (exists $s->[0]{$k}) {
    my($i) = $s->[0]{$k};
    $s->[1][$i] = $k;
    $s->[2][$i] = $v;
    $s->[0]{$k} = $i;
  }
  else {
    push(@{$s->[1]}, $k);
    push(@{$s->[2]}, $v);
    $s->[0]{$k} = $#{$s->[1]};
  }
}

sub DELETE {
  my($s, $k) = (shift, shift);

  if (exists $s->[0]{$k}) {
    my($i) = $s->[0]{$k};
    for ($i+1..$#{$s->[1]}) {    # reset higher elt indexes
      $s->[0]{$s->[1][$_]}--;    # timeconsuming, is there is better way?
    }
    delete $s->[0]{$k};
    splice @{$s->[1]}, $i, 1;
    return (splice(@{$s->[2]}, $i, 1))[0];
  }
  return undef;
}

sub EXISTS {
  exists $_[0]->[0]{ $_[1] };
}

sub FIRSTKEY {
  $_[0][3] = 0;
  &NEXTKEY;
}

sub NEXTKEY {
  return $_[0][1][$_[0][3]++] if ($_[0][3] <= $#{$_[0][1]});
  return undef;
}



#
#
# class functions that provide additional capabilities
#
#

sub new { TIEHASH(@_) }

#
# add pairs to end of indexed hash
# note that if a supplied key exists, it will not be reordered
#
sub Push {
  my($s) = shift;
  while (@_) {
    $s->STORE(shift, shift);
  }
  return scalar(@{$s->[1]});
}

sub Push2 {
  my($s) = shift;
  $s->Splice($#{$s->[1]}+1, 0, @_);
  return scalar(@{$s->[1]});
}

#
# pop last k-v pair
#
sub Pop {
  my($s) = shift;
  my($k, $v, $i);
  $k = pop(@{$s->[1]});
  $v = pop(@{$s->[2]});
  if (defined $k) {
    delete $s->[0]{$k};
    return ($k, $v);
  }
  return undef;
}

sub Pop2 {
  return $_[0]->Splice(-1);
}

#
# shift
#
sub Shift {
  my($s) = shift;
  my($k, $v, $i);
  $k = shift(@{$s->[1]});
  $v = shift(@{$s->[2]});
  if (defined $k) {
    delete $s->[0]{$k};
    for (keys %{$s->[0]}) {
      $s->[0]{$_}--;
    }
    return ($k, $v);
  }
  return undef;
}

sub Shift2 {
  return $_[0]->Splice(0, 1);
}

#
# unshift
# if a supplied key exists, it will not be reordered
#
sub Unshift {
  my($s) = shift;
  my($k, $v, @k, @v, $len, $i);

  while (@_) {
    ($k, $v) = (shift, shift);
    if (exists $s->[0]{$k}) {
      $i = $s->[0]{$k};
      $s->[1][$i] = $k;
      $s->[2][$i] = $v;
      $s->[0]{$k} = $i;
    }
    else {
      push(@k, $k);
      push(@v, $v);
      $len++;
    }
  }
  if (defined $len) {
    for (keys %{$s->[0]}) {
      $s->[0]{$_} += $len;
    }
    $i = 0;
    for (@k) {
      $s->[0]{$_} = $i++;
    }
    unshift(@{$s->[1]}, @k);
    return unshift(@{$s->[2]}, @v);
  }
  return scalar(@{$s->[1]});
}

sub Unshift2 {
  my($s) = shift;
  $s->Splice(0,0,@_);
  return scalar(@{$s->[1]});
}

#
# splice 
#
# any existing hash key order is preserved. the value is replaced for
# such keys, and the new keys are spliced in the regular fashion.
#
# supports -ve offsets but only +ve lengths
#
# always assumes a 0 start offset
#
sub Splice {
  my($s, $start, $len) = (shift, shift, shift);
  my($k, $v, @k, @v, @r, $i, $siz);
  my($end);                   # inclusive

  # XXX  inline this 
  ($start, $end, $len) = $s->_lrange($start, $len);

  if (defined $start) {
    if ($len > 0) {
      my(@k) = splice(@{$s->[1]}, $start, $len);
      my(@v) = splice(@{$s->[2]}, $start, $len);
      while (@k) {
        $k = shift(@k);
        delete $s->[0]{$k};
        push(@r, $k, shift(@v));
      }
      for ($start..$#{$s->[1]}) {
        $s->[0]{$s->[1][$_]} -= $len;
      }
    }
    while (@_) {
      ($k, $v) = (shift, shift);
      if (exists $s->[0]{$k}) {
        #      $s->STORE($k, $v);
        $i = $s->[0]{$k};
        $s->[1][$i] = $k;
        $s->[2][$i] = $v;
        $s->[0]{$k} = $i;
      }
      else {
        push(@k, $k);
        push(@v, $v);
        $siz++;
      }
    }
    if (defined $siz) {
      for ($start..$#{$s->[1]}) {
        $s->[0]{$s->[1][$_]} += $siz;
      }
      $i = $start;
      for (@k) {
        $s->[0]{$_} = $i++;
      }
      splice(@{$s->[1]}, $start, 0, @k);
      splice(@{$s->[2]}, $start, 0, @v);
    }
  }
  return @r;
}

#
# delete elements specified by key
# other elements higher than the one deleted "slide" down 
#
sub Delete {
  my($s) = shift;

  for (@_) {
    #
    # XXX potential optimization: could do $s->DELETE only if $#_ < 4.
    #     otherwise, should reset all the hash indices in one loop
    #
    $s->DELETE($_);
  }
}

#
# replace hash element at specified index
#
# if the optional key is not supplied the value at index will simply be 
# replaced without affecting the order.
#
# if an element with the supplied key already exists, it will be deleted first.
#
# returns the key of replaced value if it succeeds.
#
sub Replace {
  my($s) = shift;
  my($i, $v, $k) = (shift, shift, shift);
  if (defined $i and $i <= $#{$s->[1]} and $i >= 0) {
    if (defined $k) {
      delete $s->[0]{ $s->[1][$i] };
      $s->DELETE($k) ; #if exists $s->[0]{$k};
      $s->[1][$i] = $k;
      $s->[2][$i] = $v;
      $s->[0]{$k} = $i;
      return $k;
    }
    else {
      $s->[2][$i] = $v;
      return $s->[1][$i];
    }
  }
  return undef;
}

#
# Given an $start and $len, returns a legal start and end (where start <= end)
# for the current hash. 
# Legal range is defined as 0 to $#s+1
# $len defaults to number of elts upto end of list
#
#          0   1   2   ...
#          | X | X | X ... X | X | X |
#                           -2  -1       (no -0 alas)
# X's above are the elements 
#
sub _lrange {
  my($s) = shift;
  my($offset, $len) = @_;
  my($start, $end);         # both inclusive
  my($size) = $#{$s->[1]}+1;

  return undef unless defined $offset;
  if($offset < 0) {
    $start = $offset + $size;
    $start = 0 if $start < 0;
  }
  else {
    ($offset > $size) ? ($start = $size) : ($start = $offset);
  }

  if (defined $len) {
    $len = -$len if $len < 0;
    $len = $size - $start if $len > $size - $start;
  }
  else {
    $len = $size - $start;
  }
  $end = $start + $len - 1;

  return ($start, $end, $len);
}

#
# Return keys at supplied indices
# Returns all keys if no args.
#
sub Keys   { 
  my($s) = shift;
  return ( @_ == 1
	 ? $s->[1][$_[0]]
	 : ( @_
	   ? @{$s->[1]}[@_]
	   : @{$s->[1]} ) );
}

#
# Returns values at supplied indices
# Returns all values if no args.
#
sub Values {
  my($s) = shift;
  return ( @_ == 1
	 ? $s->[2][$_[0]]
	 : ( @_
	   ? @{$s->[2]}[@_]
	   : @{$s->[2]} ) );
}

#
# get indices of specified hash keys
#
sub Indices { 
  my($s) = shift;
  return ( @_ == 1 ? $s->[0]{$_[0]} : @{$s->[0]}{@_} );
}

#
# number of k-v pairs in the ixhash
# note that this does not equal the highest index
# owing to preextended arrays
#
sub Length {
 return scalar @{$_[0]->[1]};
}

#
# Reorder the hash in the supplied key order
#
# warning: any unsupplied keys will be lost from the hash
# any supplied keys that dont exist in the hash will be ignored
#
sub Reorder {
  my($s) = shift;
  my(@k, @v, %x, $i);
  return unless @_;

  $i = 0;
  for (@_) {
    if (exists $s->[0]{$_}) {
      push(@k, $_);
      push(@v, $s->[2][ $s->[0]{$_} ] );
      $x{$_} = $i++;
    }
  }
  $s->[1] = \@k;
  $s->[2] = \@v;
  $s->[0] = \%x;
  return $s;
}

sub SortByKey {
  my($s) = shift;
  $s->Reorder(sort $s->Keys);
}

sub SortByValue {
  my($s) = shift;
  $s->Reorder(sort { $s->FETCH($a) cmp $s->FETCH($b) } $s->Keys)
}

1;
__END__

=head1 NAME

Tie::IxHash - ordered associative arrays for Perl


=head1 SYNOPSIS

    # simple usage
    use Tie::IxHash;
    tie HASHVARIABLE, Tie::IxHash [, LIST];
    
    # OO interface with more powerful features
    use Tie::IxHash;
    TIEOBJECT = Tie::IxHash->new( [LIST] );
    TIEOBJECT->Splice( OFFSET [, LENGTH [, LIST]] );
    TIEOBJECT->Push( LIST );
    TIEOBJECT->Pop;
    TIEOBJECT->Shift;
    TIEOBJECT->Unshift( LIST );
    TIEOBJECT->Keys( [LIST] );
    TIEOBJECT->Values( [LIST] );
    TIEOBJECT->Indices( LIST );
    TIEOBJECT->Delete( [LIST] );
    TIEOBJECT->Replace( OFFSET, VALUE, [KEY] );
    TIEOBJECT->Reorder( LIST );
    TIEOBJECT->SortByKey;
    TIEOBJECT->SortByValue;
    TIEOBJECT->Length;


=head1 DESCRIPTION

This Perl module implements Perl hashes that preserve the order in which the
hash elements were added.  The order is not affected when values
corresponding to existing keys in the IxHash are changed.  The elements can
also be set to any arbitrary supplied order.  The familiar perl array
operations can also be performed on the IxHash.


=head2 Standard C<TIEHASH> Interface

The standard C<TIEHASH> mechanism is available. This interface is 
recommended for simple uses, since the usage is exactly the same as
regular Perl hashes after the C<tie> is declared.


=head2 Object Interface

This module also provides an extended object-oriented interface that can be
used for more powerful operations with the IxHash.  The following methods
are available:

=over 8

=item FETCH, STORE, DELETE, EXISTS

These standard C<TIEHASH> methods mandated by Perl can be used directly.
See the C<tie> entry in perlfunc(1) for details.

=item Push, Pop, Shift, Unshift, Splice

These additional methods resembling Perl functions are available for
operating on key-value pairs in the IxHash. The behavior is the same as the
corresponding perl functions, except when a supplied hash key already exists
in the hash. In that case, the existing value is updated but its order is
not affected.  To unconditionally alter the order of a supplied key-value
pair, first C<DELETE> the IxHash element.

=item Keys

Returns an array of IxHash element keys corresponding to the list of supplied
indices.  Returns an array of all the keys if called without arguments.
Note the return value is mostly only useful when used in a list context
(since perl will convert it to the number of elements in the array when
used in a scalar context, and that may not be very useful).

If a single argument is given, returns the single key corresponding to
the index.  This is usable in either scalar or list context.

=item Values

Returns an array of IxHash element values corresponding to the list of supplied
indices.  Returns an array of all the values if called without arguments.
Note the return value is mostly only useful when used in a list context
(since perl will convert it to the number of elements in the array when
used in a scalar context, and that may not be very useful).

If a single argument is given, returns the single value corresponding to
the index.  This is usable in either scalar or list context.

=item Indices

Returns an array of indices corresponding to the supplied list of keys.
Note the return value is mostly only useful when used in a list context
(since perl will convert it to the number of elements in the array when
used in a scalar context, and that may not be very useful).

If a single argument is given, returns the single index corresponding to
the key.  This is usable in either scalar or list context.

=item Delete

Removes elements with the supplied keys from the IxHash.

=item Replace

Substitutes the IxHash element at the specified index with the supplied
value-key pair.  If a key is not supplied, simply substitutes the value at
index with the supplied value. If an element with the supplied key already
exists, it will be removed from the IxHash first.

=item Reorder

This method can be used to manipulate the internal order of the IxHash
elements by supplying a list of keys in the desired order.  Note however,
that any IxHash elements whose keys are not in the list will be removed from
the IxHash.

=item Length

Returns the number of IxHash elements.

=item SortByKey

Reorders the IxHash elements by textual comparison of the keys.

=item SortByValue

Reorders the IxHash elements by textual comparison of the values.

=back


=head1 EXAMPLE

    use Tie::IxHash;

    # simple interface
    $t = tie(%myhash, Tie::IxHash, 'a' => 1, 'b' => 2);
    %myhash = (first => 1, second => 2, third => 3);
    $myhash{fourth} = 4;
    @keys = keys %myhash;
    @values = values %myhash;
    print("y") if exists $myhash{third};
    
    # OO interface
    $t = Tie::IxHash->new(first => 1, second => 2, third => 3);
    $t->Push(fourth => 4); # same as $myhash{'fourth'} = 4;
    ($k, $v) = $t->Pop;    # $k is 'fourth', $v is 4
    $t->Unshift(neg => -1, zeroth => 0); 
    ($k, $v) = $t->Shift;  # $k is 'neg', $v is -1
    @oneandtwo = $t->Splice(1, 2, foo => 100, bar => 101);
    
    @keys = $t->Keys;
    @values = $t->Values;
    @indices = $t->Indices('foo', 'zeroth');
    @itemkeys = $t->Keys(@indices);
    @itemvals = $t->Values(@indices);
    $t->Replace(2, 0.3, 'other');
    $t->Delete('second', 'zeroth');
    $len = $t->Length;     # number of key-value pairs

    $t->Reorder(reverse @keys);
    $t->SortByKey;
    $t->SortByValue;


=head1 BUGS

You cannot specify a negative length to C<Splice>. Negative indexes are OK,
though.

Indexing always begins at 0 (despite the current C<$[> setting) for 
all the functions.


=head1 TODO

Addition of elements with keys that already exist to the end of the IxHash
must be controlled by a switch.

Provide C<TIEARRAY> interface when it stabilizes in Perl.

Rewrite using XSUBs for efficiency.


=head1 AUTHOR

Gurusamy Sarathy        gsar@umich.edu

Copyright (c) 1995 Gurusamy Sarathy. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.


=head1 VERSION

Version 1.21    20 Nov 1997


=head1 SEE ALSO

perl(1)

=cut
