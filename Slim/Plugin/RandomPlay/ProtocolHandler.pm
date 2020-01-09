package Slim::Plugin::RandomPlay::ProtocolHandler;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use URI;
use URI::QueryParam;

use Slim::Plugin::RandomPlay::Plugin;

sub overridePlayback {
	my ( $class, $client, $url ) = @_;

	return unless $client;

	my $uri = URI->new($url);

	return unless $uri->scheme eq 'randomplay';

	if ( Slim::Player::Source::streamingSongIndex($client) ) {
		# don't start immediately if we're part of a playlist and previous track isn't done playing
		return if $client->controller()->playingSongDuration()
	}

	my ($type) = $url =~ m|^randomplay://([a-z]*)\??|i;
	my $params = $uri->query_form_hash;

	my $command = ["randomplay", $type];
	if (my $genres = $params->{genres}) {
		push @$command, "genres:$genres";
	}

	$client->execute($command);

	# caller wishes the mix to be a one-off, not to be refreshed
	if ($params->{dontContinue}) {
		$client->execute(["randomplay", "disable"]);
	}

	return 1;
}

sub canDirectStream { 0 }

sub contentType {
	return 'rnd';
}

sub isRemote { 0 }

sub getMetadataFor {
	my ( $class, $client, $url ) = @_;

	return unless $client && $url;

	my ($type) = $url =~ m{randomplay://(track|contributor|album|year)s?$};
	my $title = 'PLUGIN_RANDOMPLAY';

	if ($type) {
		$title = 'PLUGIN_RANDOM_' . uc($type);
	}

	return {
		title => $client->string($title),
		cover => $class->getIcon(),
	};
}

sub getIcon {
	return Slim::Plugin::RandomPlay::Plugin->_pluginDataFor('icon');
}

1;
