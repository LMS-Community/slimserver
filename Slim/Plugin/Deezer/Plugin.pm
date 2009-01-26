package Slim::Plugin::Deezer::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

use URI::Escape qw(uri_escape_utf8);

use Slim::Plugin::Deezer::ProtocolHandler;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.deezer',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_DEEZER_MODULE_NAME',
} );

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		deezer => 'Slim::Plugin::Deezer::ProtocolHandler'
	);

	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url( '/api/deezer/v1/opml' ),
		tag    => 'deezer',
		menu   => 'music_services',
		weight => 35,
	);
	
	# Note: Deezer does not wish to be included in context menus
	# that is why a track info menu item is not created here
	
	if ( !main::SLIM_SERVICE ) {
		# Add a function to view trackinfo in the web
		Slim::Web::HTTP::addPageFunction( 
			'plugins/deezer/trackinfo.html',
			sub {
				my $client = $_[0];
				
				my $url = Slim::Player::Playlist::url($client);
				
				Slim::Web::XMLBrowser->handleWebIndex( {
					client  => $client,
					feed    => Slim::Plugin::Deezer::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'plugins/deezer/trackinfo.html',
					title   => 'Deezer Track Info',
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}
}

sub getDisplayName {
	return 'PLUGIN_DEEZER_MODULE_NAME';
}

1;
