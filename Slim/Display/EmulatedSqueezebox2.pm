package Slim::Display::EmulatedSqueezebox2;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Display::EmulatedSqueezebox2

=head1 DESCRIPTION

L<Slim::Display::EmulatedSqueezebox2>
 Display class for clients with no physical display to allow emulation of SB2
 display for sending displaystatus to cli and jive

=cut

use base qw(Slim::Display::Squeezebox2);

use strict;

sub updateScreen {}
sub drawFrameBuf {}
sub showVisualizer {}
sub visualizer {}
sub visualizerParams {}
sub scrollInit {}
sub scrollUpdateBackground {}
sub clientAnimationComplete {}

=head1 SEE ALSO

L<Slim::Display::Display>
L<Slim::Display::Squeezebox2>

=cut

1;

