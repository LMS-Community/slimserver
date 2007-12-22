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
use Slim::Hardware::mas35x9;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

# We inherit new() completely from our parent class.

sub init {
	my $client = shift;

	$client->SUPER::init();

	$client->periodicScreenRefresh(); 
}

# periodic screen refresh for players requiring it
sub periodicScreenRefresh {
	my $client = shift;
	my $display = $client->display;

	$display->update() unless ($display->updateMode() || $display->scrollState() == 2 || $client->modeParam('modeUpdateInterval'));

	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1, \&periodicScreenRefresh);
}

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

	# The reconnect bit for Squeezebox means that we're
	# reconnecting after the control connection went down, but we
	# didn't reboot.  For Squeezebox2, it means that we're
	# reconnecting and there is an active data connection. In
	# both cases, we do the same thing:
	# If we were playing previously, either restart the track or
	# resume streaming at the bytes_received point. If we were
	# paused, then stop.

	if (!$reconnect) {

		if ($client->playmode() eq 'play') {

			# If bytes_received was sent and we're dealing 
			# with a seekable source, just resume streaming
			# else stop and restart.    

			if (!$bytes_received || $client->audioFilehandleIsSocket()) {

				Slim::Player::Source::playmode($client, "stop");
				$bytes_received = 0;
			}

			Slim::Player::Source::playmode($client, "play", $bytes_received);

		} elsif ($client->playmode() eq 'pause') {

			Slim::Player::Source::playmode($client, "stop");

		} elsif ($client->playmode() eq 'stop') {

			# Ensure that a new client is stopped, but only on sb2s
			if ( $client->isa('Slim::Player::Squeezebox2') ) {
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

	$client->update();	
	$client->display->visualizer(1) if ($client->display->isa('Slim::Display::Squeezebox2'));
}

sub connected { 
	my $client = shift;

	return ($client->tcpsock() && $client->tcpsock->connected()) ? 1 : 0;
}

sub model {
	return 'squeezebox';
}
sub modelName { 'Squeezebox' }

sub ticspersec {
	return 1000;
}

sub decoder {
	return 'mas35x9';
}

sub play {
	my $client = shift;
	my $params = shift;
	
	# Calculate the correct buffer threshold for remote URLs
	if ( Slim::Music::Info::isRemoteURL( $params->{url} ) ) {
		# begin playback once we have this much data in the decode buffer (in KB)
		$params->{bufferThreshold} = 20;
		
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $params->{url} );

		# If we know the bitrate of the stream, we instead buffer a certain number of seconds of audio
		if ( my $bitrate = Slim::Music::Info::getBitrate( $params->{url} ) ) {
			my $bufferSecs = $prefs->get('bufferSecs') || 3;
			$params->{bufferThreshold} = ( int($bitrate / 8) * $bufferSecs ) / 1000;
			
			# Max threshold is 255
			$params->{bufferThreshold} = 255 if $params->{bufferThreshold} > 255;
		}
		
		# Check with the protocol handler on whether or not to show buffering messages
		my $showBuffering = 1;
		
		if ( $handler && $handler->can('showBuffering') ) {
			$showBuffering = $handler->showBuffering( $client, $params->{url} );
		}
		
		# Set a timer for feedback during buffering
		if ( $showBuffering ) {
			$client->bufferStarted( Time::HiRes::time() ); # track when we started buffering
			Slim::Utils::Timers::killTimers( $client, \&buffering );
			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time() + 0.125,
				\&buffering,
				$params->{bufferThreshold} * 1024
			);
		}
	}

	$client->stream('s', $params);

	# make sure volume is set, without changing temp setting
	$client->volume($client->volume(), defined($client->tempVolume()));

	$client->lastSong($params->{url});

	return 1;
}

#
# tell the client to unpause the decoder
#
sub resume {
	my $client = shift;
	
	Slim::Utils::Timers::killTimers($client, \&buffering);

	$client->stream('u');
	$client->SUPER::resume();
	return 1;
}

sub startAt {
	my ($client, $at) = @_;

	Slim::Utils::Timers::killTimers($client, \&buffering);
	Slim::Utils::Timers::setHighTimer(
			$client,
			$at - $client->packetLatency(),
			\&_unpauseAfterInterval
		);
	return 1;
}

