package Slim::Plugin::OnlineLibrary::Settings;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.onlinelibrary');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_ONLINE_LIBRARY_MODULE_NAME');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/OnlineLibrary/settings.html');
}

sub prefs {
	return ($prefs, qw(yo));
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;


	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;
