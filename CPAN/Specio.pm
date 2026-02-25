package Specio;

use strict;
use warnings;

use 5.008;

our $VERSION = '0.53';

use Module::Implementation;

use Exporter qw( import );

BEGIN {
    # This env var exists for the benefit of the PurePerlTests dzil plugin, which only knows how to
    # set an env var to a true value.
    if ( $ENV{SPECIO_TEST_PP} ) {
        ## no critic (Variables::RequireLocalizedPunctuationVars)
        $ENV{SPECIO_IMPLEMENTATION} = 'PP';
    }

    my $loader = Module::Implementation::build_loader_sub(
        implementations => [ 'XS', 'PP' ],
        symbols         => ['_clone'],
    );
    $loader->();
}

# It's a bit weird to put this in the root module, but this way the env var that
# Module::Implementation::build_loader_sub uses will be named "SPECIO_IMPLEMENTATION". That way, if
# in the future there are other optional XS components besides the Clone implementation, we don't
# end up with a bunch of different env vars.
#
## no critic (Modules::ProhibitAutomaticExportation)
our @EXPORT = qw( _clone );

1;

# ABSTRACT: Type constraints and coercions for Perl

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio - Type constraints and coercions for Perl

=head1 VERSION

version 0.53

=head1 SYNOPSIS

    package MyApp::Type::Library;

    use Specio::Declare;
    use Specio::Library::Builtins;

    declare(
        'PositiveInt',
        parent => t('Int'),
        inline => sub {
            $_[0]->parent->inline_check( $_[1] )
                . ' && ( '
                . $_[1]
                . ' > 0 )';
        },
    );

    # or ...

    declare(
        'PositiveInt',
        parent => t('Int'),
        where  => sub { $_[0] > 0 },
    );

    declare(
        'ArrayRefOfPositiveInt',
        parent => t(
            'ArrayRef',
            of => t('PositiveInt'),
        ),
    );

    coerce(
        'ArrayRefOfPositiveInt',
        from  => t('PositiveInt'),
        using => sub { [ $_[0] ] },
    );

    any_can_type(
        'Duck',
        methods => [ 'duck_walk', 'quack' ],
    );

    object_isa_type('MyApp::Person');

=head1 DESCRIPTION

The C<Specio> distribution provides classes for representing type constraints
and coercion, along with syntax sugar for declaring them.

Note that this is not a proper type system for Perl. Nothing in this
distribution will magically make the Perl interpreter start checking a value's
type on assignment to a variable. In fact, there's no built-in way to apply a
type to a variable at all.

Instead, you can explicitly check a value against a type, and optionally coerce
values to that type.

=head1 WHAT IS A TYPE?

At it's core, a type is simply a constraint. A constraint is code that checks a
value and returns true or false. Most constraints are represented by
L<Specio::Constraint::Simple> objects. However, there are other type constraint
classes for specialized kinds of constraints.

Types can be named or anonymous, and each type can have a parent type. A type's
constraint is optional because sometimes you may want to create a named subtype
of some existing type without adding additional constraints.

Constraints can be expressed either in terms of a simple subroutine reference
or in terms of an inline generator subroutine reference. The former is easier
to write but the latter is preferred because it allow for better optimization.

A type can also have an optional message generator subroutine reference. You
can use this to provide a more intelligent error message when a value does not
pass the constraint, though the default message should suffice for most cases.

Finally, you can associate a set of coercions with a type. A coercion is a
subroutine reference (or inline generator, like constraints), that takes a
value of one type and turns it into a value that matches the type the coercion
belongs to.

=head1 BUILTIN TYPES

This distribution ships with a set of builtin types representing the types
provided by the Perl interpreter itself. They are arranged in a hierarchy as
follows:

  Item
      Bool
      Maybe (of `a)
      Undef
      Defined
          Value
              Str
                  Num
                      Int
                  ClassName
          Ref
              ScalarRef (of `a)
              ArrayRef (of `a)
              HashRef (of `a)
              CodeRef
              RegexpRef
              GlobRef
              FileHandle
              Object

The C<Item> type accepts anything and everything.

The C<Bool> type only accepts C<undef>, C<0>, or C<1>.

The C<Undef> type only accepts C<undef>.

The C<Defined> type accepts anything I<except> C<undef>.

The C<Num> and C<Int> types are stricter about numbers than Perl is.
Specifically, they do not allow any sort of space in the number, nor do they
accept "Nan", "Inf", or "Infinity".

The C<ClassName> type constraint checks that the name is valid I<and> that the
class is loaded.

The C<FileHandle> type accepts either a glob, a scalar filehandle, or anything
that isa L<IO::Handle>.

All types accept overloaded objects that support the required operation. See
below for details.

=head2 Overloading

Perl's overloading is horribly broken and doesn't make much sense at all.

