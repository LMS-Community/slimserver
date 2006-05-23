package Plugins::Picks::Plugin;

# $Id$

# Load Picks via an OPML file - so we can ride on top of the Podcast Browser

use strict;

use Slim::Buttons::Common;
use Slim::Buttons::XMLBrowser;
use Slim::Formats::XML;
use Slim::Utils::Misc;
use Slim::Web::XMLBrowser;

my $FEED = 'http://www.slimdevices.com/picks/radio.opml';

sub enabled {
	return ($::VERSION ge '6.3');
}

sub initPlugin {
	$::d_plugins && msg("Picks: initPlugin()\n");

	Slim::Buttons::Common::addMode('PLUGIN.Picks', getFunctions(), \&setMode);

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
    Slim::Control::Request::addDispatch(['picks', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);
	Slim::Control::Request::addDispatch(['picks', 'playlist', '_method' ],
		[1, 1, 1, \&cliQuery]);

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

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);
	
	# we'll handle the push in a callback
	$client->param('handledTransition',1)
}

sub cliQuery {
	my $request = shift;
	
	$::d_plugins && msg("Picks: cliQuery()\n");
	
	Slim::Buttons::XMLBrowser::cliQuery('picks', $FEED, $request);
}

sub webPages {
	my $title = 'PLUGIN_PICKS_MODULE_NAME';

	if (grep {$_ eq 'Picks::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages->addPageLinks('radio', { $title => undef });
	} else {
		Slim::Web::Pages->addPageLinks('radio', { $title => 'plugins/Picks/index.html' });
	}

	my %pages = ( 
		'index.html' => sub {
			Slim::Web::XMLBrowser->handleWebIndex( {
				feed   => $FEED,
				title  => $title,
				args   => \@_
			} );
		},
	);
	
	return \%pages;
}

sub strings {
	return "
PLUGIN_PICKS_MODULE_NAME
	DE	Slim Devices Auswahl
	EN	Slim Devices Picks
	ES	Preferidas de Slim Devices
	HE	המומלצים
	NL	De beste van Slim Devices

PLUGIN_PICKS_LOADING_PICKS
	DE	Lade Slim Devices Picks...
	EN	Loading Slim Devices Picks...
	ES	Cargando las Preferidas de Slim Devices...
	HE	טוען מועדפים
	NL	Laden van de beste van Slim Devices...
";}

1;
