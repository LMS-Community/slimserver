package Slim::Plugin::RadioTime::Settings;

# SlimServer Copyright (C) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub name {
        return 'PLUGIN_RADIOTIME_MODULE_NAME';
}

sub page {
        return 'plugins/RadioTime/settings/basic.html';
}

sub prefs {
	return qw(plugin_radiotime_username);
}

1;

__END__
