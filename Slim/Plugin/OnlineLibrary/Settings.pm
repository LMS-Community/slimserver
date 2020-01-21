package Slim::Plugin::OnlineLibrary::Settings;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Plugin::OnlineLibrary::Plugin;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

my $prefs = preferences('plugin.onlinelibrary');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_ONLINE_LIBRARY_MODULE_NAME');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/OnlineLibrary/settings.html');
}

sub prefs {
	my @onlineLibraries = values %{ Slim::Plugin::OnlineLibrary::Plugin->getLibraryProviders() };
	return ($prefs, qw(enableLocalTracksOnly enablePreferLocalLibraryOnly), @onlineLibraries);
}

sub beforeRender {
	my ($class, $params, $client) = @_;

	$params->{libraryProviders} = [ map {
		my $name = $_;
		$name =~ s/enable_//;
		[ $_, cstring($client, $name), $prefs->get($_) ];
	} sort values %{ Slim::Plugin::OnlineLibrary::Plugin->getLibraryProviders() } ];
}

1;
