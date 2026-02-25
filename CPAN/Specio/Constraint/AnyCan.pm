package Specio::Constraint::AnyCan;

use strict;
use warnings;

our $VERSION = '0.53';

use List::Util 1.33 ();
use Role::Tiny::With;
use Scalar::Util    ();
use Specio::Helpers qw( perlstring );
use Specio::Library::Builtins;
use Specio::OO;

use Specio::Constraint::Role::CanType;
with 'Specio::Constraint::Role::CanType';

{
    my $Defined = t('Defined');
    sub _build_parent {$Defined}
}

{
    my $_inline_generator = sub {
        my $self = shift;
        my $val  = shift;

        my $methods = join ', ', map { perlstring($_) } @{ $self->methods };
        return sprintf( <<'EOF', $val, $methods );
(
    do {
        # We need to assign this since if it's something like $_[0] then
        # inside the all block @_ gets redefined and we can no longer get at
        # the value.
        my $v = %s;
        (
            Scalar::Util::blessed($v) || (
                   defined($v)
                && !ref($v)
                && length($v)
                && $v !~ /\A
                          \s*
                          -?[0-9]+(?:\.[0-9]+)?
                          (?:[Ee][\-+]?[0-9]+)?
                          \s*
                          \z/xs

                # Passing a GLOB from (my $glob = *GLOB) gives us a very weird
                # scalar. It's not a ref and it has a length but trying to
                # call ->can on it throws an exception
                && ref( \$v ) ne 'GLOB'
            )
        ) && List::Util::all { $v->can($_) } %s;
        }
    )
EOF
    };

    sub _build_inline_generator {$_inline_generator}
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _allow_classes {1}
## use critic

__PACKAGE__->_ooify;

1;

# ABSTRACT: A class for constraints which require a class name or object with a set of methods

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Constraint::AnyCan - A class for constraints which require a class name or object with a set of methods

=head1 VERSION

version 0.53

=head1 SYNOPSIS

    my $type = Specio::Constraint::AnyCan->new(...);
    print $_, "\n" for @{ $type->methods };

=head1 DESCRIPTION

This is a specialized type constraint class for types which require a class
name or object with a defined set of methods.

=head1 API

This class provides all of the same methods as L<Specio::Constraint::Simple>,
with a few differences:

=head2 Specio::Constraint::AnyCan->new( ... )

The C<parent> parameter is ignored if it passed, as it is always set to the
C<Defined> type.

The C<inline_generator> and C<constraint> parameters are also ignored. This
class provides its own default inline generator subroutine reference.

This class overrides the C<message_generator> default if none is provided.

Finally, this class requires an additional parameter, C<methods>. This must be
an array reference of method names which the constraint requires. You can also
pass a single string and it will be converted to an array reference internally.

=head2 $any_can->methods

Returns an array reference containing the methods this constraint requires.

=head1 ROLES

This class does the L<Specio::Constraint::Role::IsaType>,
L<Specio::Constraint::Role::Interface>, and L<Specio::Role::Inlinable> roles.

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
