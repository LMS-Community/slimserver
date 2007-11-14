######################################################################
# $Id: BaseCache.pm 6973 2006-04-19 03:21:06Z andy $
# Copyright (C) 2001-2003 DeWitt Clinton  All Rights Reserved
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either expressed or
# implied. See the License for the specific language governing
# rights and limitations under the License.
######################################################################


package Cache::BaseCache;


use strict;
use vars qw( @ISA );
use Cache::Cache qw( $EXPIRES_NEVER $EXPIRES_NOW );
use Cache::CacheUtils qw( Assert_Defined Clone_Data );
use Cache::Object;
use Error;


@ISA = qw( Cache::Cache );


my $DEFAULT_EXPIRES_IN = $EXPIRES_NEVER;
my $DEFAULT_NAMESPACE = "Default";
my $DEFAULT_AUTO_PURGE_ON_SET = 0;
my $DEFAULT_AUTO_PURGE_ON_GET = 0;


# namespace that stores the keys used for the auto purge functionality

my $AUTO_PURGE_NAMESPACE = "__AUTO_PURGE__";


# map of expiration formats to their respective time in seconds

my %_Expiration_Units = ( map(($_,             1), qw(s second seconds sec)),
                          map(($_,            60), qw(m minute minutes min)),
                          map(($_,         60*60), qw(h hour hours)),
                          map(($_,      60*60*24), qw(d day days)),
                          map(($_,    60*60*24*7), qw(w week weeks)),
                          map(($_,   60*60*24*30), qw(M month months)),
                          map(($_,  60*60*24*365), qw(y year years)) );



# Takes the time the object was created, the default_expires_in and
# optionally the explicitly set expires_in and returns the time the
# object will expire. Calls _canonicalize_expiration to convert
# strings like "5m" into second values.

sub Build_Expires_At
{
  my ( $p_created_at, $p_default_expires_in, $p_explicit_expires_in ) = @_;

  my $expires_in = defined $p_explicit_expires_in ?
    $p_explicit_expires_in : $p_default_expires_in;

  return Sum_Expiration_Time( $p_created_at, $expires_in );
}


# Return a Cache::Object object

sub Build_Object
{
  my ( $p_key, $p_data, $p_default_expires_in, $p_expires_in ) = @_;

  Assert_Defined( $p_key );
  Assert_Defined( $p_default_expires_in );

  my $now = time( );

  my $object = new Cache::Object( );

  $object->set_key( $p_key );
  $object->set_data( $p_data );
  $object->set_created_at( $now );
  $object->set_accessed_at( $now );
  $object->set_expires_at( Build_Expires_At( $now,
                                             $p_default_expires_in,
                                             $p_expires_in ) );
  return $object;
}


# Compare the expires_at to the current time to determine whether or
# not an object has expired (the time parameter is optional)

sub Object_Has_Expired
{
  my ( $p_object, $p_time ) = @_;

  if ( not defined $p_object )
  {
    return 1;
  }

  $p_time = $p_time || time( );

  if ( $p_object->get_expires_at( ) eq $EXPIRES_NOW )
  {
    return 1;
  }
  elsif ( $p_object->get_expires_at( ) eq $EXPIRES_NEVER )
  {
    return 0;
  }
  elsif ( $p_time >= $p_object->get_expires_at( ) )
  {
    return 1;
  }
  else
  {
    return 0;
  }
}


# Returns the sum of the  base created_at time (in seconds since the epoch)
# and the canonical form of the expires_at string


sub Sum_Expiration_Time
{
  my ( $p_created_at, $p_expires_in ) = @_;

  Assert_Defined( $p_created_at );
  Assert_Defined( $p_expires_in );

  if ( $p_expires_in eq $EXPIRES_NEVER )
  {
    return $EXPIRES_NEVER;
  }
  else
  {
    return $p_created_at + Canonicalize_Expiration_Time( $p_expires_in );
  }
}


# turn a string in the form "[number] [unit]" into an explicit number
# of seconds from the present.  E.g, "10 minutes" returns "600"

