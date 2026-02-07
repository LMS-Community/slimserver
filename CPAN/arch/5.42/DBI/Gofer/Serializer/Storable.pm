package DBI::Gofer::Serializer::Storable;

use strict;
use warnings;

use base qw(DBI::Gofer::Serializer::Base);

#   $Id: Storable.pm 15585 2013-03-22 20:31:22Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

=head1 NAME

DBI::Gofer::Serializer::Storable - Gofer serialization using Storable

=head1 SYNOPSIS

    $serializer = DBI::Gofer::Serializer::Storable->new();

    $string = $serializer->serialize( $data );
    ($string, $deserializer_class) = $serializer->serialize( $data );

    $data = $serializer->deserialize( $string );

=head1 DESCRIPTION

Uses Storable::nfreeze() to serialize and Storable::thaw() to deserialize.

The serialize() method sets local $Storable::forgive_me = 1; so it doesn't
croak if it encounters any data types that can't be serialized, such as code refs.

See also L<DBI::Gofer::Serializer::Base>.

=cut

use Storable qw(nfreeze thaw);

our $VERSION = "0.015586";

use base qw(DBI::Gofer::Serializer::Base);


sub serialize {
    my $self = shift;
    local $Storable::forgive_me = 1; # for CODE refs etc
    local $Storable::canonical = 1; # for go_cache
    my $frozen = nfreeze(shift);
    return $frozen unless wantarray;
    return ($frozen, $self->{deserializer_class});
}

sub deserialize {
    my $self = shift;
    return thaw(shift);
}

1;
