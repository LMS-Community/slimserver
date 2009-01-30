package Slim::Player::Squeezebox;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use warnings;

use base qw(Slim::Player::Player);

use File::Spec::Functions qw(:ALL);
use IO::Socket;
use MIME::Base64;
use Scalar::Util qw(blessed);

use Slim::Hardware::IR;
use Slim::Player::ProtocolHandlers;
use Slim::Player::ReplayGain;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

my $log       = logger('network.protocol.slimproto');
my $sourcelog = logger('player.source');

# We inherit new() completely from our parent class.

sub init {
	my $client = shift;

	$client->SUPER::init();
}

sub modelName { 'Squeezebox' }

sub needsWeightedPlayPoint { 0 }

sub reconnect {
	my $client = shift;
	my $paddr = shift;
	my $revision = shift;
	my $tcpsock = shift;
	my $reconnect = shift;
	my $bytes_received = shift;

	$client->tcpsock($tcpsock);
	$client->paddr($paddr);
	$client->revision($revision);	
	
	# tell the client the server version
	if ($client->isa("Slim::Player::SoftSqueeze") || $revision > 39) {
		$client->sendFrame('vers', \$::VERSION);
	}
	
	# check if there is a sync group to restore
	Slim::Player::Sync::restoreSync($client);
	
	if ( main::SLIM_SERVICE ) {
		# SN supports reconnecting from another instance
		# without stopping the audio.  If the database contains
		# stale data, this is caught by a timer that checks the buffer
		# level after a STAT call to make sure the player is really
		# playing/paused.
		my $state = $client->playerData->playmode;
		if ( $state =~ /^(?:PLAYING|PAUSED)/ ) {
			$sourcelog->is_info && $sourcelog->info( $client->id . " current state is $state, resuming" );
			
			$reconnect = 1;
			
			my $controller = $client->controller();
			
			$controller->setState($state);
			
			$controller->playerActive($client);
			
			# SqueezeNetworkClient handles the following in it's reconnect():
			# Restoring the playlist
			# Calling reinit in protocol handler if necessary
			# Restoring SongStreamController
		}
	}

	# The reconnect bit for Squeezebox means that we're
	# reconnecting after the control connection went down, but we
	# didn't reboot.  For Squeezebox2, it means that we're
	# reconnecting and there is an active data connection. In
	# both cases, we do the same thing:
	# If we were playing previously, either restart the track or
	# resume streaming at the bytes_received point. If we were
	# paused, then stop.

	if (!$reconnect) {
		my $controller = $client->controller();

		if ($client->power()) {
			$controller->playerActive($client);
		}
		
		if ($controller->onlyActivePlayer($client)) {
			$sourcelog->is_info && $sourcelog->info($client->id . " restaring play on pseudo-reconnect at "
				. ($bytes_received ? $bytes_received : 0));
			$controller->playerReconnect($bytes_received);
		} 
		
		if ($client->isStopped()) {
			# Ensure that a new client is stopped, but only on sb2s
			if ( $client->isa('Slim::Player::Squeezebox2') ) {
				$sourcelog->is_info && $sourcelog->info($client->id . " forcing stop on pseudo-reconnect");
				$client->stop();
			}
		}
	}

	# reinitialize the irtime to the current time so that
	# (re)connecting counts as activity (and we don't
	# immediately switch into a screensaver).
	my $now = Time::HiRes::time();
	$client->epochirtime($now);

	$client->display->resetDisplay();

	$client->brightness($prefs->client($client)->get($client->power() ? 'powerOnBrightness' : 'powerOffBrightness'));

	$client->update( { 'screen1' => {}, 'screen2' => {} } );

	# put something on the display unless we are about to show the upgrade screen
	$client->update() unless $client->needsUpgrade;	

	$client->display->visualizer(1) if ($client->display->isa('Slim::Display::Squeezebox2'));
}

sub connected { 
	my $client = shift;

	return ($client->tcpsock() && $client->tcpsock->connected()) ? 1 : 0;
}

sub closeStream {
	if ( !main::SLIM_SERVICE ) {
		Slim::Web::HTTP::forgetClient(shift);
	}
}

sub ticspersec {
	return 1000;
}

