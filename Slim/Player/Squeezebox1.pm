package Slim::Player::Squeezebox1;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

use strict;
use base qw(Slim::Player::Squeezebox);

use File::Spec::Functions qw(catdir);
use Socket;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

# Not actually referenced in this module but we need to ensure that it is loaded.
use Slim::Player::SB1SliMP3Sync;

my $prefs = preferences('server');


# We inherit new() completely from our parent class.

sub model {
	return 'squeezebox';
}

sub needsWeightedPlayPoint { 1 }

sub statHandler {
	my ($client, $code) = @_;

	if ($code eq 'STMl') {
		# Just rely on player fixed threshold
		$client->bufferReady(1);
		$client->controller()->playerBufferReady($client);
	} elsif ($code eq 'STMu') {
		if ($client->streamingsocket()) {
			if ($client->controller()->isStreaming()) {
				$client->controller()->playerOutputUnderrun($client);
				return;
			} else {
				# Finished playout
				Slim::Web::HTTP::forgetClient($client);
				# and fall
			}
		}
		$client->readyToStream(1);
		$client->controller()->playerStopped($client);

	} elsif ($code eq 'STMa') {
		$client->bufferReady(1);
		$client->controller()->playerTrackStarted($client);
	} elsif ($code eq 'STMc') {
		$client->readyToStream(0);
		$client->bufferReady(0);
	} elsif ($code eq 'EoS') {
		# SB1's don't do direct streaming so no need to handle player EoS
		# as will have signalled playerEndOfStream() when we got the last chunk.
	} else {
		if ( !$client->bufferReady() && $client->bytesReceivedOffset() 		# may need to signal track-start
			&& ($client->bytesReceived() - $client->bytesReceivedOffset() - $client->bufferFullness() > 0) )
		{
			$client->bufferReady(1);	# to stop multiple starts
			$client->controller()->playerTrackStarted($client);
		} else {
			$client->controller->playerStatusHeartbeat($client);
		}
	}
}

sub play {
	my $client = shift;

	if ($client->streamingsocket) {
		assert(!$client->isSynced(1));

		$client->bytesReceivedOffset($client->streamBytes());
		$client->bufferReady(0);
		return 1;
	} else {
		$client->bytesReceivedOffset(0);
		$client->streamBytes(0);
		return $client->SUPER::play(@_);
	}
}

sub nextChunk {
	my $client = $_[0];

	my $chunk = Slim::Player::Source::nextChunk(@_);

	if (defined($chunk) && length($$chunk) == 0) {
		# EndOfStream
		$client->controller()->playerEndOfStream($client);

		# Bug 10400 - need to tell the controller to get next track ready
		# We may not actually be prepared to stream the next track yet
		# but this will be checked when the controller calls isReadyToStream()
		$client->controller()->playerReadyToStream($client);

		if ($client->isSynced(1)) {
			return $chunk;	# playout
		} else {
			return undef;
		}
	}

	return $chunk;
}


# SB1 (this module) will only set $client->readyToStream true when it is really idle

sub isReadyToStream {
	my ($client, $song, $playingSong) = @_;

	return 1 if $client->readyToStream();

	return 0 if $client->isSynced(1);

	# Determine if we can gaplessly stream the next track (return 1) or have to restart the decoder (return 0)
	my $CSF = $client->streamformat();
	my $songTrack = $song->currentTrack;
	my $playingTrack = $playingSong && $playingSong->currentTrack;

	# Only allow gapless streaming if previous track's content-type matches the next track's content-type
	if ( $songTrack && $playingTrack && $playingTrack->content_type && $playingTrack->content_type eq $songTrack->content_type ) {
		# MP3 is OK even if at a different sample rate, etc
		return 1 if $CSF eq 'mp3';

		# Bug 15490, work out whether or not we can gaplessly stream PCM/AIFF. Assume that if
		# channels, samplesize and samplerate all match, we'll be fine.
		if ( $CSF eq 'pcm' || $CSF eq 'aif' ) {
			if ( $playingSong ) {
				if (   $playingTrack->channels && $playingTrack->channels == $songTrack->channels
					&& $playingTrack->samplesize && $playingTrack->samplesize == $songTrack->samplesize
					&& $playingTrack->samplerate && $playingTrack->samplerate == $songTrack->samplerate
				) {
					return 1;
				}
			}
		}
	}

	main::DEBUGLOG && logger('player')->debug("Restart decoder required");
	return 0;
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
	if (($client->master()->streamformat() || '') eq 'mp3') {

		$client->i2c(
			Slim::Hardware::mas35x9::masWrite('OfreqControl', $freqHex).
				Slim::Hardware::mas35x9::masWrite('OutClkConfig', '00001').
				Slim::Hardware::mas35x9::masWrite('IOControlMain', '00015')     # MP3
		);

		main::DEBUGLOG && logger('player')->debug("Pitch frequency set to $freq ($freqHex)");
	}
}