sub Canonicalize_Expiration_Time
{
  my ( $p_expires_in ) = @_;

  Assert_Defined( $p_expires_in );

  my $secs;

  if ( uc( $p_expires_in ) eq uc( $EXPIRES_NOW ) )
  {
    $secs = 0;
  }
  elsif ( uc( $p_expires_in ) eq uc( $EXPIRES_NEVER ) )
  {
    throw Error::Simple( "Internal error.  expires_in eq $EXPIRES_NEVER" );
  }
  elsif ( $p_expires_in =~ /^\s*([+-]?(?:\d+|\d*\.\d*))\s*$/ )
  {
    $secs = $p_expires_in;
  }
  elsif ( $p_expires_in =~ /^\s*([+-]?(?:\d+|\d*\.\d*))\s*(\w*)\s*$/
          and exists( $_Expiration_Units{ $2 } ))
  {
    $secs = ( $_Expiration_Units{ $2 } ) * $1;
  }
  else
  {
    throw Error::Simple( "invalid expiration time '$p_expires_in'" );
  }

  return $secs;
}



sub clear
{
  my ( $self ) = @_;

  $self->_get_backend( )->delete_namespace( $self->get_namespace( ) );
}


sub get
{
  my ( $self, $p_key ) = @_;

  Assert_Defined( $p_key );

  $self->_conditionally_auto_purge_on_get( );

  my $object = $self->get_object( $p_key ) or
    return undef;

  if ( Object_Has_Expired( $object ) )
  {
    $self->remove( $p_key );
    return undef;
  }

  return $object->get_data( );
}


sub get_keys
{
  my ( $self ) = @_;

  return $self->_get_backend( )->get_keys( $self->get_namespace( ) );
}


sub get_identifiers
{
  my ( $self ) = @_;

  warn( "get_identifiers has been marked deprepricated.  use get_keys" );

  return $self->get_keys( );
}


sub get_object
{
  my ( $self, $p_key ) = @_;

  Assert_Defined( $p_key );

  my $object =
    $self->_get_backend( )->restore( $self->get_namespace( ), $p_key ) or
      return undef;

  $object->set_size( $self->_get_backend( )->
                     get_size( $self->get_namespace( ), $p_key ) );

  $object->set_key( $p_key );

  return $object;
}


sub purge
{
  my ( $self ) = @_;

  foreach my $key ( $self->get_keys( ) )
  {
    $self->get( $key );
  }
}


sub remove
{
  my ( $self, $p_key ) = @_;

  Assert_Defined( $p_key );

  $self->_get_backend( )->delete_key( $self->get_namespace( ), $p_key );
}


sub set
{
  my ( $self, $p_key, $p_data, $p_expires_in ) = @_;

  Assert_Defined( $p_key );

  $self->_conditionally_auto_purge_on_set( );

  $self->set_object( $p_key,
                     Build_Object( $p_key,
                                   $p_data,
                                   $self->get_default_expires_in( ),
                                   $p_expires_in ) );
}


sub set_object
{
  my ( $self, $p_key, $p_object ) = @_;

  my $object = Clone_Data( $p_object );

  $object->set_size( undef );
  $object->set_key( undef );

  $self->_get_backend( )->store( $self->get_namespace( ), $p_key, $object );
}


sub size
{
  my ( $self ) = @_;

  my $size = 0;

  foreach my $key ( $self->get_keys( ) )
  {
    $size += $self->_get_backend( )->get_size( $self->get_namespace( ), $key );
  }

  return $size;
}


sub get_namespaces
{
  my ( $self ) = @_;

  return $self->_get_backend( )->get_namespaces( );
}


sub _new
{
  my ( $proto, $p_options_hash_ref ) = @_;
  my $class = ref( $proto ) || $proto;
  my $self  = {};
  bless( $self, $class );
  $self->_initialize_base_cache( $p_options_hash_ref );
  return $self;
}


sub _complete_initialization
{
  my ( $self ) = @_;
  $self->_initialize_auto_purge_interval( );
}


sub _initialize_base_cache
{
  my ( $self, $p_options_hash_ref ) = @_;

  $self->_initialize_options_hash_ref( $p_options_hash_ref );
  $self->_initialize_namespace( );
  $self->_initialize_default_expires_in( );
  $self->_initialize_auto_purge_on_set( );
  $self->_initialize_auto_purge_on_get( );
}


sub _initialize_options_hash_ref
{
  my ( $self, $p_options_hash_ref ) = @_;

  $self->_set_options_hash_ref( defined $p_options_hash_ref ?
                                $p_options_hash_ref :
                                { } );
}


