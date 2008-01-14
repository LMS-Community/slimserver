package Slim::Plugin::ShoutcastBrowser::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::Base);

use Slim::Buttons::Common;
use Slim::Buttons::XMLBrowser;
use Slim::Formats::XML;
use Slim::Utils::Strings qw( string );
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Web::XMLBrowser;

my $FEED   = 'http://content.us.squeezenetwork.com:8080/shoutcast/index.opml';
my $SEARCH = 'http://www.squeezenetwork.com/api/opensearch/shoutcast/opensearch.xml';

my $cli_next;

sub initPlugin {
	my $class = shift;

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
    Slim::Control::Request::addDispatch(['shoutcast', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);
	Slim::Control::Request::addDispatch(['shoutcast', 'playlist', '_method' ],
		[1, 1, 1, \&cliQuery]);
	$cli_next = Slim::Control::Request::addDispatch(['radios', '_index', '_quantity' ],
		[0, 1, 1, \&cliRadiosQuery]);

	$class->SUPER::initPlugin();
}

sub getDisplayName {
	return 'PLUGIN_SHOUTCASTBROWSER_MODULE_NAME';
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
		header   => 'PLUGIN_SHOUTCASTBROWSER_CONNECTING',
		modeName => 'ShoutcastBrowser Plugin',
		url      => $FEED,
		search   => $SEARCH,
		title    => $client->string(getDisplayName()),
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);
	
	# we'll handle the push in a callback
	$client->modeParam('handledTransition', 1)
}

sub cliQuery {
	my $request = shift;
	
	Slim::Buttons::XMLBrowser::cliQuery('shoutcast', $FEED, $request);
}

sub cliRadiosQuery {
	my $request = shift;
	
	my $menu = $request->getParam('menu');

	my $data;
	# what we want the query to report about ourself
	if (defined $menu) {
		$data = {
			'text' => string(getDisplayName()),  # nice name
			'icon-id' => Slim::Plugin::ShoutcastBrowser::Plugin->_pluginDataFor('icon'),
			'actions' => {
				'go' => {
					'cmd' => ['shoutcast', 'items'],
					'params' => {
						'menu' => 'shoutcast',
					},
				},
			},
			window    => {
				titleStyle => 'album',
			},
		};
	}
	else {
		$data = {
			'cmd' => 'shoutcast',                    # cmd label
			'name' => string(getDisplayName()),  # nice name
			'type' => 'xmlbrowser',              # type
		};
	}
	
	# let our super duper function do all the hard work
	Slim::Control::Queries::dynamicAutoQuery($request, 'radios', $cli_next, $data);
}

sub webPages {
	my $class = shift;

	my $title = getDisplayName();
	my $url   = 'plugins/ShoutcastBrowser/index.html';

	Slim::Web::Pages->addPageLinks('radio', { $title => $url });
	
	Slim::Web::HTTP::protectURI($url);

	Slim::Web::HTTP::addPageFunction($url => sub {

		Slim::Web::XMLBrowser->handleWebIndex( {
			feed   => $FEED,
			title  => $title,
			search => $SEARCH, 
			args   => \@_
		} );
	});
}

1;
