package Specio::PartialDump;

use strict;
use warnings;

our $VERSION = '0.53';

use Scalar::Util qw( looks_like_number reftype blessed );

use Exporter qw( import );

our @EXPORT_OK = qw( partial_dump );

my $MaxLength   = 100;
my $MaxElements = 6;
my $MaxDepth    = 2;

sub partial_dump {
    my (@args) = @_;

    my $dump
        = _should_dump_as_pairs(@args)
        ? _dump_as_pairs( 1, @args )
        : _dump_as_list( 1, @args );

    if ( length($dump) > $MaxLength ) {
        my $max_length = $MaxLength - 3;
        $max_length = 0 if $max_length < 0;
        substr( $dump, $max_length, length($dump) - $max_length ) = '...';
    }

    return $dump;
}

sub _should_dump_as_pairs {
    my (@what) = @_;

    return if @what % 2 != 0;    # must be an even list

    for ( my $i = 0; $i < @what; $i += 2 ) {
        return if ref $what[$i];    # plain strings are keys
    }

    return 1;
}

sub _dump_as_pairs {
    my ( $depth, @what ) = @_;

    my $truncated;
    if ( defined $MaxElements and ( @what / 2 ) > $MaxElements ) {
        $truncated = 1;
        @what      = splice( @what, 0, $MaxElements * 2 );
    }

    return join(
        ', ', _dump_as_pairs_recursive( $depth, @what ),
        ( $truncated ? "..." : () )
    );
}

sub _dump_as_pairs_recursive {
    my ( $depth, @what ) = @_;

    return unless @what;

    my ( $key, $value, @rest ) = @what;

    return (
        ( _format_key( $depth, $key ) . ': ' . _format( $depth, $value ) ),
        _dump_as_pairs_recursive( $depth, @rest ),
    );
}

sub _dump_as_list {
    my ( $depth, @what ) = @_;

    my $truncated;
    if ( @what > $MaxElements ) {
        $truncated = 1;
        @what      = splice( @what, 0, $MaxElements );
    }

    return join(
        ', ', ( map { _format( $depth, $_ ) } @what ),
        ( $truncated ? "..." : () )
    );
}

sub _format {
    my ( $depth, $value ) = @_;

    defined($value)
        ? (
        ref($value)
        ? (
              blessed($value)
            ? _format_object( $depth, $value )
            : _format_ref( $depth, $value )
            )
        : (
              looks_like_number($value)
            ? _format_number( $depth, $value )
            : _format_string( $depth, $value )
        )
        )
        : _format_undef( $depth, $value ),;
}

sub _format_key {
    my ( undef, $key ) = @_;
    return $key;
}

sub _format_ref {
    my ( $depth, $ref ) = @_;

    if ( $depth > $MaxDepth ) {
        return overload::StrVal($ref);
    }
    else {
        my $reftype = reftype($ref);
        $reftype = 'SCALAR'
            if $reftype eq 'REF' || $reftype eq 'LVALUE';
        my $method = "_format_" . lc $reftype;

        if ( my $sub = __PACKAGE__->can($method) ) {
            return $sub->( $depth, $ref );
        }
        else {
            return overload::StrVal($ref);
        }
    }
}

sub _format_array {
    my ( $depth, $array ) = @_;

    my $class = blessed($array) || '';
    $class .= "=" if $class;

    return $class . "[ " . _dump_as_list( $depth + 1, @$array ) . " ]";
}

sub _format_hash {
    my ( $depth, $hash ) = @_;

    my $class = blessed($hash) || '';
    $class .= "=" if $class;

    return $class . "{ " . _dump_as_pairs(
        $depth + 1,
        map { $_ => $hash->{$_} } sort keys %$hash
    ) . " }";
}

sub _format_scalar {
    my ( $depth, $scalar ) = @_;

    my $class = blessed($scalar) || '';
    $class .= "=" if $class;

    return $class . "\\" . _format( $depth + 1, $$scalar );
}

sub _format_object {
    my ( $depth, $object ) = @_;

    return _format_ref( $depth, $object );
}

sub _format_string {
    my ( undef, $str ) = @_;

    # FIXME use String::Escape ?

    # remove vertical whitespace
    $str =~ s/\n/\\n/g;
    $str =~ s/\r/\\r/g;

    # reformat nonprintables
    $str =~ s/(\P{IsPrint})/"\\x{" . sprintf("%x", ord($1)) . "}"/ge;

    _quote($str);
}

sub _quote {
    my ($str) = @_;

    qq{"$str"};
}

sub _format_undef {"undef"}

sub _format_number {
    my ( undef, $value ) = @_;
    return "$value";
}

# ABSTRACT: A partially rear-ended copy of Devel::PartialDump without prereqs

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::PartialDump - A partially rear-ended copy of Devel::PartialDump without prereqs

=head1 VERSION

version 0.53

=head1 SYNOPSIS

  use Specio::PartialDump qw( partial_dump );

  partial_dump( { foo => 42 } );
  partial_dump(qw( a b c d e f g ));
  partial_dump( foo => 42, bar => [ 1, 2, 3 ], );

=head1 DESCRIPTION

This is a copy of Devel::PartialDump with all the OO bits and prereqs
removed. You may want to use this module in your own code to generate nicely
formatted messages when a type constraint fails.

This module optionally exports one sub, C<partial_dump>. This sub accepts any
number of arguments. If given more than one, it will assume that it's either
been given a list of key/value pairs (to build a hash) or a list of values (to
build an array) and dump them appropriately. Objects and references are
stringified in a sane way.

=for Pod::Coverage partial_dump

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/Specio/issues>.

=head1 SOURCE

The source code repository for Specio can be found at L<https://github.com/houseabsolute/Specio>.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2008 by יובל קוג'מן (Yuval Kogman).

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
