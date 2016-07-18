package Slim::Player::Squeezebox;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use base qw(Slim::Player::Player);

use File::Spec::Functions qw(catdir);
use MIME::Base64;
use Scalar::Util qw(blessed);
use Socket qw(:crlf);

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

sub modelName { 'Squeezebox' }

sub needsWeightedPlayPoint { 0 }

sub reconnect {
	my $client = shift;
	my $paddr = shift;
	my $revision = shift;
	my $tcpsock = shift;
	my $reconnect = shift;
	my $bytes_received = shift;
	my $syncgroupid = shift;

	$client->tcpsock($tcpsock);
	$client->paddr($paddr);
	$client->revision($revision);	
	
	# tell the client the server version
	if ($client->isa("Slim::Player::SoftSqueeze") || $revision > 39) {
		$client->sendFrame('vers', \$::VERSION);
	}
	
	# check if there is a sync group to restore
	Slim::Player::Sync::restoreSync($client, $syncgroupid);

	# The reconnect bit for Squeezebox means that we're
	# reconnecting after the control connection went down, but we
	# didn't reboot.  For Squeezebox2, it means that we're
	# reconnecting and there is an active data connection. In
	# both cases, we do the same thing:
	# If we were playing previously, either restart the track or
	# resume streaming at the bytes_received point. If we were
	# paused, then stop.

	my $controller = $client->controller();

	if (!$reconnect) {

		if ($client->power()) {
			$controller->playerActive($client);
		}
		
		if ($controller->onlyActivePlayer($client)) {
			main::INFOLOG && $sourcelog->is_info && $sourcelog->info($client->id . " restaring play on pseudo-reconnect at "
				. ($bytes_received ? $bytes_received : 0));
			$controller->playerReconnect($bytes_received);
		} 
		
		if ($client->isStopped()) {
			# Ensure that a new client is stopped, but only on sb2s
			if ( $client->isa('Slim::Player::Squeezebox2') ) {
				main::INFOLOG && $sourcelog->is_info && $sourcelog->info($client->id . " forcing stop on pseudo-reconnect");
				$client->stop();
			}
		}
	} else {
		# bug 16881: player in a sync-group may have been made inactive upon disconnect;
		# make sure it is active now.
		if ($client->power()) {
			$controller->playerActive($client);
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
	my $client = shift;
	Slim::Web::HTTP::forgetClient($client);
	@{$client->chunks} = (); # Bug 15477: flush old data
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
		my $bufferSecs = $prefs->get('bufferSecs') || 3;
			
		# begin playback once we have this much data in the decode buffer (in KB)
		$params->{bufferThreshold} = 20;
		
		# Reduce threshold if protocol handler wants to
		if ( $handler->can('bufferThreshold') ) {
			$params->{bufferThreshold} = $handler->bufferThreshold( $client, $params->{url} );
		}

		# If we know the bitrate of the stream, we instead buffer a certain number of seconds of audio
		elsif ( my $bitrate = $controller->song()->streambitrate() ) {
			
			$params->{bufferThreshold} = ( int($bitrate / 8) * $bufferSecs ) / 1000;
			
			# Max threshold is 255
			$params->{bufferThreshold} = 255 if $params->{bufferThreshold} > 255;
		}
		
		$client->buffering($params->{bufferThreshold} * 1024, $bufferSecs * 44100 * 2 * 4);
	}

	$client->bufferReady(0);
	
	my $ret = $client->stream_s($params);

	# make sure volume is set, without changing temp setting
	$client->volume($client->volume(), defined($client->tempVolume()));

	return $ret;
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

	main::INFOLOG && $log->info("Reading firmware version file: $versionFilePath");

	if (!open($versionFile, "<$versionFilePath")) {
		warn("can't open $versionFilePath\n");
		return 0;
	}

	my $to;
	my $default;

	local $_;
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
			main::INFOLOG && $log->info("No target found, using default version: $default");
			$to = $default;

		} else {

			main::INFOLOG && $log->info("No upgrades found for $model v. $from");
			$client->_needsUpgrade(0);
			return 0;
		}
	}

	if ($to == $from) {

		main::INFOLOG && $log->info("$model firmware is up-to-date, v. $from");
		$client->_needsUpgrade(0);
		return 0;
	}

	# skip upgrade if file doesn't exist
	my $file = shift || catdir( Slim::Utils::OSDetect::dirsFor('Firmware'), $model . "_$to.bin" );
	my $file2 = catdir( Slim::Utils::OSDetect::dirsFor('updates'), $model . "_$to.bin" );

	unless ( (-r $file && -s $file) || (-r $file2 && -s $file2) ) {

		main::INFOLOG && $log->info("$model v. $from could be upgraded to v. $to if the file existed.");
		
		# Try to start a background download
		Slim::Utils::Firmware::downloadAsync($file2, {cb => \&checkFirmwareUpgrade, pt => [$client]});
				
		# display an error message
		$client->showBriefly( {
			'line' => [ $client->string( 'FIRMWARE_MISSING' ), $client->string( 'FIRMWARE_MISSING_DESC' ) ]
		}, { 
			'block' => 1, 'scroll' => 1, 'firstline' => 1,
		} );
		
		return 0;
	}

	main::INFOLOG && $log->info("$model v. $from requires upgrade to $to");

	return $to;
}

