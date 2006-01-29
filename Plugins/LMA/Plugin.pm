package Plugins::LMA::Plugin;

# $Id$

# Load Live Music Archive data via an OPML file - so we can ride on top of the Podcast Browser

use Slim::Buttons::Common;
use Slim::Buttons::XMLBrowser;
use Slim::Utils::Misc;

my $FEED = 'http://content.us.squeezenetwork.com:8080/lma/artists.opml';

sub enabled {
	return ($::VERSION ge '6.1');
}

sub initPlugin {
	$::d_plugins && msg("Live Music Archive Plugin initializing.\n");

	Slim::Buttons::Common::addMode('PLUGIN.LMA', getFunctions(), \&setMode);
}

sub getDisplayName {
	return 'PLUGIN_LMA_MODULE_NAME';
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
		header   => 'PLUGIN_LMA_LOADING',
		modeName => 'LMA Plugin',
		url      => $FEED,
		title    => $client->string(getDisplayName()),
	);

	Slim::Buttons::Common::pushModeLeft($client, 'xmlbrowser', \%params);
}

sub strings {
	return "
PLUGIN_LMA_MODULE_NAME
	EN	Live Music Archive

PLUGIN_LMA_LOADING
	EN	Loading Live Music Archive...
";}

1;