sub play {
	my $client = shift;
	my $params = shift;
	
	my $controller = $params->{'controller'};
	my $handler = $controller->songProtocolHandler();

	# Calculate the correct buffer threshold for remote URLs
	if ( $handler->isRemote() ) {
		# begin playback once we have this much data in the decode buffer (in KB)
		$params->{bufferThreshold} = 20;
		
		# Reduce threshold if protocol handler wants to
		if ( $handler->can('bufferThreshold') ) {
			$params->{bufferThreshold} = $handler->bufferThreshold( $client, $params->{url} );
		}

		# If we know the bitrate of the stream, we instead buffer a certain number of seconds of audio
		elsif ( my $bitrate = $controller->song()->streambitrate() ) {
			my $bufferSecs = $prefs->get('bufferSecs') || 3;
			
			if ( main::SLIM_SERVICE ) {
				# Per-client buffer secs pref on SN
				$bufferSecs = $prefs->client($client)->get('bufferSecs') || 3;
			}
			
			$params->{bufferThreshold} = ( int($bitrate / 8) * $bufferSecs ) / 1000;
			
			# Max threshold is 255
			$params->{bufferThreshold} = 255 if $params->{bufferThreshold} > 255;
		}
		
		$client->buffering($params->{bufferThreshold} * 1024);
	}

	$client->bufferReady(0);
	
	my $ret = $client->stream_s($params);

	# make sure volume is set, without changing temp setting
	$client->volume($client->volume(), defined($client->tempVolume()));

	return $ret;
}

#
# tell the client to unpause the decoder
#
sub resume {
	my $client = shift;
	
	$client->stream('u');
	$client->SUPER::resume();
	return 1;
}

#
# pause
#
sub pause {
	my $client = shift;

	$client->stream('p');
	$client->playPoint(undef);
	$client->SUPER::pause();
	return 1;
}

sub stop {
	my $client = shift;

	$client->stream('q');
	$client->playPoint(undef);
	Slim::Networking::Slimproto::stop($client);
	# disassociate the streaming socket to the client from the client.  HTTP.pm will close the socket on the next select.
	$client->streamingsocket(undef);
	$client->readyToStream(1);
	$client->SUPER::stop();
}

sub bufferFullness {
	my $client = shift;
	return Slim::Networking::Slimproto::fullness($client);
}

sub bytesReceived {
	return Slim::Networking::Slimproto::bytesReceived(@_);
}

sub signalStrength {
	return Slim::Networking::Slimproto::signalStrength(@_);
}

sub hasIR() { 
	return 1;
}

sub hasDigitalOut {
	return 1;
}

