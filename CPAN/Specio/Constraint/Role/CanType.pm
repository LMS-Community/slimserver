package Specio::Constraint::Role::CanType;

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

    $attrs->{methods} = {
        isa      => 'ArrayRef',
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
    my @methods       = @{ $self->methods };
    my $all_word_list = _word_list(@methods);
    my $allow_classes = $self->_allow_classes;

    unless ( defined $generator ) {
        $generator = sub {
            shift;
            my $value = shift;

            return
                "An undef will never pass an $type check (wants $all_word_list)"
                unless defined $value;

            my $class = blessed $value;
            if ( !defined $class ) {

                # If we got here we know that blessed returned undef, so if
                # it's a ref then it must not be blessed.
                if ( ref $value ) {
                    my $dump = partial_dump($value);
                    return
                        "An unblessed reference ($dump) will never pass an $type check (wants $all_word_list)";
                }

                # If it's defined and not an unblessed ref it must be a
                # string. If we allow classes (vs just objects) then it might
                # be a valid class name.  But an empty string is never a valid
                # class name. We cannot call q{}->can.
                return
                    "An empty string will never pass an $type check (wants $all_word_list)"
                    unless length $value;

                if ( ref \$value eq 'GLOB' ) {
                    return
                        "A glob will never pass an $type check (wants $all_word_list)";
                }

                if (
                    $value =~ /\A
                        \s*
                        -?[0-9]+(?:\.[0-9]+)?
                        (?:[Ee][\-+]?[0-9]+)?
                        \s*
                        \z/xs
                ) {
                    return
                        "A number ($value) will never pass an $type check (wants $all_word_list)";
                }

                $class = $value if $allow_classes;

                # At this point we either have undef or a non-empty string in
                # $class.
                unless ( defined $class ) {
                    my $dump = partial_dump($value);
                    return
                        "A plain scalar ($dump) will never pass an $type check (wants $all_word_list)";
                }
            }

            my @missing = grep { !$value->can($_) } @methods;

            my $noun = @missing == 1 ? 'method' : 'methods';
            my $list = _word_list( map {qq['$_']} @missing );

            return "The $class class is missing the $list $noun";
        };
    }

    return sub { $generator->( undef, @_ ) };
}
## use critic

sub _word_list {
    my @items = sort { $a cmp $b } @_;

    return $items[0] if @items == 1;
    return join ' and ', @items if @items == 2;

    my $final = pop @items;
    my $list  = join ', ', @items;
    $list .= ', and ' . $final;

    return $list;
}

1;

# ABSTRACT: Provides a common implementation for Specio::Constraint::AnyCan and Specio::Constraint::ObjectCan

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Constraint::Role::CanType - Provides a common implementation for Specio::Constraint::AnyCan and Specio::Constraint::ObjectCan

=head1 VERSION

version 0.53

=head1 DESCRIPTION

See L<Specio::Constraint::AnyCan> and L<Specio::Constraint::ObjectCan> for
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
