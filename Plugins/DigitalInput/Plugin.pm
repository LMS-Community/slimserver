package Plugins::DigitalInput::Plugin;

# SlimServer Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Scalar::Util qw(blessed);

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;

my $digital_input = 0;

my @digital_inputs = ();

my $source_name = 'source';

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.digitalinput',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

sub getDisplayName {
	return 'PLUGIN_DIGITAL_INPUT'
}

sub initPlugin {

        $log->info("Initializing");

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

	$log->info("Calling addtracks on [$name] ($url)");

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

	my $line1;
	my $line2;
	
	if ($client->linesPerScreen == 1) {

		$line2 = $client->doubleString('NOW_PLAYING_FROM');

	} else {

		$line1 = $client->string('NOW_PLAYING_FROM');
		$line2 = $name;
	};

	$client->showBriefly({
		'line'    => [ $line1, $line2 ],
		'overlay' => [ undef, $client->symbols('notesymbol') ],
	});

	if (blessed($obj)) {
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
	return {
		'aes-ebu'    => sub { updateDigitalInput(shift, $digital_inputs[ 0 ]) },
		'bnc-spdif'  => sub { updateDigitalInput(shift, $digital_inputs[ 1 ]) },
		'rcs-spdif'  => sub { updateDigitalInput(shift, $digital_inputs[ 2 ]) },
		'toslink'    => sub { updateDigitalInput(shift, $digital_inputs[ 3 ]) },
	};
}

# This plugin leaks into the main server, Slim::Web::Pages::Home() needs to
# call this function to decide to show the Digital Input menu or not.
sub webPages {
	my $hasDigitalInput = shift;

	my %pages = (
		"digitalinput_list\.(?:htm|xml)" => \&handleWebList,
		"digitalinput_set\.(?:htm|xml)"  => \&handleSetting,
	);

	my $value = 'plugins/DigitalInput/digitalinput_list.html';

	if (grep { /^DigitalInput::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	}

	if (!$hasDigitalInput) {

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

1;

__END__
