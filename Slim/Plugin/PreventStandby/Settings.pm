package Slim::Plugin::PreventStandby::Settings;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.preventstandby');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_PREVENTSTANDBY');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/PreventStandby/settings/basic.html');
}

sub prefs {
	return ($prefs, 'idletime', 'checkpower');
}

1;

__END__
