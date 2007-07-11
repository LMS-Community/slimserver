package Slim::Plugin::Live365::Plugin;

# $Id$

# Browse Live365 via SqueezeNetwork

use strict;
use base qw(Slim::Plugin::Base);

use Slim::Networking::SqueezeNetwork;
use Slim::Player::ProtocolHandlers;
use Slim::Plugin::Live365::ProtocolHandler;

my $FEED = Slim::Networking::SqueezeNetwork->url( '/api/live365/opml' );
my $cli_next;

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		live365 => 'Slim::Plugin::Live365::ProtocolHandler'
	);

	# XXX: CLI support

	$class->SUPER::initPlugin();
}

sub getDisplayName {
	return 'PLUGIN_LIVE365_MODULE_NAME';
}

sub setMode {
	my ( $class, $client, $method ) = @_;

	if ($method eq 'pop') {

		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header   => 'PLUGIN_LIVE365_LOADING',
		modeName => 'Live365 Plugin',
		url      => $FEED,
		title    => $client->string(getDisplayName()),
		timeout  => 35,
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->modeParam( 'handledTransition', 1 );
}

# XXX: CLI/Web support

1;