# if an update is required, return the version of the appropriate upgrade image
#
sub needsUpgrade {
	my $client = shift;
	
	# Avoid reading the file if we've already read it
	if ( defined $client->_needsUpgrade ) {
		return $client->_needsUpgrade;
	}

	my $from  = $client->revision || return 0;
	my $model = $client->model;
	my $log   = logger('player.firmware');
	
	my $versionFilePath = catdir( Slim::Utils::OSDetect::dirsFor('Firmware'), "$model.version" );
	my $versionFile;

	$log->info("Reading firmware version file: $versionFilePath");

	if (!open($versionFile, "<$versionFilePath")) {
		warn("can't open $versionFilePath\n");
		return 0;
	}

	my $to;
	my $default;

	while (<$versionFile>) {

		chomp;
		next if /^\s*(#.*)?$/;

		if (/^(\d+)\s*\.\.\s*(\d+)\s+(\d+)\s*$/) {

			next unless $from >= $1 && $from <= $2;
			$to = $3;

		} elsif (/^(\d+)\s+(\d+)\s*$/) {

			next unless $1 == $from;
			$to = $2;

		} elsif (/^\*\s+(\d+)\s*$/) {

			$default = $1;

		} else {

			logError("Garbage in $versionFilePath at line $.: $_");
		}

		last;
	}

	close($versionFile);

	if (!defined $to) {

		if ($default) {

			# use the default value in case we need to go back from the future.
			$log->info("No target found, using default version: $default");
			$to = $default;

		} else {

			$log->info("No upgrades found for $model v. $from");
			$client->_needsUpgrade(0);
			return 0;
		}
	}

	if ($to == $from) {

		$log->info("$model firmware is up-to-date, v. $from");
		$client->_needsUpgrade(0);
		return 0;
	}

	# skip upgrade if file doesn't exist
	my $file = shift || catdir( Slim::Utils::OSDetect::dirsFor('Firmware'), $model . "_$to.bin" );
	my $file2 = catdir( $prefs->get('cachedir'), $model . "_$to.bin" );

	unless ( (-r $file && -s $file) || (-r $file2 && -s $file2) ) {

		$log->info("$model v. $from could be upgraded to v. $to if the file existed.");
		
		# We now download firmware from the internet.  In the case of no internet connection
		# we want to check if the file has appeared later.  This timer will check every 10 minutes
		Slim::Utils::Timers::killOneTimer( $client, \&checkFirmwareUpgrade );
		Slim::Utils::Timers::setTimer( $client, time() + 600, \&checkFirmwareUpgrade );
		
		# display an error message
		$client->showBriefly( {
			'line' => [ $client->string( 'FIRMWARE_MISSING' ), $client->string( 'FIRMWARE_MISSING_DESC' ) ]
		}, { 
			'block' => 1, 'scroll' => 1, 'firstline' => 1,
		} );
		
		return 0;
	}

	$log->info("$model v. $from requires upgrade to $to");

	return $to;
}

=head2 checkFirmwareUpgrade($client)

This timer is run every 10 minutes if a client is out of date and a firmware file is not
present in the Firmware directory.  Another timer in Slim::Utils::Firmware may have
downloaded firmware in the background, so if the file has appeared, we will prompt
the user to upgrade their firmware by holding BRIGHTNESS

=cut

sub checkFirmwareUpgrade {
	my $client = shift;

	if ( $client->needsUpgrade() ) {
		
		logger('player.firmware')->info("Firmware file has appeared, prompting player to upgrade"); 

		# don't start playing if we're upgrading
		$client->execute(['stop']);

		# ask for an update if the player will do it automatically
		$client->sendFrame('ureq');

		$client->brightness($client->maxBrightness());

		# turn of visualizers and screen2 display
		$client->modeParam('visu', [0]);
		$client->modeParam('screen2active', undef);
		
		$client->block( {
			'screen1' => {
				'line' => [
					$client->string('PLAYER_NEEDS_UPGRADE_1'),
					$client->isa('Slim::Player::Boom') ? '' : $client->string('PLAYER_NEEDS_UPGRADE_2')
				],
				'fonts' => { 
					'graphic-320x32' => 'light',
					'graphic-160x32' => 'light_n',
					'graphic-280x16' => 'small',
					'text'           => 2,
				},
			},
			'screen2' => {},
		}, 'upgrade');
	}
	
	# If the file is still missing, the timer will be reset by needsUpgrade
}

# the new way: use slimproto
sub upgradeFirmware_SDK5 {
	my ($client, $filename) = @_;

	use bytes;

	my $log = logger('player.firmware');

	$log->info("Updating firmware with file: $filename");

	my $frame;

	# disable visualizer is this mode
	$client->modeParam('visu', [0]);

	# force brightness to dim if off
	if ($client->display->currBrightness() == 0) { $client->display->brightness(1); }

	open FS, $filename || return("Open failed for: $filename\n");

	binmode FS;
	
	my $size = -s $filename;
	
	$log->info("Updating firmware: Sending $size bytes");
	
	my $line = $client->string('UPDATING_FIRMWARE_' . uc($client->model()));
	
	# Display 1 of 2, 2 of 2 during Boom 2-stage upgrade
	if ( $client->deviceid == 10 ) {
		my $from = $client->revision();
		my $to   = $client->needsUpgrade();
		
		if ( $to == 30 ) {
			$line .= ' (1 ' . $client->string('OUT_OF') . ' 2)';
		}
		elsif ( $from == 30 ) {
			$line .= ' (2 ' . $client->string('OUT_OF') . ' 2)';
		}
	}

	# place in block mode so that brightness key is now ignored
	$client->block( {
		'line'  => [ $line ],
		'fonts' => { 
			'graphic-320x32' => 'light',
			'graphic-160x32' => 'light_n',
			'graphic-280x16' => 'small',
			'text'           => 2,
		},
	}, 'upgrade', 1 );
	
	my $bytesread      = 0;
	my $totalbytesread = 0;
	my $lastFraction   = -1;
	my $byteswritten;
	my $bytesleft;
	
	while ($bytesread = read(FS, my $buf, 1024)) {

		assert(length($buf) == $bytesread);

		$client->sendFrame('upda', \$buf);

		$totalbytesread += $bytesread;

		$log->info("Updating firmware: $totalbytesread / $size");

		my $fraction = $totalbytesread / $size;

		if (($fraction - $lastFraction) > (1/40)) {

			$client->showBriefly( {

				'line'  => [ 
					$line,
					$client->symbols($client->progressBar($client->displayWidth(), $totalbytesread/$size))
				],
				'fonts' => { 
					'graphic-320x32' => 'light',
					'graphic-160x32' => 'light_n',
					'graphic-280x16' => 'small',
					'text'           => 2,
				},
				'jive'  => undef,
				'cli'   => undef,
			} );

			$lastFraction = $fraction;
		}
	}

	$client->unblock();

	$client->sendFrame('updn', \(' ')); # upgrade done

	$log->info("Firmware updated successfully.");

#	Slim::Utils::Network::blocking($client->tcpsock, 0);

	return undef;
}

sub vfd {
	my $client = shift;
	my $data = shift;

	if ($client->opened()) {
		$client->sendFrame('vfdc', \$data);
	} 
}

sub opened {
	my $client = shift;
	if ($client->tcpsock) {
		if (fileno $client->tcpsock && $client->tcpsock->connected) {
			return $client->tcpsock;
		} else {
			$client->tcpsock(undef);
		}
	}
	return undef;
}

# Squeezebox control for tcp stream
#
#	u8_t command;		// [1]	's' = start, 'p' = pause, 'u' = unpause, 'q' = stop, 'f' = flush
#	u8_t autostart;		// [1]	'0' = don't auto-start, '1' = auto-start, '2' = direct streaming, '3' direct streaming + autostart
#	u8_t mode;		// [1]	'm' = mpeg bitstream, 'p' = PCM
#	u8_t pcm_sample_size;	// [1]	'0' = 8, '1' = 16, '2' = 24, '3' = 32
#	u8_t pcm_sample_rate;	// [1]	'0' = 11kHz, '1' = 22, '2' = 32, '3' = 44.1, '4' = 48, '5' = 8, '6' = 12, '7' = 16, '8' = 24, '9' = 96
#	u8_t pcm_channels;	// [1]	'1' = mono, '2' = stereo
#	u8_t pcm_endianness;	// [1]	'0' = big, '1' = little
#	u8_t threshold;		// [1]	Kb of input buffer data before we autostart or notify the server of buffer fullness
#	u8_t spdif_enable;	// [1]  '0' = auto, '1' = on, '2' = off
#	u8_t transition_period;	// [1]	seconds over which transition should happen
#	u8_t transition_type;	// [1]	'0' = none, '1' = crossfade, '2' = fade in, '3' = fade out, '4' fade in & fade out
#	u8_t flags;		// [1]	0x80 - loop infinitely
#                               //      0x40 - stream without restarting decoder
#				//	0x01 - polarity inversion left
#				//	0x02 - polarity inversion right
#	u8_t output_threshold;	// [1]	Amount of output buffer data before playback starts in tenths of second.
#	u8_t reserved;		// [1]	reserved
#	u32_t replay_gain;	// [4]	replay gain in 16.16 fixed point, 0 means none
#	u16_t server_port;	// [2]	server's port
#	u32_t server_ip;	// [4]	server's IP
#				// ____
#				// [24]
#
sub stream_s {
	my ($client, $params) = @_;

	my $format = $params->{'format'};

	return 0 unless ($client->opened());
		
	my $controller  = $params->{'controller'};
	my $url         = $controller->streamUrl();
	my $track       = $controller->track();
	my $handler     = $controller->protocolHandler();
	my $songHandler = $controller->songProtocolHandler();
	my $isDirect    = $controller->isDirect();
	my $master      = $client->master();

	if ( $log->is_info) {
		$log->info(sprintf("stream_s called:%s format: %s url: %s",
			($params->{'paused'} ? ' paused' : ''), ($format || 'undef'), ($params->{'url'} || 'undef')
		));
	}
	
	$client->streamStartTimestamp(undef);

	# autostart off when pausing, otherwise 75%
	my $autostart = $params->{'paused'} ? 0 : 1;

	my $bufferThreshold;

	if ($params->{'paused'}) {
		$bufferThreshold = $params->{bufferThreshold} || $prefs->client($client)->get('syncBufferThreshold');
	}
	else {
		$bufferThreshold = $params->{bufferThreshold} || $prefs->client($client)->get('bufferThreshold');
	}
	
	my $formatbyte;
	my $pcmsamplesize;
	my $pcmsamplerate;
	my $pcmendian;
	my $pcmchannels;
	my $outputThreshold;
	
	if ($isDirect) {
		# use getFormatForURL only if the format is not already given
		# This method is bad because it only looks at the URL suffix and can cause
		# (for example) Ogg HTTP streams to be played using the mp3 decoder!
		if ( !$format && $handler->can("getFormatForURL") ) {
			$format = $handler->getFormatForURL($url);
		}
	}
		
	if ( !$format ) {
		logBacktrace("*** stream('s') called with no format, defaulting to mp3 decoder, url: $params->{'url'}");
	}

	$format ||= 'mp3';

	if ($format eq 'pcm') {

		$formatbyte      = 'p';
		$pcmsamplesize   = 1;
		$pcmsamplerate   = 3;
		$pcmendian       = 1;
		$pcmchannels     = 2;
		$outputThreshold = 0;

		if ( $track ) {
			$pcmsamplesize = $client->pcm_sample_sizes($track);
			$pcmsamplerate = $client->pcm_sample_rates($track);
			$pcmchannels   = $track->channels() || '2';
		}

	} elsif ($format eq 'aif') {

		my $track = Slim::Schema->rs('Track')->objectForUrl({
			'url' => $params->{url},
		});

		$formatbyte      = 'p';
		$pcmsamplesize   = 1;
		$pcmsamplerate   = 3;
		$pcmendian       = 0;
		$pcmchannels     = 2;
		$outputThreshold = 0;

		if ( $track ) {
			$pcmsamplesize = $client->pcm_sample_sizes($track);
			$pcmsamplerate = $client->pcm_sample_rates($track);
			$pcmchannels   = $track->channels() || '2';
		 }

	} elsif ($format eq 'flc') {

		$formatbyte      = 'f';
		$pcmsamplesize   = '?';
		$pcmsamplerate   = '?';
		$pcmendian       = '?';
		$pcmchannels     = '?';
		$outputThreshold = 0;

		# Threshold the output buffer for high sample-rate flac.
		if ( $track ) {
			if ( $track->samplerate() && $track->samplerate() >= 88200 ) {
		    	$outputThreshold = 20;
			}
		}

	} elsif ( $format =~ /(?:wma|asx)/ ) {

		$formatbyte = 'w';
		
		my ($chunked, $audioStream, $metadataStream) = (0, 1, undef);
		
		if ($handler->can('getMMSStreamingParameters')) {
			($chunked, $audioStream, $metadataStream) = 
				$handler->getMMSStreamingParameters($controller->song(),  $url);
		}

		# Commandeer the unused pcmsamplesize field
		# to indicate whether the data coming in is
		# going to have the mms/http chunking headers.
		$pcmsamplesize = $chunked;
		
		# Bug 3981, For WMA streams, we send the streamid using the pcmsamplerate field
		# so the firmware knows which stream to play
		$pcmsamplerate   = chr($audioStream);
		
		# And the pcmchannels fields hold the metadata stream number, if any
		$pcmchannels     = defined($metadataStream) ? chr($metadataStream) : '?';
		
		$pcmendian       = '?';
		$outputThreshold = 10;
		
	} elsif ($format eq 'ogg') {

		$formatbyte      = 'o';
		$pcmsamplesize   = '?';
		$pcmsamplerate   = '?';
		$pcmendian       = '?';
		$pcmchannels     = '?';
		$outputThreshold = 20;

	} else {

		# assume MP3
		$formatbyte      = 'm';
		$pcmsamplesize   = '?';
		$pcmsamplerate   = '?';
		$pcmendian       = '?';
		$pcmchannels     = '?';
		$outputThreshold = 0;
		
		# Handler may override pcmsamplesize (Rhapsody)
		if ( $songHandler && $songHandler->can('pcmsamplesize') ) {
			$pcmsamplesize = $songHandler->pcmsamplesize( $client, $params );
		}

		# XXX: The use of mp3 as default has been known to cause the mp3 decoder to be used for
		# other audio types, resulting in static. 
		if ( $format ne 'mp3' ) {
			logBacktrace("*** mp3 decoder used for format: $format, url: $params->{'url'}");
		}
	}
		
	my $request_string = '';
	my ($server_port, $server_ip);
	
	# When streaming a new song, we reset the buffer fullness value so buffering()
	# doesn't get an outdated fullness result
	Slim::Networking::Slimproto::fullness( $client, 0 );
			
	if ($isDirect) {

		# Logger for direct streaming
		my $log = logger('player.streaming.direct');

		$log->info("This player supports direct streaming for $params->{'url'} as $url, let's do it.");
		
		my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);
				
		# If a proxy server is set, change ip/port
		my $proxy;
		if ( main::SLIM_SERVICE ) {
			$proxy = $prefs->client($client)->get('webproxy');
		}
		else {
			$proxy = $prefs->get('webproxy');
		}
		
		if ( $proxy ) {
			my ($pserver, $pport) = split /:/, $proxy;
			$server = $pserver;
			$port   = $pport;
		}
				
		my ($name, $liases, $addrtype, $length, @addrs) = gethostbyname($server);
		if ($port && $addrs[0]) {
			$server_port = $port;
			$server_ip = unpack('N',$addrs[0]);
		}

		$request_string = $handler->requestString($client, $url, undef, $params->{'seekdata'});  
		$autostart += 2; # will be 2 for direct streaming with no autostart, or 3 for direct with autostart

		if (!$server_port || !$server_ip) {

			$log->info("Couldn't get an IP and Port for direct stream ($server_ip:$server_port), failing.");

			$client->failedDirectStream();
			Slim::Networking::Slimproto::stop($client);
			return 0;

		} else {

			$log->info("setting up direct stream ($server_ip:$server_port) autostart: $autostart.");
			$log->info("request string: $request_string");
		}
				
	} else {

		$request_string = sprintf("GET /stream.mp3?player=%s HTTP/1.0\n", $client->id);
			
		if ($prefs->get('authorize')) {

			$client->password(generate_random_string(10));
				
			my $password = encode_base64('squeezeboxXXX:' . $client->password);
				
			$request_string .= "Authorization: Basic $password\n";
		}

		$server_port = $prefs->get('httpport');

		# server IP of 0 means use IP of control server
		$server_ip = 0;
		$request_string .= "\n";

		if (length($request_string) % 2) {
			$request_string .= "\n";
		}
		
		# Possible fix for another problem when using a transcoder:
		# if ($controller->streamHandler()->isa($handler) && $handler->can('handlesStreamHeaders')) {
		#
		
		if ($handler->can('handlesStreamHeaders')) {
			# Handler wants to be called once the stream is open
			$autostart += 2;
		}
		
	}


	# If we're sending an 's' command but got no request string, don't send it
	# This is used when syncing Rhapsody radio stations so slaves don't request the radio playlist
	if ( !$request_string ) {
		return 0;
	}

	if ( $log->is_info ) {
		$log->info(sprintf(
			"Starting with decoder with format: %s autostart: %s threshold: %s samplesize: %s samplerate: %s endian: %s channels: %s",
			$formatbyte, $autostart, $bufferThreshold, $pcmsamplesize, $pcmsamplerate, $pcmendian, $pcmchannels,
		));
	}

	my $flags = 0;
	$flags |= 0x40 if $params->{reconnect};
	$flags |= 0x80 if $params->{loop};
	$flags |= ($prefs->client($client)->get('polarityInversion') || 0);
		
	my $replayGain = $client->canDoReplayGain($params->{replay_gain});
		
	# Reduce buffer threshold if a file is really small
	# Probably not necessary with fixes for bug 8861 and/or bug 9125 in place
	if ( $track && $track->filesize && $track->filesize < ( $bufferThreshold * 1024 ) ) {
		$bufferThreshold = (int( $track->filesize / 1024 ) || 2) - 1;
		$log->info( "Reducing buffer threshold to $bufferThreshold due to small file: " );
	}
		
	# If looping, reduce the threshold, some of our sounds are really short
	if ( $params->{loop} ) {
		$bufferThreshold = 10;
	}

	$log->debug("flags: $flags");

	my $transitionType;
	my $transitionDuration;
	
	if ($params->{'fadeIn'}) {
		$transitionType = 2;
		$transitionDuration = $params->{'fadeIn'};
	} else {
		$transitionType = $prefs->client($master)->get('transitionType') || 0;
		$transitionDuration = $prefs->client($master)->get('transitionDuration') || 0;
		
		# If we need to determine dynamically
		if (
			$prefs->client($master)->get('transitionSmart') 
			&&
			( Slim::Player::ReplayGain->trackAlbumMatch( $master, -1 ) 
			  ||
			  Slim::Player::ReplayGain->trackAlbumMatch( $master, 1 )
			)
		) {
			$log->info('Using smart transition mode');
			$transitionType = 0;
		}
		
		# Bug 10567, allow plugins to override transition setting
		if ( $songHandler && $songHandler->can('transitionType') ) {
			my $override = $songHandler->transitionType( $master, $controller->song(), $transitionType );
			if ( defined $override ) {
				$log->is_info && $log->info("$songHandler changed transition type to $override");
				$transitionType = $override;
			}
		}
	}
	
	if ($transitionDuration > $client->maxTransitionDuration()) {
		$transitionDuration = $client->maxTransitionDuration();
	}
	
	my $frame = pack 'aaaaaaaCCCaCCCNnN', (
		's',	# command
		$autostart,
		$formatbyte,
		$pcmsamplesize,
		$pcmsamplerate,
		$pcmchannels,
		$pcmendian,
		$bufferThreshold,
		0,		# s/pdif auto
		$transitionDuration,
		$transitionType,
		$flags,		# flags	     
		$outputThreshold,
		0,		# reserved
		$replayGain,	
		$server_port || $prefs->get('httpport'),  # use slim server's IP
		$server_ip || 0,
	);
	
	assert(length($frame) == 24);
	
	$frame .= $request_string;

	if ( $log->is_debug ) {
		$log->info("sending strm frame of length: " . length($frame) . " request string: [$request_string]");
	}

	$client->sendFrame('strm', \$frame);
	
	$client->readyToStream(0);

	if ($client->pitch() != 100) {
		$client->sendPitch($client->pitch());
	}
	
	return 1;
}

