package DBI::Gofer::Serializer::Base;

#   $Id: Base.pm 9949 2007-09-18 09:38:15Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

=head1 NAME

DBI::Gofer::Serializer::Base - base class for Gofer serialization

=head1 SYNOPSIS

    $serializer = $serializer_class->new();

    $string = $serializer->serialize( $data );
    ($string, $deserializer_class) = $serializer->serialize( $data );

    $data = $serializer->deserialize( $string );

=head1 DESCRIPTION

DBI::Gofer::Serializer::* classes implement a very minimal subset of the L<Data::Serializer> API.

Gofer serializers are expected to be very fast and are not required to deal
with anything other than non-blessed references to arrays and hashes, and plain scalars.

=cut


use strict;
use warnings;

use Carp qw(croak);

our $VERSION = "0.009950";


sub new {
    my $class = shift;
    my $deserializer_class = $class->deserializer_class;
    return bless { deserializer_class => $deserializer_class } => $class;
}

sub deserializer_class {
    my $self = shift;
    my $class = ref($self) || $self;
    $class =~ s/^DBI::Gofer::Serializer:://;
    return $class;
}

sub serialize {
    my $self = shift;
    croak ref($self)." has not implemented the serialize method";
}

sub deserialize {
    my $self = shift;
    croak ref($self)." has not implemented the deserialize method";
}

1;
