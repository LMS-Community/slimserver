package Slim::Plugin::MOG::Plugin;

# $Id: Plugin.pm 10553 2011-08-03 15:29:58Z Shaahul $

use strict;
use base qw(Slim::Plugin::OPMLBased);

use URI::Split qw(uri_split);
use Slim::Plugin::MOG::ProtocolHandler;
use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Strings qw(cstring);

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.mog',
	defaultLevel => 'DEBUG',
	description  => 'PLUGIN_MOG_MODULE_NAME',
} );

sub initPlugin {
	my $class = shift;


	Slim::Player::ProtocolHandlers->registerHandler(
		mog => 'Slim::Plugin::MOG::ProtocolHandler'
	);

	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr|squeezenetwork\.com.*/api/mog/|, 
		sub { $class->_pluginDataFor('icon') }
	);
	
	if ( main::WEBUI ) {
		# Add a function to view trackinfo in the web
		Slim::Web::Pages->addPageFunction( 
			'plugins/mog/trackinfo.html',
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
					feed    => Slim::Plugin::MOG::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'plugins/mog/trackinfo.html',
					title   => 'MOG Track Info',
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}

	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url('/api/mog/v1/opml'),
		tag    => 'mog',
		menu   => 'music_services',
		weight => 40,
		is_app => 1,
	);	

}

sub getDisplayName () {
	return 'PLUGIN_MOG_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

1;
