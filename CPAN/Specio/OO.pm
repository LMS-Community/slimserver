package Specio::OO;

use strict;
use warnings;

use Carp qw( confess );
use List::Util 1.33 qw( all );
use MRO::Compat;
use Role::Tiny;
use Scalar::Util        qw( weaken );
use Specio              qw( _clone );
use Specio::Helpers     qw( perlstring );
use Specio::PartialDump qw( partial_dump );
use Specio::TypeChecks;

our $VERSION = '0.53';

use Exporter qw( import );

## no critic (Modules::ProhibitAutomaticExportation)
our @EXPORT = qw(
    clone
    _ooify
);
## use critic

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _ooify {
    my $class = shift;

    my $attrs = $class->_attrs;
    for my $name ( sort keys %{$attrs} ) {
        my $attr = $attrs->{$name};

        _inline_reader( $class, $name, $attr );
        _inline_predicate( $class, $name, $attr );
    }

    _inline_constructor($class);
}
## use critic

sub _inline_reader {
    my $class = shift;
    my $name  = shift;
    my $attr  = shift;

    my $reader;
    if ( $attr->{lazy} && ( my $builder = $attr->{builder} ) ) {
        my $source = <<'EOF';
sub {
     unless ( exists $_[0]->{%s} ) {
         $_[0]->{%s} = $_[0]->%s;
         Scalar::Util::weaken( $_[0]->{%s} ) if %s && ref $_[0]->{%s};
     }
     $_[0]->{%s};
}
EOF
        $reader = sprintf(
            $source,
            $name,
            $name,
            $builder,
            $name,
            ( $attr->{weak_ref} ? 1 : 0 ),
            $name,
            $name,
        );
    }
    else {
        $reader = sprintf( 'sub { $_[0]->{%s} }', $name );
    }

    {
        ## no critic (TestingAndDebugging::ProhibitNoStrict)
        no strict 'refs';
        *{ $class . '::' . $name } = _eval_or_die(
            $reader, $class . '->' . $name,
        );
    }
}

sub _inline_predicate {
    my $class = shift;
    my $name  = shift;
    my $attr  = shift;

    return unless $attr->{predicate};

    my $predicate = "sub { exists \$_[0]->{$name} }";

    {
        ## no critic (TestingAndDebugging::ProhibitNoStrict)
        no strict 'refs';
        *{ $class . '::' . $attr->{predicate} } = _eval_or_die(
            $predicate, $class . '->' . $attr->{predicate},
        );
    }
}

my @RolesWithBUILD = qw( Specio::Constraint::Role::Interface );

# This is an optimization to avoid calling this many times over:
#
#     Specio::TypeChecks->can( 'is_' . $attr->{isa} )
my %TypeChecks;

BEGIN {
    for my $sub (@Specio::TypeChecks::EXPORT_OK) {
        my ($type) = $sub =~ /^is_(.+)$/
            or next;
        $TypeChecks{$type} = Specio::TypeChecks->can($sub);
    }
}

