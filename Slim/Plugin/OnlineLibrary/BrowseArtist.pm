package Slim::Plugin::OnlineLibrary::BrowseArtist;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Menu::BrowseLibrary;

use constant BROWSE_CMD => 'browseonlineartist';

my %infoProvider;

sub init {
	Slim::Menu::BrowseLibrary->registerExtraItem('artist', 'onlinelibrary', \&getBrowseArtistItems);

	Slim::Control::Request::addDispatch(
		[ BROWSE_CMD, 'items', '_index', '_quantity' ],
		[ 0, 1, 1, \&cliQuery ]
	);

	Slim::Control::Request::addDispatch(
		[ BROWSE_CMD, 'playlist', '_method' ],
		[ 1, 1, 1, \&cliQuery ]
	);

	Slim::Control::Request::addDispatch(
		[ BROWSE_CMD, 'services' ],
		[ 0, 1, 0, sub { $_[0]->addResult('services', [keys %infoProvider]) } ]
	);
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
				items => {
					'command' => [ BROWSE_CMD, 'items' ],
					'fixedParams' => {
						artist_id => $artist_id,
						service_id => $_
					},
				}
			};

			$handler;
		}
	} sort keys %infoProvider;

	return @extras;
}


# keep a very small cache of feeds to allow browsing into a folder info feed
# we will be called again without $url or $albumId when browsing into the feed
tie my %cachedFeed, 'Tie::Cache::LRU', 2;

sub cliQuery {
	my $request = shift;

	# WebUI or newWindow param from SP side results in no
	# _index _quantity args being sent, but XML Browser actually needs them, so they need to be hacked in
	# here and the tagged params mistakenly put in _index and _quantity need to be re-added
	# to the $request params
	my $index      = $request->getParam('_index');
	my $quantity   = $request->getParam('_quantity');

	if ( $index =~ /:/ ) {
		$request->addParam(split (/:/, $index));
		$index = 0;
		$request->addParam('_index', $index);
	}

	if ( $quantity =~ /:/ ) {
		$request->addParam(split(/:/, $quantity));
		$quantity = 200;
		$request->addParam('_quantity', $quantity);
	}

	my $client       = $request->client;
	my $artist_id    = $request->getParam('artist_id');
	my $service_id   = $request->getParam('service_id');
	my $connectionId = $request->connectionID || '';

	my $feed;
	if ($service_id && $artist_id) {
		my $handler = $infoProvider{$service_id};
		$feed = $handler->() if $handler;
		if ($feed) {
			$feed->{passthrough} = [{ artist_id => $artist_id}];
			$cachedFeed{ $connectionId } = $feed;
		}
	}
	elsif ($artist_id) {
		return Slim::Control::XMLBrowser::cliQuery(BROWSE_CMD, {
			name  => 'browser artist online',
			type  => 'opml',
			items => [ getBrowseArtistItems($artist_id) ],
		}, $request );
	}

	if (!$feed && $cachedFeed{$connectionId}) {
		$feed = $cachedFeed{$connectionId};
		if ($feed && (my $pt = $feed->{passthrough})) {
			$request->addParam('artist_id', $pt->[0]->{artist_id});
			$request->addParam('passthrough', $pt);
		}
	}

	if (!$feed) {
		$request->setStatusBadParams();
		return;
	}

	Slim::Control::XMLBrowser::cliQuery(BROWSE_CMD, sub {
		my ($client, $callback, $args, $pt) = @_;
		$feed->{url}->($client, $callback, $request->getParamsCopy(), $args);
	}, $request);
}

1;