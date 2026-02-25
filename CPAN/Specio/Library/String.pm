package Specio::Library::String;

use strict;
use warnings;

our $VERSION = '0.53';

use parent 'Specio::Exporter';

use Specio::Declare;
use Specio::Library::Builtins;

declare(
    'NonEmptySimpleStr',
    parent => t('Str'),
    inline => sub {
        return
            sprintf(
            <<'EOF', $_[0]->parent->inline_check( $_[1] ), ( $_[1] ) x 3 );
(
    %s
    &&
    length %s > 0
    &&
    length %s <= 255
    &&
    %s !~ /[\n\r\x{2028}\x{2029}]/
)
EOF
    },
);

declare(
    'NonEmptyStr',
    parent => t('Str'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    length %s
)
EOF
    },
);

declare(
    'SimpleStr',
    parent => t('Str'),
    inline => sub {
        return
            sprintf(
            <<'EOF', $_[0]->parent->inline_check( $_[1] ), ( $_[1] ) x 2 );
(
    %s
    &&
    length %s <= 255
    &&
    %s !~ /[\n\r\x{2028}\x{2029}]/
)
EOF
    },
);

1;

# ABSTRACT: Implements type constraint objects for some common string types

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Library::String - Implements type constraint objects for some common string types

=head1 VERSION

version 0.53

=head1 DESCRIPTION

This library provides some additional string types for common cases.

=head2 NonEmptyStr

A string which has at least one character.

=head2 SimpleStr

A string that is 255 characters or less with no vertical whitespace characters.

=head2 NonEmptySimpleStr

A non-empty string that is 255 characters or less with no vertical whitespace
characters.

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
