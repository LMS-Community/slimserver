package Plugins::RadioIO::ProtocolHandler;

# $Id$

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use Scalar::Util qw(blessed);

use Slim::Player::Source;

sub new {
	my $class  = shift;
	my $args   = shift;

	my $url    = $args->{'url'};
	my $client = $args->{'client'};

	if ($url !~ /^radioio:\/\/(.*?)\.mp3/) {
		return undef;
	}

	my $sock = $class->SUPER::new({
		'url'    => Plugins::RadioIO::Plugin::getHTTPURL($1),
		'client' => $client
	}) || return undef;
}

sub canDirectStream {
	my ($self, $client, $url) = @_;

	if ($url =~ /^radioio:\/\/stream\/(.*)/) {
		return 'http://' . Plugins::RadioIO::Plugin::decrypt($1);
	}
	elsif ($url =~ /^radioio:\/\/(.*?)\.mp3/) {
		return Plugins::RadioIO::Plugin::getHTTPURL($1);
	}

	return undef;
}

sub getHTTPURL {
	my ( $self, $url ) = @_;
	
	return $self->canDirectStream( undef, $url );
}

sub parseDirectBody {
	my $self  = shift;
	my $url   = shift;
	my $body  = shift;

	my $io    = IO::String->new($body);

	# Need to tell the parser that the playlist is in pls format.
	my $pls   = Plugins::RadioIO::Plugin::getHTTPURL($url);
	my @items = Slim::Formats::Playlists->parseList($pls, $io);

	return () unless scalar(@items);

	my $stream = $items[0];
	$stream =~ s/http:\/\///;
	$stream = 'radioio://stream/' . Plugins::RadioIO::Plugin::decrypt($stream);

	my $currentDB = Slim::Music::Info::getCurrentDataStore();
	my $track = $currentDB->objectForUrl($url);

	if (blessed($track) && $track->can('title')) {

		Slim::Music::Info::setTitle($stream, $track->title());
	}

	return ($stream);
}

1;
