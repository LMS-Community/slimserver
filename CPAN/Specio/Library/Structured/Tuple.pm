package Specio::Library::Structured::Tuple;

use strict;
use warnings;

our $VERSION = '0.53';

use Carp            qw( confess );
use List::Util 1.33 ();
use Scalar::Util    qw( blessed );
use Specio::Library::Builtins;
use Specio::TypeChecks qw( does_role );

my $arrayref = t('ArrayRef');

sub parent {$arrayref}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _inline {
    $arrayref->inline_check( $_[1] );
}

sub _parameterization_args_builder {
    shift;
    my $args = shift;

    my $saw_slurpy;
    my $saw_optional;
    for my $p ( @{$args} ) {
        if ($saw_slurpy) {
            confess
                'A Tuple cannot have any parameters after a slurpy parameter';
        }
        if ( $saw_optional && blessed($p) ) {
            confess
                'A Tuple cannot have a non-optional parameter after an optional parameter';
        }

        my $type;
        if ( blessed($p) ) {
            $type = $p;
        }
        else {
            if ( ref $p eq 'HASH' ) {
                if ( $p->{optional} ) {
                    $saw_optional = 1;
                    $type         = $p->{optional};
                }
                if ( $p->{slurpy} ) {
                    $saw_slurpy = 1;
                    $type       = $p->{slurpy};
                }
            }
            else {
                confess
                    'Can only pass types, optional types, and slurpy types when defining a Tuple';
            }
        }

        if ( $saw_optional && $saw_slurpy ) {
            confess
                'Cannot defined a slurpy Tuple with optional slots as well';
        }

        does_role( $type, 'Specio::Constraint::Role::Interface' )
            or confess
            'All parameters passed to ->parameterize must be objects which do the Specio::Constraint::Role::Interface role';

        confess
            'All parameters passed to ->parameterize must be inlinable constraints'
            unless $type->can_be_inlined;
    }

    return ( of => $args );
}

sub _name_builder {
    my $self = shift;
    my $p    = shift;

    my @names;
    for my $m ( @{ $p->{of} } ) {
        ## no critic (Subroutines::ProtectPrivateSubs)
        if ( blessed($m) ) {
            push @names, $self->_name_or_anon($m);
        }
        elsif ( $m->{optional} ) {
            push @names, $self->_name_or_anon( $m->{optional} ) . '?';
        }
        elsif ( $m->{slurpy} ) {
            push @names, $self->_name_or_anon( $m->{slurpy} ) . '...';
        }
    }

    return 'Tuple[ ' . ( join ', ', @names ) . ' ]';
}

sub _structured_inline_generator {
    shift;
    my $val  = shift;
    my %args = @_;

    my @of = @{ $args{of} };

    my $slurpy;
    $slurpy = ( pop @of )->{slurpy}
        if !blessed( $of[-1] ) && $of[-1]->{slurpy};

    my @code = sprintf( '( %s )', $arrayref->_inline_check($val) );

    unless ($slurpy) {
        my $min = 0;
        my $max = 0;
        for my $p (@of) {

            # Unblessed values are optional.
            if ( blessed($p) ) {
                $min++;
                $max++;
            }
            else {
                $max++;
            }
        }

        if ($min) {
            push @code,
                sprintf(
                '( @{ %s } >= %d && @{ %s } <= %d  )',
                $val, $min, $val, $max
                );
        }
    }

    for my $i ( 0 .. $#of ) {
        my $p      = $of[$i];
        my $access = sprintf( '%s->[%d]', $val, $i );

        if ( !blessed($p) ) {
            my $type = $p->{optional};

            push @code,
                sprintf(
                '( @{%s} >= %d ? ( %s ) : 1 )', $val, $i + 1,
                $type->_inline_check($access)
                );
        }
        else {
            push @code,
                sprintf( '( %s )', $p->_inline_check($access) );
        }
    }

    if ($slurpy) {
        my $non_slurpy = scalar @of;
        my $check
            = '( @{%s} > %d ? ( List::Util::all { %s } @{%s}[%d .. $#{%s}] ) : 1 )';
        push @code,
            sprintf(
            $check,
            $val, $non_slurpy, $slurpy->_inline_check('$_'),
            $val, $non_slurpy, $val,
            );
    }

    return '( ' . ( join ' && ', @code ) . ' )';
}

1;

# ABSTRACT: Guts of Tuple structured type

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Library::Structured::Tuple - Guts of Tuple structured type

=head1 VERSION

version 0.53

=head1 DESCRIPTION

There are no user facing parts here.

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
