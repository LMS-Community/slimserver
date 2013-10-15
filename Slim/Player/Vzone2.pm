package Slim::Player::Vzone2;

# $Id$

# Squeezebox Server Copyright 2001-2009 Logitech.
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
use base qw(Slim::Player::SqueezeSlave);



use File::Spec::Functions qw(:ALL);
use File::Temp;
use IO::Socket;
use JSON::XS::VersionOneAndTwo;
use LWP::Simple;
use MIME::Base64;
use Scalar::Util qw(blessed);

use Data::Dumper;

use Slim::Formats::Playlists;
use Slim::Player::Player;
use Slim::Player::ProtocolHandlers;
use Slim::Player::Protocols::HTTP;
use Slim::Player::Protocols::MMS;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;
use Slim::Utils::Prefs;

my $prefs = preferences('server');
my $featuresDB = preferences('vzone', '/tmp/');

my $log       = logger('network.protocol.slimproto');
my $prefslog  = logger('prefs');
my $synclog   = logger('player.sync');
my $testlog   = Slim::Utils::Log->addLogCategory( {
	category     => 'vzone.test',
	defaultLevel => 'INFO',
	description  => 'VZone2 testing logger',
} );

# overide from slimproto


our $defaultPrefs = {
	'transitionType'     => 0,
	'transitionDuration' => 10,
	'transitionSmart'    => 1,
	'replayGainMode'     => 0,
	'snLastSyncUp'       => -1,
	'snLastSyncDown'     => -1,

	# you must delete entries from server.pref for these to take effect

	'minSyncAdjust'      => 18, 

	# Vzone is about 60ms off of a SB2 to startup
	'startDelay'	     => 0,
	'playDelay'	     => 60,   
	'packetLatency'      => 2,

	# maxbitrate must be set or the server WILL default to 320 - see Prefs.pm
	'maxBitrate'         => 0,
};

our $player_features = {
	# from Vzone2.pm
	'maxBass'						=>  50,
	'minBass'						=>  50,
	'maxTreble'						=>  50,
	'minTreble'						=>  50,
	'maxPitch'						=> 100,
	'minPitch'						=> 100,
	'model'							=> 'Vzone2',
	'modelName'						=> 'Vzone', 
	'formats'						=> [ "aac", "ogg", "flc", "mp3" ],
	'canDirectStream'				=> undef,
	'canLoop'						=> 0,
	'pcm_sample_rates'				=> undef,
	'needsWeightedPlayPoint'		=> 1,
	# from SqueezeSlave.pm
	'hasIR'							=> 1,
	'hasPreAmp'						=> 1,
	'hasDigitalOut'					=> 0,
	'hasPowerControl'				=> 0,
	# from Squeezbox.pm
	'ticspersec'					=> 1000,
	# from Player.pm
	'reportsTrackStart'				=> 1,
	'isPlayer'						=> 1,
	'hasVolumeControl'				=> 1,
	# from Client.pm
	'maxTransitionDuration'			=> 0,
	'maxSupportedSamplerate'		=> 48000,
	'canDecodeRhapsody'				=> 0,
	'canImmediateCrossfade'			=> 0,
	'proxyAddress'					=> undef,
	'hidden'						=> 0,
	'hasScrolling'					=> 0,
};

sub initPrefs {
	my $client = shift;
	$testlog->info('init prefs for device with IP ['.$client->ip().']');

	$client->refreshPrefs();
	$client->SUPER::initPrefs();
}


sub reconnect {
	my $client = shift;
	$client->SUPER::reconnect(@_);

	$client->getPlayerSetting('playername');
	
	$client->refreshPrefs();
}

