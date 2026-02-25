package Specio::Declare;

use strict;
use warnings;

use parent 'Exporter';

our $VERSION = '0.53';

use Carp qw( croak );
use Specio::Coercion;
use Specio::Constraint::Simple;
use Specio::DeclaredAt;
use Specio::Helpers  qw( install_t_sub _STRINGLIKE );
use Specio::Registry qw( internal_types_for_package register );

## no critic (Modules::ProhibitAutomaticExportation)
our @EXPORT = qw(
    anon
    any_can_type
    any_does_type
    any_isa_type
    coerce
    declare
    enum
    intersection
    object_can_type
    object_does_type
    object_isa_type
    union
);
## use critic

sub import {
    my $package = shift;

    my $caller = caller();

    $package->export_to_level( 1, $package, @_ );

    install_t_sub(
        $caller,
        internal_types_for_package($caller)
    );

    return;
}

sub declare {
    my $name = _STRINGLIKE(shift)
        or croak 'You must provide a name for declared types';
    my %p = @_;

    my $tc = _make_tc( name => $name, %p );

    register( scalar caller(), $name, $tc, 'exportable' );

    return $tc;
}

sub anon {
    return _make_tc(@_);
}

sub enum {
    my $name;
    $name = shift if @_ % 2;
    my %p = @_;

    require Specio::Constraint::Enum;

    my $tc = _make_tc(
        ( defined $name ? ( name => $name ) : () ),
        values     => $p{values},
        type_class => 'Specio::Constraint::Enum',
    );

    register( scalar caller(), $name, $tc, 'exportable' )
        if defined $name;

    return $tc;
}

sub object_can_type {
    my $name;
    $name = shift if @_ % 2;
    my %p = @_;

    # This cannot be loaded earlier, since it loads Specio::Library::Builtins,
    # which in turn wants to load Specio::Declare (the current module).
    require Specio::Constraint::ObjectCan;

    my $tc = _make_tc(
        ( defined $name ? ( name => $name ) : () ),
        methods    => $p{methods},
        type_class => 'Specio::Constraint::ObjectCan',
    );

    register( scalar caller(), $name, $tc, 'exportable' )
        if defined $name;

    return $tc;
}

sub object_does_type {
    my $name;
    $name = shift if @_ % 2;
    my %p = @_;

    my $caller = scalar caller();

    # If we are being called repeatedly with a single argument, then we don't
    # want to blow up because the type has already been declared. This would
    # force the user to use t() for all calls but the first, making their code
    # pointlessly more complicated.
    unless ( keys %p ) {
        if ( my $exists = internal_types_for_package($caller)->{$name} ) {
            return $exists;
        }
    }

    require Specio::Constraint::ObjectDoes;

    my $tc = _make_tc(
        ( defined $name ? ( name => $name ) : () ),
        role => ( defined $p{role} ? $p{role} : $name ),
        type_class => 'Specio::Constraint::ObjectDoes',
    );

    register( scalar caller(), $name, $tc, 'exportable' )
        if defined $name;

    return $tc;
}

sub object_isa_type {
    my $name;
    $name = shift if @_ % 2;
    my %p = @_;

    my $caller = scalar caller();
    unless ( keys %p ) {
        if ( my $exists = internal_types_for_package($caller)->{$name} ) {
            return $exists;
        }
    }

    require Specio::Constraint::ObjectIsa;

    my $tc = _make_tc(
        ( defined $name ? ( name => $name ) : () ),
        class      => ( defined $p{class} ? $p{class} : $name ),
        type_class => 'Specio::Constraint::ObjectIsa',
    );

    register( $caller, $name, $tc, 'exportable' )
        if defined $name;

    return $tc;
}

sub any_can_type {
    my $name;
    $name = shift if @_ % 2;
    my %p = @_;

    # This cannot be loaded earlier, since it loads Specio::Library::Builtins,
    # which in turn wants to load Specio::Declare (the current module).
    require Specio::Constraint::AnyCan;

    my $tc = _make_tc(
        ( defined $name ? ( name => $name ) : () ),
        methods    => $p{methods},
        type_class => 'Specio::Constraint::AnyCan',
    );

    register( scalar caller(), $name, $tc, 'exportable' )
        if defined $name;

    return $tc;
}