#
# pause
#
sub pause {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&buffering);

	$client->stream('p');
	$client->playPoint(undef);
	$client->SUPER::pause();
	return 1;
}

sub pauseForInterval {
	my $client   = shift;
	my $interval = shift;

	# TODO - show resyncing message briefly
	# TODO - adjust interval for SB1 internal decode buffer
	
	$client->playPoint(undef);
	$client->stream('p');
	Slim::Utils::Timers::setHighTimer(
				$client,
				Time::HiRes::time() + $interval - 0.005,
				\&_unpauseAfterInterval
			);
	return 1;
}

sub _unpauseAfterInterval {
	my $client = shift;
	$client->stream('u');
	$client->playPoint(undef);
	return 1;
}

sub stop {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&buffering);

	$client->stream('q');
	$client->playPoint(undef);
	Slim::Networking::Slimproto::stop($client);
	# disassociate the streaming socket to the client from the client.  HTTP.pm will close the socket on the next select.
	$client->streamingsocket(undef);
	$client->lastSong(undef);
}

sub flush {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&buffering);

	$client->stream('f');
	$client->SUPER::flush();
	return 1;
}

sub buffering {
	my ( $client, $threshold ) = @_;
	
	my $log = logger('player.source');
	
	# If the track has started, stop displaying buffering status
	# currentPlaylistChangeTime is set to time() after a track start event
	if ( $client->currentPlaylistChangeTime() > $client->bufferStarted() ) {
		$client->update();
		return;
	}

	$client->requestStatus();
	
	my $fullness = $client->bufferFullness();
	
	$log->info("Buffering... $fullness / $threshold");
	
	# Bug 1827, display better buffering feedback while we wait for data
	my $percent = sprintf "%d", ( $fullness / $threshold ) * 100;
	
	my $stillBuffering = ( $percent < 100 ) ? 1 : 0;
	
	my ( $line1, $line2 );
	
	if ( $percent == 0 ) {
		my $string = 'CONNECTING_FOR';
		$line1 = $client->string('NOW_PLAYING') . ' (' . $client->string($string) . ')';
		
		if ( $client->linesPerScreen() == 1 ) {
			$line2 = $client->string($string);
		}
	}
	else {
		my $status;
		
		# When synced, a player may have to wait longer than the buffering time
		if ( Slim::Player::Sync::isSynced($client) && $percent >= 100 ) {
			$status = $client->string('WAITING_TO_SYNC');
			$stillBuffering = 1;
		}
		else {
			if ( $percent > 100 ) {
				$percent = 99;
			}
			
			my $string = 'BUFFERING';
			$status = $client->string($string) . ' ' . $percent . '%';
		}
		
		$line1 = $client->string('NOW_PLAYING') . ' (' . $status . ')';
		
		# Display only buffering text in large text mode
		if ( $client->linesPerScreen() == 1 ) {
			$line2 = $status;
		}
	}
	
	# Find the track title
	if ( $client->linesPerScreen() > 1 ) {
		my $url = Slim::Player::Playlist::url( $client, Slim::Player::Source::streamingSongIndex($client) );
		$line2  = Slim::Music::Info::title( $url );
	}
	
	# Only show buffering status if no user activity on player or we're on the Now Playing screen
	my $nowPlaying = Slim::Buttons::Playlist::showingNowPlaying($client);
	my $lastIR     = Slim::Hardware::IR::lastIRTime($client) || 0;
	
	if ( !$client->display->sbName() && ($nowPlaying || $lastIR < $client->bufferStarted()) ) {

		$client->showBriefly( {
			line => [ $line1, $line2 ], 
			jive => undef, 
			cli  => undef
		}, 0.5 );
		
		# Call again unless we've reached the threshold
		if ( $stillBuffering ) {
			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time() + 0.400, # was .125 but too fast sometimes in wireless settings
				\&buffering,
				$threshold,
			);
		}
	}
}

