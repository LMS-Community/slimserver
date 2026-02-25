package Specio::Library::Builtins;

use strict;
use warnings;

our $VERSION = '0.53';

use parent 'Specio::Exporter';

use List::Util 1.33 ();
use overload        ();
use re              ();
use Scalar::Util    ();
use Specio::Constraint::Parameterizable;
use Specio::Declare;
use Specio::Helpers ();

BEGIN {
    local $@ = undef;
    my $has_ref_util
        = eval { require Ref::Util; Ref::Util->VERSION('0.112'); 1 };
    sub _HAS_REF_UTIL () {$has_ref_util}
}

declare(
    'Item',
    inline => sub {'1'}
);

declare(
    'Undef',
    parent => t('Item'),
    inline => sub {
        '!defined(' . $_[1] . ')';
    }
);

declare(
    'Defined',
    parent => t('Item'),
    inline => sub {
        'defined(' . $_[1] . ')';
    }
);

declare(
    'Bool',
    parent => t('Item'),
    inline => sub {
        return sprintf( <<'EOF', ( $_[1] ) x 7 );
(
    (
        !ref( %s )
        && (
               !defined( %s )
               || %s eq q{}
               || %s eq '1'
               || %s eq '0'
           )
    )
    ||
    (
        Scalar::Util::blessed( %s )
        && defined overload::Method( %s, 'bool' )
    )
)
EOF
    }
);

declare(
    'Value',
    parent => t('Defined'),
    inline => sub {
        $_[0]->parent->inline_check( $_[1] ) . ' && !ref(' . $_[1] . ')';
    }
);

declare(
    'Ref',
    parent => t('Defined'),

    # no need to call parent - ref also checks for definedness
    inline => sub { 'ref(' . $_[1] . ')' }
);

declare(
    'Str',
    parent => t('Value'),
    inline => sub {
        return sprintf( <<'EOF', ( $_[1] ) x 6 );
(
    (
        defined( %s )
        && !ref( %s )
        && (
               ( ref( \%s ) eq 'SCALAR' )
               || do { ( ref( \( my $val = %s ) ) eq 'SCALAR' ) }
           )
    )
    ||
    (
        Scalar::Util::blessed( %s )
        && defined overload::Method( %s, q{""} )
    )
)
EOF
    }
);

declare(
    'Num',
    parent => t('Str'),
    inline => sub {
        return sprintf( <<'EOF', ( $_[1] ) x 5 );
(
    (
        defined( %s )
        && !ref( %s )
        && (
               do {
                   ( my $val = %s ) =~
                       /\A
                        -?[0-9]+(?:\.[0-9]+)?
                        (?:[Ee][\-+]?[0-9]+)?
                        \z/x
               }
           )
    )
    ||
    (
        Scalar::Util::blessed( %s )
        && defined overload::Method( %s, '0+' )
    )
)
EOF
    }
);

declare(
    'Int',
    parent => t('Num'),
    inline => sub {
        return sprintf( <<'EOF', ( $_[1] ) x 6 );
(
    (
        defined( %s )
        && !ref( %s )
        && (
               do {
                   my $val1 = %s;
                   $val1 =~ /\A-?[0-9]+(?:[Ee]\+?[0-9]+)?\z/
                   && $val1 == int($val1)
               }
           )
    )
    ||
    (
        Scalar::Util::blessed( %s )
        && defined overload::Method( %s, '0+' )
        && (
               do {
                   my $val2 = %s + 0;
                   $val2 =~ /\A-?[0-9]+(?:[Ee]\+?[0-9]+)?\z/
                   && $val2 == int($val2)
               }
           )
    )
)
EOF
    }
);

{
    my $ref_check
        = _HAS_REF_UTIL
        ? 'Ref::Util::is_plain_coderef(%s)'
        : q{ref(%s) eq 'CODE'};

    declare(
        'CodeRef',
        parent => t('Ref'),
        inline => sub {
            return sprintf( <<"EOF", ( $_[1] ) x 3 );
(
    $ref_check
    ||
    (
        Scalar::Util::blessed( %s )
        && defined overload::Method( %s, '&{}' )
    )
)
EOF
        }
    );
}

