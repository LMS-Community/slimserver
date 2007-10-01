package Slim::Plugin::Pandora::Plugin;

# $Id$

# Play Pandora via SqueezeNetwork

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SqueezeNetwork;
use Slim::Plugin::Pandora::ProtocolHandler;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.pandora',
	'defaultLevel' => $ENV{PANDORA_DEV} ? 'DEBUG' : 'WARN',
	'description'  => 'PLUGIN_PANDORA_MODULE_NAME',
});

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		pandora => 'Slim::Plugin::Pandora::ProtocolHandler'
	);
	
	# Commands init
	Slim::Control::Request::addDispatch(['pandora', 'skipTrack'],
		[0, 1, 1, \&skipTrack]);

	$class->SUPER::initPlugin(
		feed => Slim::Networking::SqueezeNetwork->url('/api/pandora/opml'),
		tag  => 'pandora',
		'icon-id' => 'html/images/ServiceProviders/pandora_56x56_p.png',
		menu => 'radio',
	);
}

sub getDisplayName () {
	return 'PLUGIN_PANDORA_MODULE_NAME';
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

1;