=head2 checkFirmwareUpgrade($client)

This callback is run when Slim::Utils::Firmware has
downloaded firmware in the background, so we will prompt
the user to upgrade their firmware by holding BRIGHTNESS

=cut

sub checkFirmwareUpgrade {
	my $client = shift;

	if ( $client->needsUpgrade() ) {
		
		main::INFOLOG && logger('player.firmware')->info("Firmware file has appeared, prompting player to upgrade"); 

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

	main::INFOLOG && $log->info("Updating firmware with file: $filename");

	my $frame;

	# disable visualizer is this mode
	$client->modeParam('visu', [0]);

	# force brightness to dim if off
	if ($client->display->currBrightness() == 0) { $client->display->brightness(1); }

	open FS, $filename || return("Open failed for: $filename\n");

	binmode FS;
	
	my $size = -s $filename;
	
	main::INFOLOG && $log->info("Updating firmware: Sending $size bytes");
	
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

		main::INFOLOG && $log->info("Updating firmware: $totalbytesread / $size");

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

	main::INFOLOG && $log->info("Firmware updated successfully.");

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
#	u8_t transition_type;	// [1]	'0' = none, '1' = crossfade, '2' = fade in, '3' = fade out, '4' fade in & fade out, '5' = crossfade-immediate
#	u8_t flags;	// [1]	0x80 - loop infinitely
#               //      0x40 - stream without restarting decoder
#               //      0x20 - Rtmp (SqueezePlay only)
#               //      0x10 - SqueezePlay direct protocol handler - pass direct to SqueezePlay
#               //      0x08 - output only right channel as mono
#               //      0x04 - output only left channel as mono
#               //      0x02 - polarity inversion right
#               //      0x01 - polarity inversion left
#				
#	u8_t output_threshold`;	// [1]	Amount of output buffer data before playback starts in tenths of second.
#	u8_t slaves;		// [1]	number of proxy stream connections to serve
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

	if ( main::INFOLOG && $log->is_info) {
		$log->info(sprintf("stream_s called:%s format: %s url: %s",
			($params->{'paused'} ? ' paused' : ''), ($format || 'undef'), ($params->{'url'} || 'undef')
		));
	}
	
	$client->streamStartTimestamp(undef);

	# autostart off when pausing, otherwise 75%
	my $autostart = $params->{'paused'} ? 0 : 1;

	my $bufferThreshold = $params->{bufferThreshold} || $prefs->client($client)->get('bufferThreshold');
	
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

		my $track = Slim::Schema->objectForUrl({
			'url' => $params->{url},
		}) || $track;

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
			
			# Bug 16341, Don't adjust endian value if file is being transcoded to aif
			if ( $track->content_type eq 'aif' ) {
				$pcmendian = $track->endian() == 1 ? 0 : 1;
			}
		 }

	} elsif ($format eq 'flc' || $format eq 'ogf') {

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

		# Oggflac support for Squeezeplay - uses same decoder with flag to indicate ogg transport stream 
		# increase default output buffer threshold as this is used for high bitrate internet radio streams
		if ($format eq 'ogf') {
			$pcmsamplesize   = 'o';
			$outputThreshold = 20;
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
		
		# Increase outputThreshold for WMA Lossless as it has a higher startup cost
		if ( $format eq 'wmal' ) {
			$outputThreshold = 50;
		}
		
	} elsif ($format eq 'ogg') {

		$formatbyte      = 'o';
		$pcmsamplesize   = '?';
		$pcmsamplerate   = '?';
		$pcmendian       = '?';
		$pcmchannels     = '?';
		$outputThreshold = 20;
		
	} elsif ($format eq 'alc') {

		$formatbyte      = 'l';
		$pcmsamplesize   = '?';
		$pcmsamplerate   = '?';
		$pcmendian       = '?';
		$pcmchannels     = '?';
		$outputThreshold = 0;

	} elsif ($format eq 'mp4' || $format eq 'aac') {
		
		# It is not really correct to assume that all MP4 files (which were not
		# otherwise recognized as ALAC or MOV by the scanner) are AAC, but that
		# is the current status
		
		$formatbyte      = 'a';
		
		# container type and bitstream format: '1' (adif), '2' (adts), '3' (latm within loas), 
		# '4' (rawpkts), '5' (mp4ff), '6' (latm within rawpkts)
		#
		# This is a hack that assumes:
		# (1) If the original content-type of the track is MP4 or SLS then we are streaming an MP4 file (without any transcoding);
		# (2) All other AAC streams will be adts.
		
		$pcmsamplesize   = Slim::Music::Info::contentType($track) =~ /^(?:mp4|sls)$/ ? '5' : '2';
		
		$pcmsamplerate   = '?';
		$pcmendian       = '?';
		$pcmchannels     = '?';
		$outputThreshold = 0;

	} elsif ($format eq 'dff' || $format eq 'dsf') {

		$formatbyte      = 'd';
		$pcmsamplesize   = '?';
		$pcmsamplerate   = '?';
		$pcmendian       = '?';
		$pcmchannels     = '?';
		$outputThreshold = 0;

	} elsif ( $handler->isa('Slim::Player::Protocols::SqueezePlayDirect') ) {

		# Format handled by squeezeplay to allow custom squeezeplay protocol handlers
		$formatbyte      = 's';
		$pcmsamplesize   = '?';
		$pcmsamplerate   = '?';
		$pcmendian       = '?';
		$pcmchannels     = '?';
		$outputThreshold = 1;

	} elsif ($format eq 'test') {

		$formatbyte      = 'n';
		$pcmsamplesize   = '?';
		$pcmsamplerate   = '?';
		$pcmendian       = '?';
		$pcmchannels     = '?';
		$outputThreshold = 0;
		
	} else {

		# assume MP3
		$formatbyte      = 'm';
		$pcmsamplesize   = '?';
		$pcmsamplerate   = '?';
		$pcmendian       = '?';
		$pcmchannels     = '?';
		$outputThreshold = 1;
		
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
	
	if ( $handler->isa('Slim::Player::Protocols::SqueezePlayDirect') ) {

		main::INFOLOG && logger('player.streaming.direct')->info("SqueezePlay direct stream: $url");

		$request_string = $handler->requestString($client, $url, undef, $params->{'seekdata'});  
		$autostart += 2; # will be 2 for direct streaming with no autostart, or 3 for direct with autostart

	} elsif (my $proxy = $params->{'proxyStream'}) {

		$request_string = ' ';	# need at least a byte to keep ip3k happy
		my ($pserver, $pport) = split (/:/, $proxy);
		$server_port = $pport;
		$server_ip = Slim::Utils::Network::intip($pserver);
		$autostart += 2; # will be 2 for direct streaming with no autostart, or 3 for direct with autostart

	} elsif ($isDirect) {

		# Logger for direct streaming
		my $log = logger('player.streaming.direct');

		main::INFOLOG && $log->info("This player supports direct streaming for $params->{'url'} as $url, let's do it.");
		
		my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);
				
		# If a proxy server is set, change ip/port
		my $proxy = $prefs->get('webproxy');
		
		if ( $proxy ) {
			my ($pserver, $pport) = split (/:/, $proxy);
			$server = $pserver;
			$port   = $pport;
		}
		
		# Get IP from async DNS cache if available
		if ( my $addr = Slim::Networking::Async::DNS->cached($server) ) {
			$server_ip = Slim::Utils::Network::intip($addr);
		}
		else {
			my $tv = AnyEvent->time;
			my (undef, undef, undef, undef, @addrs) = gethostbyname($server);
			$log->warn( sprintf "Made synchronous DNS request for $server (%.2f ms)", AnyEvent->time - $tv );
			if ( $addrs[0] ) {
				$server_ip = unpack 'N', $addrs[0];
			}
		}
		$server_port = $port;

		$request_string = $handler->requestString($client, $url, undef, $params->{'seekdata'});  
		$autostart += 2; # will be 2 for direct streaming with no autostart, or 3 for direct with autostart

		if (!$server_port || !$server_ip) {

			main::INFOLOG && $log->info("Couldn't get an IP and Port for direct stream ($server_ip:$server_port), failing.");

			$client->failedDirectStream();
			Slim::Networking::Slimproto::stop($client);
			return 0;

		} else {

			if ( main::INFOLOG && $log->is_info ) {
				$log->info("setting up direct stream ($server_ip:$server_port) autostart: $autostart format: $formatbyte.");
				$log->info("request string: $request_string");
			}
		}
				
	} else {

		$request_string = sprintf("GET /stream.mp3?player=%s HTTP/1.0" . $CRLF, $client->id);
			
		if ($prefs->get('authorize')) {

			$client->password(generate_random_string(10));
				
			my $password = encode_base64('squeezeboxXXX:' . $client->password);
				
			$request_string .= "Authorization: Basic $password" . $CRLF;
		}

		$server_port = $prefs->get('httpport');

		# server IP of 0 means use IP of control server
		$server_ip = 0;
		$request_string .= $CRLF;

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

	my $flags = 0;
	$flags |= 0x40 if $params->{reconnect};
	$flags |= 0x80 if $params->{loop};
	$flags |= 0x03 & ($prefs->client($client)->get('polarityInversion') || 0);
	
	# If the output channels pref is set, and the player is synced to at least 1 other active player
	# we tell the player to only play the desired channel. If not actively synced, the player will play
	# in stereo.
	if ( my $outputChannels = $prefs->client($client)->get('outputChannels') ) {
		if ( $client->isSynced(1) ) { # use active player count
			$flags |= ($outputChannels & 0x03) << 2;
		}
	}

	if ($handler->can('slimprotoFlags')) {
		$flags |= $handler->slimprotoFlags($client, $url, $isDirect);
	}

	my $replayGain = $client->canDoReplayGain($params->{replay_gain});
		
	# Reduce buffer threshold if a file is really small
	# Probably not necessary with fixes for bug 8861 and/or bug 9125 in place
	if ( $track && $track->filesize && $track->filesize < ( $bufferThreshold * 1024 ) ) {
		$bufferThreshold = (int( $track->filesize / 1024 ) || 2) - 1;
		main::INFOLOG && $log->info( "Reducing buffer threshold to $bufferThreshold due to small file: " );
	}
		
	# If looping, reduce the threshold, some of our sounds are really short
	if ( $params->{loop} ) {
		$bufferThreshold = 10;
	}

	main::DEBUGLOG && $log->debug("flags: $flags");

	my $transitionType;
	my $transitionDuration;
	
	if ($params->{'fadeIn'}) {
		$transitionType = 2;
		$transitionDuration = $params->{'fadeIn'};
	} elsif ($params->{'crossFade'}) {
		$transitionType = 5;
		$transitionDuration = $params->{'crossFade'};
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
			main::INFOLOG && $log->info('Using smart transition mode');
			$transitionType = 0;
		}
		
		# Bug 10567, allow plugins to override transition setting
		if ( $songHandler && $songHandler->can('transitionType') ) {
			my $override = $songHandler->transitionType( $master, $controller->song(), $transitionType );
			if ( defined $override ) {
				main::INFOLOG && $log->is_info && $log->info("$songHandler changed transition type to $override");
				$transitionType = $override;
			}
		}
		
		# Bug 13264, don't do transitions if the player is set to sleep at the end of the song
		my $sleeptime = $client->sleepTime() - Time::HiRes::time();
		my $dur = $client->controller()->playingSongDuration() || 0;
		my $remaining = 0;
		
		if ($dur) {
			$remaining = $dur - Slim::Player::Source::songTime($client);
		}
	
		if ($client->sleepTime) {
			
			# check against remaining time to see if sleep time matches within a minute.
			if (int($sleeptime/60 + 0.5) == int($remaining/60 + 0.5)) {
				main::INFOLOG && $log->info('Overriding transition due to sleeping at end of song');
				$transitionType = 0;
			}
		}

		# Don't do transitions if the sample rates of the two
		# songs differ. This avoids some unpleasant white
		# noise from (at least) the Squeezebox Touch when
		# using the analogue outputs. This might be bug#1884.
		# Whether to implement this restriction is controlled
		# by a player preference.
		my $transitionSampleRestriction = $prefs->client($master)->get('transitionSampleRestriction') || 0;

		if (!Slim::Player::ReplayGain->trackSampleRateMatch($master, -1) && $transitionSampleRestriction) {
			main::INFOLOG && $log->info('Overriding crossfade due to differing sample rates');
			$transitionType = 0;
		 } elsif ($transitionSampleRestriction) {
			main::INFOLOG && $log->info('Crossfade sample rate restriction enabled but not needed for this transition');
		 }

	}
	
	if ($transitionDuration > $client->maxTransitionDuration()) {
		$transitionDuration = $client->maxTransitionDuration();
	}
	
	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf(
			"Starting decoder with format: %s flags: 0x%x autostart: %s buffer threshold: %s output threshold: %s samplesize: %s samplerate: %s endian: %s channels: %s",
			$formatbyte, $flags, $autostart, $bufferThreshold, $outputThreshold, $pcmsamplesize, $pcmsamplerate, $pcmendian, $pcmchannels,
		));
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
		($params->{'slaveStreams'} || 0),
		$replayGain,	
		$server_port || $prefs->get('httpport'),  # use slim server's IP
		$server_ip || 0,
	);
	
	assert(length($frame) == 24);
	
	$frame .= $request_string;

	if ( main::DEBUGLOG && $log->is_debug ) {
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
	
	if ( (main::INFOLOG && $log->is_info && $command ne 't') || (main::DEBUGLOG && $log->is_debug) ) {
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
		$replayGain = 0;	# stop using this method to track latency - it is too unreliable
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
	
	if ( main::DEBUGLOG && $log->is_debug ) {
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
	
	my $frame = pack('n', $len + 4) . $type . $$dataRef;

	main::DEBUGLOG && $log->is_debug && $log->debug("sending squeezebox frame: $type, length: $len");

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
