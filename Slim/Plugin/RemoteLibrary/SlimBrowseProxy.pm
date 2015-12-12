package Slim::Plugin::RemoteLibrary::SlimBrowseProxy;

=pod

This is a very basic SlimBrowse interpreter. It's just good enough to proxy
music browse requests to a remote server, and translate them into something
we can use with locally connected players.

=cut

use strict;

use JSON::XS::VersionOneAndTwo;
use Storable qw(dclone);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;

$Slim::Plugin::RemoteLibrary::Plugin::REMOTE_BROWSE_CLASS = __PACKAGE__;

my $log = logger('plugin.remotelibrary');

my %passthroughItems = (
	actions => 1,
);

my %passthroughBaseItems = (
	base => 'base',
	count => 'total',
	offset => 'offset',
	window => 'window',
);

my %players;

sub getServerMenuItem {
	my ($class, $server) = @_;
	
	my $baseUrl = $server->{baseUrl};
	
	# for every server try to get a player, we'll need it to get the menus
	_remoteRequest($baseUrl, ['', ['player', 'id', '0', '?']], sub {
		my $results = shift || {};
		if (my $id = $results->{_id}) {
			$players{$baseUrl} = $id;
		}
		else {
			delete $players{$baseUrl};
		}
	}) unless $players{$baseUrl};
	
	# create menu item
	return {
		name => $server->{name},
		url  => \&_getRemoteMenu,
		passthrough => [{
			remote_library => Slim::Networking::Discovery::Server::getWebHostAddress($_),
		}],
	};
}

# get the remote library's Home menu
sub _getRemoteMenu {
	my ($client, $callback, $args, $pt) = @_;
	
	my $baseUrl = $pt->{remote_library} || $client->pluginData('baseUrl');
	$client->pluginData( baseUrl => $baseUrl );
	
	my $knownBrowseMenus = Slim::Plugin::RemoteLibrary::Plugin::getKnownBrowseMenus();
	
	# TODO - fall back to basic menu if we can't get the menu from the remote server
	_remoteRequest($baseUrl, 
		[ $players{$baseUrl}, ['menu', 0, 999, 'direct:1'] ], 
		sub {
			my $results = shift || {};
			
			my @items;
			foreach ( @{ $results->{item_loop} || [] } ) {
				# we only use the My Music menu at this point
				next unless $_->{node} eq 'myMusic';
				
				next unless $knownBrowseMenus->{$_->{id}} || $_->{id} =~ /(?:myMusicArtists|myMusic.*Albums)/;
				
				push @items, {
					name => $_->{text},
					icon => Slim::Plugin::RemoteLibrary::Plugin::proxiedImage($_, $baseUrl),
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
				my $isAudio = ($item->{type} || '') eq 'audio' ? 1 : 0;
				my $newItem = {
					name => $item->{text},
					icon => Slim::Plugin::RemoteLibrary::Plugin::proxiedImage($item, $baseUrl),
					url => $isAudio ? Slim::Plugin::RemoteLibrary::Plugin::proxiedStreamUrl($item, $baseUrl) : \&_handleSlimBrowse,
					passthrough => [ {
						%$item,
						base => $base, 
					} ],
					playall => $isAudio,
					type => $item->{type},
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