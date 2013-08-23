package Slim::Player::SqueezePlay;

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
use vars qw(@ISA);

use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $prefs = preferences('server');

my $log = logger('network.protocol.slimproto');

BEGIN {
	if ( main::SLIM_SERVICE ) {
		require SDI::Service::Player::SqueezeNetworkClient;
		push @ISA, qw(SDI::Service::Player::SqueezeNetworkClient);
	}
	else {
		require Slim::Player::Squeezebox2;
		push @ISA, qw(Slim::Player::Squeezebox2);
	}
}

{
	
	__PACKAGE__->mk_accessor('rw', qw(
		_model modelName
		myFormats
		maxSupportedSamplerate
		accuratePlayPoints
		firmware
		canDecodeRhapsody
		canDecodeRtmp
		hasDigitalOut
		hasPreAmp
		hasDisableDac
		spDirectHandlers
		proxyAddress
	));
}

sub new {
	my $class = shift;

	my $client = $class->SUPER::new(@_);
	
	$client->init_accessor(
		_model                  => 'squeezeplay',
		modelName               => 'SqueezePlay',
		myFormats               => [qw(ogg flc aif pcm mp3)],	# in order of preference
		maxSupportedSamplerate  => 48000,
		accuratePlayPoints      => 0,
		firmware                => 0,
		canDecodeRhapsody       => 0,
		canDecodeRtmp           => 0,
		hasDigitalOut           => 0,
		hasPreAmp               => 0,
		hasDisableDac           => 0,
		spDirectHandlers        => undef,
		proxyAddress            => undef,
	);

	return $client;
}

# model=squeezeplay,modelName=SqueezePlay,ogg,flc,pcm,mp3,tone,MaxSampleRate=96000

my %CapabilitiesMap = (
	Model                   => '_model',
	ModelName               => 'modelName',
	MaxSampleRate           => 'maxSupportedSamplerate',
	AccuratePlayPoints      => 'accuratePlayPoints',
	Firmware                => 'firmware',
	Rhap                    => 'canDecodeRhapsody',
	Rtmp                    => 'canDecodeRtmp',
	HasDigitalOut           => 'hasDigitalOut',
	HasPreAmp               => 'hasPreAmp',
	HasDisableDac           => 'hasDisableDac',
	SyncgroupID             => undef,
	Spdirect                => 'spDirectHandlers',
	Proxy                   => 'proxyAddress',

	# deprecated
	model                   => '_model',
	modelName               => 'modelName',
);

sub model {
	return shift->_model;
}

# This will return the full version + revision, i.e. 7.5.0 r8265
sub revision {
	return shift->firmware;
}

# This returns only the integer revision, i.e. 8265
sub revisionNumber {
	my ($num) = shift->firmware =~ /r(\d+)/;
	return $num;
}

sub needsUpgrade {}

sub init {
	my $client = shift;
	my ($model, $capabilities) = @_;
	
	$client->updateCapabilities($capabilities);

	$client->sequenceNumber(0);
	
	# Do this at end so that any resync that happens has the capabilities already set
	$client->SUPER::init(@_);
}


sub reconnect {
	my ($client, $paddr, $revision, $tcpsock, $reconnect, $bytes_received, $syncgroupid, $capabilities) = @_;
	
	$client->updateCapabilities($capabilities);
	
	$client->SUPER::reconnect($paddr, $revision, $tcpsock, $reconnect, $bytes_received, $syncgroupid);
}

sub updateCapabilities {
	my ($client, $capabilities) = @_; 
	
	if ($client && $capabilities) {
		
		# if we have capabilities then all CODECs must be declared that way
		my @formats;
		
		for my $cap (split(/,/, $capabilities)) {
			if ($cap =~ /^[a-z][a-z0-9]{1,4}$/) {
				push(@formats, $cap);
			} else {
				my $value;
				my $vcap;
				if ((($vcap, $value) = split(/=/, $cap)) && defined $value) {
					$cap = $vcap;
				} else {
					$value = 1;
				}
				
				if (defined($CapabilitiesMap{$cap})) {
					my $f = $CapabilitiesMap{$cap};
					$client->$f($value);
				
				} elsif (!exists($CapabilitiesMap{$cap})) {
					
					# It could be possible to have a completely generic mechanism here
					# but I have not done that for the moment
					$log->warn("unknown capability: $cap=$value, ignored");
				}
			}
		}
		
		main::INFOLOG && $log->is_info && $log->info('formats: ', join(',', @formats));
		$client->myFormats([@formats]);
	}
}

##
# Copy of Boom curve
# Special Volume control for Boom.
#
# Boom is an oddball because it requires extremes in volume adjustment, from
# dead-of-night-time listening to shower time.
# Additionally, we want 50% volume to be reasonable
#
# So....  A total dynamic range of 74dB over 100 steps is okay, the problem is how to
# distribute those steps.  When distributed evenly, center volume is way too quiet.
# So, This algorithm moves what would be 50% (i.e. -76*.5=38dB) and moves it to the 25%
# position.
#
# This is simply a mapping function from 0-100, with 2 straight lines with different slopes.
#
sub getVolumeParameters
{
	my $params =
	{
		totalVolumeRange => -74,       # dB
		stepPoint        => 25,        # Number of steps, up from the bottom, where a 2nd volume ramp kicks in.
		stepFraction     => .5,        # fraction of totalVolumeRange where alternate volume ramp kicks in.
	};
	return $params;
}

sub hasIR() { return 0; }

sub formats {
	return @{shift->myFormats};
}

sub pcm_sample_rates {
	my $client = shift;
	my $track = shift;

	# extend rate lookup table to allow for up to 384k playback with 3rd party kernels and squeezeplay desktop
	# note: higher rates only used if supported by MaxSampleRate returned by player
	my %pcm_sample_rates = (
		  8000 => '5',
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
		176400 => ';',
		192000 => '<',
		352800 => '=',
		384000 => '>',
	);
	
	my $rate = $pcm_sample_rates{$track->samplerate()};
	
	return defined $rate ? $rate : '3';
}

sub fade_volume {
	my ($client, $fade, $callback, $callbackargs) = @_;

	if (abs($fade) > 1 ) {
		# for long fades do standard behavior so that sleep/alarm work
		$client->SUPER::fade_volume($fade, $callback, $callbackargs);
	} else {
		#SP does local audio control for mute/pause/unpause so don't do fade in/out 
		my $vol = abs($prefs->client($client)->get("volume"));
		$vol = ($fade > 0) ? $vol : 0;
		$client->volume($vol, 1);
		if ($callback) {
			&{$callback}(@{$callbackargs});
		}

	}
}

# Need to use weighted play-point?
sub needsWeightedPlayPoint { !shift->accuratePlayPoints(); }

sub playPoint {
	my $client = shift;
	
	return $client->accuratePlayPoints()
		? $client->SUPER::playPoint(@_)
		: Slim::Player::Client::playPoint($client, @_);
}

sub skipAhead {
	my $client = shift;
	
	my $ret = $client->SUPER::skipAhead(@_);
	
	$client->playPoint(undef);
	
	return $ret;
}

sub forceReady {
	my $client = shift;
	
	$client->readyToStream(1);
}

1;

__END__