sub any_does_type {
    my $name;
    $name = shift if @_ % 2;
    my %p = @_;

    my $caller = scalar caller();
    unless ( keys %p ) {
        if ( my $exists = internal_types_for_package($caller)->{$name} ) {
            return $exists;
        }
    }

    require Specio::Constraint::AnyDoes;

    my $tc = _make_tc(
        ( defined $name ? ( name => $name ) : () ),
        role => ( defined $p{role} ? $p{role} : $name ),
        type_class => 'Specio::Constraint::AnyDoes',
    );

    register( scalar caller(), $name, $tc, 'exportable' )
        if defined $name;

    return $tc;
}

sub any_isa_type {
    my $name;
    $name = shift if @_ % 2;
    my %p = @_;

    my $caller = scalar caller();
    unless ( keys %p ) {
        if ( my $exists = internal_types_for_package($caller)->{$name} ) {
            return $exists;
        }
    }

    require Specio::Constraint::AnyIsa;

    my $tc = _make_tc(
        ( defined $name ? ( name => $name ) : () ),
        class      => ( defined $p{class} ? $p{class} : $name ),
        type_class => 'Specio::Constraint::AnyIsa',
    );

    register( scalar caller(), $name, $tc, 'exportable' )
        if defined $name;

    return $tc;
}

sub intersection {
    my $name;
    $name = shift if @_ % 2;
    my %p = @_;

    require Specio::Constraint::Intersection;

    my $tc = _make_tc(
        ( defined $name ? ( name => $name ) : () ),
        %p,
        type_class => 'Specio::Constraint::Intersection',
    );

    register( scalar caller(), $name, $tc, 'exportable' )
        if defined $name;

    return $tc;
}

sub union {
    my $name;
    $name = shift if @_ % 2;
    my %p = @_;

    require Specio::Constraint::Union;

    my $tc = _make_tc(
        ( defined $name ? ( name => $name ) : () ),
        %p,
        type_class => 'Specio::Constraint::Union',
    );

    register( scalar caller(), $name, $tc, 'exportable' )
        if defined $name;

    return $tc;
}

sub _make_tc {
    my %p = @_;

    my $class = delete $p{type_class} || 'Specio::Constraint::Simple';

    $p{constraint}        = delete $p{where}   if exists $p{where};
    $p{message_generator} = delete $p{message} if exists $p{message};
    $p{inline_generator}  = delete $p{inline}  if exists $p{inline};

    return $class->new(
        %p,
        declared_at => Specio::DeclaredAt->new_from_caller(2),
    );
}

sub coerce {
    my $to = shift;
    my %p  = @_;

    $p{coercion}         = delete $p{using}  if exists $p{using};
    $p{inline_generator} = delete $p{inline} if exists $p{inline};

    return $to->add_coercion(
        Specio::Coercion->new(
            to => $to,
            %p,
            declared_at => Specio::DeclaredAt->new_from_caller(1),
        )
    );
}

1;

# ABSTRACT: Specio declaration subroutines

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Declare - Specio declaration subroutines

=head1 VERSION

version 0.53