sub refreshPrefs {
	my $client = shift;
	
	my $clientPrefs = $prefs->client($client);
	my $prefsFromVzc = getPrefs($client);
	my $forcedPrefs;
	my $forcePref;

	$testlog->debug(Dumper($prefsFromVzc));

	if ($prefsFromVzc) {
		$testlog->info('init prefs from vzc');
		$testlog->debug('player_prefs' . Dumper($prefsFromVzc->{player_prefs_defaults}));
		$clientPrefs->init($prefsFromVzc->{player_prefs_defaults});
		if ($prefsFromVzc->{player_prefs_force}) {
			$testlog->debug("entering forced player_prefs section");
			$forcedPrefs = $prefsFromVzc->{player_prefs_force};
			foreach $forcePref (keys %{$forcedPrefs}) {
				$testlog->debug("forcing $forcePref to $forcedPrefs->{$forcePref}");
				$clientPrefs->set($forcePref, $forcedPrefs->{$forcePref});
			}
		}
		$testlog->debug('server_prefs' . Dumper($prefsFromVzc->{server_prefs_defaults}));
		$prefs->init($prefsFromVzc->{server_prefs_defaults});
		if ($prefsFromVzc->{server_prefs_force}) {
			$testlog->debug("entering forced server_prefs section");
			$forcedPrefs = $prefsFromVzc->{server_prefs_force};
			foreach $forcePref (keys %{$forcedPrefs}) {
				$testlog->debug("forcing $forcePref to $forcedPrefs->{$forcePref}");
				$prefs->set($forcePref, $forcedPrefs->{$forcePref});
			}
		}
		if ($prefsFromVzc->{player_features_defaults}) {
			$testlog->error("entering features section");
			$client->setFeatures($prefsFromVzc->{player_features_defaults});
		} else {
			$testlog->error("no features found");
		}
		
	} else {
		$testlog->info('init prefs from vzone2.pm defaults');
		$clientPrefs->init($defaultPrefs);
	}
	
}

sub maxBass { #50
	my $client = shift;
	my $m = $client->getFeature('maxBass');
	return $m;
};
sub minBass { #50
	my $client = shift;
	my $m = $client->getFeature('minBass');
	return $m;
};
sub maxTreble { #50
	my $client = shift;
	my $m = $client->getFeature('maxTreble');
	return $m;
};
sub minTreble { #50
	my $client = shift;
	my $m = $client->getFeature('minTreble');
	return $m;
};
sub maxPitch { #100
	my $client = shift;
	my $m = $client->getFeature('maxPitch');
	return $m;
};
sub minPitch { #100
	my $client = shift;
	my $m = $client->getFeature('minPitch');
	return $m;
};

sub model {
	my $client = shift;
	my $m = $client->getFeature('model');
	return $m;
}

sub modelName {
	my $client = shift;
	my $m = $client->getFeature('modelName');
	return $m;
}

sub formats {
	my $client = shift;
	my $m = $client->getFeature('formats');
	$testlog->debug('supported formats ['.Dumper($m).']');

	if ($client->revision == 2) {
		# VZONE2 Hardware Client Version 2 Only support flc pcm mp3
		return qw(flc mp3 pcm);
	} else {
		# VZONE2 Hardware Client Version 3 and Higher supported formats
		# should be specified by the player_features obtained
		return @$m;
	}
}


sub canDirectStream {
	#return undef;
	my $client = shift;
	my $m = $client->getFeature('canDirectStream');
	return $m;
}
	
sub canLoop {
	#return 0;
	my $client = shift;
	my $m = $client->getFeature('canLoop');
	return $m;
}

sub volume {
	my $client = shift;
	my $newvolume = shift;

	my $volume = $client->Slim::Player::Client::volume($newvolume, @_);
	
	if (defined($newvolume)) {
	
		my $preamp;
		my $oldGain;
		my $newGain;

		#VZONE2 and higher Hardware 
		$preamp = 0;
		$oldGain = $volume;
		$newGain = $newvolume;
		if ($newGain>100) {
			$newGain = 100;
		}
		if ($newGain<0) {
			$newGain = 0;
		}

		my $data = pack('NNCCNN', $oldGain, $oldGain, $prefs->client($client)->get('digitalVolumeControl'), $preamp, $newGain, $newGain);
		$client->sendFrame('audg', \$data);
	}
	return $volume;
}

