package Slim::Plugin::RandomPlay::ProtocolHandler;

# Logitech Media Server Copyright 2001-2016 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use Slim::Plugin::RandomPlay::Plugin;

sub overridePlayback {
	my ( $class, $client, $url ) = @_;

	return unless $client;

	if ($url !~ m|^randomplay://(.*)$|) {
		return undef;
	}

	if ( Slim::Player::Source::streamingSongIndex($client) ) {
		# don't start immediately if we're part of a playlist and previous track isn't done playing
		return if $client->controller()->playingSongDuration()
	}

	$client->execute(["randomplay", "$1"]);
	
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
