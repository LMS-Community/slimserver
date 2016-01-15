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
	
	Slim::Web::Pages->addRawFunction("plugin/dndplay/checkfiles", \&handleFilesCheck);
	Slim::Web::Pages->addRawFunction("plugin/dndplay/upload", \&handleUpload);
}

sub handleFilesCheck {
	my ($httpClient, $response) = @_;
	
	my $request = $response->request;
	my $result = {};
	
	my $content = eval {
		from_json($request->content())
	};
	
	if ( $@ || !$content ) {
		$result = {
			error => "Failed to get request body data: " . ($@ || 'no data'),
			code  => 500,
		};
	}
	elsif ( ref $content && ref $content eq 'ARRAY' ) {
		my @actions;
		foreach my $file ( @$content ) {
			if ( my $url = Slim::Plugin::DnDPlay::FileManager->getCachedFileUrl($file) ) {
				push @actions, $url;
			}
			else {
				push @actions, 'upload'
			}
		}
		
		$result->{actions} = \@actions;
	}
	else {
		$result = {
			error => "Invalid data, Array of file descriptions expected " . (main::DEBUGLOG && Data::Dump::dump($content)),
			code  => 500
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
			my %info;
	
			foreach my $data (split /--\Q$boundary\E/, $$content) {
				if ( $data =~ s/(.+?)${CRLF}${CRLF}//s ) {
					my $header = $1;
					$data =~ s/$CRLF*$//s;

					main::DEBUGLOG && $log->is_debug && $log->debug("New section header found: " . Data::Dump::dump($header));
					
					# uploaded file
					if ( $header =~ /filename=".+?"/si ) {
						if ( my $url = Slim::Plugin::DnDPlay::FileManager->getFileUrl($header, \$data, \%info) ) {
							$info{url} = $url;
							$client->execute([ 'playlist', Slim::Player::Playlist::count($client) ? 'add' : 'play', $url ]);
							delete $result->{code};
						}
						else {
							$result->{code} = 415; # unsupported media type
						}
					}
					elsif ( $header =~ /name="(.+?)"/si ) {
						$info{$1} = $data;
					}
				}
			}
			
			main::DEBUGLOG && $log->is_debug && $log->debug("Found additional file information: " . Data::Dump::dump(%info));
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