sub pcm_sample_rates {
	my $client = shift;
	my $track = shift;

    	my %pcm_sample_rates = ( 8000 => '5',
				 11025 => '0',
				 12000 => '6',
				 22050 => '1',
				 24000 => '8',
				 32000 => '2',
				 44100 => '3',
				 48000 => '4',
				 16000 => '7',
				 88200 => ':',
				 96000 => '9',
				192000 => 'a',
				 );

	my $rate = $pcm_sample_rates{$track->samplerate()};

	return defined $rate ? $rate : '3';
}
# The following settings are sync'd between the player firmware and SqueezeCenter
our $pref_settings = {
	'playername' => {
		firmwareid => 0,
		pack => 'Z*',
	},
	# 'digitalOutputEncoding' => {
		# firmwareid => 1,
		# pack => 'C',
	# },
	# 'wordClockOutput' => {
		# firmwareid => 2,
		# pack => 'C',
	# },
	# 'powerOffDac' => { # (Transporter only)
		# firmwareid => 3,
		# pack => 'C',
	# },
	# 'disableDac' => { # (Squezebox2/3 only)
		# firmwareid => 4,
		# pack => 'C',
	# },
	# 'fxloopSource' => { # (Transporter only)
		# firmwareid => 5,
		# pack => 'C',
	# },
	# 'fxloopClock' => { # (Transporter only)
		# firmwareid => 6,
		# pack => 'C',
	# },
};

# NV: I think this is called when this file is run  - odd placement 

$prefs->setChange( sub { my ($pref, $val, $client) = @_; $client->setPlayerSetting($pref, $val); }, keys %{$pref_settings});



# Request a pref from the player firmware
sub getPlayerSetting {
	my $client = shift;
	my $pref   = shift;

	$prefslog->is_info && $prefslog->info("Getting pref: [$pref]");

	my $currpref = $pref_settings->{$pref};

	my $data = pack('C', $currpref->{firmwareid} || 0);
	$client->sendFrame('setd', \$data);
}

# Update a pref in the player firmware
sub setPlayerSetting {
	my $client = shift;
	my $pref   = shift;
	my $value  = shift;

	return unless defined $value;
	
	my $isInfo = $prefslog->is_info;

	$isInfo && $prefslog->info("Setting pref: [$pref] to [$value]");

	my $currpref = $pref_settings->{$pref};

	my $data = pack('C'.$currpref->{pack}, $currpref->{firmwareid}, $value);
	$client->sendFrame('setd', \$data);
		
		
	}

# Allow the firmware to update a pref in SqueezeCenter
sub playerSettingsFrame {
	my $client   = shift;
	my $data_ref = shift;


	
	my $isInfo = $prefslog->is_info;

	my $id = unpack('C', $$data_ref);

	while (my ($pref, $currpref) = each %$pref_settings) {

		if ($currpref->{'firmwareid'} != $id) {
			next;
		}

		my $value = (unpack('C'.$currpref->{pack}, $$data_ref))[1];

		if (length($value) == 0) {

			$value = undef;
		}

		$isInfo && $prefslog->info(sprintf("Pref [%s] = [%s]", $pref, (defined $value ? $value : 'undef')));

		if ( !defined $value ) {
			# Only send the value to the firmware if we actually have one
			$value = $prefs->client($client)->get($pref);
			if ( defined $value ) {
				$client->setPlayerSetting( $pref, $value );
			}
		}
		else {
			$value = Slim::Utils::Unicode::utf8on($value) if $pref eq 'playername'; 
			$prefs->client($client)->set( $pref, $value );
		}
	}
}

# Need to use weighted play-point
sub needsWeightedPlayPoint {	#1
	my $client = shift;
	my $m = $client->getFeature('needsWeightedPlayPoint');
	return $m;
}


