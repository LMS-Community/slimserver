package Slim::Plugin::RemoteLibrary::Plugin;

use base qw(Slim::Plugin::OPMLBased);

use strict;

use Slim::Plugin::RemoteLibrary::ProtocolHandler;
use Slim::Utils::Log;

# replace with whatever other implementation we're going to try
#use Slim::Plugin::RemoteLibrary::SlimBrowseProxy;
use Slim::Plugin::RemoteLibrary::BrowseLibrary;

our $REMOTE_BROWSE_CLASS;

my $log = Slim::Utils::Log->addLogCategory( {
	'category'     => 'plugin.remotelibrary',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_REMOTE_LIBRARY_MODULE_NAME',
} );

# XXX - get this from Slim::Menu::BrowseLibrary?
my $knownBrowseMenus = {
	myMusic => 'mymusic.png',
	myMusicArtists => 'artists.png',
	myMusicAlbums => 'albums.png',
	myMusicGenres => 'genres.png',
	myMusicYears => 'years.png',
	myMusicNewMusic => 'newmusic.png',
	myMusicMusicFolder => 'musicfolder.png',
	myMusicPlaylists => 'playlists.png',
	myMusicSearch => 'search.png',
	myMusicSearchArtists => 'search.png',
	myMusicSearchAlbums => 'search.png',
	myMusicSearchSongs => 'search.png',
	myMusicSearchPlaylists => 'search.png',
#	randomplay => 'plugins/RandomPlay/html/images/icon.png',
};

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		lms => 'Slim::Plugin::RemoteLibrary::ProtocolHandler'
	);

	# Custom proxy to let the remote server handle the resizing.
	# The remote server very likely already has pre-cached artwork.
	Slim::Web::ImageProxy->registerHandler(
		match => qr/^http:lms/,
		func  => sub {
			my ($url, $spec) = @_;
			
			$url =~ s/http:lms/http/;
			$url =~ s/\.(gif|jpe?g|png|bmp)$//i;
			$url .= '_' . $spec if $spec;
		
			return $url;
		},
	);
	
	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => 'selectRemoteLibrary',
		node   => 'myMusic',
		menu   => 'browse',
		weight => 1000,
	)
}

sub getDisplayName () {
	return 'PLUGIN_REMOTE_LIBRARY_MODULE_NAME';
}

sub handleFeed {
	my ($client, $cb, $args) = @_;
	
	my $servers = Slim::Networking::Discovery::Server::getServerList();
	my $items = [];
	
	foreach ( keys %$servers ) {
		next if Slim::Networking::Discovery::Server::is_self(Slim::Networking::Discovery::Server::getServerAddress($_));
		
		my $server = {
			name => $_,
			baseUrl => Slim::Networking::Discovery::Server::getWebHostAddress($_),
		};
		
		push @$items, $REMOTE_BROWSE_CLASS->getServerMenuItem($server);
	}
	
	$cb->({
		items => $items
	});
}

sub proxiedStreamUrl {
	my ($item, $baseUrl) = @_;
	
	my $id = $item->{id};
	$id ||= $item->{commonParams}->{track_id} if $item->{commonParams};
	
	my $url = $baseUrl . 'music/' . ($id || 0) . '/download';
	$url =~ s/^http/lms/;

	# XXX - presetParams is only being used by the SlimBrowseProxy. Can be removed in case we're going the BrowseLibrary path
	if ($item->{url} || $item->{presetParams}) {
		my $suffix = Slim::Music::Info::typeFromSuffix($item->{url} || $item->{presetParams}->{favorites_url} || '');
		$url .= ".$suffix" if $suffix;
	}
	
	return $url;
}

sub proxiedImage {
	my ($item, $baseUrl) = @_;
	
	my $iconId = $item->{'icon-id'} || $item->{icon} || $item->{image};
	my $image;
	
	# some menu items are known locally - use local artwork, it's faster
	if ( !$iconId && (my $id = $item->{id}) ) {
		$id = 'myMusicAlbums' if $id =~ /^myMusicAlbums/;
		$id = 'myMusicArtists' if $id =~ /^myMusicArtists/;

		my $icon = $knownBrowseMenus->{$id};
		
		return 'html/images/' . $icon if $icon && $icon !~ m|/|;;
		
		$iconId = $icon;
	}

	if ($iconId && $iconId =~ /^-?[\w\d]+$/) {
		$iconId = "music/$iconId/cover";
	}
	
	if ($iconId) {
		my $image = $baseUrl . $iconId;
		$image =~ s/^http:/http:lms:/;
		return $image;	
	}
}

sub getKnownBrowseMenus {
	return $knownBrowseMenus;
}

1;
