package Plugins::ShoutcastBrowser::Plugin;

# $Id$

use strict;

use Slim::Buttons::Common;
use Slim::Buttons::XMLBrowser;
use Slim::Formats::XML;
use Slim::Utils::Misc;
use Slim::Web::XMLBrowser;

my $FEED   = 'http://content.us.squeezenetwork.com:8080/shoutcast/index.opml';
my $SEARCH = 'http://www.squeezenetwork.com/api/opensearch/shoutcast/opensearch.xml';
my $cli_next;

sub enabled {
	return ($::VERSION ge '6.3');
}

sub initPlugin {
	$::d_plugins && msg("Shoutcast: initPlugin()\n");

	Slim::Buttons::Common::addMode('PLUGIN.ShoutcastBrowser', getFunctions(), \&setMode);

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
    Slim::Control::Request::addDispatch(['shoutcast', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);
	Slim::Control::Request::addDispatch(['shoutcast', 'playlist', '_method' ],
		[1, 1, 1, \&cliQuery]);
	$cli_next=Slim::Control::Request::addDispatch(['radios', '_index', '_quantity' ],
		[0, 1, 1, \&cliRadiosQuery]);
}

sub getDisplayName {
	return 'PLUGIN_SHOUTCASTBROWSER_MODULE_NAME';
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
		header   => 'PLUGIN_SHOUTCASTBROWSER_CONNECTING',
		modeName => 'ShoutcastBrowser Plugin',
		url      => $FEED,
		search   => $SEARCH,
		title    => $client->string(getDisplayName()),
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);
	
	# we'll handle the push in a callback
	$client->modeParam('handledTransition',1)
}

sub cliQuery {
	my $request = shift;
	
	$::d_plugins && msg("Shoutcast: cliQuery()\n");
	
	Slim::Buttons::XMLBrowser::cliQuery('shoutcast', $FEED, $request);
}

sub cliRadiosQuery {
	my $request = shift;
	
	$::d_plugins && msg("Shoutcast: cliRadiosQuery()\n");
	
	# what we want the query to report about ourself
	my $data = {
		'cmd' => 'shoutcast',                    # cmd label
		'name' => Slim::Utils::Strings::string(getDisplayName()),  # nice name
		'type' => 'xmlbrowser',              # type
	};
	
	# let our super duper function do all the hard work
	Slim::Control::Queries::dynamicAutoQuery($request, 'radios', $cli_next, $data);
}

sub webPages {
	my $title = 'PLUGIN_SHOUTCASTBROWSER_MODULE_NAME';

	if (grep {$_ eq 'ShoutcastBrowser::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages->addPageLinks('radio', { $title => undef });
	} else {
		Slim::Web::Pages->addPageLinks('radio', { $title => 'plugins/ShoutcastBrowser/index.html' });
	}

	my %pages = ( 
		'index.html' => sub {
			Slim::Web::XMLBrowser->handleWebIndex( {
				feed   => $FEED,
				title  => $title,
				search => $SEARCH, 
				args   => \@_
			} );
		},
	);
	
	return \%pages;
}

sub strings {
	return "
PLUGIN_SHOUTCASTBROWSER_MODULE_NAME
	EN	SHOUTcast Internet Radio
	ES	Radio por Internet SHOUTcast
	HE	ShoutCast
	NL	SHOUTcast Internet radio

PLUGIN_SHOUTCASTBROWSER_CONNECTING
	DE	Verbinde mit SHOUTcast...
	EN	Connecting to SHOUTcast...
	ES	Conectando a SHOUTcast...
	FR	Connexion à SHOUTcast...
	IT	In connessione con SHOUTcast...
	NL	Connectie maken naar SHOUTcast...
";}

1;
