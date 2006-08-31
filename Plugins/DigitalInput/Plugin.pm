package Plugins::DigitalInput::Plugin;

# SlimServer Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Misc;

use Scalar::Util qw(blessed);

my $digital_input = 0;

my @digital_inputs = ();

sub getDisplayName {
	return 'PLUGIN_DIGITAL_INPUT'
};

sub initPlugin {

	@digital_inputs = (
		{
			'name'  => '{PLUGIN_DIGITAL_INPUT_NETWORK}',
			'value' => 0,
		},
		{
			'name'  => '{PLUGIN_DIGITAL_INPUT_BALANCED_AES}',
			'value' => 1,
		},
		{
			'name'  => '{PLUGIN_DIGITAL_INPUT_BNC_SPDIF}',
			'value' => 2,
		},
		{
			'name'  => '{PLUGIN_DIGITAL_INPUT_RCA_SPDIF}',
			'value' => 3,
		},
		{
			'name'  => '{PLUGIN_DIGITAL_INPUT_OPTICAL_SPDIF}',
			'value' => 4,
		},
	);
}

sub enabled {
	my $client = shift;
	
	# make sure this is only validated when the provided client has digital inputs.
	# when the client isn't given, we only need to report that the plugin is alive.
	return $client? $client->hasDigitalInputs() : 1;
};

sub updateDigitalInput {
	my $client = shift;
	my $valueRef = shift;

	$client->prefSet('digitalInput', $valueRef->{'value'});
	my $data = pack('C', $valueRef->{'value'});
	$client->sendFrame('audp', \$data);

	my $string = 'NOW_PLAYING_FROM';
	my $line1;
	my $line2;
	
	if ($client->linesPerScreen() == 1) {

		$line2 = $client->doubleString($string);

	} else {

		$line1 = $client->string($string);
		$line2 = Slim::Buttons::Input::Choice::formatString($client, $valueRef->{'name'});
	}
	
	$client->showBriefly( {
		'line'    => [ $line1, $line2 ],
		'overlay' => [ undef, $client->symbols('notesymbol') ]
	});
};

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		'header'       => '{PLUGIN_DIGITAL_INPUT} {count}',
		'listRef'      => \@digital_inputs,
		'modeName'     => 'Digital Input Plugin',
		'onPlay'       => \&updateDigitalInput,
		
		# temporarily required for checkbox overlay until digital url scheme is in place.
		#'pref'         => 'digitalInput',
		#'initialValue' => sub { return $_[0]->prefGet('digitalInput');},
		
		'overlayRef'   => [
			undef,
			Slim::Display::Display::symbol('notesymbol') 
		],
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub getFunctions {
	return {};
}

sub strings {  return '
PLUGIN_DIGITAL_INPUT
	EN	Digital Input

PLUGIN_DIGITAL_INPUT_NETWORK
	DE	Netzwerk
	EN	Network
	
PLUGIN_DIGITAL_INPUT_BALANCED_AES
	EN	Balanced AES/EBU
	ES	AES/EBU Balanceada
	FR	AES/EBU sym̩trique
	NL	Gebalanceerde AES/EBU
	
PLUGIN_DIGITAL_INPUT_BNC_SPDIF
	EN	BNC Coax S/PDIF
	ES	S/PDIF BNC Coax 
	FR	S/PDIF coaxial BNC
	NL	BNC coax S/PDIF
	
PLUGIN_DIGITAL_INPUT_RCA_SPDIF
	EN	RCA Coax S/PDIF
	ES	S/PDIF RCA Coax
	FR	S/PDIF coaxial RCA
	NL	RCA coax S/PDIF
	
PLUGIN_DIGITAL_INPUT_OPTICAL_SPDIF
	EN	Optical S/PDIF (TOSLINK)
'};

1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