{
    # This is a 5.8 back-compat shim stolen from Type::Tiny's Devel::Perl58Compat
    # module.
    unless ( exists &re::is_regexp || _HAS_REF_UTIL ) {
        require B;
        *re::is_regexp = sub {
            ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
            eval { B::svref_2object( $_[0] )->MAGIC->TYPE eq 'r' };
        };
    }

    my $ref_check
        = _HAS_REF_UTIL
        ? 'Ref::Util::is_regexpref(%s)'
        : 're::is_regexp(%s)';

    declare(
        'RegexpRef',
        parent => t('Ref'),
        inline => sub {
            return sprintf( <<"EOF", ( $_[1] ) x 3 );
(
    $ref_check
    ||
    (
        Scalar::Util::blessed( %s )
        && defined overload::Method( %s, 'qr' )
    )
)
EOF
        },
    );
}

{
    my $ref_check
        = _HAS_REF_UTIL
        ? 'Ref::Util::is_plain_globref(%s)'
        : q{ref( %s ) eq 'GLOB'};

    declare(
        'GlobRef',
        parent => t('Ref'),
        inline => sub {
            return sprintf( <<"EOF", ( $_[1] ) x 3 );
(
    $ref_check
    ||
    (
        Scalar::Util::blessed( %s )
        && defined overload::Method( %s, '*{}' )
    )
)
EOF
        }
    );
}

{
    my $ref_check
        = _HAS_REF_UTIL
        ? 'Ref::Util::is_plain_globref(%s)'
        : q{ref( %s ) eq 'GLOB'};

    # NOTE: scalar filehandles are GLOB refs, but a GLOB ref is not always a
    # filehandle
    declare(
        'FileHandle',
        parent => t('Ref'),
        inline => sub {
            return sprintf( <<"EOF", ( $_[1] ) x 6 );
(
    (
        $ref_check
        && Scalar::Util::openhandle( %s )
    )
    ||
    (
        Scalar::Util::blessed( %s )
        &&
        (
            %s->isa('IO::Handle')
            ||
            (
                defined overload::Method( %s, '*{}' )
                && Scalar::Util::openhandle( *{ %s } )
            )
        )
    )
)
EOF
        }
    );
}

{
    my $ref_check
        = _HAS_REF_UTIL
        ? 'Ref::Util::is_blessed_ref(%s)'
        : 'Scalar::Util::blessed(%s)';

    declare(
        'Object',
        parent => t('Ref'),
        inline => sub { sprintf( $ref_check, $_[1] ) },
    );
}

declare(
    'ClassName',
    parent => t('Str'),
    inline => sub {
        return
            sprintf(
            <<'EOF', $_[0]->parent->inline_check( $_[1] ), ( $_[1] ) x 2 );
(
    ( %s )
    && length "%s"
    && Specio::Helpers::is_class_loaded( "%s" )
)
EOF
    },
);

{
    my $ref_check
        = _HAS_REF_UTIL
        ? 'Ref::Util::is_plain_scalarref(%s) || Ref::Util::is_plain_refref(%s)'
        : q{ref( %s ) eq 'SCALAR' || ref( %s ) eq 'REF'};

    my $base_scalarref_check = sub {
        return sprintf( <<"EOF", ( $_[0] ) x 4 );
(
    (
        $ref_check
    )
    ||
    (
        Scalar::Util::blessed( %s )
        && defined overload::Method( %s, '\${}' )
    )
)
EOF
    };

    declare(
        'ScalarRef',
        type_class => 'Specio::Constraint::Parameterizable',
        parent     => t('Ref'),
        inline     => sub { $base_scalarref_check->( $_[1] ) },
        parameterized_inline_generator => sub {
            shift;
            my $parameter = shift;
            my $val       = shift;

            return sprintf(
                '( ( %s ) && ( %s ) )',
                $base_scalarref_check->($val),
                $parameter->inline_check( '${' . $val . '}' ),
            );
        }
    );
}