=head1 SYNOPSIS

    package MyApp::Type::Library;

    use parent 'Specio::Exporter';

    use Specio::Declare;
    use Specio::Library::Builtins;

    declare(
        'Foo',
        parent => t('Str'),
        where  => sub { $_[0] =~ /foo/i },
    );

    declare(
        'ArrayRefOfInt',
        parent => t( 'ArrayRef', of => t('Int') ),
    );

    my $even = anon(
        parent => t('Int'),
        inline => sub {
            my $type      = shift;
            my $value_var = shift;

            return $value_var . ' % 2 == 0';
        },
    );

    coerce(
        t('ArrayRef'),
        from  => t('Foo'),
        using => sub { [ $_[0] ] },
    );

    coerce(
        $even,
        from  => t('Int'),
        using => sub { $_[0] % 2 ? $_[0] + 1 : $_[0] },
    );

    # Specio name is DateTime
    any_isa_type('DateTime');

    # Specio name is DateTimeObject
    object_isa_type( 'DateTimeObject', class => 'DateTime' );

    any_can_type(
        'Duck',
        methods => [ 'duck_walk', 'quack' ],
    );

    object_can_type(
        'DuckObject',
        methods => [ 'duck_walk', 'quack' ],
    );

    enum(
        'Colors',
        values => [qw( blue green red )],
    );

    intersection(
        'HashRefAndArrayRef',
        of => [ t('HashRef'), t('ArrayRef') ],
    );

    union(
        'IntOrArrayRef',
        of => [ t('Int'), t('ArrayRef') ],
    );

=head1 DESCRIPTION

This package exports a set of type declaration helpers. Importing this package
also causes it to create a C<t> subroutine in the calling package.

=head1 SUBROUTINES

This module exports the following subroutines.

=head2 t('name')

This subroutine lets you access any types you have declared so far, as well as
any types you imported from another type library.

If you pass an unknown name, it throws an exception.

=head2 declare(...)

This subroutine declares a named type. The first argument is the type name,
followed by a set of key/value parameters:

=over 4

=item * parent => $type

The parent should be another type object. Specifically, it can be anything
which does the L<Specio::Constraint::Role::Interface> role. The parent can be a
named or anonymous type.

=item * where => sub { ... }

This is a subroutine which defines the type constraint. It will be passed a
single argument, the value to check, and it should return true or false to
indicate whether or not the value is valid for the type.

This parameter is mutually exclusive with the C<inline> parameter.

=item * inline => sub { ... }

This is a subroutine that is called to generate inline code to validate the
type. Inlining can be I<much> faster than simply providing a subroutine with
the C<where> parameter, but is often more complicated to get right.

The inline generator is called as a method on the type with one argument. This
argument is a I<string> containing the variable name to use in the generated
code. Typically this is something like C<'$_[0]'> or C<'$value'>.

The inline generator subroutine should return a I<string> of code representing
a single term, and it I<should not> be terminated with a semicolon. This allows
the inlined code to be safely included in an C<if> statement, for example. You
can use C<do { }> blocks and ternaries to get everything into one term. Do not
assign to the variable you are testing. This single term should evaluate to
true or false.

The inline generator is expected to include code to implement both the current
type and all its parents. Typically, the easiest way to do this is to write a
subroutine something like this:

  sub {
      my $self = shift;
      my $var  = shift;

      return $self->parent->inline_check($var)
          . ' and more checking code goes here';
  }

Or, more concisely:

  sub { $_[0]->parent->inline_check( $_[1] ) . 'more code that checks $_[1]' }

The C<inline> parameter is mutually exclusive with the C<where> parameter.

=item * message_generator => sub { ... }

A subroutine to generate an error message when the type check fails. The
default message says something like "Validation failed for type named Int
declared in package Specio::Library::Builtins
(.../Specio/blib/lib/Specio/Library/Builtins.pm) at line 147 in sub named
(eval) with value 1.1".

You can override this to provide something more specific about the way the type
failed.

