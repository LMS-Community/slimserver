package Tie::Cache::LRU;

use strict;

use base qw(Tie::Cache::LRU::Array);

use vars qw($VERSION);
BEGIN {
    $VERSION = '0.21';
}

=pod

=head1 NAME

Tie::Cache::LRU - A Least-Recently Used cache


=head1 SYNOPSIS

    use Tie::Cache::LRU;

    tie %cache, 'Tie::Cache::LRU', 500;
    tie %cache, 'Tie::Cache::LRU', '400k'; #UNIMPLEMENTED

    # Use like a normal hash.

    $cache_obj = tied %cache;
    $current_size = $cache_obj->curr_size;

    $max_size = $cache_obj->max_size;
    $cache_obj->max_size($new_size);


=head1 DESCRIPTION

This is an implementation of a least-recently used (LRU) cache keeping
the cache in RAM.

A LRU cache is similar to the kind of cache used by a web browser.
New items are placed into the top of the cache.  When the cache grows
past its size limit, it throws away items off the bottom.  The trick
is that whenever an item is -accessed-, it is pulled back to the top.
The end result of all this is that items which are frequently accessed
tend to stay in the cache.



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
Tie::Cache::LRU->DEFAULT_MAX_SIZE.

If the size is set to 0, the cache is effectively turned off.  This is
useful for "removing" the cache from a program without having to make
deep alterations to the program itself, or for checking performance
differences with and without a cache.

All of the expected hash operations (exists, delete, slices, etc...) 
work on the %cache.


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


=head1 NOTES

This is just a thin subclass of Tie::Cache::LRU::Array.


=head1 TODO

Should eventually allow the cache to be in shared memory.

Max size by memory use unimplemented.


=head1 AUTHOR

Michael G Schwern <schwern@pobox.com> for Arena Networks


=head1 SEE ALSO

L<Tie::Cache::LRU::Array>, L<Tie::Cache::LRU::LinkedList>,
L<Tie::Cache::LRU::Virtual>, L<Tie::Cache>

=cut

return q|Look at me, look at me!  I'm super fast!  I'm bionic!  I'm bionic!|;
