package Slim::Plugin::Visualizer::Plugin;

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
use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;

my $VISUALIZER_NONE = 0;
my $VISUALIZER_VUMETER = 1;
my $VISUALIZER_SPECTRUM_ANALYZER = 2;
my $VISUALIZER_WAVEFORM = 3;

my $textontime = 5;
my $textofftime = 30;
my $initialtextofftime = 5;

my %client_context = ();

my %screensaver_info = ( 

# Parameters for the spectrum analyzer:
#   0 - Channels: stereo == 0, mono == 1
#   1 - Bandwidth: 0..22050Hz == 0, 0..11025Hz == 1
#   2 - Preemphasis in dB per KHz
# Left channel parameters:
#   3 - Position in pixels
#   4 - Width in pixels
#   5 - orientation: left to right == 0, right to left == 1
#   6 - Bar width in pixels
#   7 - Bar spacing in pixels
#   8 - Clipping: show all subbands == 0, clip higher subbands == 1
#   9 - Bar intensity (greyscale): 1-3
#   10 - Bar cap intensity (greyscale): 1-3
# Right channel parameters (not required for mono):
#   11-18 - same as left channel parameters

	'SCREENSAVER.visualizer_spectrum' => {
		name => 'VISUALIZER_SPECTRUM_ANALYZER',
		params => {
				'transporter' => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 320, 0, 4, 1, 1, 1, 3, 320, 320, 1, 4, 1, 1, 1, 3],
				'squeezebox2' => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 160, 0, 4, 1, 1, 1, 3, 160, 160, 1, 4, 1, 1, 1, 3],
				'boom'        => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 80,  0, 3, 1, 1, 1, 3,  81,  80, 1, 3, 1, 1, 1, 3],
			},
		showtext => 1,
		hidevisu => 0,
	},

# Parameters for the vumeter:
#   0 - Channels: stereo == 0, mono == 1
#   1 - Style: digital == 0, analog == 1
# Left channel parameters:
#   2 - Position in pixels
#   3 - Width in pixels
# Right channel parameters (not required for mono):
#   4-5 - same as left channel parameters

	'SCREENSAVER.visualizer_analog_vumeter' => {
		name => 'VISUALIZER_ANALOG_VUMETER',
		params => {
				'transporter' => [$VISUALIZER_VUMETER, 0, 1, 0 + 80, 160, 320 + 80, 160],
				'squeezebox2' => [$VISUALIZER_VUMETER, 0, 1, 0, 160, 160, 160],
				'boom'        => [$VISUALIZER_VUMETER, 1, 1, 0, 160],
			},
		showtext => 0,
		hidevisu => 1,
	},
	'SCREENSAVER.visualizer_digital_vumeter' => {
		name => 'VISUALIZER_DIGITAL_VUMETER',
		params => {
				'transporter' => [$VISUALIZER_VUMETER, 0, 0, 20, 280, 340, 280],
				'squeezebox2' => [$VISUALIZER_VUMETER, 0, 0, 20, 130, 170, 130],
				'boom'        => [$VISUALIZER_VUMETER, 0, 0, 10, 60, 90, 60],
			},
		showtext => 1,
		hidevisu => 1,
	},
	'screensaver' => {
		name => 'PLUGIN_SCREENSAVER_VISUALIZER_DEFAULT',
	}
);

our %screensaverFunctions = (
	'done' => sub  {
		my ($client ,$funct ,$functarg) = @_;

		Slim::Buttons::Common::popMode($client);
		$client->update();

		# pass along ir code to new mode if requested
		if (defined $functarg && $functarg eq 'passback') {
			Slim::Hardware::IR::resendButton($client);
		}
	},
);


sub getDisplayName {
	return 'PLUGIN_SCREENSAVER_VISUALIZER';
}

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();

	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.visualizer_spectrum',
		\%screensaverFunctions,
		\&setVisualizerMode,
		\&leaveVisualizerMode,
		'VISUALIZER_SPECTRUM_ANALYZER',
		'PLAY',
		\&valid,
	);

	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.visualizer_analog_vumeter',
		\%screensaverFunctions,
		\&setVisualizerMode,
		\&leaveVisualizerMode,
		'VISUALIZER_ANALOG_VUMETER',
		'PLAY',
		\&valid,
	);

	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.visualizer_digital_vumeter',
		\%screensaverFunctions,
		\&setVisualizerMode,
		\&leaveVisualizerMode,
		'VISUALIZER_DIGITAL_VUMETER',
		'PLAY',
		\&valid,
	);
}

