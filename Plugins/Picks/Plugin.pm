package Plugins::Picks::Plugin;

# $Id$

# Load Picks via an OPML file - so we can ride on top of the Podcast Browser
#
# Still todo - Add web UI to replace old flat Picks list.

use strict;

use Slim::Buttons::Common;
use Slim::Buttons::XMLBrowser;
use Slim::Utils::Misc;

my $FEED = 'http://www.slimdevices.com/picks/radio.opml';

sub enabled {
	return ($::VERSION ge '6.1');
}

sub initPlugin {
	$::d_plugins && msg("Picks Plugin initializing.\n");

	Slim::Buttons::Common::addMode('PLUGIN.Picks', getFunctions(), \&setMode);
}

sub getDisplayName {
	return 'PLUGIN_PICKS_MODULE_NAME';
}

sub addMenu {
	return 'RADIO';
}

sub getFunctions {
	return {};
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
		header   => 'PLUGIN_PICKS_LOADING_PICKS',
		modeName => 'Picks Plugin',
		url      => $FEED,
		title    => $client->string(getDisplayName()),
	);

	Slim::Buttons::Common::pushModeLeft($client, 'xmlbrowser', \%params);
}

sub strings {
	return "
PLUGIN_PICKS_MODULE_NAME
	DE	Slim Devices Auswahl
	EN	Slim Devices Picks
	ES	Preferidas de Slim Devices
	NL	Slim Devices tips

PLUGIN_PICKS_LOADING_PICKS
	DE	Lade Slim Devices Picks...
	EN	Loading Slim Devices Picks...
	ES	Cargando las Preferidas de Slim Devices...
	NL	Laden Slim Devices tips...
";}

1;
