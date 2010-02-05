package Slim::Plugin::Napster::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

use URI::Escape qw(uri_escape_utf8);

use Slim::Plugin::Napster::ProtocolHandler;
use Slim::Networking::SqueezeNetwork;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.napster',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_NAPSTER_MODULE_NAME',
} );

sub initPlugin {
	my $class = shift;

	Slim::Player::ProtocolHandlers->registerHandler(
		napster => 'Slim::Plugin::Napster::ProtocolHandler'
	);
	
	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr|squeezenetwork\.com.*/api/napster/|, 
		sub { $class->_pluginDataFor('icon') }
	);
	
	# Track Info item
	Slim::Menu::TrackInfo->registerInfoProvider( napster => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );
	
	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url('/api/napster/v1/opml'),
		tag    => 'napster',
		menu   => 'music_services',
		weight => 25,
		is_app => 1,
	);
	
	if ( main::SLIM_SERVICE ) {
		# Also add to the My Music menu
		my $my_menu = {
			useMode => sub { $class->myLibraryMode(@_) },
			header  => 'PLUGIN_NAPSTER_MY_NAPSTER_LIBRARY',
		};
		
		Slim::Buttons::Home::addSubMenu( 
			'MY_MUSIC',
			'PLUGIN_NAPSTER_MY_NAPSTER_LIBRARY',
			$my_menu,
		);
		
		# Add as top-level item choice
		Slim::Buttons::Home::addMenuOption(
			'PLUGIN_NAPSTER_MY_NAPSTER_LIBRARY',
			$my_menu,
		);
		
		# Setup additional CLI methods for this menu
		$class->initCLI(
			feed         => Slim::Networking::SqueezeNetwork->url('/api/napster/v1/opml/menu?menu=favorites'),
			tag          => 'napster_library',
			menu         => 'my_music',
			display_name => 'PLUGIN_NAPSTER_MY_NAPSTER_LIBRARY',
		);
	}
	
	if ( main::WEBUI ) {
		# Add a function to view trackinfo in the web
		Slim::Web::Pages->addPageFunction( 
			'plugins/napster/trackinfo.html',
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
					feed    => Slim::Plugin::Napster::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'plugins/napster/trackinfo.html',
					title   => 'Napster Track Info',
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}
}

sub getDisplayName () {
	return 'PLUGIN_NAPSTER_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

# SLIM_SERVICE
sub myLibraryMode {
	my ( $class, $client, $method ) = @_;

	if ($method eq 'pop') {

		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my $name = 'PLUGIN_NAPSTER_MY_NAPSTER_LIBRARY';
	
	my %params = (
		header   => $name,
		modeName => $name,
		url      => $class->feed() . '/menu?menu=favorites',
		title    => $client->string( $name ),
		timeout  => 35,
	);

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );

	# we'll handle the push in a callback
	$client->modeParam( handledTransition => 1 );
}
# /SLIM_SERVICE

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	return unless $client;
	
	# Only show if in the app list
	return unless $client->isAppEnabled('napster');
	
	my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
	my $album  = $track->remote ? $remoteMeta->{album}  : ( $track->album ? $track->album->name : undef );
	my $title  = $track->remote ? $remoteMeta->{title}  : $track->title;
	
	my $snURL = Slim::Networking::SqueezeNetwork->url(
		'/api/napster/v1/opml/context?artist='
			. uri_escape_utf8($artist)
			. '&album='
			. uri_escape_utf8($album)
			. '&track='
			. uri_escape_utf8($title)
	);
	
	if ( $artist && ( $album || $title ) ) {
		return {
			type      => 'link',
			name      => $client->string('PLUGIN_NAPSTER_ON_NAPSTER'),
			url       => $snURL,
			favorites => 0,
		};
	}
}

1;
