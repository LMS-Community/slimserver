package Slim::Plugin::RadioTime::Settings;

# SlimServer Copyright (C) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('radiotime');

$prefs->migrate(1, sub {
	$prefs->set('username', Slim::Utils::Prefs::OldPrefs->get('plugin_radiotime_username')); 1;
});

sub name {
	return 'PLUGIN_RADIOTIME_MODULE_NAME';
}

sub page {
	return 'plugins/RadioTime/settings/basic.html';
}

sub prefs {
	return ($prefs, 'username');
}

1;

__END__
