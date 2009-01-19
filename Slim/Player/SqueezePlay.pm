package Slim::Player::SqueezePlay;

# SqueezeCenter Copyright (c) 2001-2008 Logitech.
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

use Slim::Utils::Log;

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
	);

	return $client;
}

# model=squeezeplay,modelName=SqueezePlay,ogg,flc,pcm,mp3,tone,MaxSampleRate=96000

my %CapabilitiesMap = (
	Model                   => '_model',
	ModelName               => 'modelName',
	MaxSampleRate           => 'maxSupportedSamplerate',
	AccuratePlayPoints      => 'accuratePlayPoints',

	# deprecated
	model                   => '_model',
	modelName               => 'modelName',
);

sub model {
	return shift->_model;
}

sub init {
	my $client = shift;
	my ($model, $capabilities) = @_;
	
	if ($capabilities) {
		
		# if we have capabilities then all CODECs must be declared that way
		my @formats;
		
		for my $cap (split(/,/, $capabilities)) {
			if ($cap =~ /^[a-z][a-z0-9]{1,3}$/) {
				push(@formats, $cap);
			} else {
				my $value = 1;
				my $vcap;
				if (($vcap, $value) = split(/=/, $cap)) {
					$cap = $vcap;
				}
				
				if (defined($CapabilitiesMap{$cap})) {
					my $f = $CapabilitiesMap{$cap};
					$client->$f($value);
				
				} else {
					
					# It could be possible to have a completely generic mechanism here
					# but I have not does that for the moment
					$log->warn("unknown capability: $cap=$value, ignored");
				}
			}
		}
		
		$log->is_info && $log->info('formats: ', join(',', @formats));
		$client->myFormats([@formats]);
	}
	
	# Do this at end so that any resync that happens has the capabilities already set
	$client->SUPER::init(@_);
}

sub hasIR() { return 0; }

sub formats {
	return @{shift->myFormats};
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
1;

__END__
