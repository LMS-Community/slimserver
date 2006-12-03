package Plugins::LMA::Plugin;

# $Id$

# Load Live Music Archive data via an OPML file - so we can ride on top of the Podcast Browser

use Slim::Buttons::Common;
use Slim::Buttons::XMLBrowser;
use Slim::Web::XMLBrowser;

my $FEED = 'http://content.us.squeezenetwork.com:8080/lma/artists.opml';
my $cli_next;

sub enabled {
	return ($::VERSION ge '6.3');
}

sub initPlugin {

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
    Slim::Control::Request::addDispatch(['lma', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);
	Slim::Control::Request::addDispatch(['lma', 'playlist', '_method' ],
		[1, 1, 1, \&cliQuery]);
	$cli_next=Slim::Control::Request::addDispatch(['radios', '_index', '_quantity' ],
		[0, 1, 1, \&cliRadiosQuery]);

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

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->modeParam('handledTransition',1);
}

sub webPages {
	my $title = 'PLUGIN_LMA_MODULE_NAME';
	
	if (grep {$_ eq 'LMA::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages->addPageLinks('radio', { $title => undef });
	} else {
		Slim::Web::Pages->addPageLinks('radio', { $title => 'plugins/LMA/index.html' });
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

sub cliQuery {
	my $request = shift;

	Slim::Buttons::XMLBrowser::cliQuery('lma', $FEED, $request);
}

sub cliRadiosQuery {
	my $request = shift;

	# what we want the query to report about ourself
	my $data = {
		'cmd' => 'lma',                      # cmd label
		'name' => Slim::Utils::Strings::string(getDisplayName()),  # nice name
		'type' => 'xmlbrowser',              # type
	};

	# let our super duper function do all the hard work
	Slim::Control::Queries::dynamicAutoQuery($request, 'radios', $cli_next, $data);
}

1;
