package Tie::Cache::LRU::Virtual;

use strict;
use vars qw($VERSION);
$VERSION = '0.01';

use base qw(Class::Virtual Class::Data::Inheritable);

__PACKAGE__->mk_classdata('DEFAULT_MAX_SIZE');
__PACKAGE__->DEFAULT_MAX_SIZE(500);

__PACKAGE__->virtual_methods(qw(TIEHASH
                                CLEAR
                                FETCH
                                STORE
                                EXISTS
                                DELETE
                                FIRSTKEY
                                NEXTKEY
                                DESTROY

                                curr_size
                                max_size
                               )
                             );

=pod

=head1 NAME

Tie::Cache::LRU::Virtual - Virtual base class for Tie::Cache::LRU::*

=head1 SYNOPSIS

  package My::Tie::Cache::LRU;

  use base qw(Tie::Cache::LRU::Virtual);

  ...override and define key methods...

=head1 DESCRIPTION

This is a pure virtual base class defining the public methods of
Tie::Cache::LRU.  It is intended that you will subclass off of it and
fill in the missing/incomplete methods.

You must implement the entire hash interface.

    TIEHASH
    CLEAR
    FETCH
    STORE
    EXISTS
    DELETE
    FIRSTKEY
    NEXTKEY

And the object interface

    curr_size
    max_size

As well as DESTROY if necessary.

I'm usually not taken to such heights of OO formality, but in this
case a virtual class seemed in order.


=head1 USAGE

The cache is extremely simple, is just holds a simple scalar.  If you
want to cache an object, just place it into the cache:

    $cache{$obj->id} = $obj;

This doesn't make a copy of the object, it just holds a reference to
it.  (Note: This means that your object's destructor will not be
called until it has fallen out of the cache (and all other references
to it have disappeared, of course)!)

If you want to cache an array, place a reference to it in the cache:

    $cache{$some_id} = \@array;

Or, if you're worried about the consequences of tossing around
references and want to cache a copy instead, you can do something like
this:

    $cache{$some_id} = [@array];


=head2 Tied Interface

=over 4

=item B<tie>

    tie %cache, 'Tie::Cache::LRU';
    tie %cache, 'Tie::Cache::LRU', $cache_size;

This ties a cache to %cache which will hold a maximum of $cache_size
keys.  If $cache_size is not given it uses a default value,
Tie::Cache::LRU::DEFAULT_MAX_SIZE.

If the size is set to 0, the cache is effectively turned off.  This is
useful for "removing" the cache from a program without having to make
deep alterations to the program itself, or for checking performance
differences with and without a cache.

All of the expected hash operations (exists, delete, slices, etc...) 
work on the %cache.


=pod

=back

=head2 Object Interface

There's a few things you just can't do through the tied interface.  To
do them, you need to get at the underlying object, which you do with
tied().

    $cache_obj = tied %cache;

And then you can call a few methods on that object:

=over 4

=item B<max_size>

  $cache_obj->max_size($size);
  $size = $cache_obj->max_size;

An accessor to alter the maximum size of the cache on the fly.

If max_size() is reset, and it is lower than the current size, the cache
is immediately truncated.

The size must be an integer greater than or equal to 0.


=item B<curr_size>

  $size = $cache_obj->curr_size;

Returns the current number of items in the cache.

=back


=head1 AUTHOR

Michael G Schwern <schwern@pobox.com>

=head1 SEE ALSO

L<Tie::Cache::LRU>, L<Tie::Cache::LRU::LinkedList>,
L<Tie::Cache::LRU::Array>, L<Tie::Cache>

=cut

1;

