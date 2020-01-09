package Slim::Buttons::RemoteTrackInfo;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::RemoteTrackInfo

=head1 DESCRIPTION

L<Slim::Buttons::RemoteTrackInfo> is a Logitech Media Server module to create a UI for viewing information 
about remote tracks.

=cut

use strict;
use Slim::Buttons::Common;
use Slim::Music::Info;
use Slim::Utils::Favorites;
use Slim::Utils::Misc;

sub init {
	Slim::Buttons::Common::addMode('remotetrackinfo', {}, \&setMode);
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $url  = $client->modeParam('url');
	my @list = ();

	# TODO: use client specific title format?
	my $title = $client->modeParam('title') || Slim::Music::Info::standardTitle($client, $url);

	push @list, "{TITLE}: $title" unless $client->modeParam('hideTitle');

	push @list, "{URL}: $url" unless $client->modeParam('hideURL');

	# include any special (plugin-specific details)
	my $details = $client->modeParam('details');

	for my $item (@{$details}) {
		push @list, $item;
	}

	# TODO: more details go here
	# see TrackInfo.pm for ideas

	# is it a favorite?
	# INPUT.Choice will display 'name' dynamically
	# 
	# Only allow adding to favorites if the URL is something we can play.

	my $favIndex;

	if ( $url && Slim::Utils::Favorites->enabled ) {

		unshift @list, {
			value => $url,
			name => sub {
				my $client = shift;

				my $index = $client->modeParam('favorite');
				if (defined $index) {
					return "{PLUGIN_FAVORITES_REMOVE}";
				} else {
					return "{PLUGIN_FAVORITES_SAVE}";
				}
			},

			onRight => sub {
				my $client = shift;
				my $favorites = Slim::Utils::Favorites->new($client) || return;
				my $index = $client->modeParam('favorite');
				my $icon  = $client->modeParam('icon');

				if (defined $index) {
					
					# Bug 6177, Menu to confirm favorite removal
					Slim::Buttons::Common::pushModeLeft( $client, 'favorites.delete', {
						title => $title,
						index => $index,
						depth => 2,
					} );

				} else {
					$index = $favorites->add($url, $title, undef, undef, undef, $icon);
					$client->modeParam('favorite', $index);
					$client->showBriefly( {
						'line' => [ $client->string('FAVORITES_ADDING'), $client->modeParam('title') ]
					});
				}
			},
			overlayRef => [ undef, $client->symbols('rightarrow') ],
		};

		$favIndex = Slim::Utils::Favorites->new($client)->findUrl($url);
	}

	# now use another mode for the heavy lifting
	my %params = (
		'header'   => $client->modeParam('header') || $title,
		'headerAddCount' => 1,
		'listRef'  => \@list,
		'url'      => $url,
		'title'    => $title,
		'favorite' => $favIndex,
		'icon'     => $client->modeParam('item') ? $client->modeParam('item')->{'image'} : undef,

		# play music when play is pressed
		'onPlay'   => sub {
			my $client = shift;

			my $station = $client->modeParam('url');

			$client->execute( [ 'playlist', 'play', $station ] );
		},

		'onAdd'    => sub {
			my $client = shift;

			my $station = $client->modeParam('url');

			$client->execute( [ 'playlist', 'add', $station ] );
		},

		'onRight'   => $client->modeParam('onRight'), # passthrough
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

=cut

1;
