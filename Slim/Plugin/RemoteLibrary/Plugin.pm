package Slim::Plugin::RemoteLibrary::Plugin;

=pod

Add a wrapper around Slim::Menu::BrowseLibrary to inject the remote_library information. 
Slim::Menu::BrowseLibrary will use this to request information from a remote server rather 
than the local database.

=cut

use base qw(Slim::Plugin::OPMLBased);

use strict;
use JSON::XS::VersionOneAndTwo;
use MIME::Base64 qw(encode_base64 decode_base64);

use Slim::Menu::BrowseLibrary;
use Slim::Plugin::RemoteLibrary::ProtocolHandler;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring string);

my $prefs = preferences('plugin.remotelibrary');

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

my %passwordProtected;

my $cache = Slim::Utils::Cache->new;

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		lms => 'Slim::Plugin::RemoteLibrary::ProtocolHandler'
	);

	# Custom proxy to let the remote server handle the resizing.
	# The remote server very likely already has pre-cached artwork.
	Slim::Web::ImageProxy->registerHandler(
		match => qr/remotelibrary\/[0-9a-z\-]{36}/i,
		func  => sub {
			my ($url, $spec) = @_;
			
			my ($remote_library, $remote_url) = $url =~ m|remotelibrary/(.*?)/(.*)|;

			my $baseUrl = $class->baseUrl($remote_library);
			
			$remote_url = $baseUrl . $remote_url;
			my ($ext) = $remote_url =~ s/(\.gif|jpe?g|png|bmp)$//i;
			$remote_url .= '_' . $spec if $spec;
			$remote_url .= $ext;
		
			return $remote_url;
		},
	);

	# tell Slim::Menu::BrowseLibrary where to get information for remote libraries from
	Slim::Menu::BrowseLibrary->registerRequestProxy(\&remoteRequest);
	Slim::Menu::BrowseLibrary->registerStreamProxy(\&_proxiedStreamUrl);
	Slim::Menu::BrowseLibrary->registerImageProxy(\&_proxiedImage);
	Slim::Menu::BrowseLibrary->registerPrefGetter(\&_getPref);
	
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
	
	foreach ( sort keys %$servers ) {
		
		next if Slim::Networking::Discovery::Server::is_self($_);
		
		my $uuid = Slim::Networking::Discovery::Server::getServerUUID($_);
		_getBrowsePrefs($uuid);
		
		# create menu item
		push @$items, {
			name => $_,
			url  => \&_getRemoteMenu,
			passthrough => [{
				remote_library => $uuid,
			}],
		};
	}
	
	$cb->({
		items => $items
	});
}

sub _getRemoteMenu {
	my ($client, $cb, $args, $pt) = @_;
	
	my $remote_library = $pt->{remote_library} || $client->pluginData('remote_library');
	$client->pluginData( remote_library => $remote_library );

	if ($passwordProtected{$remote_library}) {
		# XXX - can we pre-populate the input field with the known password?
		$cb->({
			items => [{
				name => cstring($client, 'PLUGIN_REMOTE_LIBRARY_PASSWORD_PROTECTED'),
				type => 'textarea'
			},{
				name => cstring($client, 'PLUGIN_REMOTE_LIBRARY_USERNAME'),
				type => 'search',
				url  => sub {
					my ($client, $cb, $args, $pt) = @_;
					
					$cb->({
						items => [{
							name => cstring($client, 'PLUGIN_REMOTE_LIBRARY_ENTER_PASSWORD'),
							type => 'textarea'
						},{
							name => cstring($client, 'PLUGIN_REMOTE_LIBRARY_PASSWORD'),
							type => 'search',
							url => \&_checkCredentials,
							passthrough => [{
								user => $args->{search},
								remote_library => $remote_library,
							}]
						}]
					})
				},
				passthrough => [{
					remote_library => $remote_library,
				}]
			}]
		});
	}
	else {
		$cb->( _extractBrowseMenu(Slim::Menu::BrowseLibrary::getJiveMenu($client), $remote_library) );
	}
}

sub _extractBrowseMenu {
	my ($menuItems, $remote_library) = @_;
	
	$menuItems ||= [];

	my @items;
	my $hasArtists;

	foreach ( @$menuItems ) {
		# we only use the My Music menu at this point
		next unless !$_->{node} || $_->{node} eq 'myMusic';
		
		# only allow for standard browse menus for now
		# /(?:myMusicArtists|myMusic.*Albums|myMusic.*Tracks)/;
		next unless $knownBrowseMenus->{$_->{id}} || $_->{id} =~ /(?:myMusicArtists)/;
		
		# some items require at least LMS 7.9
		if ( Slim::Utils::Versions->compareVersions(Slim::Networking::Discovery::Server::getServerVersion($remote_library), '7.9.0') < 0 ) {
			next if $_->{id} eq 'myMusicRandomAlbums';
		}
		
		$_->{icon} = _proxiedImage($_, $remote_library);
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
			remote_library => $remote_library
		}];
		
		push @items, $_;
	}
	
	return {
		items => [ sort { $a->{weight} <=> $b->{weight} } @items ]
	}
}

