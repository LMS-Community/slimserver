package Slim::Plugin::RadioTime::Settings;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.radiotime');

$prefs->migrate(1, sub {
	$prefs->set('username', Slim::Utils::Prefs::OldPrefs->get('plugin_radiotime_username')); 1;
});

sub name {
	return Slim::Web::HTTP::protectName('PLUGIN_RADIOTIME_MODULE_NAME');
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/RadioTime/settings/basic.html');
}

sub prefs {
	return ($prefs, 'username');
}

1;

__END__
