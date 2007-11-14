######################################################################
# $Id: FileCache.pm 6973 2006-04-19 03:21:06Z andy $
# Copyright (C) 2001-2003 DeWitt Clinton  All Rights Reserved
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either expressed or
# implied. See the License for the specific language governing
# rights and limitations under the License.
######################################################################


package Cache::FileCache;


use strict;
use vars qw( @ISA );
use Cache::BaseCache;
use Cache::Cache;
use Cache::CacheUtils qw ( Assert_Defined Build_Path Static_Params );
use Cache::FileBackend;
use Cache::Object;
use Error;
use File::Spec::Functions;


@ISA = qw ( Cache::BaseCache );


# by default, the cache nests all entries on the filesystem three
# directories deep

my $DEFAULT_CACHE_DEPTH = 3;


# by default, the root of the cache is located in 'FileCache'.  On a
# UNIX system, this will appear in "/tmp/FileCache/"

my $DEFAULT_CACHE_ROOT = "FileCache";


# by default, the directories in the cache on the filesystem should
# be globally writable to allow for multiple users.  While this is a
# potential security concern, the actual cache entries are written
# with the user's umask, thus reducing the risk of cache poisoning

my $DEFAULT_DIRECTORY_UMASK = 000;


sub Clear
{
  my ( $p_optional_cache_root ) = Static_Params( @_ );

  foreach my $namespace ( _Namespaces( $p_optional_cache_root ) )
  {
    _Get_Cache( $namespace, $p_optional_cache_root )->clear( );
  }
}


sub Purge
{
  my ( $p_optional_cache_root ) = Static_Params( @_ );

  foreach my $namespace ( _Namespaces( $p_optional_cache_root ) )
  {
    _Get_Cache( $namespace, $p_optional_cache_root )->purge( );
  }
}


sub Size
{
  my ( $p_optional_cache_root ) = Static_Params( @_ );

  my $size = 0;

  foreach my $namespace ( _Namespaces( $p_optional_cache_root ) )
  {
    $size += _Get_Cache( $namespace, $p_optional_cache_root )->size( );
  }

  return $size;
}


sub new
{
  my ( $self ) = _new( @_ );

  $self->_complete_initialization( );

  return $self;
}


sub _Get_Backend
{
  my ( $p_optional_cache_root ) = Static_Params( @_ );

  return new Cache::FileBackend( _Build_Cache_Root( $p_optional_cache_root ) );

}


# return the OS default temp directory

sub _Get_Temp_Directory
{
  my $tmpdir = File::Spec->tmpdir( ) or
    throw Error::Simple( "No tmpdir on this system.  Upgrade File::Spec?" );

  return $tmpdir;
}


sub _Build_Cache_Root
{
  my ( $p_optional_cache_root ) = Static_Params( @_ );

  if ( defined $p_optional_cache_root )
  {
    return $p_optional_cache_root;
  }
  else
  {
    return Build_Path( _Get_Temp_Directory( ), $DEFAULT_CACHE_ROOT );
  }
}


sub _Namespaces
{
  my ( $p_optional_cache_root ) = Static_Params( @_ );

  return _Get_Backend( $p_optional_cache_root )->get_namespaces( );
}


sub _Get_Cache
{
  my ( $p_namespace, $p_optional_cache_root ) = Static_Params( @_ );

  Assert_Defined( $p_namespace );

  if ( defined $p_optional_cache_root )
  {
    return new Cache::FileCache( { 'namespace' => $p_namespace,
                                   'cache_root' => $p_optional_cache_root } );
  }
  else
  {
    return new Cache::FileCache( { 'namespace' => $p_namespace } );
  }
}


sub _new
{
  my ( $proto, $p_options_hash_ref ) = @_;
  my $class = ref( $proto ) || $proto;

  my $self  =  $class->SUPER::_new( $p_options_hash_ref );
  $self->_initialize_file_backend( );
  return $self;
}


