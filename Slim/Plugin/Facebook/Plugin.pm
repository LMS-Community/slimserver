package Slim::Plugin::Facebook::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);

use Slim::Networking::SqueezeNetwork;

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url( '/api/facebook/v1/opml' ),
		tag    => 'facebook',
		is_app => 1,
	);
	
	# Track Info item
	Slim::Menu::TrackInfo->registerInfoProvider( facebook => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );
}

# Don't add this item to any menu
sub playerMenu { }

sub initCLI {
	my ( $class, %args ) = @_;
	
	$class->SUPER::initCLI( %args );
	
	# Facebook defines 2 SP screensavers:
	# My Facebook News Feed
	# My Facebook photos
	
	Slim::Control::Request::addDispatch(
		[ $args{tag}, 'screensaver_news' ],
		[ 1, 1, 1, \&screensaver_news ]
	);
	
	Slim::Control::Request::addDispatch(
		[ $args{tag}, 'screensaver_photos' ],
		[ 1, 1, 1, \&screensaver_photos ]
	);
}

# Extend initJive to setup screensavers
sub initJive {
	my ( $class, %args ) = @_;
	
	my $menu = $class->SUPER::initJive( %args );
	
	return if !$menu;
	
	$menu->[0]->{screensavers} = [
		{
			cmd         => [ $args{tag}, 'screensaver_news' ],
			stringToken => 'PLUGIN_FACEBOOK_SCREENSAVER_NEWS',
		},
		{
			cmd         => [ $args{tag}, 'screensaver_photos' ],
			stringToken => 'PLUGIN_FACEBOOK_SCREENSAVER_PHOTOS',
		},
	];
	
	return $menu;
}			

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	return unless $client;
	
	# Only show if in the app list
	return unless $client->isAppEnabled('facebook');
	
	my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
	my $album  = $track->remote ? $remoteMeta->{album}  : ( $track->album ? $track->album->name : undef );
	my $title  = $track->remote ? $remoteMeta->{title}  : $track->title;
	
	my $snURL = '/api/facebook/v1/opml/context';
	
	# Search by artist/album/track
	$snURL .= '?artist=' . uri_escape_utf8($artist)
		  . '&album='    . uri_escape_utf8($album)
		  . '&track='    . uri_escape_utf8($title)
		  . '&upc='      . ( $remoteMeta->{upc} || '' );
	
	if ( my $amazon = $remoteMeta->{amazon} ) {
		$snURL .= '&album_asin='         . $amazon->{album_asin}
			  . '&album_asin_digital=' . $amazon->{album_asin_digital}
			  . '&song_asin_digital='  . $amazon->{song_asin_digital};
	}
	
	if ( $artist && ( $album || $title ) ) {
		return {
			type      => 'link',
			name      => $client->string('PLUGIN_FACEBOOK_ON_FACEBOOK'),
			url       => Slim::Networking::SqueezeNetwork->url($snURL),
			favorites => 0,
		};
	}
}

### Screensavers

# Each call to a screensaver returns a new image + metadata to display
# {
#   image   => 'http://...',
#   caption => 'text',
# } 

sub screensaver_news {
	_screensaver_request( '/api/facebook/v1/screensaver/news', @_ );
}

sub screensaver_photos { 
	_screensaver_request( '/api/facebook/v1/screensaver/photos', @_ );
}

sub _screensaver_request {
	my $url     = shift;
	my $request = shift;
	my $client  = $request->client;
	
	$url = Slim::Networking::SqueezeNetwork->url($url);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_screensaver_ok,
		\&_screensaver_error,
		{
			client  => $client,
			request => $request,
			timeout => 35,
		},
	);
	
	$http->get( $url );
	
	$request->setStatusProcessing();
}

sub _screensaver_ok {
	my $http    = shift;
	my $request = $http->params('request');
	
	my $data = eval { from_json( $http->content ) };
	if ( $@ || $data->{error} || !$data->{image} ) {
		$http->error( $@ || $data->{error} );
		_screensaver_error( $http );
		return;
	}
	
	$request->addResult( data => [ $data ] );
	
	$request->setStatusDone();
}

sub _screensaver_error {
	my $http    = shift;
	my $error   = $http->error;
	my $request = $http->params('request');
	
	# Not sure what status to use here
	$request->setStatusBadParams();
}

1;
