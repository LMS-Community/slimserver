package Slim::Plugin::MP3tunes::Plugin;

# $Id$

# Browse MP3tunes via SqueezeNetwork

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SqueezeNetwork;

sub initPlugin {
	my $class = shift;

	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr/(?:squeezenetwork\.com.*\/mp3tunes|mp3tunes\.com\/)/,
		sub { return $class->_pluginDataFor('icon'); }
	);

	$class->SUPER::initPlugin(
		feed           => Slim::Networking::SqueezeNetwork->url('/api/mp3tunes/v1/opml'),
		tag            => 'mp3tunes',
		menu           => 'music_services',
		weight         => 40,
	);
	
	if ( main::SLIM_SERVICE ) {
		# Also add to MY_MUSIC menu
		my $menu = {
			useMode => sub { $class->setMode(@_) },
			header  => 'PLUGIN_MP3TUNES_MODULE_NAME',
		};
		
		Slim::Buttons::Home::addSubMenu(
			'MY_MUSIC',
			'PLUGIN_MP3TUNES_MODULE_NAME',
			$menu,
		);
		
		# Setup additional CLI methods for this menu
		$class->initCLI(
			feed => Slim::Networking::SqueezeNetwork->url('/api/mp3tunes/v1/opml'),
			tag  => 'mp3tunes_my_music',
			menu => 'my_music',
		);
	}
}

sub playerMenu () {
	return 'MUSIC_SERVICES';
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
