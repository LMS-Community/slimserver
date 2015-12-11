package Slim::Plugin::RemoteLibrary::Plugin;

use base qw(Slim::Plugin::OPMLBased);

use strict;
use JSON::XS::VersionOneAndTwo;
use Storable qw(dclone);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Plugin::RemoteLibrary::ProtocolHandler;
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string cstring);

my $log = Slim::Utils::Log->addLogCategory( {
	'category'     => 'plugin.remotelibrary',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_REMOTE_LIBRARY_MODULE_NAME',
} );

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

my %players;
sub handleFeed {
	my ($client, $cb, $args) = @_;
	
	my $servers = Slim::Networking::Discovery::Server::getServerList();
	my $items = [];
	
	my $request = ['', ['player', 'id', '0', '?']];
	
	foreach ( keys %$servers ) {
		next if Slim::Networking::Discovery::Server::is_self(Slim::Networking::Discovery::Server::getServerAddress($_));
		
		my $baseUrl = Slim::Networking::Discovery::Server::getWebHostAddress($_);
		
		# for every server try to get a player, we'll need it to get the menus
		_remoteRequest($_, $request, sub {
			my $results = shift || {};
			if (my $id = $results->{_id}) {
				$players{$baseUrl} = $id;
			}
		}) unless $players{$baseUrl};
		
		# create menu item
		push @$items, {
			name => $_,
			url  => \&_getRemoteMenu,
			passthrough => [{
				remote_library => Slim::Networking::Discovery::Server::getWebHostAddress($_),
			}],
		};
	}
	
	$cb->({
		items => $items
	});
}

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

my %passthroughItems = (
	actions => 1,
);

my %passthroughBaseItems = (
	base => 'base',
	count => 'total',
	offset => 'offset',
	window => 'window',
);

# get the remote library's Home menu
sub _getRemoteMenu {
	my ($client, $callback, $args, $pt) = @_;
	
	my $baseUrl = $pt->{remote_library} || $client->pluginData('baseUrl');
	$client->pluginData( baseUrl => $baseUrl );
	
	# TODO - fall back to basic menu if we can't get the menu from the remote server
	_remoteRequest($baseUrl, 
		[ $players{$baseUrl}, ['menu', 0, 999, 'direct:1'] ], 
		sub {
			my $results = shift || {};
			
			my @items;
			foreach ( @{ $results->{item_loop} || [] }) {
				# we only use the My Music menu at this point
				next unless $_->{node} eq 'myMusic';
				
				next unless $knownBrowseMenus->{$_->{id}} || $_->{id} =~ /(?:myMusicArtists|myMusic.*Albums)/;
				
				push @items, {
					name => $_->{text},
					icon => _proxiedImage($_, $baseUrl),
					weight => $_->{weight},
					url => \&_handleSlimBrowse,
					passthrough => [ $_ ],
				}
			}
			
			$callback->({
				items => [ sort { $a->{weight} <=> $b->{weight} } @items ]
			});
		},
		$callback,
	);
}

sub _handleSlimBrowse {
	my ($client, $callback, $args, $pt) = @_;
	
	my $baseUrl = $client->pluginData('baseUrl');
	warn Data::Dump::dump($args, $pt);
	
	# merge base params
	$pt->{actions} ||= delete $pt->{base}->{actions} if $pt->{base};
	
	my $request = dclone($pt->{actions}->{go}->{cmd});

	my $index = $args->{index} || 0;
	my $quantity = $args->{quantity} || 200;
	
	push @$request, $index;
	push @$request, $quantity;
	
	while ( my ($k, $v) = each %{$pt->{actions}->{go}->{params} || {}} ) {
		push @$request, "$k:$v";
	}
	
	while ( my ($k, $v) = each %{$pt->{commonParams} || {}} ) {
		push @$request, "$k:$v";
	}

warn Data::Dump::dump($request);

	_remoteRequest($baseUrl, 
		[$client ? $client->id : '', $request],
		sub {
			my $results = shift || {};
			
			my $base = $results->{base};
			
			if ($base->{actions}) {
				$base->{actions} = { map { $_ => $base->{actions}->{$_} } grep { $_ !~ /^set-preset/ } keys %{$base->{actions}} };
			}
			
			my $items;
			foreach my $item ( @{ $results->{item_loop} || [] }) {
				my $newItem = {
					name => $item->{text},
					icon => _proxiedImage($item, $baseUrl),
					url => ($item->{type} || '') eq 'audio' ? _proxiedStreamUrl($item, $baseUrl) : \&_handleSlimBrowse,
					passthrough => [ {
						%$item,
						base => $base, 
					} ],
					type => $item->{type}
				};

				if ( my ($line1, $line2) = $item->{text} =~ /(.+?)\n(.+)/ ) {
					$newItem->{line1} = $line1;
					$newItem->{line2} = $line2;
				}
				
				push @$items, $newItem;
			}

			my $response = {
				items => $items 
			};
			
			foreach (keys %passthroughBaseItems) {
				$response->{$passthroughBaseItems{$_}} = $results->{$_} if $results->{$_};
			}

			$callback->($response);
		}
	);
}

sub _proxiedStreamUrl {
	my ($item, $baseUrl) = @_;
	
	my $id = $item->{id};
	$id ||= $item->{commonParams}->{track_id} if $item->{commonParams};
	
	my $url = $baseUrl . 'music/' . ($id || 0) . '/download';
	$url =~ s/^http/lms/;
	
	if ($item->{presetParams}) {
		my $suffix = Slim::Music::Info::typeFromSuffix($item->{presetParams}->{favorites_url} || '');
		$url .= ".$suffix" if $suffix;
	}
	
	return $url;
}

sub _proxiedImage {
	my ($item, $baseUrl) = @_;
	
	my $iconId = $item->{'icon-id'} || $item->{icon};
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
			timeout => 15,
		},
	)->post( $baseUrl . 'jsonrpc.js', $postdata );
}

1;
