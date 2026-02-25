package Specio::Constraint::ObjectCan;

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
    my $Object = t('Object');
    sub _build_parent {$Object}
}

{
    my $_inline_generator = sub {
        my $self = shift;
        my $val  = shift;

        my $methods = join ', ', map { perlstring($_) } @{ $self->methods };
        return sprintf( <<'EOF', $val, $methods );
(
    do {
        my $v = %s;
        Scalar::Util::blessed($v)
            && List::Util::all { $v->can($_) } %s;
        }
    )
EOF
    };

    sub _build_inline_generator {$_inline_generator}
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _allow_classes {0}
## use critic

__PACKAGE__->_ooify;

1;

# ABSTRACT: A class for constraints which require an object with a set of methods

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Constraint::ObjectCan - A class for constraints which require an object with a set of methods

=head1 VERSION

version 0.53

=head1 SYNOPSIS

    my $type = Specio::Constraint::ObjectCan->new(...);
    print $_, "\n" for @{ $type->methods };

=head1 DESCRIPTION

This is a specialized type constraint class for types which require an object
with a defined set of methods.

=head1 API

This class provides all of the same methods as L<Specio::Constraint::Simple>,
with a few differences:

=head2 Specio::Constraint::ObjectCan->new( ... )

The C<parent> parameter is ignored if it passed, as it is always set to the
C<Object> type.

The C<inline_generator> and C<constraint> parameters are also ignored. This
class provides its own default inline generator subroutine reference.

This class overrides the C<message_generator> default if none is provided.

Finally, this class requires an additional parameter, C<methods>. This must be
an array reference of method names which the constraint requires. You can also
pass a single string and it will be converted to an array reference internally.

=head2 $object_can->methods

Returns an array reference containing the methods this constraint requires.

=head1 ROLES

This class does the L<Specio::Constraint::Role::CanType>,
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
