package Slim::Web::UPnPMediaServer;

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use URI::Escape;

use Slim::Utils::UPnPMediaServer;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

sub init {
	Slim::Web::HTTP::addPageFunction(qr/^browseupnp\.(?:htm|xml)/, \&browseUPnP);
	Slim::Web::HTTP::addPageFunction(qr/^upnpinfo\.(?:htm|xml)/, \&UPnPInfo);
}

sub UPnPInfo {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $deviceUDN = $params->{'device'};
	my $hierarchy = $params->{'hierarchy'};
	my $player = $params->{'player'};
	my $trackid = $params->{'trackid'};

	my @levels = map { URI::Escape::uri_unescape($_) } split("/", $hierarchy);
	my $containerId = $levels[-2];
	my $container = Slim::Utils::UPnPMediaServer::getContainerInfo($deviceUDN, $containerId);

	$params->{'browseby'} = uc(Slim::Utils::UPnPMediaServer::getDisplayName($deviceUDN)) || 'BROWSE';

	unless ($container) {
		$params->{'browse_list'} = $player ? $player->string('UPNP_CONNECTION_ERROR') : Slim::Utils::Strings::string('UPNP_CONNECTION_ERROR');

		return Slim::Web::HTTP::filltemplatefile("browsedb.html", $params);
	}

	my $item = Slim::Utils::UPnPMediaServer::getItemInfo($deviceUDN, $trackid);
	$params->{'track'} = $item;

	return Slim::Web::HTTP::filltemplatefile("upnpinfo.html", $params);
}

sub browseUPnP {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $deviceUDN = $params->{'device'};
	my $hierarchy = $params->{'hierarchy'};
	my $player = $params->{'player'};
	my @levels = map { URI::Escape::uri_unescape($_) } split("/", $hierarchy);
	
	$params->{'browseby'} = uc(Slim::Utils::UPnPMediaServer::getDisplayName($deviceUDN)) || 'BROWSE';

	my $id = $levels[-1];
	# Reload the container every time (as opposed to getting a cached
	# one), since it may have changed.
	my $container = Slim::Utils::UPnPMediaServer::loadContainer($deviceUDN, $id);
	unless ($container) {
		$params->{'browse_list'} = defined($client) ? $client->string('UPNP_CONNECTION_ERROR') : Slim::Utils::Strings::string('UPNP_CONNECTION_ERROR');

		return Slim::Web::HTTP::filltemplatefile("browsedb.html", $params);
	}

	# Construct the pwd header
	for (my $i = 0; $i < scalar @levels; $i++) {
		
		my $item = Slim::Utils::UPnPMediaServer::getItemInfo($deviceUDN, $levels[$i]);
		next unless defined($item);

		my %list_form = (
			'player'       => $player,
			'device'       => $deviceUDN,
			'pwditem'        => $item->{'title'},
			'hierarchy'    => join('/', map URI::Escape::uri_escape($_), @levels[0..$i]),
		);
		
		$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseupnp_pwdlist.html", \%list_form)};
	}

	if (defined $container->{'children'}) {
		my $itemnumber = 0;

		my $items = $container->{'children'};
		my $otherparams = join('&',
			"device=$deviceUDN",
			'player=' . Slim::Web::HTTP::escape($player || ''),
			"hierarchy=$hierarchy",
		);

		my ($start, $end) = Slim::Web::Pages::pageBar(
			scalar(@$items),
			$params->{'path'},
			0,
			$otherparams,
			\$params->{'start'},
			\$params->{'browselist_header'},
			\$params->{'browselist_pagebar'},
			$params->{'skinOverride'},
			$params->{'itemsPerPage'},
		);

		for my $item (@{$items}[$start..$end]) {
			my %list_form = %$params;

			$list_form{'player'} = $player;
			$list_form{'device'} = $deviceUDN;
			$list_form{'hierarchy'} = join('/', $hierarchy, URI::Escape::uri_escape($item->{'id'}));
			$list_form{'item'} = $item;
			$list_form{'odd'} = (++$itemnumber) % 2;

			$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseupnp_list.html", \%list_form)};
		}
	}

	return Slim::Web::HTTP::filltemplatefile("browsedb.html", $params);
}

1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
