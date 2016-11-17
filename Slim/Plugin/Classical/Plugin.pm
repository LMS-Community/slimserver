package Slim::Plugin::Classical::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Plugin::Classical::ProtocolHandler;
use Slim::Networking::SqueezeNetwork;

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		classical => 'Slim::Plugin::Classical::ProtocolHandler'
	);
	
	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr|mysqueezebox\.com.*/api/classical/|, 
		sub { $class->_pluginDataFor('icon') }
	);
	
	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url('/api/classical/v1/opml'),
		tag    => 'classical',
		menu   => 'music_services',
		weight => 38,
		is_app => 1,
	);
	
	if ( main::WEBUI ) {
		# Add a function to view trackinfo in the web
		Slim::Web::Pages->addPageFunction( 
			'plugins/classical/trackinfo.html',
			sub {
				my $client = $_[0];
				my $params = $_[1];
				
				my $url;
				
				my $id = $params->{sess} || $params->{item};
				
				if ( $id ) {
					# The user clicked on a different URL than is currently playing
					if ( my $track = Slim::Schema->find( Track => $id ) ) {
						$url = $track->url;
					}
					
					# Pass-through track ID as sess param
					$params->{sess} = $id;
				}
				else {
					$url = Slim::Player::Playlist::url($client);
				}
				
				Slim::Web::XMLBrowser->handleWebIndex( {
					client  => $client,
					feed    => Slim::Plugin::Classical::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'plugins/classical/trackinfo.html',
					title   => 'Classical Track Info',
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}
}

sub getDisplayName () {
	return 'PLUGIN_CLASSICAL_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

1;
