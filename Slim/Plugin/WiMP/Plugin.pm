package Slim::Plugin::WiMP::Plugin;

use strict;
use base qw(Slim::Plugin::OPMLBased);
use URI::Escape qw(uri_escape_utf8);

use Slim::Plugin::WiMP::ProtocolHandler;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.tidal',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_WIMP_MODULE_NAME',
} );

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		wimp => 'Slim::Plugin::WiMP::ProtocolHandler'
	);
	
	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr/squeezenetwork\.com.*\/wimp\//, 
		sub { return $class->_pluginDataFor('icon'); }
	);

	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url( '/api/wimp/v1/opml' ),
		tag    => 'wimp',
		menu   => 'music_services',
		weight => 35,
		is_app => 1,
	);
	
	# Track Info item
	Slim::Menu::TrackInfo->registerInfoProvider( wimp => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );
	
	if ( main::WEBUI ) {
		# Add a function to view trackinfo in the web
		Slim::Web::Pages->addPageFunction( 
			'plugins/wimp/trackinfo.html',
			sub {
				my $client = $_[0];
				my $params = $_[1] || {};
				
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
					feed    => Slim::Plugin::WiMP::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'plugins/wimp/trackinfo.html',
					title   => 'TIDAL Track Info',
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}
}

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;

	return unless $client;

	# Only show if in the app list
	return unless $client->isAppEnabled('wimp');
	
	my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
	my $album  = $track->remote ? $remoteMeta->{album}  : ( $track->album ? $track->album->name : undef );
	my $title  = $track->remote ? $remoteMeta->{title}  : $track->title;
	
	if ( $artist || $album || $title ) {
	
		my $snURL = Slim::Networking::SqueezeNetwork->url(
			'/api/wimp/v1/opml/context?artist=' . uri_escape_utf8($artist)
			. '&album=' . uri_escape_utf8($album)
			. '&track='	. uri_escape_utf8($title)
		);

		return {
			type      => 'link',
			name      => $client->string('PLUGIN_WIMP_ON_WIMP'),
			url       => $snURL,
			favorites => 0,
		};
	}
}

sub getDisplayName {
	return 'PLUGIN_WIMP_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

1;