#
# playout - play out what's in the buffer
#
sub playout {
	my $client = shift;
	return 1;
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

sub hasDigitalOut {
	return 1;
}

# if an update is required, return the version of the appropriate upgrade image
#
sub needsUpgrade {
	my $client = shift;

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
			return 0;
		}
	}

	if ($to == $from) {

		$log->info("$model firmware is up-to-date, v. $from");
		return 0;
	}

	# skip upgrade if file doesn't exist
	my $file = shift || catdir( Slim::Utils::OSDetect::dirsFor('Firmware'), $model . "_$to.bin" );

	unless (-r $file && -s $file) {

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
				'line' => [ $client->string('PLAYER_NEEDS_UPGRADE_1'), $client->string('PLAYER_NEEDS_UPGRADE_2') ],
				'fonts' => { 
					'graphic-320x32' => 'light',
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

	# place in block mode so that brightness key is now ignored
	$client->block( {
		'line'  => [ $client->string('UPDATING_FIRMWARE_' . uc($client->model())) ],
		'fonts' => { 
			'graphic-320x32' => 'light',
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

				'line'  => [ $client->string('UPDATING_FIRMWARE_' . uc($client->model())),
					 $client->symbols($client->progressBar($client->displayWidth(), $totalbytesread/$size)) ],

				'fonts' => { 
					'graphic-320x32' => 'light',
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

# the old way: connect to 31337 and dump the file
sub upgradeFirmware_SDK4 {
	my ($client, $filename) = @_;

	use bytes;

	my $ip;

	if (ref $client ) {

		$ip = $client->ip;
		$prefs->client($client)->set('powerOnBrightness', 4);
		$prefs->client($client)->set('powerOffBrightness', 1);
		$client->brightness($prefs->client($client)->get($client->power() ? 'powerOnBrightness' : 'powerOffBrightness'));

	} else {

		$ip = $client;
	}

	my $port    = 31337;  # upgrade port
	my $iaddr   = inet_aton($ip) || return("Bad IP address: $ip\n");
	my $paddr   = sockaddr_in($port, $iaddr);
	my $proto   = getprotobyname('tcp');

	socket(SOCK, PF_INET, SOCK_STREAM, $proto) || return("Couldn't open socket: $!\n");
	binmode SOCK;

	connect(SOCK, $paddr) || return("Connect failed $!\n");
	
	open FS, $filename || return("can't open $filename");
	binmode FS;
	
	my $size = -s $filename;	
	my $log  = logger('player.firmware');

	$log->info("Updating firmware: Sending $size bytes");
	
	my $bytesread      = 0;
	my $totalbytesread = 0;

	while ($bytesread = read(FS, my $buf, 256)) {

		syswrite(SOCK, $buf);

		$totalbytesread += $bytesread;

		$log->info("Updating firmware: $totalbytesread / $size");
	}
	
	$log->info("Firmware updated successfully.");

	close (SOCK) || return("Couldn't close socket to player.");

	return undef; 
}

sub upgradeFirmware {
	my $client = shift;

	my $to_version;

	if (ref $client ) {
		$to_version = $client->needsUpgrade();
	} else {
		# for the "upgrade by ip address" web form:
		$to_version = 10;
	}

	# if no upgrade path is given, then "upgrade" the client to itself.
	$to_version = $client->revision unless $to_version;

	my $file = catdir( Slim::Utils::OSDetect::dirsFor('Firmware'), "squeezebox_$to_version.bin" );
	my $log  = logger('player.firmware');

	if (!-f $file) {

		logWarning("File does not exist: $file");

		return 0;
	}

	my $err;

	if ((!ref $client) || ($client->revision <= 10)) {

		$log->info("Using old update mechanism");

		# not calling as a client method, because it might just be an
		# IP address, if triggered from the web page.
		$err = upgradeFirmware_SDK4($client, $file);

	} else {

		$log->info("Using new update mechanism");

		$err = $client->upgradeFirmware_SDK5($file);
	}

	if (defined($err)) {

		logWarning("Upgrade failed: $err");

	} else {

		$client->forgetClient();
	}
}

# in order of preference based on whether we're connected via wired or wireless...
sub formats {
	my $client = shift;
	
	return qw(aif wav mp3);
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
sub stream {
	my ($client, $command, $params) = @_;

	my $log    = logger('network.protocol.slimproto');
	my $format = $params->{'format'};

	if ($client->opened()) {

		if ( $log->is_info ) {
			$log->info(sprintf("stream called: $command paused: %s format: %s url: %s",
				($params->{'paused'} || 'undef'), ($format || 'undef'), ($params->{'url'} || 'undef')
			));
		}

		$log->debug( sub { bt(1) } );

		my $autostart = 1;

		# autostart off when pausing or stopping, otherwise 75%
		if ($params->{'paused'} || $command =~ /^[pq]$/) {
			$autostart = 0;
		}

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

		my $handler;
		my $server_url = $client->canDirectStream($params->{'url'});

		if ($server_url) {

			$handler = Slim::Player::ProtocolHandlers->handlerForURL($server_url);

			# use getFormatForURL only if the format is not already given
			# This method is bad because it only looks at the URL suffix and can cause
			# (for example) Ogg HTTP streams to be played using the mp3 decoder!
			if ( !$format && $handler->can("getFormatForURL") ) {
				$format = $handler->getFormatForURL($server_url, $format);
			}
		}
		
		if ( !$format && $command eq 's' ) {

			logBacktrace("*** stream('s') called with no format, defaulting to mp3 decoder, url: $params->{'url'}");
		}

		$format ||= 'mp3';

		if ($format eq 'wav') {

			$formatbyte      = 'p';
			$pcmsamplesize   = 1;
			$pcmsamplerate   = 3;
			$pcmendian       = 1;
			$pcmchannels     = 2;
			$outputThreshold = 0;

			if ($params->{url}) {

				my $track = Slim::Schema->rs('Track')->objectForUrl({
					'url' => $params->{'url'},
		       		});

				$pcmsamplesize = $client->pcm_sample_sizes($track);
				$pcmsamplerate = $client->pcm_sample_rates($track);
				$pcmchannels = $track->channels() || '2';
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

			if ($params->{url}) {

				my $track = Slim::Schema->rs('Track')->objectForUrl({
					'url' => $params->{url},
		       		});

				$pcmsamplesize = $client->pcm_sample_sizes($track);
				$pcmsamplerate = $client->pcm_sample_rates($track);
				$pcmchannels = $track->channels() || '2';
			 }

		} elsif ($format eq 'flc') {

			$formatbyte      = 'f';
			$pcmsamplesize   = '?';
			$pcmsamplerate   = '?';
			$pcmendian       = '?';
			$pcmchannels     = '?';
			$outputThreshold = 0;

			# Threshold the output buffer for high sample-rate flac.
			if ($params->{url}) {

				my $track = Slim::Schema->rs('Track')->objectForUrl({
					'url' => $params->{url},
				});

				if ($track && $track->samplerate() && $track->samplerate() >= 88200) {
			    		$outputThreshold = 20;
				}
			}

		} elsif ( $format =~ /(?:wma|asx)/ ) {

			$formatbyte = 'w';

			# Commandeer the unused pcmsamplesize field
			# to indicate whether the data coming in is
			# going to have the mms/http chunking headers.
			if ($server_url) {

				if ( $server_url =~ /\.rad$/ ) {
					# Rhapsody Direct
					$pcmsamplesize = 3;
				}
				elsif ( $server_url =~ /^rhap:/ ) {
					# Rhapsody UPnP
					$pcmsamplesize = 2;
				}
				else {
					$pcmsamplesize = 1;
				}
				
				# Bug 5631
				# Check WMA metadata to see if this remote stream is a live stream
				# or a normal file.  Normal file requires pcmsamplesize = 0 whereas
				# live streams require pcmsamplesize = 1
				my $mmsURL = $server_url;
				$mmsURL    =~ s/^http/mms/;
				my $cache = Slim::Utils::Cache->new;
				my $wma   = $cache->get( 'wma_metadata_'  . $mmsURL );
				
				if ( $wma ) {
					my $flags = $wma->info('flags');
					if ( $flags->{broadcast} == 0 ) {
						# A normal file
						$pcmsamplesize = 0;
					}
				}

			} else {

				$pcmsamplesize = 0;
			}

			$pcmsamplerate   = chr(1);
			$pcmendian       = '?';
			$pcmchannels     = '?';
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
			
			# XXX: The use of mp3 as default has been known to cause the mp3 decoder to be used for
			# other audio types, resulting in static. 
			if ( $format ne 'mp3' ) {

				logBacktrace("*** mp3 decoder used for format: $format, url: $params->{'url'}");
			}
		}
		
		my $request_string = '';
		my ($server_port, $server_ip);

		if ($command eq 's') {
			
			# When streaming a new song, we reset the buffer fullness value so buffering()
			# doesn't get an outdated fullness result
			Slim::Networking::Slimproto::fullness( $client, 0 );
			
			if ($server_url) {

				# Logger for direct streaming
				my $log = logger('player.streaming.direct');

				$log->info("This player supports direct streaming for $params->{'url'} as $server_url, let's do it.");
		
				my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($server_url);
				
				# If a proxy server is set, change ip/port
				my $proxy = $prefs->get('webproxy');
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

				$request_string = $handler->requestString($client, $server_url, undef, 1);  
				$autostart += 2; # will be 2 for direct streaming with no autostart, or 3 for direct with autostart

				if (!$server_port || !$server_ip) {

					$log->info("Couldn't get an IP and Port for direct stream ($server_ip:$server_port), failing.");

					$client->failedDirectStream();
					Slim::Networking::Slimproto::stop($client);
					return;

				} else {

					$log->info("setting up direct stream ($server_ip:$server_port) autostart: $autostart.");
					$log->info("request string: $request_string");

					$client->directURL($params->{url});
				}
				
				if ( $format =~ /(?:wma|asx)/ ) {
					# Bug 3981, For WMA streams, we send the streamid using the pcmsamplerate field
					# so the firmware knows which stream to play
					if ( my ($streamNum) = $request_string =~ /ffff:(\d+):0/ ) {
						$pcmsamplerate = chr($streamNum);
					}
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
			}
		}

		# If we're sending an 's' command but got no request string, don't send it
		# This is used when syncing Rhapsody radio stations so slaves don't request the radio playlist
		if ( $command eq 's' && !$request_string ) {
			return;
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
		
		# If looping, reduce the threshold, some of our sounds are really short
		if ( $params->{loop} ) {
			$bufferThreshold = 10;
		}

		$log->info("flags: $flags");

		my $frame = pack 'aaaaaaaCCCaCCCNnN', (
			$command,	# command
			$autostart,
			$formatbyte,
			$pcmsamplesize,
			$pcmsamplerate,
			$pcmchannels,
			$pcmendian,
			$bufferThreshold,
			0,		# s/pdif auto
			$prefs->client($client)->get('transitionDuration') || 0,
			$prefs->client($client)->get('transitionType') || 0,
			$flags,		# flags	     
			$outputThreshold,
			0,		# reserved
			$replayGain,	
			$server_port || $prefs->get('httpport'),  # use slim server's IP
			$server_ip || 0,
		);
	
		assert(length($frame) == 24);
	
		$frame .= $request_string;

		if ( $log->is_info ) {
			$log->info("sending strm frame of length: " . length($frame) . " request string: [$request_string]");
		}

		$client->sendFrame('strm', \$frame);

		if ($client->pitch() != 100 && $command eq 's') {
			$client->sendPitch($client->pitch());
		}
	}
}

sub pcm_sample_sizes {
	my $client = shift;
	my $track = shift;

	my %pcm_sample_sizes = ( 8 => '0',
				 16 => '1',
				 24 => '2',
				 32 => '4',
				 );

	my $size = $pcm_sample_sizes{$track->samplesize()};

	return defined $size ? $size : '1';
}

sub pcm_sample_rates {
	my $client = shift;
	my $track = shift;

    	my %pcm_sample_rates = ( 11000 => '0',				 
				 22000 => '1',				 
				 32000 => '2',
				 44100 => '3',
				 48000 => '4',
				 );

	my $rate = $pcm_sample_rates{$track->samplerate()};

	return defined $rate ? $rate : '3';
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

	logger('network.protocol.slimproto')->debug("sending squeezebox frame: $type, length: $len");

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

		if ( logger('network.protocol.slimproto')->is_debug ) {
			logger('network.protocol.slimproto')->debug("sending " . length($data) . " bytes");
		}

		$client->sendFrame('i2cc', \$data);
	}
}

# set the mas35x9 pitch rate as a percentage of the normal rate, where 100% is 100.
sub pitch {
	my $client = shift;
	my $newpitch = shift;
	
	my $pitch = $client->SUPER::pitch($newpitch, @_) || $newpitch;

	if (defined($newpitch)) {
		$client->sendPitch($pitch);
	}

	return $pitch;
}

sub sendPitch {
	my $client = shift;
	my $pitch = shift;
	
	my $freq = int(18432 / ($pitch / 100));
	my $freqHex = sprintf('%05X', $freq);

	# This only works for mp3 - only change pitch for mp3 format
	if ($client->masterOrSelf->streamformat() && ($client->masterOrSelf->streamformat() eq 'mp3')) {

		$client->i2c(
			Slim::Hardware::mas35x9::masWrite('OfreqControl', $freqHex).
				Slim::Hardware::mas35x9::masWrite('OutClkConfig', '00001').
				Slim::Hardware::mas35x9::masWrite('IOControlMain', '00015')     # MP3
		);

		logger('player')->debug("Pitch frequency set to $freq ($freqHex)");
	}
}
	
sub maxPitch {
	return 110;
}

sub minPitch {
	return 80;
}

sub volume {
	my $client = shift;
	my $newvolume = shift;

	my $volume = $client->SUPER::volume($newvolume, @_);

	if (defined($newvolume)) {
		# really the only way to make everyone happy will be use a combination of digital and analog volume controls as the 
		# default, but then have knobs so you can tune it for max headphone power, lowest noise at low volume, 
		# fixed/variable s/pdif, etc.
	
		if ($prefs->client($client)->get('digitalVolumeControl')) {
			# here's one way to do it: adjust digital gains, leave fixed 3db boost on the main volume control
			# this does achieve good analog output voltage (important for headphone power) but is not optimal
			# for low volume levels. If only the analog outputs are being used, and digital gain is not required, then 
			# use the other method.
			#
			# When the main volume control is set to +3db (0x7600), there is no clipping at the analog outputs 
			# at max volume, for the loudest 1KHz sine wave I could record.
			#
			# At +12db, the clipping level is around 23/40 (on our thermometer bar).
			#
			# The higher the analog gain is set, the closer it can "match" (3v pk-pk) the max S/PDIF level. 
			# However, at any more than +3db it starts to get noisy, so +3db is the max we should use without 
			# some clever tricks to combine the two gain controls.
			#
	
			my $level = sprintf('%05X', 0x80000 * (($volume / $client->maxVolume)**2));

			$client->i2c(
				Slim::Hardware::mas35x9::masWrite('out_LL', $level) .
				Slim::Hardware::mas35x9::masWrite('out_RR', $level) .
				Slim::Hardware::mas35x9::masWrite('VOLUME', '7600')
			);
	
		} else {

			# or: leave the digital controls always at 0db and vary the main volume:
			# much better for the analog outputs, but this does force the S/PDIF level to be fixed.
			my $level = sprintf('%02X00', 0x73 * ($volume / $client->maxVolume)**0.1);
	
			$client->i2c(
				Slim::Hardware::mas35x9::masWrite('out_LL',  '80000') .
				Slim::Hardware::mas35x9::masWrite('out_RR', '80000') .
				Slim::Hardware::mas35x9::masWrite('VOLUME', $level)
			);
		}
	}

	return $volume;
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

sub bass {
	my $client = shift;
	my $newbass = shift;

	my $bass = $client->SUPER::bass($newbass);
	$client->i2c( Slim::Hardware::mas35x9::masWrite('BASS', Slim::Hardware::mas35x9::getToneCode($bass,'bass'))) if (defined($newbass));	

	return $bass;
}

sub treble {
	my $client = shift;
	my $newtreble = shift;

	my $treble = $client->SUPER::treble($newtreble);
	$client->i2c( Slim::Hardware::mas35x9::masWrite('TREBLE', Slim::Hardware::mas35x9::getToneCode($treble,'treble'))) if (defined($newtreble));	

	return $treble;
}

sub requestStatus {
	shift->sendFrame('i2cc');
}

1;
