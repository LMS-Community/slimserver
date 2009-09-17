package Slim::Plugin::Amazon::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

use URI::Escape qw(uri_escape_utf8);

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url( '/api/amazon/v1/opml' ),
		tag    => 'amazon',
		menu   => 'music_stores',
		weight => 30,
		is_app => 1,
	);
	
	# Track Info item
	Slim::Menu::TrackInfo->registerInfoProvider( amazon => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );
}

sub getDisplayName {
	return 'PLUGIN_AMAZON_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	return unless $client;
	
	# Only show if in the app list
	return unless $client->isAppEnabled('amazon');
	
	my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
	my $album  = $track->remote ? $remoteMeta->{album}  : ( $track->album ? $track->album->name : undef );
	my $title  = $track->remote ? $remoteMeta->{title}  : $track->title;
	
	my $snURL = '/api/amazon/v1/opml/context';
	
	# Check for amazon-specific metadata
	if ( my $amazon = $remoteMeta->{amazon} ) {
		$snURL .= '?album_asin='         . $amazon->{album_asin}
			  . '&album_asin_digital=' . $amazon->{album_asin_digital}
			  . '&song_asin_digital='  . $amazon->{song_asin_digital};
	}
	else {
		# Search by artist/album/track
		$snURL .= '?artist=' . uri_escape_utf8($artist)
			  . '&album='    . uri_escape_utf8($album)
			  . '&track='    . uri_escape_utf8($title)
			  . '&upc='      . $remoteMeta->{upc};
	}
	
	if ( $artist && ( $album || $title ) ) {
		return {
			type      => 'link',
			name      => $client->string('PLUGIN_AMAZON_ON_AMAZON'),
			url       => Slim::Networking::SqueezeNetwork->url($snURL),
			favorites => 0,
		};
	}
}

1;
