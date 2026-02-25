package Specio::Library::Numeric;

use strict;
use warnings;

our $VERSION = '0.53';

use parent 'Specio::Exporter';

use Specio::Declare;
use Specio::Library::Builtins;

declare(
    'PositiveNum',
    parent => t('Num'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    %s > 0
)
EOF
    },
);

declare(
    'PositiveOrZeroNum',
    parent => t('Num'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    %s >= 0
)
EOF
    },
);

declare(
    'PositiveInt',
    parent => t('Int'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    %s > 0
)
EOF
    },
);

declare(
    'PositiveOrZeroInt',
    parent => t('Int'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    %s >= 0
)
EOF
    },
);

declare(
    'NegativeNum',
    parent => t('Num'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    %s < 0
)
EOF
    },
);

declare(
    'NegativeOrZeroNum',
    parent => t('Num'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    %s <= 0
)
EOF
    },
);

declare(
    'NegativeInt',
    parent => t('Int'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    %s < 0
)
EOF
    },
);

declare(
    'NegativeOrZeroInt',
    parent => t('Int'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    %s <= 0
)
EOF
    },
);

declare(
    'SingleDigit',
    parent => t('Int'),
    inline => sub {
        return
            sprintf(
            <<'EOF', $_[0]->parent->inline_check( $_[1] ), ( $_[1] ) x 2 );
(
    %s
    &&
    %s >= -9
    &&
    %s <= 9
)
EOF
    },
);

1;

# ABSTRACT: Implements type constraint objects for some common numeric types

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Library::Numeric - Implements type constraint objects for some common numeric types

=head1 VERSION

version 0.53

=head1 DESCRIPTION

This library provides some additional string numeric for common cases.

=head2 PositiveNum

=head2 PositiveOrZeroNum

=head2 PositiveInt

=head2 PositiveOrZeroInt

=head2 NegativeNum

=head2 NegativeOrZeroNum

=head2 NegativeInt

=head2 NegativeOrZeroInt

=head2 SingleDigit

A single digit from -9 to 9.

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
