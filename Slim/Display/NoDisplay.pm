package Slim::Display::NoDisplay;

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# $Id$

# Display class for clients with no display, e.g. http streaming sessions
#  - used to stub out common display methods in Display::Display

use base qw(Slim::Display::Display);

use strict;
use Slim::Utils::Misc;

sub update {}
sub showBriefly {}
sub brightness {}
sub prevline1 {}
sub prevline2 {}
sub curDisplay {}
sub curLines {}
sub parseLines {}
sub renderOverlay {}
sub progressBar {}
sub balanceBar {}
sub scrollInit {}
sub scrollStop {}
sub scrollUpdateBackground {}
sub scrollTickerTimeLeft {}
sub scrollUpdate {}
sub killAnimation {}
sub resetDisplay {}
sub endAnimation {}

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
