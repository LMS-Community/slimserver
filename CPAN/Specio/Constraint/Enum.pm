package Specio::Constraint::Enum;

use strict;
use warnings;

our $VERSION = '0.53';

use Role::Tiny::With;
use Scalar::Util qw( refaddr );
use Specio::Library::Builtins;
use Specio qw( _clone );
use Specio::OO;

use Specio::Constraint::Role::Interface;
with 'Specio::Constraint::Role::Interface';

{
    ## no critic (Subroutines::ProtectPrivateSubs)
    my $attrs = _clone( Specio::Constraint::Role::Interface::_attrs() );
    ## use critic

    for my $name (qw( parent _inline_generator )) {
        $attrs->{$name}{init_arg} = undef;
        $attrs->{$name}{builder}
            = $name =~ /^_/ ? '_build' . $name : '_build_' . $name;
    }

    $attrs->{values} = {
        isa      => 'ArrayRef',
        required => 1,
    };

    ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    sub _attrs {
        return $attrs;
    }
}

{
    my $Str = t('Str');
    sub _build_parent {$Str}
}

{
    my $_inline_generator = sub {
        my $self = shift;
        my $val  = shift;

        return sprintf( <<'EOF', ($val) x 2, $self->_env_var_name, $val );
( !ref( %s ) && defined( %s ) && $%s{ %s } )
EOF
    };

    sub _build_inline_generator {$_inline_generator}
}

sub _build_inline_environment {
    my $self = shift;

    my %values = map { $_ => 1 } @{ $self->values };

    return { '%' . $self->_env_var_name => \%values };
}

sub _env_var_name {
    my $self = shift;

    return '_Specio_Constraint_Enum_' . refaddr($self);
}

__PACKAGE__->_ooify;

1;

# ABSTRACT: A class for constraints which require a string matching one of a set of values

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Constraint::Enum - A class for constraints which require a string matching one of a set of values

=head1 VERSION

version 0.53

=head1 SYNOPSIS

    my $type = Specio::Constraint::Enum->new(...);
    print $_, "\n" for @{ $type->values };

=head1 DESCRIPTION

This is a specialized type constraint class for types which require a string
that matches one of a list of values.

=head1 API

This class provides all of the same methods as L<Specio::Constraint::Simple>,
with a few differences:

=head2 Specio::Constraint::Enum->new( ... )

The C<parent> parameter is ignored if it passed, as it is always set to the
C<Str> type.

The C<inline_generator> and C<constraint> parameters are also ignored. This
class provides its own default inline generator subroutine reference.

Finally, this class requires an additional parameter, C<values>. This must be a
an arrayref of valid strings for the type.

=head2 $enum->values

Returns an array reference of valid values for the type.

=head1 ROLES

This class does the L<Specio::Constraint::Role::Interface> and
L<Specio::Role::Inlinable> roles.

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
