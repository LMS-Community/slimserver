package Specio::Registry;

use strict;
use warnings;

use parent 'Exporter';

our $VERSION = '0.53';

use Carp qw( confess croak );

our @EXPORT_OK
    = qw( exportable_types_for_package internal_types_for_package register );

my %Registry;

sub register {
    confess
        'register requires three or four arguments (package, name, type, [exportable])'
        unless @_ == 3 || @_ == 4;

    my $package    = shift;
    my $name       = shift;
    my $type       = shift;
    my $exportable = shift;

    croak "The $package package already has a type named $name"
        if $Registry{$package}{internal}{$name};

    # This is structured so that we can always return a _reference_ for
    # *_types_for_package. This means that the generated t sub sees any
    # changes to the registry as they happen. This is important inside a
    # package that is declaring new types. It needs to be able to see types it
    # has declared.
    $Registry{$package}{internal}{$name}   = $type;
    $Registry{$package}{exportable}{$name} = $type
        if $exportable;

    return;
}

sub exportable_types_for_package {
    my $package = shift;

    return $Registry{$package}{exportable} ||= {};
}

sub internal_types_for_package {
    my $package = shift;

    return $Registry{$package}{internal} ||= {};
}

1;

# ABSTRACT: Implements the per-package type registry

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Registry - Implements the per-package type registry

=head1 VERSION

version 0.53

=head1 DESCRIPTION

There's nothing public here.

=for Pod::Coverage .*

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/Specio/issues>.

=head1 SOURCE

The source code repository for Specio can be found at L<https://github.com/houseabsolute/Specio>.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2012 - 2025 by Dave Rolsky.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
