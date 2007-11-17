package Slim::Buttons::RemoteTrackInfo;

# $Id$

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::RemoteTrackInfo

=head1 DESCRIPTION

L<Slim::Buttons::RemoteTrackInfo> is a SqueezeCenter module to create a UI for viewing information 
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

	if (Slim::Utils::Favorites->enabled && (Slim::Music::Info::isSong($url) || Slim::Music::Info::isPlaylist($url)) ) {

		unshift @list, {
			value => $url,
			name => sub {
				my $client = shift;

				my $index = $client->modeParam('favorite');
				if (defined $index) {
					return "{FAVORITES_FAVORITE_NUM}$index {FAVORITES_RIGHT_TO_DELETE}";
				} else {
					return "{FAVORITES_RIGHT_TO_ADD}";
				}
			},

			onRight => sub {
				my $client = shift;
				my $favorites = Slim::Utils::Favorites->new($client) || return;
				my $index = $client->modeParam('favorite');

				if (defined $index) {
					$favorites->deleteIndex($index);
					$client->modeParam('favorite', undef);
					$client->showBriefly( {
						'line' => [ $client->string('FAVORITES_DELETING'), $client->modeParam('title') ]
					});
				} else {
					$index = $favorites->add($url, $title);
					$client->modeParam('favorite', $index);
					$client->showBriefly( {
						'line' => [ $client->string('FAVORITES_ADDING'), $client->modeParam('title') ]
					});
				}
			}
		};

		$favIndex = Slim::Utils::Favorites->new($client)->findUrl($url);
	}

	# now use another mode for the heavy lifting
	my %params = (
		'header'   => $client->modeParam('header') || ($title . ' {count}'),
		'listRef'  => \@list,
		'url'      => $url,
		'title'    => $title,
		'favorite' => $favIndex,

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
