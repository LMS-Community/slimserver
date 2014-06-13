package Slim::Plugin::ExtendedBrowseModes::Settings;

# Logitech Media Server Copyright 2001-2014 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);
use Storable;

use Slim::Plugin::ExtendedBrowseModes::Plugin;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.extendedbrowsemodes');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_EXTENDED_BROWSEMODES');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/ExtendedBrowseModes/settings/browsemodes.html');
}

sub needsClient { 1 }

sub handler {
	my ($class, $client, $params) = @_;

	my $serverPrefs = preferences('server')->client($client);

	if ($params->{'saveSettings'}) {
		my $menus = $prefs->get('additionalMenuItems');
		
		for (my $i = 1; defined $params->{"id$i"}; $i++) {
			
			if ( $params->{"delete$i"} ) {
				Slim::Menu::BrowseLibrary->deregisterNode($params->{"id$i"});
				$menus = [ grep { $_->{id} ne $params->{"id$i"} } @$menus ];
				next;
			}

			my ($menu) = $params->{"id$i"} eq '_new_' ? {} : grep { $_->{id} eq $params->{"id$i"} } @$menus;

			# reguler menu items
			if (!$menu) {
				if ($params->{"enabled$i"}) {
					$serverPrefs->remove('disabled_' . $params->{"id$i"});
				}
				else {
					$serverPrefs->set('disabled_' . $params->{"id$i"}, 1);
				}
				next;
			}

			$menu->{enabled} = $params->{"enabled$i"} || 0;
			
			next unless $params->{"name$i"} && $params->{"feed$i"} && ($params->{"roleid$i"} || $params->{"genreid$i"});

			if ( $params->{"id$i"} eq '_new_' ) {
				
				$menu = {
					id => Time::HiRes::time(),
					enabled => 1,
				};
				
				$params->{"id$i"} = $menu->{id};
				
				push @$menus, $menu;
			}
			
			my $feedType = $params->{"feed$i"};
			if ($params->{"id$i"} !~ /\Q$feedType\E/i) {
				$serverPrefs->remove('disabled_' . $params->{"id$i"});
				Slim::Menu::BrowseLibrary->deregisterNode($params->{"id$i"});
				
				$menu->{id} = $params->{"id$i"}; 
				$menu->{id} =~ s/^(?:myMusicAlbums|myMusicArtists)//;

				if ( $params->{"feed$i"} eq 'albums' ) {
					$menu->{id}     = 'myMusicAlbums' . $menu->{id} if $menu->{id} !~ /^myMusic/;
					$menu->{weight} = 25;
				}
				else {
					$menu->{id}     = 'myMusicArtists' . $menu->{id} if $menu->{id} !~ /^myMusic/;
					$menu->{weight} = 15;
				}
			}
			
			foreach (qw(feed name)) {
				$menu->{$_} = $params->{$_ . $i};
			}
			
			if ($params->{"roleid$i"}) {
				$menu->{params}->{role_id} = $params->{"roleid$i"}; 
			}
			else {
				delete $menu->{params}->{role_id};
			}
			
			if ($params->{"genreid$i"}) {
				$menu->{params}->{genre_id} = $params->{"genreid$i"}; 
			}
			else {
				delete $menu->{params}->{genre_id};
			}
		}
		
		$prefs->set('additionalMenuItems', $menus);
	}

	$params->{genre_list} = [ map { $_->name } Slim::Schema->search('Genre')->all ];
	$params->{roles} = [ Slim::Schema::Contributor->contributorRoles ];

	my %ids;
	$params->{menu_items} = [ map {
		$ids{$_->{id}}++;
		$_;
	} @{Storable::dclone($prefs->get('additionalMenuItems'))}, { id => '_new_' } ];
	
	unshift @{$params->{menu_items}}, map { {
		name => $_->{name},
		id   => $_->{id},
		enabled => $serverPrefs->get('disabled_' . $_->{id}) ? 0 : 1,
	} } sort { 
		$a->{weight} <=> $b->{weight}
	# don't allow to disable some select browse menus
	} grep {
		#$_->{id} !~ /^(?:myMusicArtists|myMusicArtistsAlbumArtists|myMusicArtistsAllArtists|myMusicAlbums)$/ && 
		!$ids{$_->{id}}
	} @{Slim::Menu::BrowseLibrary->_getNodeList()}, { 
		id => Slim::Plugin::ExtendedBrowseModes::Plugin->tag,
		name => Slim::Plugin::ExtendedBrowseModes::Plugin->getDisplayName,
		weight => Slim::Plugin::ExtendedBrowseModes::Plugin->weight,
	};
	

	$class->SUPER::handler($client, $params);
}

1;

__END__
