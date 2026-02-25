package Specio::Constraint::Role::Interface;

use strict;
use warnings;

our $VERSION = '0.53';

use Carp            qw( confess );
use Eval::Closure   qw( eval_closure );
use List::Util 1.33 qw( all any first );
use Specio::Exception;
use Specio::PartialDump qw( partial_dump );
use Specio::TypeChecks  qw( is_CodeRef );

use Role::Tiny 1.003003;

use Specio::Role::Inlinable;
with 'Specio::Role::Inlinable';

use overload(
    q{""}  => '_stringify',
    '&{}'  => '_subification',
    'bool' => sub {1},
    'eq'   => 'is_same_type_as',
);

{
    ## no critic (Subroutines::ProtectPrivateSubs)
    my $role_attrs = Specio::Role::Inlinable::_attrs();
    ## use critic

    my $attrs = {
        %{$role_attrs},
        name => {
            isa       => 'Str',
            predicate => '_has_name',
        },
        parent => {
            does      => 'Specio::Constraint::Role::Interface',
            predicate => '_has_parent',
        },
        _constraint => {
            isa       => 'CodeRef',
            init_arg  => 'constraint',
            predicate => '_has_constraint',
        },
        _optimized_constraint => {
            isa      => 'CodeRef',
            init_arg => undef,
            lazy     => 1,
            builder  => '_build_optimized_constraint',
        },
        _ancestors => {
            isa      => 'ArrayRef',
            init_arg => undef,
            lazy     => 1,
            builder  => '_build_ancestors',
        },
        _message_generator => {
            isa      => 'CodeRef',
            init_arg => undef,
        },
        _coercions => {
            builder => '_build_coercions',
            clone   => '_clone_coercions',
        },
        _subification => {
            init_arg => undef,
            lazy     => 1,
            builder  => '_build_subification',
        },

        # Because types are cloned on import, we can't directly compare type
        # objects. Because type names can be reused between packages (no global
        # registry) we can't compare types based on name either.
        _signature => {
            isa      => 'Str',
            init_arg => undef,
            lazy     => 1,
            builder  => '_build_signature',
        },
    };

    ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    sub _attrs {
        return $attrs;
    }
}

my $NullConstraint = sub {1};

# See Specio::OO to see how this is used.

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _Specio_Constraint_Role_Interface_BUILD {
    my $self = shift;
    my $p    = shift;

    unless ( $self->_has_constraint || $self->_has_inline_generator ) {
        $self->{_constraint} = $NullConstraint;
    }

    die
        'A type constraint should have either a constraint or inline_generator parameter, not both'
        if $self->_has_constraint && $self->_has_inline_generator;

    $self->{_message_generator}
        = $self->_wrap_message_generator( $p->{message_generator} );

    return;
}
## use critic

sub _wrap_message_generator {
    my $self      = shift;
    my $generator = shift;

    unless ( defined $generator ) {
        $generator = sub {
            my $description = shift;
            my $value       = shift;

            return "Validation failed for $description with value "
                . partial_dump($value);
        };
    }

    my $d = $self->description;

    return sub { $generator->( $d, @_ ) };
}

sub coercions               { values %{ $_[0]->{_coercions} } }
sub coercion_from_type      { $_[0]->{_coercions}{ $_[1] } }
sub _has_coercion_from_type { exists $_[0]->{_coercions}{ $_[1] } }
sub _add_coercion           { $_[0]->{_coercions}{ $_[1] } = $_[2] }
sub has_coercions           { scalar keys %{ $_[0]->{_coercions} } }

sub validate_or_die {
    my $self  = shift;
    my $value = shift;

    return if $self->value_is_valid($value);

    Specio::Exception->throw(
        message => $self->_message_generator->($value),
        type    => $self,
        value   => $value,
    );
}

sub value_is_valid {
    my $self  = shift;
    my $value = shift;

    return $self->_optimized_constraint->($value);
}

sub _ancestors_and_self {
    my $self = shift;

    return ( ( reverse @{ $self->_ancestors } ), $self );
}

sub is_a_type_of {
    my $self = shift;
    my $type = shift;

    return
        any { $_->_signature eq $type->_signature }
        $self->_ancestors_and_self;
}

sub is_same_type_as {
    my $self = shift;
    my $type = shift;

    return $self->_signature eq $type->_signature;
}

sub is_anon {
    my $self = shift;

    return !$self->_has_name;
}

sub has_real_constraint {
    my $self = shift;

    return ( $self->_has_constraint && $self->_constraint ne $NullConstraint )
        || $self->_has_inline_generator;
}

sub can_be_inlined {
    my $self = shift;

    return 1 if $self->_has_inline_generator;
    return 0
        if $self->_has_constraint && $self->_constraint ne $NullConstraint;

    # If this type is an empty subtype of an inlinable parent, then we can
    # inline this type as well.
    return 1 if $self->_has_parent && $self->parent->can_be_inlined;
    return 0;
}

