package Slim::Plugin::RemoteLibrary::LMS;

# Logitech Media Server Copyright 2001-2016 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=pod

Add a wrapper around Slim::Menu::BrowseLibrary to inject the remote_library information. 
Slim::Menu::BrowseLibrary will use this to request information from a remote server rather 
than the local database.

=cut

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
my $log   = logger('plugin.remotelibrary');

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

sub init {
	my $class = shift;
	
	# get details about the manually added servers
	$class->getServerDetails(1);
	
	# update server details whenever the list of manually added LMS fails
	$prefs->setChange(sub {
		$class->getServerDetails();
	}, 'remoteLMS');
	
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
	Slim::Menu::BrowseLibrary->setRemoteLibraryHandler($class);
	
	Slim::Plugin::RemoteLibrary::Plugin->addRemoteLibraryProvider($class);
}

sub getLibraryList {
	return unless $prefs->get('useLMS');

	my %servers;
	my $items;
	
	# locally discovered servers
	my $servers = Slim::Networking::Discovery::Server::getServerList();
	foreach ( keys %$servers ) {
		$servers{ Slim::Networking::Discovery::Server::getServerUUID($_) } = $_;
	}
	
	my $otherServers = $prefs->get('remoteLMSDetails') || {};

	# manually addes servers
	foreach ( @{ $prefs->get('remoteLMS') || [] } ) {
		my $details = $otherServers->{$_} || next;
		$servers{$details->{uuid}} = $details->{name} || $_;
	}

	my $server_uuid = preferences('server')->get('server_uuid');
	
	while ( my ($uuid, $name) = each %servers ) {
		
		# ignore servers with invalid UUID, or ourselves
		next if !$uuid || $uuid eq $server_uuid || $uuid =~ /[^a-z\-\d]/i;
		
		main::DEBUGLOG && $log->is_debug && $log->debug("Using remote Logitech Media Server: $name");
		
		_getBrowsePrefs($uuid);
		
		# create menu item
		push @$items, {
			name => $name,
			type => 'link',
			url  => \&_getRemoteMenu,
			image => 'plugins/RemoteLibrary/html/lms.png',
			passthrough => [{
				remote_library => $uuid,
			}],
		};
	}
	
	return $items;
}

sub _getRemoteMenu {
	my ($client, $cb, $args, $pt) = @_;
	
	my $remote_library = $pt->{remote_library} || ($client && $client->pluginData('remote_library'));
	$client->pluginData( remote_library => $remote_library ) if $client;

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
			
			# older servers can't filter artists by role
			if ($_->{id} =~ /^myMusicArtists/ ) {
				next if $hasArtists;
				
				$_ = {
					actions => {
						go => {
								cmd => ["browselibrary", "items"],
								params => { menu => 1, mode => "artists" },
							},
						},
					homeMenuText => string('BROWSE_ARTISTS'),
					id => "myMusicArtists",
					text => string('BROWSE_BY_ARTIST'),
					weight => 10,
				};
				$hasArtists++;
			}
		}
		
		$_->{icon} = __PACKAGE__->proxiedImageUrl($_, $remote_library);
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
	__PACKAGE__->remoteRequest($remote_library, 
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

sub proxiedStreamUrl {
	my ($class, $item, $remote_library) = @_;
	
	my $id = $item->{id};
	$id ||= $item->{commonParams}->{track_id} if $item->{commonParams};
	
	my $url = 'lms://' . $remote_library . '/music/' . ($id || 0) . '/download';
	my $suffix;

	# We're using the content type as suffix, though this is not always the correct 
	# file extension. But we'll need it to be able to correctly transcode if needed.
	my $suffix = $item->{ct} || Slim::Music::Info::typeFromSuffix($item->{url});

	# transcode anything but mp3 if needed
	if ( $suffix ne 'mp3' ) {
		if ( $prefs->get('transcodeLMS') ) {
			$suffix = $prefs->get('transcodeLMS');
		}
		elsif ( !main::TRANSCODING ) {
			$suffix = 'flac' 
		}
	}
	
	$url .= ".$suffix";
	
	# m4a is difficult: it can be lossless (alac) or lossy (mp4)
	# you'll need an up to date remote server for this to work reliably
	if ( !$item->{ct} && $suffix eq 'mp4' ) {
		$log->error("Streaming m4a/mp4 files from remote source can be problematic. Make sure you're running the latest software on the remote server: $item->{url}");
	}
	
	return $url;
}

sub proxiedImageUrl {
	my ($class, $item, $remote_library) = @_;

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
				__PACKAGE__->remoteRequest($serverId, 
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

sub getPref {
	my ($class, $pref, $remote_library) = @_;
	
	if ( $remote_library && (my $cached = $cache->get($remote_library . '_prefs')) ) {
		return $cached->{$pref};
	}
}

sub baseUrl {
	my ($class, $remote_library) = @_;

	my $baseUrl;
	
	$baseUrl = $remote_library if $remote_library =~ /^http/;

	if (!$baseUrl) {
		my $serverDetails = $prefs->get('remoteLMSDetails');
		($baseUrl) = grep {
			$serverDetails->{$_} && lc($serverDetails->{$_}->{uuid}) eq lc($remote_library) 
		} @{ $prefs->get('remoteLMS') || [] };
	}

	$baseUrl ||= Slim::Networking::Discovery::Server::getWebHostAddress($remote_library);

	if ( my $creds = $prefs->get($remote_library) ) {
		$creds = unpack(chr(ord("a") + 19 + print ""), decode_base64($creds));
		$baseUrl =~ s/^(http:\/\/)/$1$creds\@/;
	}
	
	$baseUrl .= '/' unless $baseUrl =~ m|/$|;
	
	return $baseUrl;
}

# Send a CLI command to a remote server
sub remoteRequest {
	my ($class, $remote_library, $request, $cb, $ecb, $pt) = @_;

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
				$log->warn( "Failed to get data from $baseUrl ($postdata): " . ($http->error || $http->mess || Data::Dump::dump($http)) );
			}

			$ecb->(undef, $pt);
		},
		{
			timeout => 60,
		},
	)->post( $baseUrl . 'jsonrpc.js', $postdata );
}

sub getServerDetails {
	my ($class, $force) = @_;
	
	my $servers = $prefs->get('remoteLMS') || [];

	my @detailsQueries = (
		{ name => 'version', query => ['version', '?'], key => '_version' },
		{ name => 'name', query => ['pref', 'libraryname', '?'], key => '_p2' },
		{ name => 'uuid', query => ['pref', 'server_uuid', '?'], key => '_p2' },
	);
	
	foreach my $server ( @$servers ) {
		if (!$force) {
			my $details = $prefs->get('remoteLMSDetails') || {};
			next if $details->{$server};
		}
		
		foreach ( @detailsQueries ) {
			$class->remoteRequest($server, 
				['', $_->{query}],
				sub {
					my ($results, $pt) = @_;

					return unless $results && $pt && $pt->{server} && $pt->{name} && $pt->{key};
					
					my $server = $pt->{server};
					
					my $details = $prefs->get('remoteLMSDetails') || {};

					$details->{$server} ||= {};
					$details->{$server}->{$pt->{name}} = $results->{$pt->{key}};
					
					$prefs->set('remoteLMSDetails', $details);
				},
				# XXX - what to do in case of failure?
				sub {},
				{
					%$_,
					server => $server,
				}
			);
		}
	}
}

1;