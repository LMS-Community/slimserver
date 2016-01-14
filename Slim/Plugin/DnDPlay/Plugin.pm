package Slim::Plugin::DnDPlay::Plugin;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Slim::Plugin::DnDPlay::FileManager;

use constant MAX_UPLOAD_SIZE => 100_000_000;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.dndplay',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_DNDPLAY',
});

my $CRLF = $Socket::CRLF;

my $cacheFolder;

sub initPlugin {
	my $class = shift;
	
	Slim::Plugin::DnDPlay::FileManager->init();

	# this handler hijacks the default handler for js-main, to inject the D'n'd code
	Slim::Web::Pages->addPageFunction("js-main\.html", sub {
		Slim::Web::HTTP::filltemplatefile('html/js-main-dd.html', $_[1]);
	});
	
	Slim::Web::Pages->addRawFunction("plugin/dndplay/upload", \&handleUpload);
}

sub handleUpload {
	my ($httpClient, $response) = @_;
	
	my $request = $response->request;
	my $result = {};

	my $client;
	if ( my $id = $request->uri->query_param('player') ) {
		$client = Slim::Player::Client::getClient($id);
	}
			
	if ( !$client && (my $cookie = $request->header('Cookie')) ) {
		my $cookies = { CGI::Cookie->parse($cookie) };
		if ( my $player = $cookies->{'Squeezebox-player'} ) {
			$client = Slim::Player::Client::getClient( $player->value );
		}
	}
	
	# don't accept the data unless we have a client
	if ( $client ) {
		if ( $request->content_length > MAX_UPLOAD_SIZE ) {
			$result = {
				error => sprintf("File size (%s) exceeds maximum upload size (%s)", $request->content_length, MAX_UPLOAD_SIZE),
				code  => 413,
			};
		}
		else {
			my $ct = $request->header('Content-Type');
			my ($boundary) = $ct =~ /boundary=(.*)/;
			
			my $content = $request->content_ref;
	
			foreach my $param (split /--\Q$boundary\E/, $$content) {
				if ( $param =~ s/(.+?)${CRLF}${CRLF}//s ) {
					my $header = $1;

					main::DEBUGLOG && $log->is_debug && $log->debug("New section header found: " . Data::Dump::dump($header));
					
					if ( my $url = Slim::Plugin::DnDPlay::FileManager->getFileUrl($header, \$param) ) {
						$client->execute([ 'playlist', Slim::Player::Playlist::count($client) ? 'add' : 'play', $url ]);
						delete $result->{code};
						
						# we don't accept more than one file per upload
						last;
					}
					else {
						$result->{code} = 415; # unsupported media type
					}
				}
			}
		}
	}
	else {
		$result = {
			error => 'No player defined',
			code  => 500,
		};
	}
	
	$log->error($result->{error}) if $result->{error};

	my $content = to_json($result);
	$response->header( 'Content-Length' => length($content) );
	$response->code($result->{code} || 200);
	$response->header('Connection' => 'close');
	$response->content_type('application/json');
	
	Slim::Web::HTTP::addHTTPResponse( $httpClient, $response, \$content	);
}

1;

