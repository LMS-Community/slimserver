#####################################################################
# $Id: Cache.pm 6973 2006-04-19 03:21:06Z andy $
# Copyright (C) 2001-2003 DeWitt Clinton  All Rights Reserved
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either expressed or
# implied. See the License for the specific language governing
# rights and limitations under the License.
######################################################################


package Cache::Cache;


use strict;
use vars qw( @ISA @EXPORT_OK $VERSION $EXPIRES_NOW $EXPIRES_NEVER );
use Exporter;

@ISA = qw( Exporter );

@EXPORT_OK = qw( $VERSION $EXPIRES_NOW $EXPIRES_NEVER );

$VERSION = "1.04";
$EXPIRES_NOW = 'now';
$EXPIRES_NEVER = 'never';


sub Clear;

sub Purge;

sub Size;

sub new;

sub clear;

sub get;

sub get_object;

sub purge;

sub remove;

sub set;

sub set_object;

sub size;

sub get_default_expires_in;

sub get_namespace;

sub set_namespace;

sub get_keys;

sub get_auto_purge_interval;

sub set_auto_purge_interval;

sub get_auto_purge_on_set;

sub set_auto_purge_on_set;

sub get_namespaces;

sub get_identifiers;  # deprecated


1;


__END__


=pod

=head1 NAME

Cache::Cache -- the Cache interface.

=head1 DESCRIPTION

The Cache modules are designed to assist a developer in persisting
data for a specified period of time.  Often these modules are used in
web applications to store data locally to save repeated and redundant
expensive calls to remote machines or databases.  People have also
been known to use Cache::Cache for its straightforward interface in
sharing data between runs of an application or invocations of a
CGI-style script or simply as an easy to use abstraction of the
filesystem or shared memory.

The Cache::Cache interface is implemented by classes that support the
get, set, remove, size, purge, and clear instance methods and their
corresponding static methods for persisting data across method calls.

=head1 USAGE

First, choose the best type of cache implementation for your needs.
The simplest cache is the MemoryCache, which is suitable for
applications that are serving multiple sequential requests, and wish
to avoid making redundant expensive queries, such as an
Apache/mod_perl application talking to a database.  If you wish to
share that data between processes, then perhaps the SharedMemoryCache
is appropriate, although its behavior is tightly bound to the
underlying IPC mechanism, which varies from system to system, and is
unsuitable for large objects or large numbers of objects.  When the
SharedMemoryCache is not acceptable, then FileCache offers all of the
same functionality with similar performance metrics, and it is not
limited in terms of the number of objects or their size.  If you wish
to maintain a strict limit on the size of a file system based cache,
then the SizeAwareFileCache is the way to go.  Similarly, the
SizeAwareMemoryCache and the SizeAwareSharedMemoryCache add size
management functionality to the MemoryCache and SharedMemoryCache
classes respectively.

Using a cache is simple.  Here is some sample code for instantiating
and using a file system based cache.

  use Cache::FileCache;

  my $cache = new Cache::FileCache( );

  my $customer = $cache->get( $name );

  if ( not defined $customer )
  {
    $customer = get_customer_from_db( $name );
    $cache->set( $name, $customer, "10 minutes" );
  }

  return $customer;


=head1 CONSTANTS

=over

=item I<$EXPIRES_NEVER>

The item being set in the cache will never expire.

=item I<$EXPIRES_NOW>

The item being set in the cache will expire immediately.

=back

=head1 METHODS

=over

=item B<Clear( )>

Remove all objects from all caches of this type.

=item B<Purge( )>

Remove all objects that have expired from all caches of this type.

=item B<Size( )>

Returns the total size of all objects in all caches of this type.

=item B<new( $options_hash_ref )>

Construct a new instance of a Cache::Cache. I<$options_hash_ref> is a
reference to a hash containing configuration options; see the section
OPTIONS below.

=item B<clear(  )>

Remove all objects from the namespace associated with this cache instance.

=item B<get( $key )>

Returns the data associated with I<$key>.

=item B<get_object( $key )>

Returns the underlying Cache::Object object used to store the cached
data associated with I<$key>.  This will not trigger a removal
of the cached object even if the object has expired.

=item B<purge(  )>

Remove all objects that have expired from the namespace associated
with this cache instance.

=item B<remove( $key )>

Delete the data associated with the I<$key> from the cache.

=item B<set( $key, $data, [$expires_in] )>

Associates I<$data> with I<$key> in the cache. I<$expires_in>
indicates the time in seconds until this data should be erased, or the
constant $EXPIRES_NOW, or the constant $EXPIRES_NEVER.  Defaults to
$EXPIRES_NEVER.  This variable can also be in the extended format of
"[number] [unit]", e.g., "10 minutes".  The valid units are s, second,
seconds, sec, m, minute, minutes, min, h, hour, hours, d, day, days, w,
week, weeks, M, month, months, y, year, and years.  Additionally,
$EXPIRES_NOW can be represented as "now" and $EXPIRES_NEVER can be
represented as "never".

=item B<set_object( $key, $object )>

Associates I<$key> with Cache::Object I<$object>.  Using set_object
(as opposed to set) does not trigger an automatic removal of expired
objects.

=item B<size(  )>

Returns the total size of all objects in the namespace associated with
this cache instance.

=item B<get_namespaces( )>

Returns all the namespaces associated with this type of cache.

=back

=head1 OPTIONS

The options are set by passing in a reference to a hash containing any
of the following keys:

=over

=item I<namespace>

The namespace associated with this cache.  Defaults to "Default" if
not explicitly set.

=item I<default_expires_in>

The default expiration time for objects place in the cache.  Defaults
to $EXPIRES_NEVER if not explicitly set.

=item I<auto_purge_interval>

Sets the auto purge interval.  If this option is set to a particular
time ( in the same format as the expires_in ), then the purge( )
routine will be called during the first set after the interval
expires.  The interval will then be reset.

=item I<auto_purge_on_set>

If this option is true, then the auto purge interval routine will be
checked on every set.

=item I<auto_purge_on_get>

If this option is true, then the auto purge interval routine will be
checked on every get.

=back

=head1 PROPERTIES

=over

=item B<(get|set)_namespace( )>

The namespace of this cache instance

=item B<get_default_expires_in( )>

The default expiration time for objects placed in this cache instance

=item B<get_keys( )>

The list of keys specifying objects in the namespace associated
with this cache instance

=item B<get_identifiers( )>

This method has been deprecated in favor of B<get_keys( )>.

=item B<(get|set)_auto_purge_interval( )>

Accesses the auto purge interval.  If this option is set to a particular
time ( in the same format as the expires_in ), then the purge( )
routine will be called during the first get after the interval
expires.  The interval will then be reset.

=item B<(get|set)_auto_purge_on_set( )>

If this property is true, then the auto purge interval routine will be
checked on every set.

=item B<(get|set)_auto_purge_on_get( )>

If this property is true, then the auto purge interval routine will be
checked on every get.

=back

=head1 SEE ALSO

Cache::Object, Cache::MemoryCache, Cache::FileCache,
Cache::SharedMemoryCache, and Cache::SizeAwareFileCache

=head1 AUTHOR

Original author: DeWitt Clinton <dewitt@unto.net>

Last author:     $Author: andy $

Copyright (C) 2001-2003 DeWitt Clinton

=cut
