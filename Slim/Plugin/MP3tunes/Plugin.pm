package Slim::Plugin::MP3tunes::Plugin;

# $Id$

# Browse MP3tunes via SqueezeNetwork

use strict;
use base qw(Slim::Plugin::OPMLBased);
use Date::Parse;

use Slim::Formats::RemoteMetadata;
use Slim::Networking::SqueezeNetwork;

sub initPlugin {
	my $class = shift;

	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr/(?:mysqueezebox\.com.*\/mp3tunes|mp3tunes\.com\/)/,
		sub { return $class->_pluginDataFor('icon'); }
	);

	$class->SUPER::initPlugin(
		feed           => Slim::Networking::SqueezeNetwork->url('/api/mp3tunes/v1/opml'),
		tag            => 'mp3tunes',
		menu           => 'music_services',
		weight         => 50,
		is_app         => 1,
	);
	
	Slim::Formats::RemoteMetadata->registerProvider(
		match => qr{mp3tunes\.com|mysqueezebox\.com/mp3tunes},
		func   => \&metaProvider,
	);
}

sub getDisplayName () {
	return 'PLUGIN_MP3TUNES_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

# If the HTTP protocol handler sees an mp3tunes X-Locker-Info header, it will
# pass it to us
sub setLockerInfo {
	my ( $class, $client, $url, $info ) = @_;
	
	if ( $info =~ /(.+) - (.+) - (\d+) - (.+)/ ) {
		my $artist   = $1;
		my $album    = $2;
		my $tracknum = $3;
		my $title    = $4;
		
		# DAR.fm has slightly different formatting: $title would be the same as the track no.
		# let's shuffle things around to get the recording title as the track title
		if ($artist && $title && $title + 0 == $tracknum) {
			$title = $artist;
			$artist = '';
			
			# DAR.fm appends the station name to the title - move it to the $artist value
			if ($title =~ s/ \((.*?)\)$//) {
				$artist = $1;
			}
			
			# try to localize the recording date
			if (my $date = Date::Parse::str2time($album)) {
				$album  = Slim::Utils::DateTime::shortDateF($date);
			}
		}
		
		my $cover;
		
		if ( $url =~ /hasArt=1/ ) {
			my ($id)  = $url =~ m/([0-9a-f]+\?sid=[0-9a-f]+)/;
			$cover    = "http://content.mp3tunes.com/storage/albumartget/$id";
		}
		
		$client->master->pluginData( currentTrack => {
			url      => $url,
			artist   => $artist,
			album    => $album,
			tracknum => $tracknum,
			title    => $title,
			cover    => $cover,
		} );
	}
}

sub getLockerInfo {
	my ( $class, $client, $url ) = @_;
	
	my $meta = $client->master->pluginData('currentTrack');
	
	if ( $meta->{url} eq $url ) {
		return $meta;
	}
	
	return;
}

sub metaProvider {
	my ( $client, $url ) = @_;
	
	my $icon = __PACKAGE__->_pluginDataFor('icon');
	my $meta = __PACKAGE__->getLockerInfo( $client, $url );
	
	if ( $meta ) {
		# Metadata for currently playing song
		return {
			artist   => $meta->{artist},
			album    => $meta->{album},
			tracknum => $meta->{tracknum},
			title    => $meta->{title},
			cover    => $meta->{cover} || $icon,
			icon     => $icon,
			type     => 'MP3tunes',
		};
	}
	else {
		# Metadata for items in the playlist that have not yet been played
	
		# We can still get cover art for items not yet played
		my $cover;
		if ( $url =~ /hasArt=1/ ) {
			my ($id)  = $url =~ m/([0-9a-f]+\?sid=[0-9a-f]+)/;
			$cover    = "http://content.mp3tunes.com/storage/albumartget/$id";
		}
	
		return {
			cover    => $cover || $icon,
			icon     => $icon,
			type     => 'MP3tunes',
		};
	}
}

1;