sub maxPitch {
	return 110;
}

sub minPitch {
	return 80;
}

sub decoder {
	return 'mas35x9';
}

# in order of preference based on whether we're connected via wired or wireless...
sub formats {
	my $client = shift;

	return qw(aif pcm mp3);
}

# periodic screen refresh
sub periodicScreenRefresh {
	my $client = shift;
	my $display = $client->display;

	$display->update() unless ($display->updateMode() || $display->scrollState() == 2 || $client->modeParam('modeUpdateInterval'));

	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1, \&periodicScreenRefresh);
}

sub pcm_sample_rates {
	my $client = shift;
	my $track = shift;

    	my %pcm_sample_rates = ( 11025 => '0',
				 22050 => '1',
				 32000 => '2',
				 44100 => '3',
				 48000 => '4',
				 );

	my $rate = $pcm_sample_rates{$track->samplerate()};

	return defined $rate ? $rate : '3';
}

sub requestStatus {
	shift->sendFrame('i2cc');
}

#
# tell the client to unpause the decoder
#
sub resume {
	my ($client, $at) = @_;

	if ($at) {
		Slim::Utils::Timers::setHighTimer(
			$client,
			$at - $client->packetLatency(),
			\&_unpauseAfterInterval
		);
	} else {
		$client->stream('u');
	}

	$client->SUPER::resume();
	return 1;
}

sub startAt {
	my ($client, $at) = @_;

	Slim::Utils::Timers::killTimers($client, \&_buffering);
	Slim::Utils::Timers::setHighTimer(
			$client,
			$at - $client->packetLatency(),
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

sub upgradeFirmware {
	my $client = shift;

	my $to_version;

	if (ref $client ) {
		$to_version = $client->needsUpgrade();
	} else {
		# for the "upgrade by ip address" web form:
		$to_version = 10;
		$client = Slim::Player::Client::getClient($client);
	}

	# if no upgrade path is given, then "upgrade" the client to itself.
	$to_version = $client->revision unless $to_version;

	my $file  = catdir( scalar Slim::Utils::OSDetect::dirsFor('Firmware'), "squeezebox_$to_version.bin" );
	my $file2 = catdir( scalar Slim::Utils::OSDetect::dirsFor('updates'), "squeezebox_$to_version.bin" );
	my $log   = logger('player.firmware');

	if (!-f $file && !-f $file2) {

		logWarning("File does not exist: $file");

		return 0;
	}

	if (-f $file2 && !-f $file) {
		$file = $file2;
	}

	$client->isUpgrading(1);

	# Notify about firmware upgrade starting
	Slim::Control::Request::notifyFromArray( $client, [ 'firmware_upgrade' ] );

	my $err;

	if ((!ref $client) || ($client->revision <= 10)) {

		main::INFOLOG && $log->info("Using old update mechanism");

		# not calling as a client method, because it might just be an
		# IP address, if triggered from the web page.
		$err = _upgradeFirmware_SDK4($client, $file);

	} else {

		main::INFOLOG && $log->info("Using new update mechanism");

		$err = $client->upgradeFirmware_SDK5($file);
	}

	if (defined($err)) {

		logWarning("Upgrade failed: $err");

	} else {

		$client->forgetClient();
	}
}

# the old way: connect to 31337 and dump the file
sub _upgradeFirmware_SDK4 {
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

	main::INFOLOG && $log->info("Updating firmware: Sending $size bytes");

	my $bytesread      = 0;
	my $totalbytesread = 0;

	while ($bytesread = read(FS, my $buf, 256)) {

		syswrite(SOCK, $buf);

		$totalbytesread += $bytesread;

		main::INFOLOG && $log->info("Updating firmware: $totalbytesread / $size");
	}

	main::INFOLOG && $log->info("Firmware updated successfully.");

	close (SOCK) || return("Couldn't close socket to player.");

	return undef;
}


1;
