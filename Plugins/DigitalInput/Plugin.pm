package Plugins::DigitalInput::Plugin;

# SlimServer Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Utils::Misc;

my $digital_input = 0;

my @digital_inputs = (
	{
		name => '{PLUGIN_DIGITAL_INPUT_OFF}',
		value => 0,
	},
	{
		name => '{PLUGIN_DIGITAL_INPUT_BALANCED_AES}',
		value => 1,
	},
	{
		name => '{PLUGIN_DIGITAL_INPUT_BNC_SPDIF}',
		value => 2,
	},
	{
		name => '{PLUGIN_DIGITAL_INPUT_RCA_SPDIF}',
		value => 3,
	},
	{
		name => '{PLUGIN_DIGITAL_INPUT_OPTICAL_SPDIF}',
		value => 4,
	},
);


sub getDisplayName {
	return 'PLUGIN_DIGITAL_INPUT'
};

sub enabled {
	return 1;
};

sub updateDigitalInput {
	my $client = shift;
	my $input = shift;

	my $data = pack('C', $input);
	$client->sendFrame('audp', \$data);	
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
		header => '{PLUGIN_DIGITAL_INPUT} {count}',
		listRef => \@digital_inputs,
		modeName => 'Digital Input Plugin',
		onRight => sub {
			my $client = shift;
			my $item = shift;
			updateDigitalInput($client, $item->{value});
		},
		onPlay => sub {
			my $client = shift;
			my $item = shift;
			updateDigitalInput($client, $item->{value});
		},

		overlayRef => [
			undef,
			Slim::Display::Display::symbol('rightarrow') 
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

PLUGIN_DIGITAL_INPUT_OFF
	EN	Off
	
PLUGIN_DIGITAL_INPUT_BALANCED_AES
	EN	Balanced AES/EBU
	
PLUGIN_DIGITAL_INPUT_BNC_SPDIF
	EN	BNC Coax S/PDIF
	
PLUGIN_DIGITAL_INPUT_RCA_SPDIF
	EN	RCA Coax S/PDIF
	
PLUGIN_DIGITAL_INPUT_OPTICAL_SPDIF
	EN	Optical S/PDIF
'};


1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
