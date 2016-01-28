package Slim::Plugin::DnDPlay::Settings;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.dndplay');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_DNDPLAY_SHORT');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/DnDPlay/settings.html');
}

sub prefs {
	return ($prefs, 'maxfilesize');
}

1;

__END__
