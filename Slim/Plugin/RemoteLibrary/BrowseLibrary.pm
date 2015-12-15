package Slim::Plugin::RemoteLibrary::BrowseLibrary;

=pod

This is a small wrapper around Slim::Menu::BrowseLibrary to inject the remote_library
information. Slim::Menu::BrowseLibrary will use this to request information from a remote
server rather than the local database.

=cut

use strict;

use Slim::Menu::BrowseLibrary;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $cache = Slim::Utils::Cache->new;
my $log = logger('plugin.remotelibrary');
my $serverprefs = preferences('server');

$Slim::Plugin::RemoteLibrary::Plugin::REMOTE_BROWSE_CLASS = __PACKAGE__;
	
Slim::Menu::BrowseLibrary->registerStreamProxy(\&Slim::Plugin::RemoteLibrary::Plugin::proxiedStreamUrl);
Slim::Menu::BrowseLibrary->registerImageProxy(\&Slim::Plugin::RemoteLibrary::Plugin::proxiedImage);
Slim::Menu::BrowseLibrary->registerPrefGetter(\&_getPref);

sub getServerMenuItem {
	my ($class, $server) = @_;
	
	_getBrowsePrefs($server->{baseUrl});
	
	# create menu item
	return {
		name => $server->{name},
		url  => \&_getRemoteMenu,
		passthrough => [{
#			name => $server->{name},
			remote_library => $server->{baseUrl},
		}],
	};
}

sub _getRemoteMenu {
	my ($client, $callback, $args, $pt) = @_;
	
	my $baseUrl = $pt->{remote_library} || $client->pluginData('baseUrl');
	$client->pluginData( baseUrl => $baseUrl );
	
# XXX - we don't currently grab the browse menu from the remote server, as it's prone to errors and misunderstandings.
#	my $players = Slim::Networking::Discovery::Players::getPlayerList();
#
# We can't handle them all anyway, as some of them require local information. I'm leaving the code here, just in case...
#	if ( my ($player) = grep { $players->{$_}->{server} eq $pt->{name} } keys %$players ) {
#		# try to get the real browse menu from the remote server
#		Slim::Plugin::RemoteLibrary::Plugin::remoteRequest($baseUrl, 
#			[ $player, ['menu', 0, 999, 'direct:1'] ],
#			sub {
#				my $results = shift || {};
#				$callback->( _extractBrowseMenu($results->{item_loop} || [], $baseUrl) );
#			},
#			$callback,
#		);
#	}
#	else {
		$callback->( _extractBrowseMenu(Slim::Menu::BrowseLibrary::getJiveMenu($client), $baseUrl) );
#	}
}

sub _extractBrowseMenu {
	my ($menuItems, $baseUrl) = @_;
	
	$menuItems ||= [];

	my $knownBrowseMenus = Slim::Plugin::RemoteLibrary::Plugin::getKnownBrowseMenus();
	my @items;

	foreach ( @$menuItems ) {
		# we only use the My Music menu at this point
		next unless !$_->{node} || $_->{node} eq 'myMusic';
		
		# only allow for standard browse menus for now
		next unless $knownBrowseMenus->{$_->{id}}; # || $_->{id} =~ /(?:myMusicArtists|myMusic.*Albums|myMusic.*Tracks)/;
		
		$_->{icon} = Slim::Plugin::RemoteLibrary::Plugin::proxiedImage($_, $baseUrl);
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

# get some of the prefs we need for the browsing from the remote host
my @prefsFetcher;
sub _getBrowsePrefs {
	my ($baseUrl) = @_;
	
	my $cacheKey = $baseUrl . '_prefs';
	my $cached = $cache->get($cacheKey) || {};
	
	foreach my $pref ( 'noGenreFilter', 'noRoleFilter', 'useUnifiedArtistsList', 'composerInArtists', 'conductorInArtists', 'bandInArtists' ) {
		if (!$cached->{$pref}) {
			push @prefsFetcher, sub {
				Slim::Plugin::RemoteLibrary::Plugin::remoteRequest($baseUrl, 
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

1;