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

my %client_context = ();
my @visualizer_screensavers = ( 'SCREENSAVER.visualizer_spectrum', 
								'SCREENSAVER.visualizer_digital_vumeter', 
								'SCREENSAVER.visualizer_analog_vumeter' );
my %screensaver_info = ( 
	'SCREENSAVER.visualizer_spectrum' => {
		name => 'PLUGIN_SCREENSAVER_VISUALIZER_SPECTRUM_ANALYZER',
		type => $VISUALIZER_SPECTRUM_ANALYZER,
		params => [0, 0, 0x10000, 0, 160, 0, 4, 1, 1, 1, 3, 160, 160, 1, 4, 1, 1, 1, 3],
	},
	'SCREENSAVER.visualizer_analog_vumeter' => {
		name => 'PLUGIN_SCREENSAVER_VISUALIZER_ANALOG_VUMETER',
		type => $VISUALIZER_VUMETER,
		params => [0, 1, 0, 160, 160, 160],
	},
	'SCREENSAVER.visualizer_digital_vumeter' => {
		name => 'PLUGIN_SCREENSAVER_VISUALIZER_DIGITAL_VUMETER',
		type => $VISUALIZER_VUMETER,
		params => [0, 0, 20, 130, 170, 130],
	},
	'screensaver' => {
		name => 'PLUGIN_SCREENSAVER_VISUALIZER_DEFAULT',
	}
);

sub getDisplayName {
	return 'PLUGIN_SCREENSAVER_VISUALIZER';
}

sub strings { return '
PLUGIN_SCREENSAVER_VISUALIZER
	DE	Visualizer Bildschirmschoner
	EN	Visualizer Screensaver
	ES	Salvapantallas de Visualizador

PLUGIN_SCREENSAVER_VISUALIZER_NEEDS_SQUEEZEBOX2
	DE	Benötigt Squeezebox2
	EN	Needs Squeezebox2
	ES	Requiere Squeezebox2

PLUGIN_SCREENSAVER_VISUALIZER_SPECTRUM_ANALYZER
	EN	Spectrum Analyzer
	ES	Analizador de Espectro

PLUGIN_SCREENSAVER_VISUALIZER_ANALOG_VUMETER
	DE	Analoger VU Meter
	EN	Analog VU Meter
	ES	VUmetro análogo

PLUGIN_SCREENSAVER_VISUALIZER_DIGITAL_VUMETER
	DE	Digitaler VU Meter
	EN	Digital VU Meter
	ES	VUmetro digital

PLUGIN_SCREENSAVER_VISUALIZER_PRESS_RIGHT_TO_CHOOSE
	DE	RIGHT drücken zum Aktivieren des Bildschirmschoners
	EN	Press -> to enable this screensaver 
	ES	Presionar -> para activar este salvapantallas

PLUGIN_SCREENSAVER_VISUALIZER_ENABLED
	DE	Bildschirmschoner aktiviert
	EN	This screensaver is enabled
	ES	Este salvapantallas está activo

PLUGIN_SCREENSAVER_VISUALIZER_DEFAULT
	DE	Standard Bildschirmschoner
	EN	Default screenaver
	ES	Salvapantallas por defecto
'};

##################################################
### Screensaver configuration mode
##################################################

our %configFunctions = (
	'up' => sub  {
		my $client = shift;
		$client_context{$client}->{position} = Slim::Buttons::Common::scroll(
								$client,
								-1,
								scalar(@{$client_context{$client}->{list}}),
								$client_context{$client}->{position},
								);
		$client->update();
	},
	'down' => sub  {
		my $client = shift;
		$client_context{$client}->{position} = Slim::Buttons::Common::scroll(
								$client,
								1,
								scalar(@{$client_context{$client}->{list}}),
								$client_context{$client}->{position},
								);
		$client->update();
	},
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;

		my $screensaver = $client_context{$client}->{list}->[$client_context{$client}->{position}];
		$client_context{$client}->{screensaver} = $screensaver;
		Slim::Utils::Prefs::clientSet($client,'screensaver',$screensaver);
		$client->update();
	}
);

sub configLines {
	my $client = shift;
	
	my ($line1, $line2, $select);
	my $item = $client_context{$client}->{list}->[$client_context{$client}->{position}];
	if ($item eq $client_context{$client}->{screensaver}) {
		$line1 = $client->string('PLUGIN_SCREENSAVER_VISUALIZER_ENABLED');
		$select = '[x]';
	}
	else {
		$line1 = $client->string('PLUGIN_SCREENSAVER_VISUALIZER_PRESS_RIGHT_TO_CHOOSE');
		$select = '[ ]';
	}

	$line2 = $client->string($screensaver_info{$item}->{name});

	return ($line1, $line2, undef, $select);
}

sub getFunctions {
	return \%configFunctions;
}

sub setMode {
	my $client = shift;

	my $cursaver = Slim::Utils::Prefs::clientGet($client,'screensaver');
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
	if( $client->isa( "Slim::Player::Squeezebox2")) {
		$line1 = $line2 = '';
	}
	else {
		$line1 = $client->string('PLUGIN_SCREENSAVER_VISUALIZER');
		$line2 = $client->string('PLUGIN_SCREENSAVER_VISUALIZER_NEEDS_SQUEEZEBOX2');
	}

	return( $line1, $line2);
}

sub screenSaver {
	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.visualizer_spectrum',
		\%screensaverFunctions,
		\&setVisualizerMode,
		\&leaveVisualizerMode,
		'PLUGIN_SCREENSAVER_VISUALIZER_SPECTRUM_ANALYZER',
	);
	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.visualizer_analog_vumeter',
		\%screensaverFunctions,
		\&setVisualizerMode,
		\&leaveVisualizerMode,
		'PLUGIN_SCREENSAVER_VISUALIZER_ANALOG_VUMETER',
	);
	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.visualizer_digital_vumeter',
		\%screensaverFunctions,
		\&setVisualizerMode,
		\&leaveVisualizerMode,
		'PLUGIN_SCREENSAVER_VISUALIZER_DIGITAL_VUMETER',
	);
}

sub leaveVisualizerMode() {
	my $client = shift;

	$client->visualizer($client_context{$client}->{last_pdm});
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

	$client_context{$client}->{last_pdm} = Slim::Utils::Prefs::clientGet(
														$client, 
														"playingDisplayMode");
	
	my $mode = Slim::Buttons::Common::mode($client);
	my $visu = pack "CC", $screensaver_info{$mode}->{type}, scalar(@{$screensaver_info{$mode}->{params}});
	for my $param (@{$screensaver_info{$mode}->{params}}) {
		$visu .= pack "N", $param;
	}
	$client->sendFrame('visu', \$visu);
	$client->lines(\&screensaverLines);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
