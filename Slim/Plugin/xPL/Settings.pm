package Slim::Plugin::xPL::Settings;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.xpl');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_XPL');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/xPL/settings/basic.html');
}

sub prefs {
	return ($prefs, qw(interval ir) );
}

1;

__END__