# Everything except 's' command
sub stream {
	my ($client, $command, $params) = @_;

	return unless ($client->opened());
	
	if ( ($log->is_info && $command ne 't') || $log->is_debug) {
		$log->info("strm-$command");
	}

	my $flags = 0;
	$flags |= ($prefs->client($client)->get('polarityInversion') || 0);
		
	# ReplayGain field is also used for startAt, pauseAt, unpauseAt, timestamp
	my $replayGain = 0;
	my $interval = $params->{interval} || 0;
	if ($command eq 'a' || $command eq 'p') {
		$replayGain = int($interval * 1000);
	}
	elsif ($command eq 'u') {
		 $replayGain = $interval;
	}
	elsif ($command eq 't') {
		$replayGain = int(Time::HiRes::time() * 1000 % 0xffffffff);
	}
	else {
		$replayGain = $client->canDoReplayGain($params->{replay_gain});
	}
		
	my $frame = pack 'aaaaaaaCCCaCCCNnN', (
		$command,	# command
		0,		# autostart
		'm',	# format byte
		'?',
		'?',
		'?',
		'?',
		0,		# bufferTthreshold
		0,		# s/pdif auto
		0,		# transition duration
		0,		# transition type
		$flags,	# flags	     
		0,		# outputThreshold
		0,		# reserved
		$replayGain,	
		0,		# server_port 
		0,		# server_ip 
	);

	assert(length($frame) == 24);
	
	if ( $log->is_debug ) {
		$log->info("sending strm frame of length: " . length($frame));
	}

	$client->sendFrame('strm', \$frame);	
}

