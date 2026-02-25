package Specio::Constraint::Structurable;

use strict;
use warnings;

our $VERSION = '0.53';

use Carp qw( confess );
use Role::Tiny::With;
use Scalar::Util qw( blessed );
use Specio::DeclaredAt;
use Specio::OO;
use Specio::Constraint::Structured;
use Specio::TypeChecks qw( does_role isa_class );

use Specio::Constraint::Role::Interface;
with 'Specio::Constraint::Role::Interface';

{
    ## no critic (Subroutines::ProtectPrivateSubs)
    my $role_attrs = Specio::Constraint::Role::Interface::_attrs();
    ## use critic

    my $attrs = {
        %{$role_attrs},
        _parameterization_args_builder => {
            isa      => 'CodeRef',
            init_arg => 'parameterization_args_builder',
            required => 1,
        },
        _name_builder => {
            isa      => 'CodeRef',
            init_arg => 'name_builder',
            required => 1,
        },
        _structured_constraint_generator => {
            isa       => 'CodeRef',
            init_arg  => 'structured_constraint_generator',
            predicate => '_has_structured_constraint_generator',
        },
        _structured_inline_generator => {
            isa       => 'CodeRef',
            init_arg  => 'structured_inline_generator',
            predicate => '_has_structured_inline_generator',
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
            'A structurable constraint with a constraint parameter must also have a structured_constraint_generator'
            unless $self->_has_structured_constraint_generator;
    }

    if ( $self->_has_inline_generator ) {
        die
            'A structurable constraint with an inline_generator parameter must also have a structured_inline_generator'
            unless $self->_has_structured_inline_generator;
    }

    return;
}

sub parameterize {
    my $self = shift;
    my %args = @_;

    my $declared_at = $args{declared_at};

    if ($declared_at) {
        isa_class( $declared_at, 'Specio::DeclaredAt' )
            or confess
            q{The "declared_at" parameter passed to ->parameterize must be a Specio::DeclaredAt object};
    }

    my %parameters
        = $self->_parameterization_args_builder->( $self, $args{of} );

    $declared_at = Specio::DeclaredAt->new_from_caller(1)
        unless defined $declared_at;

    my %new_p = (
        parent      => $self,
        parameters  => \%parameters,
        declared_at => $declared_at,
        name        => $self->_name_builder->( $self, \%parameters ),
    );

    if ( $self->_has_structured_constraint_generator ) {
        $new_p{constraint}
            = $self->_structured_constraint_generator->(%parameters);
    }
    else {
        for my $p (
            grep {
                       blessed($_)
                    && does_role('Specio::Constraint::Role::Interface')
            } values %parameters
        ) {

            confess
                q{Any type objects passed to ->parameterize must be inlinable constraints if the structurable type has an inline_generator}
                unless $p->can_be_inlined;
        }

        my $ig = $self->_structured_inline_generator;
        $new_p{inline_generator}
            = sub { $ig->( shift, shift, %parameters, @_ ) };
    }

    return Specio::Constraint::Structured->new(%new_p);
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _name_or_anon {
    return $_[1]->_has_name ? $_[1]->name : 'ANON';
}
## use critic

__PACKAGE__->_ooify;

1;

# ABSTRACT: A class which represents structurable constraints

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Constraint::Structurable - A class which represents structurable constraints

=head1 VERSION

version 0.53

=head1 SYNOPSIS

    my $tuple = t('Tuple');

    my $tuple_of_str_int = $tuple->parameterize( of => [ t('Str'), t('Int') ] );

=head1 DESCRIPTION

This class implements the API for structurable types like C<Dict>, C<Map>< and
C<Tuple>.

=for Pod::Coverage BUILD

=head1 API

This class implements the same API as L<Specio::Constraint::Simple>, with a few
additions.

=head2 Specio::Constraint::Structurable->new(...)

This class's constructor accepts two additional parameters:

=over 4

=item * parameterization_args_builder

This is a subroutine that takes the values passed to C<of> and returns a hash
of named arguments. These arguments will then be passed into the
C<structured_constraint_generator> or C<structured_inline_generator>.

This should also do argument checking to make sure that the argument passed are
valid. For example, the C<Tuple> type turns the arrayref passed to C<of> into a
hash, along the way checking that the caller did not do things like interleave
optional and required elements or mix optional and slurpy together in the
definition.

This parameter is required.

=item * name_builder

This is a subroutine that is called to generate a name for the structured type
when it is created. This will be called as a method on the
C<Specio::Constraint::Structurable> object. It will be passed the hash of
arguments returned by the C<parameterization_args_builder>.

This parameter is required.

=item * structured_constraint_generator

This is a subroutine that generates a new constraint subroutine when the type
is structured.

It will be called as a method on the type and will be passed the hash of
arguments returned by the C<parameterization_args_builder>.

This parameter is mutually exclusive with the C<structured_inline_generator>
parameter.

This parameter or the C<structured_inline_generator> parameter is required.

=item * structured_inline_generator

This is a subroutine that generates a new inline generator subroutine when the
type is structured.

It will be called as a method on the L<Specio::Constraint::Structured> object
when that object needs to generate an inline constraint. It will receive the
type parameter as the first argument and the variable name as a string as the
second.

The remaining arguments will be the parameter hash returned by the
C<parameterization_args_builder>.

This probably seems fairly confusing, so looking at the examples in the
L<Specio::Library::Structured::*> code may be helpful.

This parameter is mutually exclusive with the
C<structured_constraint_generator> parameter.

This parameter or the C<structured_constraint_generator> parameter is required.

=back

=head2 $type->parameterize(...)

This method takes two arguments. The C<of> argument should be an object which
does the L<Specio::Constraint::Role::Interface> role, and is required.

The other argument, C<declared_at>, is optional. If it is not given, then a new
L<Specio::DeclaredAt> object is creating using a call stack depth of 1.

This method returns a new L<Specio::Constraint::Structured> object.

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
