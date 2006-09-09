# $Id: $

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

package Plugins::Visualizer;

use Slim::Player::Squeezebox2;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.0 $,10);

my $VISUALIZER_NONE = 0;
my $VISUALIZER_VUMETER = 1;
my $VISUALIZER_SPECTRUM_ANALYZER = 2;
my $VISUALIZER_WAVEFORM = 3;

my $textontime = 5;
my $textofftime = 30;
my $initialtextofftime = 5;

my %client_context = ();
my @visualizer_screensavers = ( 'SCREENSAVER.visualizer_spectrum', 
								'SCREENSAVER.visualizer_digital_vumeter', 
								'SCREENSAVER.visualizer_analog_vumeter' );
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
		name => 'PLUGIN_SCREENSAVER_VISUALIZER_SPECTRUM_ANALYZER',
		params => {
				'transporter' =>     [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 320, 0, 4, 1, 1, 1, 3, 320, 320, 1, 4, 1, 1, 1, 3],
				'squeezebox2' => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 160, 0, 4, 1, 1, 1, 3, 160, 160, 1, 4, 1, 1, 1, 3],
			},
		showtext => 1,
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
				'transporter' => [$VISUALIZER_VUMETER, 0, 1, 0 + 320, 160, 160 + 320, 160],
				'squeezebox2' => [$VISUALIZER_VUMETER, 0, 1, 0, 160, 160, 160],
			},
		showtext => 0,
	},
	'SCREENSAVER.visualizer_digital_vumeter' => {
		name => 'VISUALIZER_DIGITAL_VUMETER',
		params => {
				'transporter' =>     [$VISUALIZER_VUMETER, 0, 0, 20, 280, 340, 280],
				'squeezebox2' => [$VISUALIZER_VUMETER, 0, 0, 20, 130, 170, 130],
			},
		showtext => 1,
	},
	'screensaver' => {
		name => 'PLUGIN_SCREENSAVER_VISUALIZER_DEFAULT',
	}
);

sub getDisplayName {
	return 'PLUGIN_SCREENSAVER_VISUALIZER';
}

sub enabled {
	return ($::VERSION ge '6.1');
}

sub strings { return '
PLUGIN_SCREENSAVER_VISUALIZER
	DE	Visualizer Bildschirmschoner
	EN	Visualizer Screensaver
	ES	Salvapantallas de Visualizador
	FI	Visualisointi ruudunsäästäjä
	FR	Ecran de veille Visualisation
	NL	Visualisatie schermbeveiliger

PLUGIN_SCREENSAVER_VISUALIZER_NEEDS_SQUEEZEBOX2
	DE	Benötigt Squeezebox2
	EN	Needs Squeezebox2
	ES	Requiere Squeezebox2
	FR	Squeezebox2 requise
	IT	Necessita Squeezebox2/3
	NL	Squeezebox2/3 nodig

PLUGIN_SCREENSAVER_VISUALIZER_PRESS_RIGHT_TO_CHOOSE
	DE	RECHTS drücken zum Aktivieren des Bildschirmschoners
	EN	Press -> to enable this screensaver
	ES	Presionar -> para activar este salvapantallas
	NL	Druk -> om deze schermbeveiliger te activeren

PLUGIN_SCREENSAVER_VISUALIZER_ENABLED
	CS	Spořič je nastaven
	DE	Bildschirmschoner aktiviert
	EN	This screensaver is enabled
	ES	Este salvapantallas está activo
	FI	Tämä ruudunsäästäjä on kytketty
	IT	Questo salvaschermo e\' abilitato
	NL	Deze schermbeveiliger is actief

PLUGIN_SCREENSAVER_VISUALIZER_DEFAULT
	CS	Výchozí spořič
	DE	Standard Bildschirmschoner
	EN	Default screenaver
	ES	Salvapantallas por defecto
	FR	Ecran de veille par défaut
	IT	Salvaschermo di default
	NL	Standaard schermbeveiliger
'};

##################################################
### Screensaver configuration mode
##################################################

our %configFunctions = (
	'up' => sub  {
		my $client = shift;
		my $newpos = Slim::Buttons::Common::scroll(
								$client,
								-1,
								scalar(@{$client_context{$client}->{list}}),
								$client_context{$client}->{position},
								);
		if ($client_context{$client}->{position} != $newpos) {
			$client_context{$client}->{position} = $newpos;
			$client->pushUp();
		}
	},
	'down' => sub  {
		my $client = shift;
		my $newpos = Slim::Buttons::Common::scroll(
								$client,
								1,
								scalar(@{$client_context{$client}->{list}}),
								$client_context{$client}->{position},
								);
		if ($client_context{$client}->{position} != $newpos) {
			$client_context{$client}->{position} = $newpos;
			$client->pushDown();
		}
	},
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;

		my $screensaver = $client_context{$client}->{list}->[$client_context{$client}->{position}];
		my $saver = Slim::Player::Source::playmode($client) eq 'play' ? 'screensaver' : 'idlesaver';
		
		if ($client->prefGet($saver) ne $screensaver) {
			$client->prefSet($saver,$screensaver);
		} else {
			$client->prefSet($saver,$Slim::Player::Player::defaultPrefs->{$saver});
		}
		$client->update();
	}
);