sub pcm_sample_sizes {
	my $client = shift;
	my $track = shift;

	my %pcm_sample_sizes = ( 8 => '0',
				 16 => '1',
				 24 => '2',
				 32 => '3',
				 );

	my $size = $pcm_sample_sizes{$track->samplesize() || 16};

	return defined $size ? $size : '1';
}

sub sendFrame {
	my $client = shift;
	my $type = shift;
	my $dataRef = shift;
	my $empty = '';

	# don't try to send if the player has disconnected.
	if (!defined($client->tcpsock)) {
		return;
	}

	if (!defined($dataRef)) {
		$dataRef = \$empty;
	}

	my $len = length($$dataRef);

	assert(length($type) == 4);
	
	my $frame;
	
	# Compress all graphic frames on SN, saves a huge amount of bandwidth
	if ( main::SLIM_SERVICE && $type eq 'grfe' && $client->hasCompression ) {
		# Bug 8250, firmware bug in TP breaks if compressed frame sent for screen 2
		# so for now disable all compression for TP
		if ( $client->deviceid == 5 ) {
			$frame = pack('n', $len + 4) . $type . $$dataRef;
		}
		else {		
			# Compress only graphic frames, other frames are very small
			# or don't compress well.
			my $compressed = Compress::LZF::compress($$dataRef);
		
			# XXX: This should be fixed in a future version of Compress::LZF
			# Replace Perl header with C header so we can decompress
			# properly in the firmware
			if ( ord( substr $compressed, 0, 1 ) == 0 ) {
				# The data wasn't able to be compressed
				my $c_header = "ZV\0" . pack('n', $len);
				substr $compressed, 0, 1, $c_header;
			}
			else {
				my $csize = length($compressed) - 2;
				my $c_header = "ZV\1" . pack('n', $csize) . pack('n', $len);
				substr $compressed, 0, 2, $c_header;
			}
		
			$frame
				= pack( 'n', length($compressed) + 4 ) 
				. ( $type | pack( 'N', 0x80000000 ) )
				. $compressed;
		}
	}
	else {
		$frame = pack('n', $len + 4) . $type . $$dataRef;
	}

	$log->is_debug && $log->debug("sending squeezebox frame: $type, length: $len");

	$::perfmon && $client->slimprotoQLenLog()->log(Slim::Networking::Select::writeNoBlockQLen($client->tcpsock));

	Slim::Networking::Select::writeNoBlock($client->tcpsock, \$frame);
}

