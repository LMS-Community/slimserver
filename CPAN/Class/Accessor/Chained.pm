use strict;
package Class::Accessor::Chained;
use base 'Class::Accessor';
our $VERSION = '0.01';

sub make_accessor {
    my($class, $field) = @_;

    # Build a closure around $field.
    return sub {
        my($self) = shift;

        if (@_) {
            $self->set($field, @_);
            return $self;
        }
        else {
            return $self->get($field);
        }
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
            $self->set($field, @_);
            return $self;
        }
    };
}

1;
__END__

=head1 NAME

Class::Accessor::Chained - make chained accessors

=head1 SYNOPSIS

 package Foo;
 use base qw( Class::Accessor::Chained );
 __PACKAGE__->mk_accessors(qw( foo bar baz ));

 my $foo = Foo->new->foo(1)->bar(2)->baz(4);
 print $foo->bar; # prints 2

=head1 DESCRIPTION

A chained accessor is one that always returns the object when called
with parameters (to set), and the value of the field when called with
no arguments.

This module subclasses Class::Accessor in order to provide the same
mk_accessors interface.

=head1 AUTHOR

Richard Clamp <richardc@unixbeard.net>

=head1 COPYRIGHT

Copyright (C) 2003 Richard Clamp.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Class::Accessor>, L<Class::Accessor::Chained::Fast>

=cut
