use strict;
package Class::Accessor::Chained::Fast;
use base 'Class::Accessor::Fast';

sub make_accessor {
    my($class, $field) = @_;

    return sub {
        my $self = shift;
        if(@_) {
            $self->{$field} = (@_ == 1 ? $_[0] : [@_]);
            return $self;
        }
        return $self->{$field};
    };
}

sub make_wo_accessor {
    my($class, $field) = @_;

    return sub {
        my($self) = shift;

        unless (@_) {
            my $caller = caller;
            require Carp;
            Carp::croak("'$caller' cannot access the value of '$field' on ".
                        "objects of class '$class'");
        }
        else {
            $self->{$field} = (@_ == 1 ? $_[0] : [@_]);
            return $self;
        }
    };
}

1;

=head1 NAME

Class::Accessor::Chained::Fast - Faster, but less expandable, chained accessors

=head1 SYNOPSIS

 package Foo;
 use base qw(Class::Accessor::Chained::Fast);

  # The rest as Class::Accessor::Chained except no set() or get().

=head1 DESCRIPTION

By analogue to Class::Accessor and Class::Accessor::Fast this module
provides a faster less-flexible chained accessor maker.

=head1 AUTHOR

Richard Clamp <richardc@unixbeard.net>

=head1 COPYRIGHT

Copyright (C) 2003 Richard Clamp.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Class::Accessor::Fast>, L<Class::Accessor::Chained>

=cut
