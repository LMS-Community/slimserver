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
		weight => 30,
	);
	
	# Track Info item
	Slim::Menu::TrackInfo->registerInfoProvider( deezer => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );
	
	
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

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	return unless $client;
	
	my $artist = $track->remote ? $remoteMeta->{artist} : ( $track->artist ? $track->artist->name : undef );
	my $album  = $track->remote ? $remoteMeta->{album}  : ( $track->album ? $track->album->name : undef );
	my $title  = $track->remote ? $remoteMeta->{title}  : $track->title;
	
	my $snURL = '/api/deezer/v1/opml/context';

	# Search by artist/album/track
	$snURL .= '?artist=' . uri_escape_utf8($artist)
	  . '&album='    . uri_escape_utf8($album)
	  . '&track='    . uri_escape_utf8($title);
	
	if ( $artist || $album || $title ) {
		return {
			type      => 'link',
			name      => $client->string('PLUGIN_DEEZER_ON_DEEZER'),
			url       => Slim::Networking::SqueezeNetwork->url($snURL),
			favorites => 0,
		};
	}
}

1;
