package Slim::Plugin::DigitalInput::Plugin;

# SlimServer Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

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
	my $class = shift;

	$log->info("Initializing");
	
	$class->SUPER::initPlugin();

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

	Slim::Player::ProtocolHandlers->registerHandler('source', 'Slim::Plugin::DigitalInput::ProtocolHandler');
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
	my $class  = shift;
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
		'overlayRef'   => sub { return [ undef, shift->symbols('notesymbol') ] },
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub getFunctions {
	return {
		'aes-ebu'     => sub { updateDigitalInput(shift, $digital_inputs[ 0 ]) },
		'bnc-spdif'   => sub { updateDigitalInput(shift, $digital_inputs[ 1 ]) },
		'rcs-spdif'   => sub { updateDigitalInput(shift, $digital_inputs[ 2 ]) },
		'toslink'     => sub { updateDigitalInput(shift, $digital_inputs[ 3 ]) },
	};
}

# This plugin leaks into the main server, Slim::Web::Pages::Home() needs to
# call this function to decide to show the Digital Input menu or not.
sub webPages {
	my $class        = shift;
	my $hasDigitalIn = shift;

	my $urlBase = 'plugins/DigitalInput';

	if ($hasDigitalIn) {
		Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_DIGITAL_INPUT' => "$urlBase/list.html" });
	} else {
		Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_DIGITAL_INPUT' => undef });
	}

	Slim::Web::HTTP::addPageFunction("$urlBase/list.html", \&handleWebList);
	Slim::Web::HTTP::addPageFunction("$urlBase/set.html", \&handleSetting);
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;
	my $url;

	if ($client) {

		my $song = Slim::Player::Playlist::song($client);
		
		if ($song) {
			$url = $song->url;

		
			my $name;
			for my $input (@digital_inputs) {
				if ($url && $url eq $input->{'url'}) {
					$name = $input->{'name'};
					last;
				}
			}
	
			if (defined $name) {
				# pre-localised string served to template
				$params->{'digitalInputCurrent'} = Slim::Buttons::Input::Choice::formatString(
					$client, $name,
				);
			}
		}
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/DigitalInput/list.html', $params);
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
