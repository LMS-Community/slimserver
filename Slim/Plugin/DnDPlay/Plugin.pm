package Slim::Plugin::DnDPlay::Plugin;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);

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

	if (main::WEBUI) {
		# this handler hijacks the default handler for js-main, to inject the D'n'd code
		Slim::Web::Pages->addPageFunction("js-main\.html", sub {
			my $params = $_[1];
			$params->{maxUploadSize} = MAX_UPLOAD_SIZE;
			$params->{fileTooLarge}  = string('PLUGIN_DNDPLAY_FILE_TOO_LARGE', '{0}', '{1}');
			Slim::Web::HTTP::filltemplatefile('html/js-main-dd.html', $params);
		});
	} 
	
	# the file upload is handled through a custom request handler, dealing with multi-part POST requests
	Slim::Web::Pages->addRawFunction("plugin/dndplay/upload", \&handleUpload);
	
    Slim::Control::Request::addDispatch(['uploadcheck'], [0, 1, 1, \&cliFilesCheck]);
}

sub handleUpload {
	my ($httpClient, $response, $func) = @_;
	
	my $request = $response->request;
	my $result = {};
	
	if ( my $client = _getClient($request) ) {
		if ( $request->content_length > MAX_UPLOAD_SIZE ) {
			$result = {
				error => sprintf(cstring($client, 'PLUGIN_DNDPLAY_FILE_TOO_LARGE'), $request->content_length, MAX_UPLOAD_SIZE),
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
							$result->{url} = $url;
							delete $result->{code};
						}
						else {
							$result->{error} = cstring($client, 'PROBLEM_UNKNOWN_TYPE') . (main::DEBUGLOG && (' ' . Data::Dump::dump(%info)) );
							$result->{code} = 415;
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
			error => string('PLUGIN_DNDPLAY_NO_PLAYER_CONNECTED'),
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

sub cliFilesCheck {
	my $request = shift;
	
	my $files = $request->getParam('files');
	utf8::encode($files);

	$files = eval {
		from_json($files)
	};

	my $count;
	
	if ($@ || !$files || !ref $files) {
		$log->error("Error decoding data: " . ($@ || 'no data'));
	}
	elsif ( ref $files && ref $files eq 'ARRAY' ) {
		my @urls;
		foreach my $file ( @$files ) {
			my $url = Slim::Plugin::DnDPlay::FileManager->getCachedFileUrl($file);
			
			if (!$url) {
				my $key = Slim::Plugin::DnDPlay::FileManager->cacheKey($file);
				$url = 'upload:' . $key;
			}
			
			$request->addResultLoop('files_loop', $count, 'url', $url);				

			$count++;
		}
	}
	else {
		$log->error( "Invalid data, Array of file descriptions expected. " . (main::DEBUGLOG && Data::Dump::dump($files)) );
	}
	
	$request->addResult('count', $count);

	$request->setStatusDone();
}

sub _getClient {
	my $request = shift;
	
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
	
	return $client;
}


1;

