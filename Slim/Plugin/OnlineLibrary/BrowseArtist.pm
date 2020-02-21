package Slim::Plugin::OnlineLibrary::BrowseArtist;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Menu::BrowseLibrary;

my %infoProvider;

sub init {
	Slim::Menu::BrowseLibrary->registerExtraItem('artist', 'onlinelibrary', \&getBrowseArtistItems);
}

sub registerBrowseArtistItem {
	my ($class, $name, $handler) = @_;

	if ($name && $handler && ref $handler) {
		$infoProvider{$name} = $handler;
	}
}

sub getBrowseArtistItems {
	my ($artist_id) = @_;

	my @extras = map {
		if (my $handler = $infoProvider{$_}->()) {
			$handler->{passthrough} = [{ artist_id => $artist_id}];
			$handler->{itemActions} = {
				allAvailableActionsDefined => 1,
			};

			$handler;
		}
	} sort keys %infoProvider;

	return @extras;
}

1;