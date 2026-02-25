package Specio::Constraint::Parameterized;

use strict;
use warnings;

our $VERSION = '0.53';

use Role::Tiny::With;
use Specio qw( _clone );
use Specio::OO;

use Specio::Constraint::Role::Interface;
with 'Specio::Constraint::Role::Interface';

{
    ## no critic (Subroutines::ProtectPrivateSubs)
    my $attrs = _clone( Specio::Constraint::Role::Interface::_attrs() );
    ## use critic

    $attrs->{parent}{isa}      = 'Specio::Constraint::Parameterizable';
    $attrs->{parent}{required} = 1;

    delete $attrs->{name}{predicate};
    $attrs->{name}{lazy}    = 1;
    $attrs->{name}{builder} = '_build_name';

    $attrs->{parameter} = {
        does     => 'Specio::Constraint::Role::Interface',
        required => 1,
    };

    ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    sub _attrs {
        return $attrs;
    }
}

sub _has_name {
    my $self = shift;
    return defined $self->name;
}

sub _build_name {
    my $self = shift;

    ## no critic (Subroutines::ProtectPrivateSubs)
    return unless $self->parent->_has_name && $self->parameter->_has_name;
    return $self->parent->name . '[' . $self->parameter->name . ']';
}

sub can_be_inlined {
    my $self = shift;

    return $self->_has_inline_generator
        && $self->parameter->can_be_inlined;
}

# Moose compatibility methods - these exist as a temporary hack to make Specio
# work with Moose.

sub type_parameter {
    shift->parameter;
}

__PACKAGE__->_ooify;

1;

# ABSTRACT: A class which represents parameterized constraints

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Constraint::Parameterized - A class which represents parameterized constraints

=head1 VERSION

version 0.53

=head1 SYNOPSIS

    my $arrayref = t('ArrayRef');

    my $arrayref_of_int = $arrayref->parameterize( of => t('Int') );

    my $parent = $arrayref_of_int->parent; # returns ArrayRef
    my $parameter = $arrayref_of_int->parameter; # returns Int

=head1 DESCRIPTION

This class implements the API for parameterized types.

=for Pod::Coverage can_be_inlined type_parameter

=head1 API

This class implements the same API as L<Specio::Constraint::Simple>, with a few
additions.

=head2 Specio::Constraint::Parameterized->new(...)

This class's constructor accepts two additional parameters:

=over 4

=item * parent

This should be the L<Specio::Constraint::Parameterizable> object from which
this object was created.

This parameter is required.

=item * parameter

This is the type parameter for the parameterized type. This must be an object
which does the L<Specio::Constraint::Role::Interface> role.

This parameter is required.

=back

=head2 $type->parameter

Returns the type that was passed to the constructor.

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