sub _build_generated_inline_sub {
    my $self = shift;

    my $type = $self->_self_or_first_inlinable_ancestor;

    my $source
        = 'sub { ' . $type->_inline_generator->( $type, '$_[0]' ) . '}';

    return eval_closure(
        source      => $source,
        environment => $type->inline_environment,
        description => 'inlined sub for ' . $self->description,
    );
}

sub _self_or_first_inlinable_ancestor {
    my $self = shift;

    my $type = first { $_->_has_inline_generator }
        reverse $self->_ancestors_and_self;

    # This should never happen because ->can_be_inlined should always be
    # checked before this builder is called.
    die 'Cannot generate an inline sub' unless $type;

    return $type;
}

sub _build_optimized_constraint {
    my $self = shift;

    if ( $self->can_be_inlined ) {
        return $self->_generated_inline_sub;
    }
    else {
        return $self->_constraint_with_parents;
    }
}

sub _constraint_with_parents {
    my $self = shift;

    my @constraints;
    for my $type ( $self->_ancestors_and_self ) {
        next unless $type->has_real_constraint;

        # If a type can be inlined, we can use that and discard all of the
        # ancestors we've seen so far, since we can assume that the inlined
        # constraint does all of the ancestor checks in addition to its own.
        if ( $type->can_be_inlined ) {
            @constraints = $type->_generated_inline_sub;
        }
        else {
            push @constraints, $type->_constraint;
        }
    }

    return $NullConstraint unless @constraints;

    return sub {
        all { $_->( $_[0] ) } @constraints;
    };
}

# This is only used for identifying from types as part of coercions, but I
# want to leave open the possibility of using something other than
# _description in the future.
sub id {
    my $self = shift;

    return $self->description;
}

sub add_coercion {
    my $self     = shift;
    my $coercion = shift;

    my $from_id = $coercion->from->id;

    confess "Cannot add two coercions fom the same type: $from_id"
        if $self->_has_coercion_from_type($from_id);

    $self->_add_coercion( $from_id => $coercion );

    return;
}

sub has_coercion_from_type {
    my $self = shift;
    my $type = shift;

    return $self->_has_coercion_from_type( $type->id );
}

sub coerce_value {
    my $self  = shift;
    my $value = shift;

    for my $coercion ( $self->coercions ) {
        next unless $coercion->from->value_is_valid($value);

        return $coercion->coerce($value);
    }

    return $value;
}

sub can_inline_coercion {
    my $self = shift;

    return all { $_->can_be_inlined } $self->coercions;
}

sub can_inline_coercion_and_check {
    my $self = shift;

    return all { $_->can_be_inlined } $self, $self->coercions;
}

sub inline_coercion {
    my $self     = shift;
    my $arg_name = shift;

    die 'Cannot inline coercion'
        unless $self->can_inline_coercion;

    my $source = 'do { my $value = ' . $arg_name . ';';

    my ( $coerce, $env );
    ( $coerce, $arg_name, $env ) = $self->_inline_coercion($arg_name);
    $source .= $coerce . $arg_name . '};';

    return ( $source, $env );
}

sub inline_coercion_and_check {
    my $self     = shift;
    my $arg_name = shift;

    die 'Cannot inline coercion and check'
        unless $self->can_inline_coercion_and_check;

    my $source = 'do { my $value = ' . $arg_name . ';';

    my ( $coerce, $env );
    ( $coerce, $arg_name, $env ) = $self->_inline_coercion($arg_name);
    my ( $assert, $assert_env ) = $self->inline_assert($arg_name);

    $source .= $coerce;
    $source .= $assert;
    $source .= $arg_name . '};';

    return ( $source, { %{$env}, %{$assert_env} } );
}

sub _inline_coercion {
    my $self     = shift;
    my $arg_name = shift;

    return ( q{}, $arg_name, {} ) unless $self->has_coercions;

    my %env;

    $arg_name = '$value';
    my $source = $arg_name . ' = ';
    for my $coercion ( $self->coercions ) {
        $source
            .= '('
            . $coercion->from->inline_check($arg_name) . ') ? ('
            . $coercion->inline_coercion($arg_name) . ') : ';

        %env = (
            %env,
            %{ $coercion->inline_environment },
            %{ $coercion->from->inline_environment },
        );
    }
    $source .= $arg_name . ';';

    return ( $source, $arg_name, \%env );
}

{
    my $counter = 1;

    sub inline_assert {
        my $self = shift;

        my $type_var_name = '$_Specio_Constraint_Interface_type' . $counter;
        my $message_generator_var_name
            = '$_Specio_Constraint_Interface_message_generator' . $counter;
        my %env = (
            $type_var_name              => \$self,
            $message_generator_var_name => \( $self->_message_generator ),
            %{ $self->inline_environment },
        );

        my $source = $self->inline_check( $_[0] );
        $source .= ' or ';
        $source .= $self->_inline_throw_exception(
            $_[0],
            $message_generator_var_name,
            $type_var_name
        );
        $source .= ';';

        $counter++;

        return ( $source, \%env );
    }
}