# We are taking this directly from Squeezbox.pm file
# We need to allow "bufferThreshold" to be called even when isRemote() is 0.
#   Protocol handlers that want to force the bufferThreshold check, should implement 
#   a dummy method "forceBufferThreshold"
sub play {
	my $client = shift;
	my $params = shift;
	
	my $controller = $params->{'controller'};
	my $handler = $controller->songProtocolHandler();

	# Calculate the correct buffer threshold for remote URLs
	if ( $handler->isRemote() or $handler->can('forceBufferThreshold') ) {
		my $bufferSecs = $prefs->get('bufferSecs') || 3;
		if ( main::SLIM_SERVICE ) {
			# Per-client buffer secs pref on SN
			$bufferSecs = $prefs->client($client)->get('bufferSecs') || 3;
		}
			
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

sub playPoint {
	my $client = shift;

	my ($jiffies, $elapsedMilliseconds, $elapsedSeconds) = Slim::Networking::Slimproto::getPlayPointData($client);

	return unless $elapsedMilliseconds;

	my $statusTime = $client->jiffiesToTimestamp($jiffies);
	my $apparentStreamStartTime = $statusTime - ($elapsedMilliseconds / 1000);

	my $songElapsed = $elapsedMilliseconds / 1000;
	if ($songElapsed < $elapsedSeconds) {
		$songElapsed = $elapsedSeconds + ($elapsedMilliseconds % 1000) / 1000;
	}

	0 && logger('player.sync')->debug($client->id() . " playPoint: jiffies=$jiffies, epoch="
		. ($client->jiffiesEpoch) . ", statusTime=$statusTime, elapsedMilliseconds=$elapsedMilliseconds");

	return [$statusTime, $apparentStreamStartTime, $songElapsed];
}


sub statHandler {
	my ($client, $code, $jiffies, $error_code) = @_;
	
	if ($code eq 'STMc') {
		$client->streamStartTimestamp($jiffies);
	} else {
		return if ! defined($client->streamStartTimestamp());
	}
	
	
	if ($code eq 'STMd') {
		$client->readyToStream(1);
		$client->controller()->playerReadyToStream($client);
	} elsif ($code eq 'STMn') {
		$client->readyToStream(1);
		logError($client->id(). ": Decoder does not support file format, code $error_code");
		my $string = $error_code ? 'DECODE_ERROR_' . $error_code : 'PROBLEM_OPENING';
		$client->controller()->playerStreamingFailed($client, $string);
	} elsif ($code eq 'STMl') {
		$client->bufferReady(1);
		$client->controller()->playerBufferReady($client);
	} elsif ($code eq 'STMu') {
		$client->readyToStream(1);
		$client->controller()->playerStopped($client);
	} elsif ($code eq 'STMa') {
		$client->bufferReady(1);
	} elsif ($code eq 'STMc') {
		$client->readyToStream(0);
		$client->bufferReady(0);
		$client->connecting(1);	# reset in Slim::Networking::Slimproto::_http_response_handler() upon connection establishment
	} elsif ($code eq 'STMs') {
		$client->controller()->playerTrackStarted($client);
	} elsif ($code eq 'STMo') {
		$client->controller()->playerOutputUnderrun($client);
	} elsif ($code eq 'EoS') {
		$client->controller()->playerEndOfStream($client);
	} else {
		$client->controller->playerStatusHeartbeat($client);
	}	
	
}



sub startAt {
	my ($client, $at) = @_;
	
	main::DEBUGLOG && $synclog->is_debug && $synclog->debug( $client->id, ' startAt: ' . int(($at - $client->jiffiesEpoch()) * 1000) );

	$client->stream( 'u', { 'interval' => int(($at - $client->jiffiesEpoch()) * 1000) } );
	return 1;
}

sub resume {
	my ($client, $at) = @_;
	
	$client->stream('u', ($at ? { 'interval' => int(($at - $client->jiffiesEpoch()) * 1000) } : undef));
	$client->SUPER::resume();
	return 1;
}

sub pauseForInterval {
	my $client   = shift;
	my $interval = shift;

	$client->stream( 'p', { 'interval' => $interval } );
	return 1;
}

#### Overriding from SqueezeSlave.pm
sub hasIR {	#1
	my $client = shift;
	my $m = $client->getFeature('hasIR');
	return $m;
}

sub hasPreAmp {	#1
	my $client = shift;
	my $m = $client->getFeature('hasPreAmp');
	return $m;
}

sub hasDigitalOut {	#0
	my $client = shift;
	my $m = $client->getFeature('hasDigitalOut');
	return $m;
}

sub hasPowerControl {	#0
	my $client = shift;
	my $m = $client->getFeature('hasPowerControl');
	return $m;
}

#### Overriding from Squeezebox.pm
sub ticspersec {	#1000
	my $client = shift;
	my $m = $client->getFeature('ticspersec');
	return $m;
}

#### Overriding from Player.pm
sub reportsTrackStart {	#1
	my $client = shift;
	my $m = $client->getFeature('reportsTrackStart');
	return $m;
}

sub isPlayer {	#1
	my $client = shift;
	my $m = $client->getFeature('isPlayer');
	return $m;
}

sub hasVolumeControl {	#1
	my $client = shift;
	my $m = $client->getFeature('hasVolumeControl');
	return $m;
}

#### Overriding from Client.pm
sub maxTransitionDuration {	#0
	my $client = shift;
	my $m = $client->getFeature('maxTransitionDuration');
	return $m;
}

sub maxSupportedSamplerate {	#48000
	my $client = shift;
	my $m = $client->getFeature('maxSupportedSamplerate');
	return $m;
}

sub canDecodeRhapsody {	#0
	my $client = shift;
	my $m = $client->getFeature('maxTransitionDuration');
	return $m;
}

sub canImmediateCrossfade {	#0
	my $client = shift;
	my $m = $client->getFeature('canImmediateCrossfade');
	return $m;
}

sub proxyAddress {	#undef
	my $client = shift;
	my $m = $client->getFeature('proxyAddress');
	return $m;
}

sub hidden {	#0
	my $client = shift;
	my $m = $client->getFeature('hidden');
	return $m;
}

sub hasScrolling {	#0
	my $client = shift;
	my $m = $client->getFeature('hasScrolling');
	return $m;
}

#### Helpful methods to call a Vdevice's cgi interface

sub buildUrlForVzc {
	my ($clientIP, $command)  = @_;
	my $vzcURL = 'http://' . $clientIP . '/vzc/cgi?command=' . $command;
	return $vzcURL;
}

sub getVzcResponse {
	# args are: $clientIP, $command
	my $vzcURL = buildUrlForVzc(@_);
	$testlog->debug('vzcURL  [' . $vzcURL . ']' );
	my $content = get($vzcURL); # From LWP::Simple
	$testlog->debug('content ['.$content.']');
	return $content;
}

sub getModelName {
	my $client = shift;
	my $m = 'Vzone';
	if ($client->ip()) {
		eval {
			my $content = getVzcResponse($client->ip(), 'get_features');
			$m = decode_json($content)->{name};
		};
		if ($@) {
			$testlog->error('error getting model, returning [Vzone2-error]');
			$m = 'Vzone2-error';
		}
	}
	return $m;
}

sub getPrefs {
	my $client = shift;
	my $prefs;
	if ($client->ip()) {
		eval {
			my $content = getVzcResponse($client->ip(), 'service&s=utils&m=prefs');
			$prefs = decode_json($content)->{result};
		};
		if ($@) {
			$testlog->error('error getting prefs, returning [undef]');
			$prefs = undef;
		}
	}
	return $prefs;
}


sub getFeature {
	my $client = shift;
	my $feature = shift;

	my $clientFeatures = $featuresDB->client($client);
	$testlog->debug("get feature $feature");
	$testlog->debug("default value is [".$player_features->{$feature}."]");
	my $data = $clientFeatures->get($feature);
	if (!$data) {
		$data = $player_features->{$feature};
	}
	$testlog->debug("obtained data is [".$data."]");

	return $data;
}

sub setFeatures {
	my $client = shift;
	my $features = shift;
	$testlog->debug("setting features from vzc");
	my $clientFeatures = $featuresDB->client($client);
	foreach my $feat (keys %{$features}) {
		$testlog->debug("feat $feat, value ".$features->{$feat});
		$clientFeatures->set($feat, $features->{$feat});
	}
	$testlog->debug("done!");
}

1;