However, unlike Moose, all type constraints allow overloaded objects where they
make sense.

For types where overloading makes sense, we explicitly check that the object
provides the type overloading we expect. We I<do not> simply try to use the
object as the type in question and hope it works. This means that these checks
effectively ignore the C<fallback> setting for the overloaded object. In other
words, an object that overloads stringification will not pass the C<Bool> type
check unless it I<also> overloads boolification.

Most types do not check that the overloaded method actually returns something
that matches the constraint. This may change in the future.

The C<Bool> type accepts an object that implements C<bool> overloading.

The C<Str> type accepts an object that implements string (C<q{""}>)
overloading.

The C<Num> type accepts an object that implements numeric (C<'0+'}>)
overloading. The C<Int> type does as well, but it will check that the
overloading returns an actual integer.

The C<ClassName> type will accept an object with string overloading that
returns a class name.

To make this all more confusing, the C<Value> type will I<never> accept an
object, even though some of its subtypes will.

The various reference types all accept objects which provide the appropriate
overloading. The C<FileHandle> type accepts an object which overloads
globification as long as the returned glob is an open filehandle.

=head1 PARAMETERIZABLE TYPES

Any type followed by a type parameter C<of `a> in the hierarchy above can be
parameterized. The parameter is itself a type, so you can say you want an
"ArrayRef of Int", or even an "ArrayRef of HashRef of ScalarRef of ClassName".

When they are parameterized, the C<ScalarRef> and C<ArrayRef> types check that
the value(s) they refer to match the type parameter. For the C<HashRef> type,
the parameter applies to the values (keys are never checked).

=head2 Maybe

The C<Maybe> type is a special parameterized type. It allows for either
C<undef> or a value. All by itself, it is meaningless, since it is equivalent
to "Maybe of Item", which is equivalent to Item. When parameterized, it accepts
either an C<undef> or the type of its parameter.

This is useful for optional attributes or parameters. However, you're probably
better off making your code simply not pass the parameter at all This usually
makes for a simpler API.

=head1 REGISTRIES AND IMPORTING

Types are local to each package where they are used. When you "import" types
from some other library, you are actually making a copy of that type.

This means that a type named "Foo" in one package may not be the same as "Foo"
in another package. This has potential for confusion, but it also avoids the
magic action at a distance pollution that comes with a global type naming
system.

The registry is managed internally by the Specio distribution's modules, and is
not exposed to your code. To access a type, you always call C<t('TypeName')>.

This returns the named type or dies if no such type exists.

Because types are always copied on import, it's safe to create coercions on any
type. Your coercion from C<Str> to C<Int> will not be seen by any other
package, unless that package explicitly imports your C<Int> type.

When you import types, you import every type defined in the package you import
from. However, you I<can> overwrite an imported type with your own type
definition. You I<cannot> define the same type twice internally.

=head1 CREATING A TYPE LIBRARY

By default, all types created inside a package are invisible to other packages.
If you want to create a type library, you need to inherit from
L<Specio::Exporter> package:

  package MyApp::Type::Library;

  use parent 'Specio::Exporter';

  use Specio::Declare;
  use Specio::Library::Builtins;

  declare(
      'Foo',
      parent => t('Str'),
      where  => sub { $_[0] =~ /foo/i },
  );

Now the MyApp::Type::Library package will export a single type named C<Foo>. It
I<does not> re-export the types provided by L<Specio::Library::Builtins>.

If you want to make your library re-export some other libraries types, you can
ask for this explicitly:

  package MyApp::Type::Library;

  use parent 'Specio::Exporter';

  use Specio::Declare;
  use Specio::Library::Builtins -reexport;

  declare( 'Foo, ... );

Now MyApp::Types::Library exports any types it defines, as well as all the
types defined in L<Specio::Library::Builtins>.

=head1 DECLARING TYPES

Use the L<Specio::Declare> module to declare types. It exports a set of helpers
for declaring types. See that module's documentation for more details on these
helpers.

=head1 USING SPECIO WITH L<Moose>

This should just work. Use a Specio type anywhere you'd specify a type.

=head1 USING SPECIO WITH L<Moo>

Using Specio with Moo is easy. You can pass Specio constraint objects as C<isa>
parameters for attributes. For coercions, simply call C<< $type->coercion_sub
>>.

    package Foo;

    use Specio::Declare;
    use Specio::Library::Builtins;
    use Moo;

    my $str_type = t('Str');
    has string => (
       is  => 'ro',
       isa => $str_type,
    );

    my $ucstr = declare(
        'UCStr',
        parent => t('Str'),
        where  => sub { $_[0] =~ /^[A-Z]+$/ },
    );

    coerce(
        $ucstr,
        from  => t('Str'),
        using => sub { return uc $_[0] },
    );

    has ucstr => (
        is     => 'ro',
        isa    => $ucstr,
        coerce => $ucstr->coercion_sub,
    );

The subs returned by Specio use L<Sub::Quote> internally and are suitable for
inlining.

=head1 USING SPECIO WITH OTHER THINGS

See L<Specio::Constraint::Simple> for the API that all constraint objects
share.

=head1 L<Moose>, L<MooseX::Types>, and Specio

This module aims to supplant both L<Moose>'s built-in type system (see
L<Moose::Util::TypeConstraints> aka MUTC) and L<MooseX::Types>, which attempts
to patch some of the holes in the Moose built-in type design.

Here are some of the salient differences:

=over 4

=item * Types names are strings, but they're not global

Unlike Moose and MooseX::Types, type names are always local to the current
package. There is no possibility of name collision between different modules,
so you can safely use short type names.

Unlike MooseX::Types, types are strings, so there is no possibility of
colliding with existing class or subroutine names.

=item * No type auto-creation

Types are always retrieved using the C<t()> subroutine. If you pass an unknown
name to this subroutine it dies. This is different from Moose and
MooseX::Types, which assume that unknown names are class names.

=item * Anon types are explicit

With L<Moose> and L<MooseX::Types>, you use the same subroutine, C<subtype()>,
to declare both named and anonymous types. With Specio, you use C<declare()>
for named types and C<anon()> for anonymous types.

=item * Class and object types are separate

Moose and MooseX::Types have C<class_type> and C<duck_type>. The former type
requires an object, while the latter accepts a class name or object.

With Specio, the distinction between accepting an object versus object or class
is explicit. There are six declaration helpers, C<object_can_type>,
C<object_does_type>, C<object_isa_type>, C<any_can_type>, C<any_does_type>, and
C<any_isa_type>.

=item * Overloading support is baked in

Perl's overloading is quite broken but ignoring it makes Moose's type system
frustrating to use in many cases.

=item * Types can either have a constraint or inline generator, not both

Moose and MooseX::Types types can be defined with a subroutine reference as the
constraint, an inline generator subroutine, or both. This is purely for
backwards compatibility, and it makes the internals more complicated than they
need to be.

With Specio, a constraint can have I<either> a subroutine reference or an
inline generator, not both.

=item * Coercions can be inlined

I simply never got around to implementing this in Moose.

=item * No crazy coercion features

Moose has some bizarre (and mostly) undocumented features relating to coercions
and parameterizable types. This is a misfeature.

=back

=head1 OPTIONAL PREREQS

There are several optional prereqs that if installed will make this
distribution better in some way.

=over 4

=item * L<Ref::Util>

Installing this will speed up a number of type checks for built-in types.

=item * L<XString>

If this is installed it will be loaded instead of the L<B> module if you have
Perl 5.10 or greater. This module is much more memory efficient than loading
all of L<B>.

=item * L<Sub::Util> or L<Sub::Name>

If one of these is installed then stack traces that end up in Specio code will
have much better subroutine names for any frames.

=back

=head1 FORCING PURE PERL MODE

For some use cases (notably fatpacking a program), you may want to force Specio
to use pure Perl code instead of XS code. This can be done by setting the
environment variable C<SPECIO_IMPLEMENTATION> to C<PP>.

=head1 WHY THE NAME?

This distro was originally called "Type", but that's an awfully generic top
level namespace. Specio is Latin for for "look at" and "spec" is the root for
the word "species". It's short, relatively easy to type, and not used by any
other distro.

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/Specio/issues>.

=head1 SOURCE

The source code repository for Specio can be found at L<https://github.com/houseabsolute/Specio>.

=head1 DONATIONS

If you'd like to thank me for the work I've done on this module, please
consider making a "donation" to me via PayPal. I spend a lot of free time
creating free software, and would appreciate any support you'd care to offer.

Please note that B<I am not suggesting that you must do this> in order for me
to continue working on this particular software. I will continue to do so,
inasmuch as I have in the past, for as long as it interests me.

Similarly, a donation made in this way will probably not make me work on this
software much more, unless I get so many donations that I can consider working
on free software full time (let's all have a chuckle at that together).

To donate, log into PayPal and send money to autarch@urth.org, or use the
button at L<https://houseabsolute.com/foss-donations/>.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 CONTRIBUTORS

=for stopwords Andrew Rodland Chris White cpansprout Graham Knop Karen Etheridge Vitaly Lipatov

=over 4

=item *

Andrew Rodland <andrewr@vimeo.com>

=item *

Chris White <chrisw@leehayes.com>

=item *

cpansprout <cpansprout@gmail.com>

=item *

Graham Knop <haarg@haarg.org>

=item *

Karen Etheridge <ether@cpan.org>

=item *

Vitaly Lipatov <lav@altlinux.ru>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2012 - 2025 by Dave Rolsky.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
