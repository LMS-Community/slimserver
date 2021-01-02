package Slim::Plugin::Deezer::API;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;

use constant GET_ARTIST_URL => '/api/deezer/v1/opml/artist_by_name_or_id?id=%s&name=%s';

my $log = logger('plugin.deezer');


sub getArtistMenu {
	my ($class, $client, $args, $cb) = @_;

	$class->_call(sprintf(GET_ARTIST_URL, $args->{id}, uri_escape_utf8($args->{name})), $client, sub {
		my $info = shift;

		my $items = eval { $info->{body}->{outline} };
		$@ && $log->error("Failed to parse Deezer's response: $@");

		$cb->($items);
	});
}

sub _call {
	my ($class, $url, $client, $cb) = @_;

	Slim::Networking::SqueezeNetwork->new(
		sub {
			my $http   = shift;
			my $client = $http->params->{client};

			my $info = eval { from_json( $http->content ) };
			$@ && $log->error("Failed to parse Deezer's response: $@");

			$cb->($info);
		},
		sub {
			my $http   = shift;
			my $client = $http->params('client');
			my $error  = $http->error;

			$log->warn("Error getting track metadata from SN: $error");

			$cb->();
		},
		{
			client  => $client,
			timeout => 60,
		},
	)->get( Slim::Networking::SqueezeNetwork->url($url) );
}

1;
