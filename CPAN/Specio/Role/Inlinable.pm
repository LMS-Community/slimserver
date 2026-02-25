package Specio::Role::Inlinable;

use strict;
use warnings;

our $VERSION = '0.53';

use Eval::Closure qw( eval_closure );

use Role::Tiny;

requires '_build_description';

{
    my $attrs = {
        _inline_generator => {
            is        => 'ro',
            isa       => 'CodeRef',
            predicate => '_has_inline_generator',
            init_arg  => 'inline_generator',
        },
        inline_environment => {
            is       => 'ro',
            isa      => 'HashRef',
            lazy     => 1,
            init_arg => 'inline_environment',
            builder  => '_build_inline_environment',
        },
        _generated_inline_sub => {
            is       => 'ro',
            isa      => 'CodeRef',
            init_arg => undef,
            lazy     => 1,
            builder  => '_build_generated_inline_sub',
        },
        declared_at => {
            is       => 'ro',
            isa      => 'Specio::DeclaredAt',
            required => 1,
        },
        description => {
            is       => 'ro',
            isa      => 'Str',
            init_arg => undef,
            lazy     => 1,
            builder  => '_build_description',
        },
    };

    ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    sub _attrs {
        return $attrs;
    }
}

# These are here for backwards compatibility. Some other packages that I wrote
# may call the private methods.

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _description        { $_[0]->description }
sub _inline_environment { $_[0]->inline_environment }
## use critic

sub can_be_inlined {
    my $self = shift;

    return $self->_has_inline_generator;
}

sub _build_generated_inline_sub {
    my $self = shift;

    my $source
        = 'sub { ' . $self->_inline_generator->( $self, '$_[0]' ) . '}';

    return eval_closure(
        source      => $source,
        environment => $self->inline_environment,
        description => 'inlined sub for ' . $self->description,
    );
}

sub _build_inline_environment {
    return {};
}

1;

# ABSTRACT: A role for things which can be inlined (type constraints and coercions)

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Role::Inlinable - A role for things which can be inlined (type constraints and coercions)

=head1 VERSION

version 0.53

=head1 DESCRIPTION

This role implements a common API for inlinable things, type constraints and
coercions. It is fully documented in the relevant classes.

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
