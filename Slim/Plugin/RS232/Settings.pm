package Slim::Plugin::RS232::Settings;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.rs232');

$prefs->setChange(\&Slim::Plugin::RS232::Plugin::cliOverRS232Change, 'clioverrs232enable');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_RS232_NAME');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/RS232/settings/basic.html');
}

sub prefs {
	return ($prefs, 'clioverrs232enable');
}

1;

__END__
