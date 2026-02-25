package Specio::Constraint::Role::IsaType;

use strict;
use warnings;

our $VERSION = '0.53';

use Scalar::Util        qw( blessed );
use Specio              qw( _clone );
use Specio::PartialDump qw( partial_dump );

use Role::Tiny;

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

    $attrs->{class} = {
        isa      => 'ClassName',
        required => 1,
    };

    ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    sub _attrs {
        return $attrs;
    }
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _wrap_message_generator {
    my $self      = shift;
    my $generator = shift;

    my $type          = ( split /::/, blessed $self )[-1];
    my $class         = $self->class;
    my $allow_classes = $self->_allow_classes;

    unless ( defined $generator ) {
        $generator = sub {
            shift;
            my $value = shift;

            return "An undef will never pass an $type check (wants $class)"
                unless defined $value;

            if ( ref $value && !blessed $value ) {
                my $dump = partial_dump($value);
                return
                    "An unblessed reference ($dump) will never pass an $type check (wants $class)";
            }

            if ( !blessed $value ) {
                return
                    "An empty string will never pass an $type check (wants $class)"
                    unless length $value;

                if (
                    $value =~ /\A
                        \s*
                        -?[0-9]+(?:\.[0-9]+)?
                        (?:[Ee][\-+]?[0-9]+)?
                        \s*
                        \z/xs
                ) {
                    return
                        "A number ($value) will never pass an $type check (wants $class)";
                }

                if ( !$allow_classes ) {
                    my $dump = partial_dump($value);
                    return
                        "A plain scalar ($dump) will never pass an $type check (wants $class)";
                }
            }

            my $got = blessed $value;
            $got ||= $value;

            return "The $got class is not a subclass of the $class class";
        };
    }

    return sub { $generator->( undef, @_ ) };
}
## use critic

1;

# ABSTRACT: Provides a common implementation for Specio::Constraint::AnyIsa and Specio::Constraint::ObjectIsa

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Constraint::Role::IsaType - Provides a common implementation for Specio::Constraint::AnyIsa and Specio::Constraint::ObjectIsa

=head1 VERSION

version 0.53

=head1 DESCRIPTION

See L<Specio::Constraint::AnyIsa> and L<Specio::Constraint::ObjectIsa> for
details.

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
