package Slim::Plugin::RemoteLibrary::BrowseLibrary;

=pod

This is a small wrapper around Slim::Menu::BrowseLibrary to inject the remote_library
information. Slim::Menu::BrowseLibrary will use this to request information from a remote
server rather than the local database.

=cut

use strict;

use Slim::Menu::BrowseLibrary;

$Slim::Plugin::RemoteLibrary::Plugin::REMOTE_BROWSE_CLASS = __PACKAGE__;

sub getServerMenuItem {
	my ($class, $server) = @_;
	
	my $baseUrl = $server->{baseUrl};
	
	# create menu item
	return {
		name => $server->{name},
		url  => \&_getRemoteMenu,
		passthrough => [{
			remote_library => Slim::Networking::Discovery::Server::getWebHostAddress($_),
		}],
	};
}

sub _getRemoteMenu {
	my ($client, $callback, $args, $pt) = @_;
	
	my $baseUrl = $pt->{remote_library} || $client->pluginData('baseUrl');
	$client->pluginData( baseUrl => $baseUrl );
	
	my $knownBrowseMenus = Slim::Plugin::RemoteLibrary::Plugin::getKnownBrowseMenus();
	
	my @items;
	my $menuItems = Slim::Menu::BrowseLibrary::getJiveMenu($client);

	# make sure we only request items compatible with the remote server
	foreach ( @$menuItems ) {
		next unless $knownBrowseMenus->{$_->{id}} || $_->{id} =~ /(?:myMusicArtists|myMusic.*Albums)/;
		
		$_->{icon} = Slim::Plugin::RemoteLibrary::Plugin::proxiedImage($_, $baseUrl);
		$_->{url}  = \&Slim::Menu::BrowseLibrary::_topLevel;
		$_->{name} = $_->{text};
		
		my $params = {};
		if ($_->{actions} && $_->{actions}->{go} && $_->{actions}->{go}->{params}) {
			$params = $_->{actions}->{go}->{params};
		}

		$_->{passthrough} = [{
			%$params,
			remote_library => $baseUrl
		}];
		
		push @items, $_;
	}
	
	$callback->({
		items => [ sort { $a->{weight} <=> $b->{weight} } @items ]
	});
}


1;