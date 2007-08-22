package Slim::Plugin::Pandora::Plugin;

# $Id$

# Play Pandora via SqueezeNetwork

use strict;
use base qw(Slim::Plugin::Base);

use Slim::Networking::SqueezeNetwork;
use Slim::Plugin::Pandora::ProtocolHandler;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.pandora',
	'defaultLevel' => $ENV{PANDORA_DEV} ? 'DEBUG' : 'WARN',
	'description'  => 'PLUGIN_PANDORA_MODULE_NAME',
});

my $FEED = Slim::Networking::SqueezeNetwork->url( '/api/pandora/opml' );
my $cli_next;

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		pandora => 'Slim::Plugin::Pandora::ProtocolHandler'
	);
	
	# Commands init
	Slim::Control::Request::addDispatch(['pandora', 'skipTrack'],
		[0, 1, 1, \&skipTrack]);

	# CLI support
    Slim::Control::Request::addDispatch(['pandora', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);
	Slim::Control::Request::addDispatch(['pandora', 'playlist', '_method' ],
		[1, 1, 1, \&cliQuery]);
	$cli_next=Slim::Control::Request::addDispatch(['radios', '_index', '_quantity' ],
		[0, 1, 1, \&cliRadiosQuery]);

	$class->SUPER::initPlugin();
}

sub getDisplayName () {
	return 'PLUGIN_PANDORA_MODULE_NAME';
}

sub setMode {
	my ( $class, $client, $method ) = @_;

	if ($method eq 'pop') {

		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header   => 'PLUGIN_PANDORA_MODULE_NAME',
		modeName => 'Pandora Plugin',
		url      => $FEED,
		title    => $client->string(getDisplayName()),
		timeout  => 35,
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->modeParam( 'handledTransition', 1 );
}

sub skipTrack {
	my $request = shift;
	my $client  = $request->client();
	
	return unless defined $client;
	
	# ignore if user is not using Pandora
	my $url = Slim::Player::Playlist::url($client) || return;
	return unless $url =~ /^pandora/;
		
	$log->debug("Pandora: Skip requested");
	
	# Tell onJump not to display buffering info, so we don't
	# mess up the showBriefly message
	$client->pluginData( banMode => 1 );
	
	$client->execute(["playlist", "jump", "+1"]);
}

# XXX: Web support

# XXX: Move this into a super-class, Slim::Plugin::OPMLBased or something
sub cliQuery {
	my $request = shift;
	
	Slim::Buttons::XMLBrowser::cliQuery('pandora', $FEED, $request);
}

sub cliRadiosQuery {
	my $request = shift;

	my $menu = $request->getParam('menu');

	my $data;
	# what we want the query to report about ourself
	if (defined $menu) {
		$data = {
			'text' => Slim::Utils::Strings::string(getDisplayName()),  # nice name
			'actions' => {
				'go' => {
					'cmd' => ['pandora', 'items'],
					'params' => {
						'menu' => 'pandora',
					},
				},
			},
		};
	}
	else {
		$data = {
			'cmd' => 'pandora',                    # cmd label
			'name' => Slim::Utils::Strings::string(getDisplayName()),  # nice name
			'type' => 'xmlbrowser',              # type
		};
	}
	
	# let our super duper function do all the hard work
	Slim::Control::Queries::dynamicAutoQuery($request, 'radios', $cli_next, $data);
}

1;