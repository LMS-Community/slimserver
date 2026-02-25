package Params::ValidationCompiler;

use strict;
use warnings;

our $VERSION = '0.31';

use Params::ValidationCompiler::Compiler;

use Exporter qw( import );

our @EXPORT_OK = qw( compile source_for validation_for );

sub validation_for {
    return Params::ValidationCompiler::Compiler->new(@_)->subref;
}

## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';
*compile = \&validation_for;
## use critic

sub source_for {
    return Params::ValidationCompiler::Compiler->new(@_)->source;
}

1;

# ABSTRACT: Build an optimized subroutine parameter validator once, use it forever

__END__

=pod

=encoding UTF-8

=head1 NAME

Params::ValidationCompiler - Build an optimized subroutine parameter validator once, use it forever

=head1 VERSION

version 0.31

=head1 SYNOPSIS

    use Types::Standard qw( Int Str );
    use Params::ValidationCompiler qw( validation_for );

    {
        my $validator = validation_for(
            params => {
                foo => { type => Int },
                bar => {
                    type     => Str,
                    optional => 1,
                },
                baz => {
                    type    => Int,
                    default => 42,
                },
            },
        );

        sub foo {
            my %args = $validator->(@_);
        }
    }

    {
        my $validator = validation_for(
            params => [
                { type => Int },
                {
                    type     => Str,
                    optional => 1,
                },
            ],
        );

        sub bar {
            my ( $int, $str ) = $validator->(@_);
        }
    }

    {
        my $validator = validation_for(
            params => [
                foo => { type => Int },
                bar => {
                    type     => Str,
                    optional => 1,
                },
            ],
            named_to_list => 1,
        );

        sub baz {
            my ( $foo, $bar ) = $validator->(@_);
        }
    }

=head1 DESCRIPTION

This module creates a customized, highly efficient parameter checking
subroutine. It can handle named or positional parameters, and can return the
parameters as key/value pairs or a list of values.

In addition to type checks, it also supports parameter defaults, optional
parameters, and extra "slurpy" parameters.

=for Pod::Coverage compile

=head1 PARAMETERS

This module has two options exports, C<validation_for> and C<source_for>. Both
of these subs accept the same options:

=head2 params

An arrayref or hashref containing a parameter specification.

If you pass a hashref then the generated validator sub will expect named
parameters. The C<params> value should be a hashref where the parameter names
are keys and the specs are the values.

If you pass an arrayref and C<named_to_list> is false, the validator will
expect positional params. Each element of the C<params> arrayref should be a
parameter spec.

If you pass an arrayref and C<named_to_list> is true, the validator will expect
named params, but will return a list of values. In this case the arrayref
should contain a I<list> of key/value pairs, where parameter names are the keys
and the specs are the values.

Each spec can contain either a boolean or hashref. If the spec is a boolean,
this indicates required (true) or optional (false).

The spec hashref accepts the following keys:

=over 4

=item * type

A type object. This can be a L<Moose> type (from L<Moose> or L<MooseX::Types>),
a L<Type::Tiny> type, or a L<Specio> type.

If the type has coercions, those will always be used.

=item * default

This can either be a simple (non-reference) scalar or a subroutine reference.
The sub ref will be called without any arguments (for now).

=item * optional

A boolean indicating whether or not the parameter is optional. By default,
parameters are required unless you provide a default.

=back

=head2 slurpy

If this is a simple true value, then the generated subroutine accepts
additional arguments not specified in C<params>. By default, extra arguments
cause an exception.

You can also pass a type constraint here, in which case all extra arguments
must be values of the specified type.

=head2 named_to_list

If this is true, the generated subroutine will expect a list of key-value pairs
or a hashref and it will return a list containing only values. The C<params>
you pass must be a arrayref of key-value pairs. The order of these pairs
determines the order in which values are returned.

You cannot combine C<slurpy> with C<named_to_list> as there is no way to know
how to order the extra return values.

=head2 return_object

If this is true, the generated subroutine will return an object instead of a
hashref. You cannot set this option to true if you set either or C<slurpy> or
C<named_to_list>.

The object's methods correspond to the parameter names passed to the
subroutine. While calling methods on an object is slower than accessing a
hashref, the advantage is that if you typo a parameter name you'll get a
helpful error.

If you have L<Class::XSAccessor> installed then this will be used to create the
class's methods, which makes it fairly fast.

The returned object is in a generated class. Do not rely on this class name
being anything in specific, and don't check this object using C<isa>, C<DOES>,
or anything similar.

When C<return_object> is true, the parameter spec hashref also accepts to the
following additional keys:

=over 4

=item * getter

Use this to set an explicit getter method name for the parameter. By default
the method name will be the same as the parameter name. Note that if the
parameter name is not a valid sub name, then you will get an error compiling
the validation sub unless you specify a getter for the parameter.

=item * predicate

Use this to ask for a predicate method to be created for this parameter. The
predicate method returns true if the parameter was passed and false if it
wasn't. Note that this is only useful for optional parameters, but you can ask
for a predicate for any parameter.

=back

=head1 EXPORTS

The exported subs are:

=head2 validation_for(...)

This returns a subroutine that implements the specific parameter checking. This
subroutine expects to be given the parameters to validate in C<@_>. If all the
parameters are valid, it will return the validated parameters (with defaults as
appropriate), either as a list of key-value pairs or as a list of just values.
If any of the parameters are invalid it will throw an exception.

For validators expected named params, the generated subroutine accepts either a
list of key-value pairs or a single hashref. Otherwise the validator expects a
list of values.

For now, you must shift off the invocant yourself.

This subroutine accepts the following additional parameters:

=over 4

=item * name

If this is given, then the generated subroutine will be named using
L<Sub::Util>. This is strongly recommended as it makes it possible to
distinguish different check subroutines when profiling or in stack traces.

This name will also be used in some exception messages, even if L<Sub::Util> is
not available.

Note that you must install L<Sub::Util> yourself separately, as it is not
required by this distribution, in order to avoid requiring a compiler.

=item * name_is_optional

If this is true, then the name is ignored when C<Sub::Util> is not installed.
If this is false, then passing a name when L<Sub::Util> cannot be loaded causes
an exception.

This is useful for CPAN modules where you want to set a name if you can, but
you do not want to add a prerequisite on L<Sub::Util>.

=item * debug

Sets the C<EVAL_CLOSURE_PRINT_SOURCE> environment variable to true before
calling C<Eval::Closure::eval_closure()>. This causes the source of the
subroutine to be printed before it's C<eval>'d.

=back

=head2 source_for(...)

This returns a two element list. The first is a string containing the source
code for the generated sub. The second is a hashref of "environment" variables
to be used when generating the subroutine. These are the arguments that are
passed to L<Eval::Closure>.

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/Params-ValidationCompiler/issues>.

=head1 SOURCE

The source code repository for Params-ValidationCompiler can be found at L<https://github.com/houseabsolute/Params-ValidationCompiler>.

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

=for stopwords Gregory Oschwald Tomasz Konojacki

=over 4

=item *

Gregory Oschwald <goschwald@maxmind.com>

=item *

Gregory Oschwald <oschwald@gmail.com>

=item *

Tomasz Konojacki <me@xenu.pl>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2016 - 2023 by Dave Rolsky.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