sub _initialize_file_backend
{
  my ( $self ) = @_;

  $self->_set_backend( new Cache::FileBackend( $self->_get_initial_root( ),
                                               $self->_get_initial_depth( ),
                                               $self->_get_initial_umask( ) ));
}


sub _get_initial_root
{
  my ( $self ) = @_;

  if ( defined $self->_read_option( 'cache_root' ) )
  {
    return $self->_read_option( 'cache_root' );
  }
  else
  {
    return Build_Path( _Get_Temp_Directory( ), $DEFAULT_CACHE_ROOT );
  }
}


sub _get_initial_depth
{
  my ( $self ) = @_;

  return $self->_read_option( 'cache_depth', $DEFAULT_CACHE_DEPTH );
}


sub _get_initial_umask
{
  my ( $self ) = @_;

  return $self->_read_option( 'directory_umask', $DEFAULT_DIRECTORY_UMASK );
}


sub get_cache_depth
{
  my ( $self ) = @_;

  return $self->_get_backend( )->get_depth( );
}


sub set_cache_depth
{
  my ( $self, $p_cache_depth ) = @_;

  $self->_get_backend( )->set_depth( $p_cache_depth );
}


sub get_cache_root
{
  my ( $self ) = @_;

  return $self->_get_backend( )->get_root( );
}


sub set_cache_root
{
  my ( $self, $p_cache_root ) = @_;

  $self->_get_backend( )->set_root( $p_cache_root );
}


sub get_directory_umask
{
  my ( $self ) = @_;

  return $self->_get_backend( )->get_directory_umask( );
}


sub set_directory_umask
{
  my ( $self, $p_directory_umask ) = @_;

  $self->_get_backend( )->set_directory_umask( $p_directory_umask );
}


1;


__END__

=pod

=head1 NAME

Cache::FileCache -- implements the Cache interface.

=head1 DESCRIPTION

The FileCache class implements the Cache interface.  This cache stores
data in the filesystem so that it can be shared between processes.

=head1 SYNOPSIS

  use Cache::FileCache;

  my $cache = new Cache::FileCache( { 'namespace' => 'MyNamespace',
                                      'default_expires_in' => 600 } );

  See Cache::Cache for the usage synopsis.

=head1 METHODS

See Cache::Cache for the API documentation.

=over

=item B<Clear( [$cache_root] )>

See Cache::Cache, with the optional I<$cache_root> parameter.

=item B<Purge( [$cache_root] )>

See Cache::Cache, with the optional I<$cache_root> parameter.

=item B<Size( [$cache_root] )>

See Cache::Cache, with the optional I<$cache_root> parameter.

=back

=head1 OPTIONS

See Cache::Cache for standard options.  Additionally, options are set
by passing in a reference to a hash containing any of the following
keys:

=over

=item I<cache_root>

The location in the filesystem that will hold the root of the cache.
Defaults to the 'FileCache' under the OS default temp directory (
often '/tmp' on UNIXes ) unless explicitly set.

=item I<cache_depth>

The number of subdirectories deep to cache object item.  This should
be large enough that no cache directory has more than a few hundred
objects.  Defaults to 3 unless explicitly set.

=item I<directory_umask>

The directories in the cache on the filesystem should be globally
writable to allow for multiple users.  While this is a potential
security concern, the actual cache entries are written with the user's
umask, thus reducing the risk of cache poisoning.  If you desire it to
only be user writable, set the 'directory_umask' option to '077' or
similar.  Defaults to '000' unless explicitly set.

=back

=head1 PROPERTIES

See Cache::Cache for default properties.

=over

=item B<(get|set)_cache_root>

See the definition above for the option I<cache_root>

=item B<(get|set)_cache_depth>

See the definition above for the option I<cache_depth>

=item B<(get|set)_directory_umask>

See the definition above for the option I<directory_umask>

=back

=head1 SEE ALSO

Cache::Cache

=head1 AUTHOR

Original author: DeWitt Clinton <dewitt@unto.net>

Last author:     $Author: andy $

Copyright (C) 2001-2003 DeWitt Clinton

=cut