The subroutine you provide will be called as a method on the type with two
arguments. The first is the description of the type (the bit in the message
above that starts with "type named Int ..." and ends with "... in sub named
(eval)". This description says what the thing is and where it was defined.

The second argument is the value that failed the type check, after any
coercions that might have been applied.

=back

=head2 anon(...)

This subroutine declares an anonymous type. It is identical to C<declare>
except that it expects a list of key/value parameters without a type name as
the first parameter.

=head2 coerce(...)

This declares a coercion from one type to another. The first argument should be
an object which does the L<Specio::Constraint::Role::Interface> role. This can
be either a named or anonymous type. This type is the type that the coercion is
I<to>.

The remaining arguments are key/value parameters:

=over 4

=item * from => $type

This must be an object which does the L<Specio::Constraint::Role::Interface>
role. This is type that we are coercing I<from>. Again, this can be either a
named or anonymous type.

=item * using => sub { ... }

This is a subroutine which defines the type coercion. It will be passed a
single argument, the value to coerce. It should return a new value of the type
this coercion is to.

This parameter is mutually exclusive with the C<inline> parameter.

=item * inline => sub { ... }

This is a subroutine that is called to generate inline code to perform the
coercion.

The inline generator is called as a method on the type with one argument. This
argument is a I<string> containing the variable name to use in the generated
code. Typically this is something like C<'$_[0]'> or C<'$value'>.

The inline generator subroutine should return a I<string> of code representing
a single term, and it I<should not> be terminated with a semicolon. This allows
the inlined code to be safely included in an C<if> statement, for example. You
can use C<do { }> blocks and ternaries to get everything into one term. This
single term should evaluate to the new value.

=back

=head1 DECLARATION HELPERS

This module also exports some helper subs for declaring certain kinds of types:

=head2 any_isa_type, object_isa_type

The C<any_isa_type> helper creates a type which accepts a class name or object
of the given class. The C<object_isa_type> helper creates a type which only
accepts an object of the given class.

These subroutines take a type name as the first argument. The remaining
arguments are key/value pairs. Currently this is just the C<class> key, which
should be a class name. This is the class that the type requires.

The type name argument can be omitted to create an anonymous type.

You can also pass just a single argument, in which case that will be used as
both the type's name and the class for the constraint to check.

=head2 any_does_type, object_does_type

The C<any_does_type> helper creates a type which accepts a class name or object
which does the given role. The C<object_does_type> helper creates a type which
only accepts an object which does the given role.

These subroutines take a type name as the first argument. The remaining
arguments are key/value pairs. Currently this is just the C<role> key, which
should be a role name. This is the class that the type requires.

This should just work (I hope) with roles created by L<Moose>, L<Mouse>, and
L<Moo> (using L<Role::Tiny>).

The type name argument can be omitted to create an anonymous type.

You can also pass just a single argument, in which case that will be used as
both the type's name and the role for the constraint to check.

=head2 any_can_type, object_can_type

The C<any_can_type> helper creates a type which accepts a class name or object
with the given methods. The C<object_can_type> helper creates a type which only
accepts an object with the given methods.

These subroutines take a type name as the first argument. The remaining
arguments are key/value pairs. Currently this is just the C<methods> key, which
can be either a string or array reference of strings. These strings are the
required methods for the type.

The type name argument can be omitted to create an anonymous type.

=head2 enum

This creates a type which accepts a string matching a given list of acceptable
values.

The first argument is the type name. The remaining arguments are key/value
pairs. Currently this is just the C<values> key. This should an array reference
of acceptable string values.

The type name argument can be omitted to create an anonymous type.

=head2 intersection

This creates a type which is the intersection of two or more other types. A
union only accepts values which match all of its underlying types.

The first argument is the type name. The remaining arguments are key/value
pairs. Currently this is just the C<of> key. This should an array reference of
types.

The type name argument can be omitted to create an anonymous type.

=head2 union

This creates a type which is the union of two or more other types. A union
accepts any of its underlying types.

The first argument is the type name. The remaining arguments are key/value
pairs. Currently this is just the C<of> key. This should an array reference of
types.

The type name argument can be omitted to create an anonymous type.

=head1 PARAMETERIZED TYPES

You can create a parameterized type by calling C<t> with additional parameters,
like this:

  my $arrayref_of_int = t( 'ArrayRef', of => t('Int') );

  my $arrayref_of_hashref_of_int = t(
      'ArrayRef',
      of => t(
          'HashRef',
          of => t('Int'),
      ),
  );

The C<t> subroutine assumes that if it receives more than one argument, it
should look up the named type and call C<< $type->parameterize(...) >> with the
additional arguments.

If the named type cannot be parameterized, it throws an error.

You can also call C<< $type->parameterize >> directly if needed. See
L<Specio::Constraint::Parameterizable> for details.

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
