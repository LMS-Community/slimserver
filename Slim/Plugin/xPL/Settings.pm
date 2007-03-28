package Slim::Plugin::xPL::Settings;

# SlimServer Copyright (C) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub name {
        return 'PLUGIN_XPL';
}

sub page {
        return 'plugins/xPL/settings/basic.html';
}

sub prefs {

	return qw(xplinterval xplir);
}

1;

__END__
