package Specio::Coercion;

use strict;
use warnings;

our $VERSION = '0.53';

use Specio::OO;

use Role::Tiny::With;

use Specio::Role::Inlinable;
with 'Specio::Role::Inlinable';

{
    ## no critic (Subroutines::ProtectPrivateSubs)
    my $role_attrs = Specio::Role::Inlinable::_attrs();
    ## use critic

    my $attrs = {
        %{$role_attrs},
        from => {
            does     => 'Specio::Constraint::Role::Interface',
            required => 1,
        },
        to => {
            does     => 'Specio::Constraint::Role::Interface',
            required => 1,
            weak_ref => 1,
        },
        _coercion => {
            isa       => 'CodeRef',
            predicate => '_has_coercion',
            init_arg  => 'coercion',
        },
        _optimized_coercion => {
            isa      => 'CodeRef',
            init_arg => undef,
            lazy     => 1,
            builder  => '_build_optimized_coercion',
        },
    };

    ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    sub _attrs {
        return $attrs;
    }
}

sub BUILD {
    my $self = shift;

    die
        'A type coercion should have either a coercion or inline_generator parameter, not both'
        if $self->_has_coercion && $self->_has_inline_generator;

    die
        'A type coercion must have either a coercion or inline_generator parameter'
        unless $self->_has_coercion || $self->_has_inline_generator;

    return;
}

sub coerce {
    my $self  = shift;
    my $value = shift;

    return $self->_optimized_coercion->($value);
}

sub inline_coercion {
    my $self = shift;

    return $self->_inline_generator->( $self, @_ );
}

sub _build_optimized_coercion {
    my $self = shift;

    if ( $self->_has_inline_generator ) {
        return $self->_generated_inline_sub;
    }
    else {
        return $self->_coercion;
    }
}

sub can_be_inlined {
    my $self = shift;

    return $self->_has_inline_generator && $self->from->can_be_inlined;
}

sub _build_description {
    my $self = shift;

    my $from_name
        = defined $self->from->name ? $self->from->name : 'anonymous type';
    my $to_name
        = defined $self->to->name ? $self->to->name : 'anonymous type';
    my $desc = "coercion from $from_name to $to_name";

    $desc .= q{ } . $self->declared_at->description;

    return $desc;
}

sub clone_with_new_to {
    my $self   = shift;
    my $new_to = shift;

    my $from = $self->from;

    local $self->{from} = undef;
    local $self->{to}   = undef;

    my $clone = $self->clone;

    $clone->{from} = $from;
    $clone->{to}   = $new_to;

    return $clone;
}

__PACKAGE__->_ooify;

1;

# ABSTRACT: A class representing a coercion from one type to another

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Coercion - A class representing a coercion from one type to another

=head1 VERSION

version 0.53

=head1 SYNOPSIS

    my $coercion = $type->coercion_from_type('Int');

    my $new_value = $coercion->coerce_value(42);

    if ( $coercion->can_be_inlined() ) {
        my $code = $coercion->inline_coercion('$_[0]');
    }

=head1 DESCRIPTION

This class represents a coercion from one type to another. Internally, a
coercion is a piece of code that takes a value of one type returns a new value
of a new type. For example, a coercion from c<Num> to C<Int> might round a
number to its nearest integer and return that integer.

Coercions can be implemented either as a simple subroutine reference or as an
inline generator subroutine. Using an inline generator is faster but more
complicated.

=for Pod::Coverage BUILD clone_with_new_to

=head1 API

This class provides the following methods.

=head2 Specio::Coercion->new( ... )

This method creates a new coercion object. It accepts the following named
parameters:

=over 4

=item * from => $type

The type this coercion is from. The type must be an object which does the
L<Specio::Constraint::Role::Interface> interface.

This parameter is required.

=item * to => $type

The type this coercion is to. The type must be an object which does the
L<Specio::Constraint::Role::Interface> interface.

This parameter is required.

=item * coercion => sub { ... }

A subroutine reference implementing the coercion. It will be called as a method
on the object and passed a single argument, the value to coerce.

It should return the new value.

This parameter is mutually exclusive with C<inline_generator>.

Either this parameter or the C<inline_generator> parameter is required.

You can also pass this option with the key C<using> in the parameter list.

=item * inline_generator => sub { ... }

This should be a subroutine reference which returns a string containing a
single term. This code should I<not> end in a semicolon. This code should
implement the coercion.

The generator will be called as a method on the coercion with a single
argument. That argument is the name of the variable being coerced, something
like C<'$_[0]'> or C<'$var'>.

This parameter is mutually exclusive with C<coercion>.

Either this parameter or the C<coercion> parameter is required.

You can also pass this option with the key C<inline> in the parameter list.

=item * inline_environment => {}

This should be a hash reference of variable names (with sigils) and values for
that variable. The values should be I<references> to the values of the
variables.

This environment will be used when compiling the coercion as part of a
subroutine. The named variables will be captured as closures in the generated
subroutine, using L<Eval::Closure>.

It should be very rare to need to set this in the constructor. It's more likely
that a special coercion subclass would need to provide values that it generates
internally.

This parameter defaults to an empty hash reference.

=item * declared_at => $declared_at

This parameter must be a L<Specio::DeclaredAt> object.

This parameter is required.

=back

=head2 $coercion->from(), $coercion->to(), $coercion->declared_at()

These methods are all read-only attribute accessors for the corresponding
attribute.

=head2 $coercion->description

This returns a string describing the coercion. This includes the names of the
to and from type and where the coercion was declared, so you end up with
something like C<'coercion from Foo to Bar declared in package My::Lib
(lib/My/Lib.pm) at line 42'>.

=head2 $coercion->coerce($value)

Given a value of the right "from" type, returns a new value of the "to" type.

This method does not actually check that the types of given or return values.

=head2 $coercion->inline_coercion($var)

Given a variable name like C<'$_[0]'> this returns a string with code for the
coercion.

Note that this method will die if the coercion does not have an inline
generator.

=head2 $coercion->can_be_inlined()

This returns true if the coercion has an inline generator I<and> the constraint
it is from can be inlined. This exists primarily for the benefit of the
C<inline_coercion_and_check()> method for type constraint object.

=head2 $coercion->inline_environment()

This returns a hash defining the variables that need to be closed over when
inlining the coercion. The keys are full variable names like C<'$foo'> or
C<'@bar'>. The values are I<references> to a variable of the matching type.

=head2 $coercion->clone()

Returns a clone of this object.

=head2 $coercion->clone_with_new_to($new_to_type)

This returns a clone of the coercion, replacing the "to" type with a new one.
This is intended for use when the to type itself is being cloned as part of
importing that type. We need to make sure the newly cloned coercion has the
newly cloned type as well.

=head1 ROLES

This class does the L<Specio::Role::Inlinable> role.

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