sub inline_check {
    my $self = shift;

    die 'Cannot inline' unless $self->can_be_inlined;

    my $type = $self->_self_or_first_inlinable_ancestor;
    return $type->_inline_generator->( $type, @_ );
}

# For some idiotic reason I called $type->_subify directly in Code::TidyAll so
# I'll leave this in here for now.

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _subify { $_[0]->_subification }
## use critic

sub _build_subification {
    my $self = shift;

    if ( defined &Sub::Quote::quote_sub && $self->can_be_inlined ) {
        return Sub::Quote::quote_sub( $self->inline_assert('$_[0]') );
    }
    else {
        return sub { $self->validate_or_die( $_[0] ) };
    }
}

sub _inline_throw_exception {
    shift;
    my $value_var                  = shift;
    my $message_generator_var_name = shift;
    my $type_var_name              = shift;

    #<<<
    return 'Specio::Exception->throw( '
        . ' message => ' . $message_generator_var_name . '->(' . $value_var . '),'
        . ' type    => ' . $type_var_name . ','
        . ' value   => ' . $value_var . ' )';
    #>>>
}

# This exists for the benefit of Moo
sub coercion_sub {
    my $self = shift;

    if ( defined &Sub::Quote::quote_sub
        && all { $_->can_be_inlined } $self->coercions ) {

        my $inline = q{};
        my %env;

        for my $coercion ( $self->coercions ) {
            $inline .= sprintf(
                '$_[0] = %s if %s;' . "\n",
                $coercion->inline_coercion('$_[0]'),
                $coercion->from->inline_check('$_[0]')
            );

            %env = (
                %env,
                %{ $coercion->inline_environment },
                %{ $coercion->from->inline_environment },
            );
        }

        $inline .= sprintf( "%s;\n", '$_[0]' );

        return Sub::Quote::quote_sub( $inline, \%env );
    }
    else {
        return sub { $self->coerce_value(shift) };
    }
}

sub _build_ancestors {
    my $self = shift;

    my @parents;

    my $type = $self;
    while ( $type = $type->parent ) {
        push @parents, $type;
    }

    return \@parents;

}

sub _build_description {
    my $self = shift;

    my $desc
        = $self->is_anon ? 'anonymous type' : 'type named ' . $self->name;

    $desc .= q{ } . $self->declared_at->description;

    return $desc;
}

sub _build_coercions { {} }

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _clone_coercions {
    my $self = shift;

    my $coercions = $self->_coercions;
    my %clones;

    for my $name ( keys %{$coercions} ) {
        my $coercion = $coercions->{$name};
        $clones{$name} = $coercion->clone_with_new_to($self);
    }

    return \%clones;
}
## use critic

sub _stringify {
    my $self = shift;

    return $self->name unless $self->is_anon;

    return sprintf( '__ANON__(%s)', $self->parent . q{} );
}

sub _build_signature {
    my $self = shift;

    # This assumes that when a type is cloned, the underlying constraint or
    # generator sub is copied by _reference_, so it has the same memory
    # address and stringifies to the same value. XXX - will this break under
    # threads?
    return join "\n",
        ## no critic (Subroutines::ProtectPrivateSubs)
        ( $self->_has_parent ? $self->parent->_signature : () ),
        (
        defined $self->_constraint
        ? $self->_constraint
        : $self->_inline_generator
        );
}

# Moose compatibility methods - these exist as a temporary hack to make Specio
# work with Moose.

sub has_coercion {
    shift->has_coercions;
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _inline_check {
    shift->inline_check(@_);
}

sub _compiled_type_constraint {
    shift->_optimized_constraint;
}
## use critic;

# This class implements the methods that Moose expects from coercions as well.
sub coercion {
    return shift;
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _compiled_type_coercion {
    my $self = shift;

    return sub {
        return $self->coerce_value(shift);
    };
}
## use critic

sub has_message {
    1;
}

sub message {
    shift->_message_generator;
}

sub get_message {
    my $self  = shift;
    my $value = shift;

    return $self->_message_generator->( $self, $value );
}

sub check {
    shift->value_is_valid(@_);
}

sub coerce {
    shift->coerce_value(@_);
}

1;

# ABSTRACT: The interface all type constraints should provide

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Constraint::Role::Interface - The interface all type constraints should provide

=head1 VERSION

version 0.53

=head1 DESCRIPTION

This role defines the interface that all type constraints must provide, and
provides most (or all) of the implementation. The L<Specio::Constraint::Simple>
class simply consumes this role and provides no additional code. Other
constraint classes add features or override some of this role's functionality.

=for Pod::Coverage .*

=head1 API

See the L<Specio::Constraint::Simple> documentation for details. See the
internals of various constraint classes to see how this role can be overridden
or expanded upon.

=head1 ROLES

This role does the L<Specio::Role::Inlinable> role.

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
