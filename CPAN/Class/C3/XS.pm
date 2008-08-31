package Class::C3::XS;

use 5.006_000;
use strict;
use warnings;

our $VERSION = '0.08';

=pod

=head1 NAME

Class::C3::XS - XS speedups for Class::C3

=head1 SUMMARY

  use Class::C3; # Automatically loads Class::C3::XS
                 #  if it's installed locally

=head1 DESCRIPTION

This contains XS performance enhancers for L<Class::C3> version
0.16 and higher.  The main L<Class::C3> package will use this
package automatically if it can find it.  Do not use this
package directly, use L<Class::C3> instead.

The test suite here is not complete, although it does verify
a few basic things.  The best testing comes from running the
L<Class::C3> test suite *after* this module is installed.

This module won't do anything for you if you're running a
version of L<Class::C3> older than 0.16.  (It's not a
dependency because it would be circular with the optional
dep from that package to this one).

=head1 AUTHOR

Brandon L. Black, E<lt>blblack@gmail.comE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

require XSLoader;
XSLoader::load('Class::C3::XS', $VERSION);

package # hide me from PAUSE
    next;

sub can { Class::C3::XS::_nextcan($_[0], 0) }

sub method {
    my $method = Class::C3::XS::_nextcan($_[0], 1);
    goto &$method;
}

package # hide me from PAUSE
    maybe::next;

sub method {
    my $method = Class::C3::XS::_nextcan($_[0], 0);
    goto &$method if defined $method;
    return;
}

1;