{
    my $ref_check
        = _HAS_REF_UTIL
        ? 'Ref::Util::is_plain_arrayref(%s)'
        : q{ref( %s ) eq 'ARRAY'};

    my $base_arrayref_check = sub {
        return sprintf( <<"EOF", ( $_[0] ) x 3 );
(
    $ref_check
    ||
    (
        Scalar::Util::blessed( %s )
        && defined overload::Method( %s, '\@{}' )
    )
)
EOF
    };

    declare(
        'ArrayRef',
        type_class => 'Specio::Constraint::Parameterizable',
        parent     => t('Ref'),
        inline     => sub { $base_arrayref_check->( $_[1] ) },
        parameterized_inline_generator => sub {
            shift;
            my $parameter = shift;
            my $val       = shift;

            return sprintf(
                '( ( %s ) && ( List::Util::all { %s } @{ %s } ) )',
                $base_arrayref_check->($val),
                $parameter->inline_check('$_'),
                $val,
            );
        }
    );
}

{
    my $ref_check
        = _HAS_REF_UTIL
        ? 'Ref::Util::is_plain_hashref(%s)'
        : q{ref( %s ) eq 'HASH'};

    my $base_hashref_check = sub {
        return sprintf( <<"EOF", ( $_[0] ) x 3 );
(
    $ref_check
    ||
    (
        Scalar::Util::blessed( %s )
        && defined overload::Method( %s, '%%{}' )
    )
)
EOF
    };

    declare(
        'HashRef',
        type_class => 'Specio::Constraint::Parameterizable',
        parent     => t('Ref'),
        inline     => sub { $base_hashref_check->( $_[1] ) },
        parameterized_inline_generator => sub {
            shift;
            my $parameter = shift;
            my $val       = shift;

            return sprintf(
                '( ( %s ) && ( List::Util::all { %s } values %%{ %s } ) )',
                $base_hashref_check->($val),
                $parameter->inline_check('$_'),
                $val,
            );
        }
    );
}

declare(
    'Maybe',
    type_class                     => 'Specio::Constraint::Parameterizable',
    parent                         => t('Item'),
    inline                         => sub {'1'},
    parameterized_inline_generator => sub {
        shift;
        my $parameter = shift;
        my $val       = shift;

        return sprintf( <<'EOF', $val, $parameter->inline_check($val) );
( !defined( %s ) || ( %s ) )
EOF
    },
);

1;

# ABSTRACT: Implements type constraint objects for Perl's built-in types

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Library::Builtins - Implements type constraint objects for Perl's built-in types

=head1 VERSION

version 0.53

=head1 DESCRIPTION

This library provides a set of types parallel to those provided by Moose.

The types are in the following hierarchy

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

=head2 Item

Accepts any value

=head2 Bool

Accepts a non-reference that is C<undef>, an empty string, C<0>, or C<1>. It
also accepts any object which overloads boolification.

=head2 Maybe (of `a)

A parameterizable type which accepts C<undef> or the type C<`a>. If not
parameterized this type will accept any value.

=head2 Undef

Only accepts C<undef>.

=head2 Value

Accepts any non-reference value.

=head2 Str

Accepts any non-reference value or an object which overloads stringification.

=head2 Num

Accepts nearly the same values as C<Scalar::Util::looks_like_number>, but does
not accept numbers with leading or trailing spaces, infinities, or NaN. Also
accepts an object which overloads numification.

=head2 Int

Accepts any integer value, or an object which overloads numification and
numifies to an integer.

=head2 ClassName

Accepts any value which passes C<Str> where the string is a loaded package.

=head2 Ref

Accepts any reference.

=head2 ScalarRef (of `a)

Accepts a scalar reference or an object which overloads scalar dereferencing.
If parameterized, the dereferenced value must be of type C<`a>.

=head2 ArrayRef (of `a)

Accepts a array reference or an object which overloads array dereferencing. If
parameterized, the values in the arrayref must be of type C<`a>.

=head2 HashRef (of `a)

Accepts a hash reference or an object which overloads hash dereferencing. If
parameterized, the values in the hashref must be of type C<`a>.

=head2 CodeRef

Accepts a code (sub) reference or an object which overloads code dereferencing.

=head2 RegexpRef

Accepts a regex object created by C<qr//> or an object which overloads regex
interpolation.

=head2 GlobRef

Accepts a glob reference or an object which overloads glob dereferencing.

=head2 FileHandle

Accepts a glob reference which is an open file handle, any C<IO::Handle> Object
or subclass, or an object which overloads glob dereferencing and returns a glob
reference which is an open file handle.

=head2 Object

Accepts any blessed object.

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
