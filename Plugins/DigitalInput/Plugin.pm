package Plugins::DigitalInput::Plugin;

# SlimServer Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Scalar::Util qw(blessed);

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Misc;

my $digital_input = 0;

my @digital_inputs = ();

my $source_name = 'source';

sub getDisplayName {
	return 'PLUGIN_DIGITAL_INPUT'
}

sub initPlugin {

        $::d_plugins && msg("DigitalInput Plugin initializing.\n");

	@digital_inputs = (
		{
			'name'  => '{PLUGIN_DIGITAL_INPUT_BALANCED_AES}',
			'value' => 1,
			'url'   => "$source_name:aes-ebu",
		},
		{
			'name'  => '{PLUGIN_DIGITAL_INPUT_BNC_SPDIF}',
			'value' => 2,
			'url'   => "$source_name:bnc-spdif",
		},
		{
			'name'  => '{PLUGIN_DIGITAL_INPUT_RCA_SPDIF}',
			'value' => 3,
			'url'   => "$source_name:rca-spdif",
		},
		{
			'name'  => '{PLUGIN_DIGITAL_INPUT_OPTICAL_SPDIF}',
			'value' => 4,
			'url'   => "$source_name:toslink",
		},
	);

	Slim::Player::ProtocolHandlers->registerHandler('source', 'Plugins::DigitalInput::ProtocolHandler');
}

sub enabled {
	my $client = shift;
	
	# make sure this is only validated when the provided client has digital inputs.
	# when the client isn't given, we only need to report that the plugin is alive.
	return $client ? $client->hasDigitalIn() : 1;
}

sub valueForSourceName {
	my $sourceName = shift || return 0;

	for my $input (@digital_inputs) {

		if ($input->{'url'} eq $sourceName) {

			return $input->{'value'};
		}
	}

	return 0;
}

sub updateDigitalInput {
	my $client = shift;
	my $valueRef = shift;

	my $name  = $valueRef->{'name'};
	my $value = $valueRef->{'value'};
	my $url   = $valueRef->{'url'};

	# Strip off INPUT.Choice brackets.
	$name =~ s/[{}]//g;
	$name = $client->string($name);

	$::d_plugins && msg("updateDigitalInput: Calling addtracks on [$name] ($url)\n");

	# Create an object in the database for this meta source: url.
	my $obj = Slim::Schema->rs('Track')->updateOrCreate({
		'url'        => $url,
		'create'     => 1,
		'readTags'   => 0,
		'attributes' => {
			'TITLE' => $name,
			'CT'    => 'src',
		},
	});

	if (blessed($obj)) {

		$client->prefSet('digitalInput', $value);
		$client->sendFrame('audp', \pack('C', $value));

		# Always clear the current playlist for Digital Inputs
		$client->execute([ 'playlist', 'clear' ] );
		$client->execute([ 'playlist', 'playtracks', 'listRef', [ $obj ] ]);
	}
}

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

sub webPages {

	my %pages = (
		"digitalinput_list\.(?:htm|xml)" => \&handleWebList,
		"digitalinput_set\.(?:htm|xml)"  => \&handleSetting,
	);

	my $value = 'plugins/DigitalInput/digitalinput_list.html';

	if (grep { /^DigitalInput::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	}

	Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_DIGITAL_INPUT' => $value });

	return \%pages;
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	if ($client) {

		# Pass on the current pref
		# 0 is Network, but we don't keep it in our digital_input list.
		my $value = $client->prefGet('digitalInput') - 1;

		# pre-localised string served to template
		$params->{'digitalInputCurrent'} = Slim::Buttons::Input::Choice::formatString(
			$client, $digital_inputs[$value]->{'name'},
		);
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/DigitalInput/digitalinput_list.html', $params);
}

# Handles play requests from plugin's web page
sub handleSetting {
	my ($client, $params) = @_;

	if (defined $client) {

		updateDigitalInput($client, $digital_inputs[ ($params->{'type'} - 1) ]);
	}

	handleWebList($client, $params);
}

sub strings {

	return '
PLUGIN_DIGITAL_INPUT
	DE	Digitaler Eingang
	EN	Digital Inputs

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

PLUGIN_DIGITAL_INPUT_CHOOSE_BELOW
	DE	Wählen Sie einen digitalen Eingang:
	EN	Choose a Digital Input option below:
'};

1;

__END__
