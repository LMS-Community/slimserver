package Specio::Constraint::Parameterizable;

use strict;
use warnings;

our $VERSION = '0.53';

use Carp qw( confess );
use Role::Tiny::With;
use Specio::Constraint::Parameterized;
use Specio::DeclaredAt;
use Specio::OO;
use Specio::TypeChecks qw( does_role isa_class );

use Specio::Constraint::Role::Interface;
with 'Specio::Constraint::Role::Interface';

{
    ## no critic (Subroutines::ProtectPrivateSubs)
    my $role_attrs = Specio::Constraint::Role::Interface::_attrs();
    ## use critic

    my $attrs = {
        %{$role_attrs},
        _parameterized_constraint_generator => {
            isa       => 'CodeRef',
            init_arg  => 'parameterized_constraint_generator',
            predicate => '_has_parameterized_constraint_generator',
        },
        _parameterized_inline_generator => {
            isa       => 'CodeRef',
            init_arg  => 'parameterized_inline_generator',
            predicate => '_has_parameterized_inline_generator',
        },
    };

    ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    sub _attrs {
        return $attrs;
    }
}

sub BUILD {
    my $self = shift;

    if ( $self->_has_constraint ) {
        die
            'A parameterizable constraint with a constraint parameter must also have a parameterized_constraint_generator'
            unless $self->_has_parameterized_constraint_generator;
    }

    if ( $self->_has_inline_generator ) {
        die
            'A parameterizable constraint with an inline_generator parameter must also have a parameterized_inline_generator'
            unless $self->_has_parameterized_inline_generator;
    }

    return;
}

sub parameterize {
    my $self = shift;
    my %args = @_;

    my ( $parameter, $declared_at ) = @args{qw( of declared_at )};
    does_role( $parameter, 'Specio::Constraint::Role::Interface' )
        or confess
        'The "of" parameter passed to ->parameterize must be an object which does the Specio::Constraint::Role::Interface role';

    if ($declared_at) {
        isa_class( $declared_at, 'Specio::DeclaredAt' )
            or confess
            'The "declared_at" parameter passed to ->parameterize must be a Specio::DeclaredAt object';
    }

    $declared_at = Specio::DeclaredAt->new_from_caller(1)
        unless defined $declared_at;

    my %p = (
        parent      => $self,
        parameter   => $parameter,
        declared_at => $declared_at,
    );

    if ( $self->_has_parameterized_constraint_generator ) {
        $p{constraint}
            = $self->_parameterized_constraint_generator->($parameter);
    }
    else {
        confess
            'The "of" parameter passed to ->parameterize must be an inlinable constraint if the parameterizable type has an inline_generator'
            unless $parameter->can_be_inlined;

        my $ig = $self->_parameterized_inline_generator;
        $p{inline_generator} = sub { $ig->( shift, $parameter, @_ ) };
    }

    return Specio::Constraint::Parameterized->new(%p);
}

__PACKAGE__->_ooify;

1;

# ABSTRACT: A class which represents parameterizable constraints

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Constraint::Parameterizable - A class which represents parameterizable constraints

=head1 VERSION

version 0.53

=head1 SYNOPSIS

    my $arrayref = t('ArrayRef');

    my $arrayref_of_int = $arrayref->parameterize( of => t('Int') );

=head1 DESCRIPTION

This class implements the API for parameterizable types like C<ArrayRef> and
C<Maybe>.

=for Pod::Coverage BUILD

=head1 API

This class implements the same API as L<Specio::Constraint::Simple>, with a few
additions.

=head2 Specio::Constraint::Parameterizable->new(...)

This class's constructor accepts two additional parameters:

=over 4

=item * parameterized_constraint_generator

This is a subroutine that generates a new constraint subroutine when the type
is parameterized.

It will be called as a method on the type and will be passed a single argument,
the type object for the type parameter.

This parameter is mutually exclusive with the C<parameterized_inline_generator>
parameter.

=item * parameterized_inline_generator

This is a subroutine that generates a new inline generator subroutine when the
type is parameterized.

It will be called as a method on the L<Specio::Constraint::Parameterized>
object when that object needs to generate an inline constraint. It will receive
the type parameter as the first argument and the variable name as a string as
the second.

This probably seems fairly confusing, so looking at the examples in the
L<Specio::Library::Builtins> code may be helpful.

This parameter is mutually exclusive with the
C<parameterized_constraint_generator> parameter.

=back

=head2 $type->parameterize(...)

This method takes two arguments. The C<of> argument should be an object which
does the L<Specio::Constraint::Role::Interface> role, and is required.

The other argument, C<declared_at>, is optional. If it is not given, then a new
L<Specio::DeclaredAt> object is creating using a call stack depth of 1.

This method returns a new L<Specio::Constraint::Parameterized> object.

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
