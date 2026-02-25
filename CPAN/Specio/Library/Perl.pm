package Specio::Library::Perl;

use strict;
use warnings;

our $VERSION = '0.53';

use parent 'Specio::Exporter';

use Specio::Library::String;
use version 0.83 ();

use Specio::Declare;

my $package_inline = sub {
    return sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    %s =~ /\A[^\W\d]\w*(?:::\w+)*\z/
)
EOF
};

declare(
    'PackageName',
    parent => t('NonEmptyStr'),
    inline => $package_inline,
);

declare(
    'ModuleName',
    parent => t('NonEmptyStr'),
    inline => $package_inline,
);

declare(
    'DistName',
    parent => t('NonEmptyStr'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    %s =~ /\A[^\W\d]\w*(?:-\w+)*\z/
)
EOF
    },
);

declare(
    'Identifier',
    parent => t('NonEmptyStr'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    %s =~ /\A[^\W\d]\w*\z/
)
EOF
    },
);

declare(
    'SafeIdentifier',
    parent => t('Identifier'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    %s !~ /\A[_ab]\z/
)
EOF
    },
);

declare(
    'LaxVersionStr',
    parent => t('NonEmptyStr'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    version::is_lax(%s)
)
EOF
    },
);

declare(
    'StrictVersionStr',
    parent => t('NonEmptyStr'),
    inline => sub {
        return
            sprintf( <<'EOF', $_[0]->parent->inline_check( $_[1] ), $_[1] );
(
    %s
    &&
    version::is_strict(%s)
)
EOF
    },
);

1;

# ABSTRACT: Implements type constraint objects for some common Perl language things

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Library::Perl - Implements type constraint objects for some common Perl language things

=head1 VERSION

version 0.53

=head1 DESCRIPTION

This library provides some additional string types for common cases.

=head2 PackageName

A valid package name. Unlike the C<ClassName> constraint from the
L<Specio::Library::Builtins> library, this package does not need to be loaded.

This type does allow Unicode characters.

=head2 ModuleName

Same as C<PackageName>.

=head2 DistName

A valid distribution name like C<DBD-Pg> Basically this is the same as a
package name with the double-colons replaced by dashes. Note that there are
some historical distribution names that don't fit this pattern, like C<CGI.pm>.

This type does allow Unicode characters.

=head2 Identifier

An L<Identifier|perldata/Variable names> is something that could be used as a
symbol name or other identifier (filehandle, directory handle, subroutine name,
format name, or label). It's what you put after the sigil (dollar sign, at
sign, percent sign) in a variable name. Generally, it's a bunch of word
characters not starting with a digit.

This type does allow Unicode characters.

=head2 SafeIdentifier

This is just like an C<Identifier> but it excludes the single-character
variables underscore (C<_>), C<a>< and C<b>, as these are special variables to
the Perl interpreter.

=head2 LaxVersionStr and StrictVersionStr

Lax and strict version strings use the L<is_lax|version/is_lax> and
L<is_strict|version/is_strict> methods from C<version> to check if the given
string would be a valid lax or strict version. L<version::Internals> covers the
details but basically: lax versions are everything you may do, and strict omit
many of the usages best avoided.

=head2 CREDITS

Much of the code and docs for this library comes from MooseX::Types::Perl,
written by Ricardo SIGNES <rjbs@cpan.org>.

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