sub _inline_constructor {
    my $class = shift;

    my @build_subs;
    for my $parent ( @{ mro::get_linear_isa($class) } ) {
        {
            ## no critic (TestingAndDebugging::ProhibitNoStrict)
            no strict 'refs';
            push @build_subs, $parent . '::BUILD'
                if defined &{ $parent . '::BUILD' };
        }
    }

    # This is all a hack to avoid needing Class::Method::Modifiers to add a
    # BUILD from a role. We can't just call the method in the role "BUILD" or
    # it will be shadowed by a class's BUILD. So we give it a wacky unique
    # name. We need to explicitly know which roles have a _X_BUILD method
    # because Role::Tiny doesn't provide a way to list all the roles applied
    # to a class.
    for my $role (@RolesWithBUILD) {
        if ( Role::Tiny::does_role( $class, $role ) ) {
            ( my $build_name = $role ) =~ s/::/_/g;
            $build_name = q{_} . $build_name . '_BUILD';
            push @build_subs, $role . '::' . $build_name;
        }
    }

    my $constructor = <<'EOF';
sub {
    my $class = shift;

    my %p = do {
        if ( @_ == 1 ) {
            if ( ref $_[0] eq 'HASH' ) {
                %{ shift() };
            }
            else {
                Specio::OO::_constructor_confess(
                    Specio::OO::_bad_args_message( $class, @_ ) );
            }
        }
        else {
            Specio::OO::_constructor_confess(
                Specio::OO::_bad_args_message( $class, @_ ) )
                if @_ % 2;
            @_;
        }
    };

    my $self = bless {}, $class;

EOF

    my $attrs = $class->_attrs;
    for my $name ( sort keys %{$attrs} ) {
        my $attr     = $attrs->{$name};
        my $key_name = defined $attr->{init_arg} ? $attr->{init_arg} : $name;

        if ( $attr->{required} ) {
            $constructor .= <<"EOF";
    Specio::OO::_constructor_confess(
        "$class->new requires a $key_name argument.")
        unless exists \$p{$key_name};
EOF
        }

        if ( $attr->{builder} && !$attr->{lazy} ) {
            my $builder = $attr->{builder};
            $constructor .= <<"EOF";
    \$p{$key_name} = $class->$builder unless exists \$p{$key_name};
EOF
        }

        if ( $attr->{isa} ) {
            my $validator;
            if ( $TypeChecks{ $attr->{isa} } ) {
                $validator
                    = 'Specio::TypeChecks::is_'
                    . $attr->{isa}
                    . "( \$p{$key_name} )";
            }
            else {
                my $quoted_class = perlstring( $attr->{isa} );
                $validator
                    = "Specio::TypeChecks::isa_class( \$p{$key_name}, $quoted_class )";
            }

            $constructor .= <<"EOF";
    if ( exists \$p{$key_name} && !$validator ) {
        Carp::confess(
            Specio::OO::_bad_value_message(
                "The value you provided to $class->new for $key_name is not a valid $attr->{isa}.",
                \$p{$key_name},
            )
        );
    }
EOF
        }

        if ( $attr->{does} ) {
            my $quoted_role = perlstring( $attr->{does} );
            $constructor .= <<"EOF";
    if ( exists \$p{$key_name} && !Specio::TypeChecks::does_role( \$p{$key_name}, $quoted_role ) ) {
        Carp::confess(
            Specio::OO::_bad_value_message(
                "The value you provided to $class->new for $key_name does not do the $attr->{does} role.",
                \$p{$key_name},
            )
        );
    }
EOF
        }

        if ( $attr->{weak_ref} ) {
            $constructor .= "    Scalar::Util::weaken( \$p{$key_name} );\n";
        }

        $constructor
            .= "    \$self->{$name} = \$p{$key_name} if exists \$p{$key_name};\n";

        $constructor .= "\n";
    }

    $constructor .= '    $self->' . $_ . "(\\%p);\n" for @build_subs;
    $constructor .= <<'EOF';

    return $self;
}
EOF

    {
        ## no critic (TestingAndDebugging::ProhibitNoStrict)
        no strict 'refs';
        *{ $class . '::new' } = _eval_or_die(
            $constructor, $class . '->new',
        );
    }
}

# This used to be done with Eval::Closure but that added a lot of unneeded
# overhead. We're never actually eval'ing a closure, just plain source, so
# doing it by hand is a worthwhile optimization.
sub _eval_or_die {
    local $@ = undef;
    ## no critic (Variables::RequireInitializationForLocalVars)
    # $SIG{__DIE__} = undef causes warnings with 5.8.x
    local $SIG{__DIE__};
    ## no critic (BuiltinFunctions::ProhibitStringyEval)
    my $sub = eval <<"EOF";
#line 1 "$_[1]"
$_[0];
EOF
    my $e = $@;
    die $e if $e;
    return $sub;
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _constructor_confess {
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;
    confess shift;
}

sub _bad_args_message {
    my $class = shift;

    return
        "$class->new requires either a hashref or hash as arguments. You passed "
        . partial_dump(@_);
}

sub _bad_value_message {
    my $message = shift;
    my $value   = shift;

    return $message . ' You passed ' . partial_dump($value);
}
## use critic

my %BuiltinTypes = map { $_ => 1 } qw(
    SCALAR
    ARRAY
    HASH
    CODE
    REF
    GLOB
    LVALUE
    FORMAT
    IO
    VSTRING
    Regexp
);

sub clone {
    my $self = shift;

    # Attributes which provide a clone method are cloned by calling that
    # method on the _clone_ (not the original). This is primarily to allow us
    # to clone the coercions contained by a type in a way that doesn't lead to
    # circular clone (type clones coercions which in turn need to clone their
    # to/from types which in turn ...).
    my $attrs   = $self->_attrs;
    my %special = map { $_ => $attrs->{$_}{clone} }
        grep { $attrs->{$_}{clone} } keys %{$attrs};

    my $new;
    for my $key ( keys %{$self} ) {
        my $value = $self->{$key};

        if ( $special{$key} ) {
            $new->{$key} = $value;
            next;
        }

        # This is a weird hacky way of trying to avoid calling
        # Scalar::Util::blessed, which showed up as a hotspot in profiling of
        # loading DateTime. That's because we call ->clone a _lot_ (it's
        # called every time a type is exported).
        my $ref = ref $value;
        $new->{$key}
            = !$ref               ? $value
            : $ref eq 'CODE'      ? $value
            : $BuiltinTypes{$ref} ? _clone($value)
            :                       $value->clone;
    }

    bless $new, ( ref $self );

    for my $key ( keys %special ) {
        my $method = $special{$key};
        $new->{$key} = $new->$method;
    }

    return $new;
}

1;

# ABSTRACT: A painfully poor reimplementation of Moo(se)

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::OO - A painfully poor reimplementation of Moo(se)

=head1 VERSION

version 0.53

=head1 DESCRIPTION

Specio can't depend on Moo or Moose, so this module provides a terrible
reimplementation of a small slice of their features.

=for Pod::Coverage .*

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
