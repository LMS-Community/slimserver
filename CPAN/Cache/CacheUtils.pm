######################################################################
# $Id: CacheUtils.pm 6973 2006-04-19 03:21:06Z andy $
# Copyright (C) 2001-2003 DeWitt Clinton  All Rights Reserved
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either expressed or
# implied. See the License for the specific language governing
# rights and limitations under the License.
######################################################################

package Cache::CacheUtils;

use strict;
use vars qw( @ISA @EXPORT_OK );
use Cache::Cache;
use Error;
use Exporter;
use File::Spec;
use Storable qw( nfreeze thaw dclone );

@ISA = qw( Exporter );

@EXPORT_OK = qw( Assert_Defined
                 Build_Path
                 Clone_Data
                 Freeze_Data
                 Static_Params
                 Thaw_Data );

use vars ( @EXPORT_OK );


# throw an Exception if the Assertion fails

sub Assert_Defined
{
  if ( not defined $_[0] )
  {
    my ( $package, $filename, $line ) = caller( );
    throw Error::Simple( "Assert_Defined failed: $package line $line\n" );
  }
}


# Take a list of directory components and create a valid path

sub Build_Path
{
  my ( @p_elements ) = @_;

  # TODO: add this to Untaint_Path or something
  #  ( $p_unique_key !~ m|[0-9][a-f][A-F]| ) or
  #  throw Error::Simple( "key '$p_unique_key' contains illegal characters'" );

  if ( grep ( /\.\./, @p_elements ) )
  {
    throw Error::Simple( "Illegal path characters '..'" );
  }

  return File::Spec->catfile( @p_elements );
}


# use Storable to clone an object

sub Clone_Data
{
  my ( $p_object  ) = @_;

  return defined $p_object ? dclone( $p_object ) : undef;
}


# use Storable to freeze an object

sub Freeze_Data
{
  my ( $p_object  ) = @_;

  return defined $p_object ? nfreeze( $p_object ) : undef;
}


# Take a parameter list and automatically shift it such that if
# the method was called as a static method, then $self will be
# undefined.  This allows the use to write
#
#   sub Static_Method
#   {
#     my ( $parameter ) = Static_Params( @_ );
#   }
#
# and not worry about whether it is called as:
#
#   Class->Static_Method( $param );
#
# or
#
#   Class::Static_Method( $param );


sub Static_Params
{
  my $type = ref $_[0];

  if ( $type and ( $type !~ /^(SCALAR|ARRAY|HASH|CODE|REF|GLOB|LVALUE)$/ ) )
  {
    shift( @_ );
  }

  return @_;
}


# use Storable to thaw an object

sub Thaw_Data
{
  my ( $p_frozen_object ) = @_;

  return defined $p_frozen_object ? thaw( $p_frozen_object ) : undef;
}


1;


__END__

=pod

=head1 NAME

Cache::CacheUtils -- miscellaneous utility routines

=head1 DESCRIPTION

The CacheUtils package is a collection of static methods that provide
functionality useful to many different classes.

=head1 AUTHOR

Original author: DeWitt Clinton <dewitt@unto.net>

Last author:     $Author: andy $

Copyright (C) 2001-2003 DeWitt Clinton

=cut

