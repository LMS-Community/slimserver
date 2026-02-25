package Specio::Library::Structured;

use strict;
use warnings;

our $VERSION = '0.53';

use parent 'Specio::Exporter';

use Carp         qw( confess );
use Scalar::Util qw( blessed );
use Specio::Constraint::Structurable;
use Specio::Declare;
use Specio::Library::Builtins;
use Specio::Library::Structured::Dict;
use Specio::Library::Structured::Map;
use Specio::Library::Structured::Tuple;
use Specio::TypeChecks qw( does_role );

## no critic (Variables::ProtectPrivateVars)
declare(
    'Dict',
    type_class => 'Specio::Constraint::Structurable',
    parent     => Specio::Library::Structured::Dict->parent,
    inline     => \&Specio::Library::Structured::Dict::_inline,
    parameterization_args_builder =>
        \&Specio::Library::Structured::Dict::_parameterization_args_builder,
    name_builder => \&Specio::Library::Structured::Dict::_name_builder,
    structured_inline_generator =>
        \&Specio::Library::Structured::Dict::_structured_inline_generator,
);

declare(
    'Map',
    type_class => 'Specio::Constraint::Structurable',
    parent     => Specio::Library::Structured::Map->parent,
    inline     => \&Specio::Library::Structured::Map::_inline,
    parameterization_args_builder =>
        \&Specio::Library::Structured::Map::_parameterization_args_builder,
    name_builder => \&Specio::Library::Structured::Map::_name_builder,
    structured_inline_generator =>
        \&Specio::Library::Structured::Map::_structured_inline_generator,
);

declare(
    'Tuple',
    type_class => 'Specio::Constraint::Structurable',
    parent     => Specio::Library::Structured::Tuple->parent,
    inline     => \&Specio::Library::Structured::Tuple::_inline,
    parameterization_args_builder =>
        \&Specio::Library::Structured::Tuple::_parameterization_args_builder,
    name_builder => \&Specio::Library::Structured::Tuple::_name_builder,
    structured_inline_generator =>
        \&Specio::Library::Structured::Tuple::_structured_inline_generator,
);
## use critic

sub optional {
    return { optional => shift };
}

sub slurpy {
    return { slurpy => shift };
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _also_export {qw( optional slurpy )}
## use critic

1;

# ABSTRACT: Structured types for Specio (Dict, Map, Tuple)

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Library::Structured - Structured types for Specio (Dict, Map, Tuple)

=head1 VERSION

version 0.53

=head1 SYNOPSIS

    use Specio::Library::Builtins;
    use Specio::Library::String;
    use Specio::Library::Structured;

    my $map = t(
        'Map',
        of => {
            key   => t('NonEmptyStr'),
            value => t('Int'),
        },
    );
    my $tuple = t(
        'Tuple',
        of => [ t('Str'), t('Num') ],
    );
    my $dict = t(
        'Dict',
        of => {
            kv => {
                name => t('Str'),
                age  => t('Int'),
            },
        },
    );

=head1 DESCRIPTION

This library provides a set of structured types for Specio, C<Dict>, C<Map>,
and C<Tuple>. This library also exports two helper subs used for some types,
C<optional> and C<slurpy>.

All structured types are parameterized by calling C<< t( 'Type Name', of => ...
) >>. The arguments passed after C<of> vary for each type.

=head2 Dict

A C<Dict> is a hashref with a well-defined set of keys and types for those key.

The argument passed to C<of> should be a single hashref. That hashref must
contain a C<kv> key defining the expected keys and the types for their values.
This C<kv> value is itself a hashref. If a key/value pair is optional, use
C<optional> around the I<type> for that key:

    my $person = t(
        'Dict',
        of => {
            kv => {
                first  => t('NonEmptyStr'),
                middle => optional( t('NonEmptyStr') ),
                last   => t('NonEmptyStr'),
            },
        },
    );

If a key is optional, then it can be omitted entirely, but if it passed then
it's type will be checked, so it cannot just be set to C<undef>.

You can also pass a C<slurpy> key. If this is passed, then the C<Dict> will
allow other, unknown keys, as long as they match the specified type:

    my $person = t(
        'Dict',
        of => {
            kv => {
                first  => t('NonEmptyStr'),
                middle => optional( t('NonEmptyStr') ),
                last   => t('NonEmptyStr'),
            },
            slurpy => t('Int'),
        },
    );

=head2 Map

A C<Map> is a hashref with specified types for its keys and values, but no
well-defined key names.

The argument passed to C<of> should be a single hashref with two keys, C<key>
and C<value>. The type for the C<key> will typically be some sort of key, but
if you're using a tied hash or an object with hash overloading it could
conceivably be any sort of value.

=head2 Tuple

A C<Tuple> is an arrayref with a fixed set of members in a specific order.

The argument passed to C<of> should be a single arrayref consisting of types.
You can mark a slot in the C<Tuple> as optional by wrapping the type in a call
to C<optional>:

    my $record = t(
        'Tuple',
        of => [
            t('PositiveInt'),
            t('Str'),
            optional( t('Num') ),
            optional( t('Num') ),
        ],
    );

You can have as many C<optional> elements as you want, but they must always
come in sequence at the end of the tuple definition. You cannot interleave
required and optional elements.

You can also make the Tuple accept an arbitrary number of values by wrapping
the last type in a call to C<slurpy>:

    my $record = t(
        'Tuple',
        of => [
            t('PositiveInt'),
            t('Str'),
            slurpy( t('Num') ),
        ],
    );

In this case, the C<Tuple> will require the first two elements and then allow
any number (including zero) of C<Num> elements.

You cannot mix C<optional> and C<slurpy> in a C<Tuple> definition.

=for Pod::Coverage optional slurpy

=head1 LIMITATIONS

Currently all structured types require that the types they are structured with
can be inlined. This may change in the future, but inlining all your types is a
really good idea, so you should do that anyway.

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