sub valid { shift->isa('Slim::Player::Squeezebox2') }
	

##################################################
### Screensaver display mode
##################################################

sub screensaverLines {
	my $client = shift;

	if (!$client->display->isa( "Slim::Display::Squeezebox2")) {

		return {
			'line' => [
				$client->string('PLUGIN_SCREENSAVER_VISUALIZER'),
				$client->string('PLUGIN_SCREENSAVER_VISUALIZER_NEEDS_SQUEEZEBOX2')
			]
		};
	}

	if ($client->modeParam('showText')) {

		my $prefix = $client->display->isa('Slim::Display::Boom') ? '' : $client->string('NOW_PLAYING') . ': ';

		return {
			'screen1' => {
				'fonts' => { 'graphic-320x32' => 'high',  'graphic-160x32' => 'high' },
				'line' => [ '', $prefix . Slim::Music::Info::getCurrentTitle($client, Slim::Player::Playlist::url($client)) ]
			}
		};
	}

	return { 'screen1' => {} };
}

sub leaveVisualizerMode {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&_pushoff);
	Slim::Utils::Timers::killTimers($client, \&_pushon);
}

sub setVisualizerMode {
	my $client = shift;
	my $method = shift;

	my $mode = Slim::Buttons::Common::mode($client);
	my $paramsRef;

	if (ref($screensaver_info{$mode}->{params}) eq 'ARRAY') {

		$paramsRef = $screensaver_info{$mode}->{params};

	} else {

		if ($client->display->isa('Slim::Display::Transporter')) {

			$paramsRef = $screensaver_info{$mode}->{params}->{'transporter'};

		} elsif ($client->display->isa('Slim::Display::Boom')) {

			$paramsRef = $screensaver_info{$mode}->{params}->{'boom'};

		} elsif ($client->display->isa('Slim::Display::Squeezebox2')) {

			$paramsRef = $screensaver_info{$mode}->{params}->{'squeezebox2'};
		}
	}
	
	$client->modeParam('visu', $paramsRef);
	$client->modeParam('hidevisu', $screensaver_info{$mode}->{hidevisu});

	# visualiser uses screen 2 - blank it and turn off other screen two displays
	$client->update( { 'screen2' => {} } );
	$client->modeParam('screen2', 'visualizer');

	$client->lines(\&screensaverLines);

	# do it again at the next period
	if ($screensaver_info{$mode}->{showtext}) {

		Slim::Control::Request::subscribe(\&_showsongtransition, [['playlist'], ['newsong']]);

		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + $initialtextofftime,
			\&_pushon,
			$client,
		);
	}
}

sub _showsongtransition {
	my $request = shift;
	
	my $client = $request->client() || return;
	my $mode   = Slim::Buttons::Common::mode($client);

	if (!$mode || $mode !~ /^SCREENSAVER\.visualizer_/) {
		return;
	}

	if (!$screensaver_info{$mode}->{'showtext'}) {
		return;
	}
	
	_pushon($client);
}

sub _pushon {
	my $client = shift;
	
	Slim::Utils::Timers::killTimers($client, \&_pushoff);
	Slim::Utils::Timers::killTimers($client, \&_pushon);

	$client->modeParam('showText', 1);
		
	$client->pushLeft;

	# do it again at the next period
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + $textontime,
		\&_pushoff,
		$client
	);
}

sub _pushoff {
	my $client = shift;
	
	Slim::Utils::Timers::killTimers($client, \&_pushoff);
	Slim::Utils::Timers::killTimers($client, \&_pushon);
	
	$client->modeParam('showText', 0);

	$client->pushRight;

	# do it again at the next period
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + $textofftime,
		\&_pushon,
		$client
	);
}

sub shutdownPlugin {
	Slim::Control::Request::unsubscribe(\&_showsongtransition);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