sub _initialize_namespace
{
  my ( $self ) = @_;

  my $namespace = $self->_read_option( 'namespace', $DEFAULT_NAMESPACE );

  $self->set_namespace( $namespace );
}


sub _initialize_default_expires_in
{
  my ( $self ) = @_;

  my $default_expires_in =
    $self->_read_option( 'default_expires_in', $DEFAULT_EXPIRES_IN );

  $self->_set_default_expires_in( $default_expires_in );
}


sub _initialize_auto_purge_interval
{
  my ( $self ) = @_;

  my $auto_purge_interval = $self->_read_option( 'auto_purge_interval' );

  if ( defined $auto_purge_interval )
  {
    $self->set_auto_purge_interval( $auto_purge_interval );
    $self->_auto_purge( );
  }
}


sub _initialize_auto_purge_on_set
{
  my ( $self ) = @_;

  my $auto_purge_on_set =
    $self->_read_option( 'auto_purge_on_set', $DEFAULT_AUTO_PURGE_ON_SET );

  $self->set_auto_purge_on_set( $auto_purge_on_set );
}


sub _initialize_auto_purge_on_get
{
  my ( $self ) = @_;

  my $auto_purge_on_get =
    $self->_read_option( 'auto_purge_on_get', $DEFAULT_AUTO_PURGE_ON_GET );

  $self->set_auto_purge_on_get( $auto_purge_on_get );
}



# _read_option looks for an option named 'option_name' in the
# option_hash associated with this instance.  If it is not found, then
# 'default_value' will be returned instead

sub _read_option
{
  my ( $self, $p_option_name, $p_default_value ) = @_;

  my $options_hash_ref = $self->_get_options_hash_ref( );

  if ( defined $options_hash_ref->{ $p_option_name } )
  {
    return $options_hash_ref->{ $p_option_name };
  }
  else
  {
    return $p_default_value;
  }
}



# this method checks to see if the auto_purge property is set for a
# particular cache.  If it is, then it switches the cache to the
# $AUTO_PURGE_NAMESPACE and stores that value under the name of the
# current cache namespace

sub _reset_auto_purge_interval
{
  my ( $self ) = @_;

  return if not $self->_should_auto_purge( );

  my $real_namespace = $self->get_namespace( );

  $self->set_namespace( $AUTO_PURGE_NAMESPACE );

  if ( not defined $self->get( $real_namespace ) )
  {
    $self->_insert_auto_purge_object( $real_namespace );
  }

  $self->set_namespace( $real_namespace );
}


sub _should_auto_purge
{
  my ( $self ) = @_;

  return ( defined $self->get_auto_purge_interval( ) &&
           $self->get_auto_purge_interval( ) ne $EXPIRES_NEVER );
}

sub _insert_auto_purge_object
{
  my ( $self, $p_real_namespace ) = @_;

  my $object = Build_Object( $p_real_namespace,
                             1,
                             $self->get_auto_purge_interval( ),
                             undef );

  $self->set_object( $p_real_namespace, $object );
}



# this method checks to see if the auto_purge property is set, and if
# it is, switches to the $AUTO_PURGE_NAMESPACE and sees if a value
# exists at the location specified by a key named for the current
# namespace.  If that key doesn't exist, then the purge method is
# called on the cache

sub _auto_purge
{
  my ( $self ) = @_;

  if ( $self->_needs_auto_purge( ) )
  {
    $self->purge( );
    $self->_reset_auto_purge_interval( );
  }
}


sub _get_auto_purge_object
{
  my ( $self ) = @_;

  my $real_namespace = $self->get_namespace( );
  $self->set_namespace( $AUTO_PURGE_NAMESPACE );
  my $auto_purge_object = $self->get_object( $real_namespace );
  $self->set_namespace( $real_namespace );
  return $auto_purge_object;
}


sub _needs_auto_purge
{
  my ( $self ) = @_;

  return ( $self->_should_auto_purge( ) &&
           Object_Has_Expired( $self->_get_auto_purge_object( ) ) );
}


# call auto_purge if the auto_purge_on_set option is true

sub _conditionally_auto_purge_on_set
{
  my ( $self ) = @_;

  if ( $self->get_auto_purge_on_set( ) )
  {
    $self->_auto_purge( );
  }
}


# call auto_purge if the auto_purge_on_get option is true