sub configLines {
	my $client = shift;
	
	my $saver = Slim::Player::Source::playmode($client) eq 'play' ? 'screensaver' : 'idlesaver';
	
	my $item = $client_context{$client}->{list}->[$client_context{$client}->{position}];

	$line1 = $client->string('PLUGIN_SCREENSAVER_VISUALIZER');
	$line2 = $client->string($screensaver_info{$item}->{name});
	my $overlay2 = Slim::Buttons::Common::checkBoxOverlay($client, $client->prefGet($saver) eq $item);

	return {
		'line'    => [ $line1, $line2 ],
		'overlay' => [ undef, $overlay2 ],
	};
}

sub getFunctions {
	return \%configFunctions;
}

sub setMode {
	my $client = shift;

	my $cursaver = $client->prefGet('screensaver');
	$client_context{$client}->{screensaver} = $cursaver;
	if (grep $_ eq $cursaver, @visualizer_screensavers) {
		$client_context{$client}->{list} = [ @visualizer_screensavers, 'screensaver' ];
	}
	else {
		$client_context{$client}->{list} = [ @visualizer_screensavers ];
	}
	unless (defined($client_context{$client}->{position}) &&
			$client_context{$client}->{position} < scalar(@{$client_context{$client}->{list}})) {
		$client_context{$client}->{position} = 0;
	}

	$client->lines(\&configLines);
}


##################################################
### Screensaver display mode
##################################################

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

sub screensaverLines {
	my $client = shift;
	if( $client->display->isa( "Slim::Display::Squeezebox2")) {
	}
	else {
		return {
			'line' => [ $client->string('PLUGIN_SCREENSAVER_VISUALIZER'),
						$client->string('PLUGIN_SCREENSAVER_VISUALIZER_NEEDS_SQUEEZEBOX2') ]
		};
	}
}

sub screenSaver {
	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.visualizer_spectrum',
		\%screensaverFunctions,
		\&setVisualizerMode,
		\&leaveVisualizerMode,
		'VISUALIZER_SPECTRUM_ANALYZER',
	);
	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.visualizer_analog_vumeter',
		\%screensaverFunctions,
		\&setVisualizerMode,
		\&leaveVisualizerMode,
		'VISUALIZER_ANALOG_VUMETER',
	);
	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.visualizer_digital_vumeter',
		\%screensaverFunctions,
		\&setVisualizerMode,
		\&leaveVisualizerMode,
		'VISUALIZER_DIGITAL_VUMETER',
	);
}

sub leaveVisualizerMode() {
	my $client = shift;
	Slim::Utils::Timers::killTimers($client, \&_pushoff);
	Slim::Utils::Timers::killTimers($client, \&_pushon);
}

sub setVisualizerMode() {
	my $client = shift;
	my $method = shift;

	# If we're popping back into this mode, it's because another screensaver
	# got stacked above us...so we really shouldn't be here.
	if (defined($method) && $method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $mode = Slim::Buttons::Common::mode($client);
	my $paramsRef;
	if (ref($screensaver_info{$mode}->{params}) eq 'ARRAY') {
		$paramsRef = $screensaver_info{$mode}->{params};
	} else {
		if ($client->display->isa('Slim::Display::Transporter')) {
			$paramsRef = $screensaver_info{$mode}->{params}->{'transporter'};
		} elsif ($client->display->isa('Slim::Display::Squeezebox2')) {
			$paramsRef = $screensaver_info{$mode}->{params}->{'squeezebox2'};
		}
	}
	
	$client->modeParam('visu', $paramsRef);

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
#	my $client = shift;
#	my $paramsRef = shift;
	my $request = shift;
	
	my $client = $request->client();
	
#	return if ($paramsRef->[0] ne 'newsong');
	$::d_plugins && Slim::Utils::Misc::msg("Visualizer: _showsongtransition()\n");
	
	my $mode = Slim::Buttons::Common::mode($client);
	return if (!$mode || $mode !~ /^SCREENSAVER.visualizer_/);
	return if (!$screensaver_info{$mode}->{showtext});
	
	_pushon($client);
}

sub _pushon {
	my $client = shift;
	
	Slim::Utils::Timers::killTimers($client, \&_pushoff);
	Slim::Utils::Timers::killTimers($client, \&_pushon);

	my $screen = {
		'fonts' => { 'graphic-320x32' => 'high' },
		'line' => [ '', $client->string('NOW_PLAYING') . ': ' . 
					Slim::Music::Info::getCurrentTitle($client, Slim::Player::Playlist::url($client)) ]
	};
	
	$client->pushLeft(undef, $screen);
	# do it again at the next period
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $textontime,
								  \&_pushoff,
								  $client);	
}

sub _pushoff {
	my $client = shift;
	
	Slim::Utils::Timers::killTimers($client, \&_pushoff);
	Slim::Utils::Timers::killTimers($client, \&_pushon);

	my $screen = {
		'line' => ['','']
	};
	$client->pushRight(undef,$screen);
	# do it again at the next period
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $textofftime,
								  \&_pushon,
								  $client);	
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
