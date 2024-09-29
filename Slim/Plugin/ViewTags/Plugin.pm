package Slim::Plugin::ViewTags::Plugin;

# Logitech Media Server Copyright 2005-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::Base);

use Audio::Scan;

use Slim::Plugin::ViewTags::Common;
use Slim::Menu::TrackInfo;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.viewtags');

$prefs->init({
	customTags => {},
});

sub initPlugin {
	if (main::WEBUI) {
		require Slim::Plugin::ViewTags::Settings;
		Slim::Plugin::ViewTags::Settings->new();
	}

	initInfoProviders();
	$prefs->setChange(\&initInfoProviders, 'customTags', 'toplevel');
}

sub initInfoProviders {
	# get rid of old registrations
	foreach my $provider (keys %{ Slim::Menu::TrackInfo->getInfoProvider }) {
		if ($provider =~ /^viewTagsPlugin_/) {
			Slim::Menu::TrackInfo->deregisterInfoProvider($provider);
		}
	}

	foreach my $tag (@{Slim::Plugin::ViewTags::Common::getActiveTags()}) {
		my $toplevel = $prefs->get('toplevel');

		Slim::Menu::TrackInfo->registerInfoProvider("viewTagsPlugin_${tag}" => (
			parent => $toplevel ? undef : 'moreinfo',
			after  => $toplevel ? 'comment' : undef,
			before => $toplevel ? undef : 'tagdump',
			func   => sub {
				tagItem($tag, @_);
			}
		));
	}
}

sub tagItem {
	my ( $tag, $client, $url, $track ) = @_;

	return unless Slim::Music::Info::isFileURL($url) || Slim::Music::Info::isVolatile($url);

	my $details = Slim::Plugin::ViewTags::Common::getDetailsForTag($tag) || return;

	my $menu = Slim::Menu::TrackInfo::tagDump($client, undef, undef, $track->path, $tag, $details->{name});

	if (ref $menu && ref $menu eq 'ARRAY') {
		$menu = $menu->[0];
		$menu->{parseURLs} = 1 if $details->{url};
		return $menu;
	}

	return;
}

1;
