package Class::Accessor::Fast;

use strict;
use vars qw($VERSION @ISA);
$VERSION = '0.02';
require Class::Accessor;
@ISA = qw(Class::Accessor);


=pod

=head1 NAME

Class::Accessor::Fast - Faster, but less expandable, accessors

=head1 SYNOPSIS

  package Foo;
  use base qw(Class::Accessor::Fast);

  # The rest as Class::Accessor except no set() or get().

=head1 DESCRIPTION

This is a somewhat faster, but less expandable, version of
Class::Accessor.  Class::Accessor's generated accessors require two
method calls to accompish their task (one for the accessor, another
for get() or set()).  Class::Accessor::Fast eliminates calling
set()/get() and does the access itself, resulting in a somewhat faster
accessor.

The downside is that you can't easily alter the behavior of your
accessors, nor can your subclasses.  Of course, should you need this
later, you can always swap out Class::Accessor::Fast for
Class::Accessor.

=cut

sub make_accessor {
    my($class, $field) = @_;

    return sub {
        my $self = shift;
        if(@_) {
            $self->{$field} = (@_ == 1 ? $_[0] : [@_]);
        }
        return $self->{$field};
    };
}


sub make_ro_accessor {
    my($class, $field) = @_;

    return sub {
        my $self = shift;

        if(@_) {
            my $caller = caller;
            require Carp;
            Carp::croak("'$caller' cannot alter the value of '$field' on ".
                        "objects of class '$class'");
        }
        else {
            return $self->{$field};
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
            return $self->{$field} = (@_ == 1 ? $_[0] : [@_]);
        }
    };
}


=pod

=head1 EFFICIENCY

L<Class::Accessor/EFFICIENCY> for an efficiency comparison.


=head1 AUTHOR

Michael G Schwern <schwern@pobox.com>


=head1 SEE ALSO

L<Class::Accessor>

=cut


1;
