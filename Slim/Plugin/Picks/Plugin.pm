package Slim::Plugin::Picks::Plugin;

# $Id$

# Load Picks via an OPML file - so we can ride on top of the Podcast Browser

use strict;
use base qw(Slim::Plugin::Base);

use Slim::Buttons::Common;
use Slim::Buttons::XMLBrowser;
use Slim::Web::XMLBrowser;

my $FEED = 'http://www.slimdevices.com/picks/radio.opml';
my $cli_next;

sub initPlugin {
	my $class = shift;

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
    Slim::Control::Request::addDispatch(['picks', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);
	Slim::Control::Request::addDispatch(['picks', 'playlist', '_method' ],
		[1, 1, 1, \&cliQuery]);
	$cli_next=Slim::Control::Request::addDispatch(['radios', '_index', '_quantity' ],
		[0, 1, 1, \&cliRadiosQuery]);

	$class->SUPER::initPlugin();
}

sub getDisplayName {
	return 'PLUGIN_PICKS_MODULE_NAME';
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
		header   => 'PLUGIN_PICKS_LOADING_PICKS',
		modeName => 'Picks Plugin',
		url      => $FEED,
		title    => $client->string(getDisplayName()),
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);
	
	# we'll handle the push in a callback
	$client->modeParam('handledTransition', 1)
}

sub cliQuery {
	my $request = shift;
	
	Slim::Buttons::XMLBrowser::cliQuery('picks', $FEED, $request);
}

sub cliRadiosQuery {
	my $request = shift;
	
	# what we want the query to report about ourself
	my $data = {
		'cmd' => 'picks',                    # cmd label
		'name' => Slim::Utils::Strings::string(getDisplayName()),  # nice name
		'type' => 'xmlbrowser',              # type
	};
	
	# let our super duper function do all the hard work
	Slim::Control::Queries::dynamicAutoQuery($request, 'radios', $cli_next, $data);
}

sub webPages {
	my $class = shift;

	my $title = getDisplayName();
	my $url   = 'plugins/Picks/index.html';
	
	Slim::Web::Pages->addPageLinks('radio', { $title => $url });

	Slim::Web::HTTP::addPageFunction($url, sub {

		Slim::Web::XMLBrowser->handleWebIndex( {
			feed   => $FEED,
			title  => $title,
			args   => \@_
		} );
	});
}

1;
