package Slim::Plugin::Flickr::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);

use Slim::Networking::SqueezeNetwork;

# SP screensavers
# XXX these user-required screensavers should be defined some other way
my @savers = qw(
	mine
	contacts
	favorites
	interesting
	recent
);

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url( '/api/flickr/v1/opml' ),
		tag    => 'flickr',
		is_app => 1,
	);
	
	# Track Info item
	Slim::Menu::TrackInfo->registerInfoProvider( flickr => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );
}

# Don't add this item to any menu
sub playerMenu { }

sub initCLI {
	my ( $class, %args ) = @_;
	
	$class->SUPER::initCLI( %args );
	
	for my $saver ( @savers ) {
		Slim::Control::Request::addDispatch(
			[ $args{tag}, 'screensaver_' . $saver ],
			[ 1, 1, 1, sub {
				_screensaver_request( "/api/flickr/v1/screensaver/$saver", @_ );
			} ]
		);
	}
}

# Extend initJive to setup screensavers
sub initJive {
	my ( $class, %args ) = @_;
	
	my $menu = $class->SUPER::initJive( %args );
	
	return if !$menu;
	
	$menu->[0]->{screensavers} = [];
	
	for my $saver ( @savers ) {
		push @{ $menu->[0]->{screensavers} }, {
			cmd         => [ $args{tag}, 'screensaver_' . $saver ],
			stringToken => 'PLUGIN_FLICKR_SCREENSAVER_' . uc($saver),
		};
	}
	
	return $menu;
}

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	return unless $client;
	
	# Only display on SP devices
	return unless $client->isa('Slim::Player::SqueezePlay') || $client->controlledBy eq 'squeezeplay';

	# Only show if in the app list
	return unless $client->isAppEnabled('flickr');
	
	my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
	
	if ( $artist ) {
		my $snURL = '/api/flickr/v1/opml/context';
		$snURL .= '?artist=' . uri_escape_utf8($artist);
		
		return {
			type      => 'slideshow',
			name      => $client->string('PLUGIN_FLICKR_ON_FLICKR'),
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
