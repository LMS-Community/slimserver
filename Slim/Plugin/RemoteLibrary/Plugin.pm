package Slim::Plugin::RemoteLibrary::Plugin;

=pod

Add a wrapper around Slim::Menu::BrowseLibrary to inject the remote_library information. 
Slim::Menu::BrowseLibrary will use this to request information from a remote server rather 
than the local database.

=cut

use base qw(Slim::Plugin::OPMLBased);

use strict;
use JSON::XS::VersionOneAndTwo;

use Slim::Menu::BrowseLibrary;
use Slim::Plugin::RemoteLibrary::ProtocolHandler;
use Slim::Utils::Cache;
use Slim::Utils::Log;

Slim::Menu::BrowseLibrary->registerStreamProxy(\&_proxiedStreamUrl);
Slim::Menu::BrowseLibrary->registerImageProxy(\&_proxiedImage);
Slim::Menu::BrowseLibrary->registerPrefGetter(\&_getPref);

my $log = Slim::Utils::Log->addLogCategory( {
	'category'     => 'plugin.remotelibrary',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_REMOTE_LIBRARY_MODULE_NAME',
} );

my $knownBrowseMenus = {
#	myMusic => 'mymusic.png',
	myMusicArtists => 'artists.png',
	myMusicAlbums => 'albums.png',
	myMusicGenres => 'genres.png',
	myMusicYears => 'years.png',
	myMusicNewMusic => 'newmusic.png',
	myMusicMusicFolder => 'musicfolder.png',
	myMusicPlaylists => 'playlists.png',
	myMusicRandomAlbums => 'plugins/ExtendedBrowseModes/html/randomalbums.png',
	myMusicSearch => 'search.png',
	myMusicSearchArtists => 'search.png',
	myMusicSearchAlbums => 'search.png',
	myMusicSearchSongs => 'search.png',
	myMusicSearchPlaylists => 'search.png',
#	randomplay => 'plugins/RandomPlay/html/images/icon.png',
};

my $cache = Slim::Utils::Cache->new;

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
		
		my $baseUrl = Slim::Networking::Discovery::Server::getWebHostAddress($_);

		_getBrowsePrefs($baseUrl);
		
		# create menu item
		push @$items, {
			name => $_,
			url  => \&_getRemoteMenu,
			passthrough => [{
				remote_library => $baseUrl,
			}],
		};
	}
	
	$cb->({
		items => $items
	});
}

sub _getRemoteMenu {
	my ($client, $callback, $args, $pt) = @_;
	
	my $baseUrl = $pt->{remote_library} || $client->pluginData('baseUrl');
	$client->pluginData( baseUrl => $baseUrl );
	
	$callback->( _extractBrowseMenu(Slim::Menu::BrowseLibrary::getJiveMenu($client), $baseUrl) );
}

sub _extractBrowseMenu {
	my ($menuItems, $baseUrl) = @_;
	
	$menuItems ||= [];

	my @items;

	foreach ( @$menuItems ) {
		# we only use the My Music menu at this point
		next unless !$_->{node} || $_->{node} eq 'myMusic';
		
		# only allow for standard browse menus for now
		# /(?:myMusicArtists|myMusic.*Albums|myMusic.*Tracks)/;
		next unless $knownBrowseMenus->{$_->{id}} || $_->{id} =~ /(?:myMusicArtists)/;
		
		$_->{icon} = _proxiedImage($_, $baseUrl);
		$_->{url}  = \&Slim::Menu::BrowseLibrary::_topLevel;
		$_->{name} = $_->{text};
		
		my $params = {};
		if ($_->{actions} && $_->{actions}->{go} && $_->{actions}->{go}->{params}) {
			$params = $_->{actions}->{go}->{params};
		}
		
		# we can't handle library views on remote servers
		next if $params->{library_id};

		$_->{passthrough} = [{
			%$params,
			remote_library => $baseUrl
		}];
		
		push @items, $_;
	}
	
	return {
		items => [ sort { $a->{weight} <=> $b->{weight} } @items ]
	}
}

sub _proxiedStreamUrl {
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

sub _proxiedImage {
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

# get some of the prefs we need for the browsing from the remote host
my @prefsFetcher;
sub _getBrowsePrefs {
	my ($baseUrl) = @_;
	
	my $cacheKey = $baseUrl . '_prefs';
	my $cached = $cache->get($cacheKey) || {};
	
	foreach my $pref ( 'noGenreFilter', 'noRoleFilter', 'useUnifiedArtistsList', 'composerInArtists', 'conductorInArtists', 'bandInArtists' ) {
		if (!$cached->{$pref}) {
			push @prefsFetcher, sub {
				_remoteRequest($baseUrl, 
					[ '', ['pref', $pref, '?' ] ],
					sub {
						my $result = shift || {};
						
						$cached->{$pref} = $result->{'_p2'} || 0;
						$cache->set($cacheKey, $cached, 3600);

						if (my $next = shift @prefsFetcher) {
							$next->();
						}	
					},
				);
			}
		}
	}
	
	if (my $next = shift @prefsFetcher) {
		$next->();
	}	
}

sub _getPref {
	my ($pref, $remote_library) = @_;
	
	if ( $remote_library && (my $cached = $cache->get($remote_library . '_prefs')) ) {
		return $cached->{$pref};
	}
}

# Send a CLI command to a remote server
sub _remoteRequest {
	my ($server, $request, $cb, $ecb) = @_;

	$ecb ||= $cb;
	
	if ( !($server && $request && ref $request && scalar @$request && $ecb) ) {
		$ecb->() if $ecb;
		return;
	}

	my $baseUrl = $server =~ /^http/ ? $server : Slim::Networking::Discovery::Server::getWebHostAddress($server);
	
	my $postdata = to_json({
		id     => 1,
		method => 'slim.request',
		params => $request,
	});
	
	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $http = shift;

			my $res = eval { from_json( $http->content ) };
		
			if ( $@ || ref $res ne 'HASH' ) {
				$log->error( $@ || 'Invalid JSON response: ' . $http->content );
				$ecb->();
				return;
			}

			$res ||= {};
	
			$cb->($res->{result});
		},
		sub {
			my $http = shift;
			$log->error( "Failed to get menu: " . ($http->error || $http->mess || Data::Dump::dump($http)) );
			$ecb->();
		},
		{
			timeout => 60,
		},
	)->post( $baseUrl . 'jsonrpc.js', $postdata );
}

1;
