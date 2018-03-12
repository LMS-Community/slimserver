package Slim::Plugin::DnDPlay::Plugin;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Temp qw(tempfile);
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);

use Slim::Plugin::DnDPlay::FileManager;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.dndplay',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_DNDPLAY',
});

my $prefs = preferences('plugin.dndplay');

sub MAX_UPLOAD_SIZE {
	return $prefs->get('maxfilesize') * 1024 * 1024;
}

my $CRLF = $Socket::CRLF;

my $cacheFolder;

sub initPlugin {
	my $class = shift;

	$prefs->init({
		maxfilesize => 100,
	});
	
	if (main::WEBUI) {
		require Slim::Plugin::DnDPlay::Settings;
		Slim::Plugin::DnDPlay::Settings->new();
		
		Slim::Web::Pages->addPageFunction("js-main-dd.js", sub {
			my $params = $_[1];
			$params->{maxUploadSize} = MAX_UPLOAD_SIZE;
			$params->{fileTooLarge}  = string('PLUGIN_DNDPLAY_FILE_TOO_LARGE', '{0}', '{1}');
			$params->{validTypeExtensions} = '\.(' . join('|', Slim::Music::Info::validTypeExtensions()) . ')$';
			Slim::Web::HTTP::filltemplatefile('js-main-dd.js', $params);
		});

		require Slim::Web::Pages::JS;
		Slim::Web::Pages::JS->addJSFunction('js-main', 'js-main-dd.js');		
	} 
	
	# the file upload is handled through a custom request handler, dealing with multi-part POST requests
	Slim::Web::Pages->addRawFunction("plugins/dndplay/upload", \&handleUpload);
	
    Slim::Control::Request::addDispatch(['playlist', 'playmatch'], [1, 1, 1, \&cliPlayMatch]);
    Slim::Control::Request::addDispatch(['playlist', 'addmatch'], [1, 1, 1, \&cliPlayMatch]);
}

# don't run the cleanup before all protocol handlers from plugins are initialized
sub postinitPlugin {
	Slim::Plugin::DnDPlay::FileManager->init();
}

sub handleUpload {
	my ($httpClient, $response, $func) = @_;
	
	my $request = $response->request;
	my $result = {};
	
	my $t = Time::HiRes::time();
	
	if ( my $client = _getClient($request) ) {
		if ( $request->content_length > MAX_UPLOAD_SIZE ) {
			$result = {
				error => sprintf(cstring($client, 'PLUGIN_DNDPLAY_FILE_TOO_LARGE'), formatMB($request->content_length), formatMB(MAX_UPLOAD_SIZE)),
				code  => 413,
			};
		}
		else {
			my $ct = $request->header('Content-Type');
			my ($boundary) = $ct =~ /boundary=(.*)/;
			
			my %info;
			my ($k, $v, $fh);

			# open a pseudo-filehandle to the uploaded data ref for further processing
			open TEMP, '<', $request->content_ref;
			
			while (<TEMP>) {
				if ( Time::HiRes::time - $t > 0.1 ) {
					main::idleStreams();
					$t = Time::HiRes::time();
				}
				
				# a new part starts - reset some variables
				if ( /--\Q$boundary\E/i ) {
					$k = $v = '';
					
					# remove potential superfluous cr/lf from the end of the file, then close it
					if ($fh) {
						truncate $fh, $info{size} if $info{size};
						close $fh;
					}
				}
				
				# write data to file handle
				elsif ( $fh ) {
					print $fh $_;
				}
				
				# we got an uploaded file
				elsif ( !$k && /filename="(.+?)"/i ) {
					$k = 'upload';
				}
				
				# we got the separator after the upload file name: file data comes next. Open a file handle to write the data to.
				elsif ( $k && $k eq 'upload' && /^\s*$/ ) {
					($fh, $info{tempfile}) = tempfile('tmp-XXXX',
						DIR => Slim::Plugin::DnDPlay::FileManager->uploadFolder(),
						UNLINK => 0
					);
				}
				
				# we received some variable name
				elsif ( /\bname="(.+?)"/i ) {
					$k = $1;
				}
				
				# an uploaded variable's content
				elsif ( $k && $k ne 'upload' && $_ ) {
					s/$CRLF*$//s;
					$info{$k} = $_ if $_;
				}
			}
			
			main::DEBUGLOG && $log->is_debug && $log->debug("Uploaded file information found: " . Data::Dump::dump(%info));
			
			close TEMP;

			if ( !$info{name} ) {
				$result->{error} = string('PLUGIN_DNDPLAY_INVALID_DATA');
				$result->{code} = 500;
			}
			elsif ( my $url = Slim::Plugin::DnDPlay::FileManager->getFileUrl(\%info) ) {
				$result->{url} = $url;
				
				if ($info{action}) {
					$client->execute(['playlist', $info{action}, $url]);
				}
				delete $result->{code};
			}
			else {
				$result->{error} = cstring($client, 'PROBLEM_UNKNOWN_TYPE');
				$result->{code} = 415;
			}
			
			if ( $result->{error} && $info{tempfile} && -f $info{tempfile} ) {
				unlink $info{tempfile};
			}
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

sub formatMB {
	return Slim::Utils::Misc::delimitThousands(int($_[0] / 1024 / 1024)) . 'MB';
}

sub cliPlayMatch {
	my $request = shift;
	
	my $client = $request->client;
	
	my $file = {
		name => $request->getParam('name'),
		timestamp => $request->getParam('timestamp'),
		size => $request->getParam('size'),
		type => $request->getParam('type'),
	};

	if ($request->isNotQuery([['playlist'], ['addmatch', 'playmatch']]) || !($file->{name} && $file->{timestamp} && defined $file->{size})) {
		$log->error('Missing file information.');
		$request->setStatusBadDispatch();
		return;
	}
	
	my $action = $request->isQuery([['playlist'], ['playmatch']]) ? 'play' : 'add';

	# if we have a cached or local file, we can play it
	if ( my $url = Slim::Plugin::DnDPlay::FileManager->getCachedOrLocalFileUrl($file) ) {
		$client->execute(['playlist', $action, $url]);
		$request->addResult('success', $action);
	}
	# we should upload, but file is too large
	elsif ( $file->{size} > MAX_UPLOAD_SIZE ) {
		$request->addResult( 'error', sprintf(cstring($client, 'PLUGIN_DNDPLAY_FILE_TOO_LARGE'), formatMB($file->{size}), formatMB(MAX_UPLOAD_SIZE)) );
		$request->addResult( 'maxUploadSize', MAX_UPLOAD_SIZE );
	}
	else {
		my $key = Slim::Plugin::DnDPlay::FileManager->cacheKey($file);
		$request->addResult('upload', $key);
	}

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

