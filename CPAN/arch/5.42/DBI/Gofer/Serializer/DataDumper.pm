package DBI::Gofer::Serializer::DataDumper;

use strict;
use warnings;

our $VERSION = "0.009950";

#   $Id: DataDumper.pm 9949 2007-09-18 09:38:15Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

=head1 NAME

DBI::Gofer::Serializer::DataDumper - Gofer serialization using DataDumper

=head1 SYNOPSIS

    $serializer = DBI::Gofer::Serializer::DataDumper->new();

    $string = $serializer->serialize( $data );

=head1 DESCRIPTION

Uses DataDumper to serialize. Deserialization is not supported.
The output of this class is only meant for human consumption.

See also L<DBI::Gofer::Serializer::Base>.

=cut

use Data::Dumper;

use base qw(DBI::Gofer::Serializer::Base);


sub serialize {
    my $self = shift;
    local $Data::Dumper::Indent    = 1;
    local $Data::Dumper::Terse     = 1;
    local $Data::Dumper::Useqq     = 0; # enabling this disables xs
    local $Data::Dumper::Sortkeys  = 1;
    local $Data::Dumper::Quotekeys = 0;
    local $Data::Dumper::Deparse   = 0;
    local $Data::Dumper::Purity    = 0;
    my $frozen = Data::Dumper::Dumper(shift);
    return $frozen unless wantarray;
    return ($frozen, $self->{deserializer_class});
}

1;
