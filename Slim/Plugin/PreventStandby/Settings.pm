package Slim::Plugin::PreventStandby::Settings;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.preventstandby');

sub name {
	return Slim::Web::HTTP::protectName('PLUGIN_PREVENTSTANDBY');
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/PreventStandby/settings/basic.html');
}

sub prefs {
	return ($prefs, 'idletime', 'checkpower');
}

1;

__END__
