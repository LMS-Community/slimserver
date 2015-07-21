package Slim::Plugin::InternetRadio::TuneIn::Settings;

# Logitech Media Server Copyright 2001-2013 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.radiotime');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_RADIOTIME_MODULE_TITLE');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/TuneIn/settings/basic.html');
}

sub prefs {
	return ($prefs, 'username');
}

1;

__END__