sub _conditionally_auto_purge_on_get
{
  my ( $self ) = @_;

  if ( $self->get_auto_purge_on_get( ) )
  {
    $self->_auto_purge( );
  }
}


sub _get_options_hash_ref
{
  my ( $self ) = @_;

  return $self->{_Options_Hash_Ref};
}


sub _set_options_hash_ref
{
  my ( $self, $options_hash_ref ) = @_;

  $self->{_Options_Hash_Ref} = $options_hash_ref;
}


sub get_namespace
{
  my ( $self ) = @_;

  return $self->{_Namespace};
}


sub set_namespace
{
  my ( $self, $namespace ) = @_;

  $self->{_Namespace} = $namespace;
}


sub get_default_expires_in
{
  my ( $self ) = @_;

  return $self->{_Default_Expires_In};
}


sub _set_default_expires_in
{
  my ( $self, $default_expires_in ) = @_;

  $self->{_Default_Expires_In} = $default_expires_in;
}


sub get_auto_purge_interval
{
  my ( $self ) = @_;

  return $self->{_Auto_Purge_Interval};
}


sub set_auto_purge_interval
{
  my ( $self, $auto_purge_interval ) = @_;

  $self->{_Auto_Purge_Interval} = $auto_purge_interval;

  $self->_reset_auto_purge_interval( );
}


sub get_auto_purge_on_set
{
  my ( $self ) = @_;

  return $self->{_Auto_Purge_On_Set};
}


sub set_auto_purge_on_set
{
  my ( $self, $auto_purge_on_set ) = @_;

  $self->{_Auto_Purge_On_Set} = $auto_purge_on_set;
}


sub get_auto_purge_on_get
{
  my ( $self ) = @_;

  return $self->{_Auto_Purge_On_Get};
}


sub set_auto_purge_on_get
{
  my ( $self, $auto_purge_on_get ) = @_;

  $self->{_Auto_Purge_On_Get} = $auto_purge_on_get;
}


sub _get_backend
{
  my ( $self ) = @_;

  return $self->{ _Backend };
}


sub _set_backend
{
  my ( $self, $p_backend ) = @_;

  $self->{ _Backend } = $p_backend;
}



1;


__END__


=pod

=head1 NAME

Cache::BaseCache -- abstract cache base class

=head1 DESCRIPTION

BaseCache provides functionality common to all instances of a cache.
It differes from the CacheUtils package insofar as it is designed to
be used as superclass for cache implementations.

=head1 SYNOPSIS

Cache::BaseCache is to be used as a superclass for cache
implementations.  The most effective way to use BaseCache is to use
the protected _set_backend method, which will be used to retrieve the
persistance mechanism.  The subclass can then inherit the BaseCache's
implentation of get, set, etc.  However, due to the difficulty
inheriting static methods in Perl, the subclass will likely need to
explicitly implement Clear, Purge, and Size.  Also, a factory pattern
should be used to invoke the _complete_initialization routine after
the object is constructed.


  package Cache::MyCache;

  use vars qw( @ISA );
  use Cache::BaseCache;
  use Cache::MyBackend;

  @ISA = qw( Cache::BaseCache );

  sub new
  {
    my ( $self ) = _new( @_ );

    $self->_complete_initialization( );

    return $self;
  }

  sub _new
  {
    my ( $proto, $p_options_hash_ref ) = @_;
    my $class = ref( $proto ) || $proto;
    my $self = $class->SUPER::_new( $p_options_hash_ref );
    $self->_set_backend( new Cache::MyBackend( ) );
    return $self;
  }


  sub Clear
  {
    foreach my $namespace ( _Namespaces( ) )
    {
      _Get_Backend( )->delete_namespace( $namespace );
    }
  }


  sub Purge
  {
    foreach my $namespace ( _Namespaces( ) )
    {
      _Get_Cache( $namespace )->purge( );
    }
  }


  sub Size
  {
    my $size = 0;

    foreach my $namespace ( _Namespaces( ) )
    {
      $size += _Get_Cache( $namespace )->size( );
    }

    return $size;
  }


=head1 SEE ALSO

Cache::Cache, Cache::FileCache, Cache::MemoryCache

=head1 AUTHOR

Original author: DeWitt Clinton <dewitt@unto.net>

Last author:     $Author: andy $

Copyright (C) 2001-2003 DeWitt Clinton

=cut
