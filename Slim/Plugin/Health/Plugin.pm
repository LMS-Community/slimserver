# Plugin for Slimserver to monitor Server and Network Health

# $Id: Plugin.pm 11029 2006-12-22 19:38:49Z adrian $

# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2005 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Slim::Plugin::Health::Plugin;

# Plugin is implemented in two sub plugins:

use base qw(Slim::Plugin::Health::NetTest Slim::Plugin::Health::PerfMon);
use Class::C3;

Class::C3::initialize();

1;
