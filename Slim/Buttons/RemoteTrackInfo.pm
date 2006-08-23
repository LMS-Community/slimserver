package Slim::Buttons::RemoteTrackInfo;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::RemoteTrackInfo

=head1 DESCRIPTION

L<Slim::Buttons::RemoteTrackInfo> is a SlimServer module to create a UI for viewing information 
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

	my $url  = $client->param('url');
	my @list = ();

	# TODO: use client specific title format?
	my $title = $client->param('title') || Slim::Music::Info::standardTitle($client, $url);

	push @list, "{TITLE}: $title" unless $client->param('hideTitle');

	push @list, "{URL}: $url" unless $client->param('hideURL');

	# include any special (plugin-specific details)
	my $details = $client->param('details');

	for my $item (@{$details}) {
		push @list, $item;
	}

	# TODO: more details go here
	# see TrackInfo.pm for ideas

	# is it a favorite?
	# INPUT.Choice will display 'name' dynamically
	# 
	# Only allow adding to favorites if the URL is something we can play.
	if (Slim::Music::Info::isSong($url) || Slim::Music::Info::isPlaylist($url)) {

		unshift @list, {
			value => $url,
			name => sub {
				my $client = shift;

				my $num = $client->param('favorite');
				if ($num) {
					return "{FAVORITES_FAVORITE_NUM}$num {FAVORITES_RIGHT_TO_DELETE}";
				} else {
					return "{FAVORITES_RIGHT_TO_ADD}";
				}
			},

			onRight => sub {
				my $client = shift;
				my $num = $client->param('favorite');
				if ($num) {
					Slim::Utils::Favorites->deleteByClientAndURL($client, $client->param('url'));
					$client->param('favorite', 0);
					$client->showBriefly($client->string('FAVORITES_DELETING'), $client->param('title'));
				} else {
					$num = Slim::Utils::Favorites->clientAdd($client, $url, $title);
					$client->param('favorite', $num);
					$client->showBriefly($client->string('FAVORITES_ADDING'), $client->param('title'));
				}
			}
		};
	}

	# is the url already a favorite?
	my $favorite = Slim::Utils::Favorites->findByClientAndURL($client, $url);

	# now use another mode for the heavy lifting
	my %params = (
		'header'   => $client->param('header') || ($title . ' {count}'),
		'listRef'  => \@list,
		'url'      => $url,
		'title'    => $title,
		'favorite' => $favorite ? $favorite->{'num'} : undef,

		# play music when play is pressed
		'onPlay'   => sub {
			my $client = shift;

			my $station = $client->param('url');

			$client->execute( [ 'playlist', 'play', $station ] );
		},

		'onAdd'    => sub {
			my $client = shift;

			my $station = $client->param('url');

			$client->execute( [ 'playlist', 'add', $station ] );
		},

		'onRigh'   => $client->param('onRight'), # passthrough
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

=cut

1;
