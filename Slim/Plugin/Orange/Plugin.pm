package Slim::Plugin::Orange::Plugin;

# $Id: Plugin.pm 10712 2011-06-29 10:26:15Z shaahul21 $

use strict;
use base qw(Slim::Plugin::OPMLBased);

use URI::Split qw(uri_split);
use Slim::Player::ProtocolHandlers;
use Slim::Plugin::Orange::Metadata;
use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Strings qw(cstring);

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.orange',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_ORANGE_LIVERADIO',
} );

sub initPlugin {
	my $class = shift;
	
	Slim::Plugin::Orange::Metadata->init();
	
	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr|mysqueezebox\.com.*/api/orange/|, 
		sub { $class->_pluginDataFor('icon') }
	);
	
	# Track Info handler
	Slim::Menu::TrackInfo->registerInfoProvider( infoOrange => (
		before => 'top',
		func   => \&trackInfoHandler,
	) );
	
	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url('/api/orange/v1/opml'),
		tag    => 'orange',
		menu   => 'radios',
		weight => 40,
		is_app => 1,
	);	
}

sub getDisplayName () {
	return 'PLUGIN_ORANGE_LIVERADIO';
}

# Don't add this item to any menu
sub playerMenu { }

sub trackInfoHandler {
	my ( $client, $url, $track ) = @_;
	
	my $items = [];
	
	if ( $url =~ m{^http://.*/api/orange/v1} ) {
		push @$items, {
			name => cstring($client, 'PLUGIN_ORANGE_OPTIONS'),
			url  => __PACKAGE__->trackInfoURL( $client, $url, 'orange_options' ),
		};
		push @$items , {
			name => cstring($client, 'PLUGIN_ORANGE_FAVORITES'),
			url  => __PACKAGE__->trackInfoURL( $client, $url, 'orange_favorites' ),
		};
	}
	
	return $items;
}

# URL used for CLI trackinfo queries
sub trackInfoURL {
	my ( $class, $client, $url, $type ) = @_;
	
	my ($scheme, $auth, $path, $query, $frag) = uri_split($url);

	$query .= '&type=' . $type;

	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		'/api/orange/v1/opml/trackinfo?' . $query
	);
	
	return $trackInfoURL;
}

1;
