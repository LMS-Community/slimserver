package Slim::Display::Boom;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# $Id$

=head1 NAME

Slim::Display::Squeezebox2

=head1 DESCRIPTION

L<Slim::Display::Boom>
 Display class for Boom class display
  - 160 x 32 pixel display
  - client side animations

=cut

use strict;

use base qw(Slim::Display::Squeezebox2);

sub displayWidth {
	return shift->widthOverride(@_) || 160;
}

sub vfdmodel {
	return 'graphic-160x32';
}

=head1 SEE ALSO

L<Slim::Display::Graphics>

=cut

1;