# This function generates random strings of a given length
sub generate_random_string
{
	# the length of the random string to generate
        my $length_of_randomstring = shift;

        my @chars = ('a'..'z','A'..'Z','0'..'9','_');
        my $random_string;

        foreach (1..$length_of_randomstring) {
                #rand @chars will generate a random number between 0 and scalar @chars
                $random_string .= $chars[rand @chars];
        }

        return $random_string;
}

sub i2c {
	my ($client, $data) = @_;

	if ($client->opened()) {
		$client->sendFrame('i2cc', \$data);
	}
}

sub mixerConstant {
	my ($client, $feature, $aspect) = @_;

	# Return 1 for increment so that we can have a range of 0 - 100.
	# Char based displays only have 0 - 40, so the mixerConstant defined
	# in Slim::Player::Client with an increment of 2.5 is correct.
	if ($feature eq 'volume' && !$client->display->isa('Slim::Display::Text')) {

		if ($aspect eq 'scale' || $aspect eq 'increment') {
			return 1;
		}
	}

	return $client->SUPER::mixerConstant($feature, $aspect);
}

sub volumeString {
	my ($client, $volume) = @_;

	if ($volume <= 0) {

		return sprintf(' (%s)', $client->string('MUTED'));
	}

	return sprintf(' (%i)', $volume);
}

1;
