package Slim::Plugin::MP3tunes::Plugin;

# $Id$

# Browse MP3tunes via SqueezeNetwork

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SqueezeNetwork;

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed           => Slim::Networking::SqueezeNetwork->url('/api/mp3tunes/v1/opml'),
		tag            => 'mp3tunes',
		'icon-id'      => 'html/images/ServiceProviders/mp3tunes.png',
		menu           => 'music_on_demand',
	);
}

sub playerMenu () {
	return 'MUSIC_ON_DEMAND';
}

sub getDisplayName () {
	return 'PLUGIN_MP3TUNES_MODULE_NAME';
}

# If the HTTP protocol handler sees an mp3tunes X-Locker-Info header, it will
# pass it to us
sub setLockerInfo {
	my ( $class, $client, $url, $info ) = @_;
	
	if ( $info =~ /(.+) - (.+) - (\d+) - (.+)/ ) {
		my $artist   = $1;
		my $album    = $2;
		my $tracknum = $3;
		my $title    = $4;
		my $cover;
		
		if ( $url =~ /hasArt=1/ ) {
			my ($id)  = $url =~ m/([0-9a-f]+\?sid=[0-9a-f]+)/;
			$cover    = "http://content.mp3tunes.com/storage/albumartget/$id";
		}
		
		$client->pluginData( currentTrack => {
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
	
	my $meta = $client->pluginData('currentTrack');
	
	if ( $meta->{url} eq $url ) {
		return $meta;
	}
	
	return;
}

1;