sub _checkCredentials {
	my ($client, $cb, $args, $pt) = @_;

	my $username = $pt->{user};
	my $password = $args->{search};
	my $remote_library = $pt->{remote_library};
	
	$prefs->set($remote_library, encode_base64(pack("u", "$username:$password"), ''));
	
	# Run a request against this server to test credentials
	remoteRequest($remote_library, 
		[ '', ['serverstatus', 0, 1 ] ],
		sub {
			my $result = shift || {};
			
			# we've successfully authenticated - remove this server from the blacklist
			delete $passwordProtected{$remote_library};

			$cb->({
				items => [{
					name => cstring($client, 'PLUGIN_REMOTE_LIBRARY_LOGIN_SUCCESS'),
					type => 'text'
				},{
					name => cstring($client, 'CONTINUE'),
					nextWindow => 'myMusic'
				}]
			});
		},
		sub {
			$cb->({
				items => [{
					name => cstring($client, 'PLUGIN_REMOTE_LIBRARY_LOGIN_FAILURE'),
					type => 'textarea',
				}]
			});
		}
	);
}

sub _proxiedStreamUrl {
	my ($item, $remote_library) = @_;
	
	my $id = $item->{id};
	$id ||= $item->{commonParams}->{track_id} if $item->{commonParams};
	
	my $url = 'lms://' . $remote_library . '/music/' . ($id || 0) . '/download';

	# XXX - presetParams is only being used by the SlimBrowseProxy. Can be removed in case we're going the BrowseLibrary path
	if ($item->{url} || $item->{presetParams}) {
		my $suffix = Slim::Music::Info::typeFromSuffix($item->{url} || $item->{presetParams}->{favorites_url} || '');
		$url .= ".$suffix" if $suffix;
	}
	
	return $url;
}

sub _proxiedImage {
	my ($item, $remote_library) = @_;

	my $image = $item->{'icon-id'} || $item->{icon} || $item->{image} || $item->{coverid};
	
	# some menu items are known locally - use local artwork, it's faster
	if ( my $id = $item->{id} ) {
		$id = 'myMusicAlbums' if $id =~ /^myMusicAlbums/;
		$id = 'myMusicArtists' if $id =~ /^myMusicArtists/;

		if ( my $image = $knownBrowseMenus->{$id} ) {
			$image = 'html/images/' . $image unless $image =~ m|/|;
			return $image;
		}
	}

	if ($image && $image =~ /^-?[\w\d]+$/) {
		$image = "music/$image/cover";
	}
	
	if ($image) {
		return join('/', 'imageproxy', 'remotelibrary', $remote_library, $image, 'image.png');
	}
}

# get some of the prefs we need for the browsing from the remote host
my @prefsFetcher;
sub _getBrowsePrefs {
	my ($serverId) = @_;
	
	my $cacheKey = $serverId . '_prefs';
	my $cached = $cache->get($cacheKey) || {};
	
	foreach my $pref ( 'noGenreFilter', 'noRoleFilter', 'useUnifiedArtistsList', 'composerInArtists', 'conductorInArtists', 'bandInArtists' ) {
		if (!defined $cached->{$pref} && !$passwordProtected{$serverId}) {
			push @prefsFetcher, sub {
				remoteRequest($serverId, 
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

sub baseUrl {
	my ($class, $remote_library) = @_;

	my $baseUrl = $remote_library =~ /^http/ ? $remote_library : Slim::Networking::Discovery::Server::getWebHostAddress($remote_library);

	if ( my $creds = $prefs->get($remote_library) ) {
		$creds = unpack(chr(ord("a") + 19 + print ""), decode_base64($creds));
		$baseUrl =~ s/^(http:\/\/)/$1$creds\@/;
	}
	
	return $baseUrl;
}

# Send a CLI command to a remote server
sub remoteRequest {
	my ($remote_library, $request, $cb, $ecb, $pt) = @_;

	$ecb ||= $cb;
	
	if ( !($remote_library && $request && ref $request && scalar @$request && $ecb) ) {
		$ecb->() if $ecb;
		return;
	}

	my $baseUrl = __PACKAGE__->baseUrl($remote_library);
	
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
	
			$cb->($res->{result}, $pt);
		},
		sub {
			my $http = shift;

			if ( ($http->error || $http->mess || '') =~ /\b401\b/ ) {
				$log->error( "$baseUrl is password protected? " . $http->error) unless $passwordProtected{$remote_library}++;
			}
			else {
				$log->error( "Failed to get data from $baseUrl ($postdata): " . ($http->error || $http->mess || Data::Dump::dump($http)) );
			}

			$ecb->(undef, $pt);
		},
		{
			timeout => 60,
		},
	)->post( $baseUrl . 'jsonrpc.js', $postdata );
}

1;
