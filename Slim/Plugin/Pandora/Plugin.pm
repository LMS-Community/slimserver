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
	
	# XXX: CLI support

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
	
	# XXX: figure out how to avoid buffering display
	
	$client->execute(["playlist", "jump", "+1"]);
}

# XXX: CLI/Web support

1;