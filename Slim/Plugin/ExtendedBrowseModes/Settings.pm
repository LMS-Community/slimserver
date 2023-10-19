package Slim::Plugin::ExtendedBrowseModes::Settings;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);
use Storable;

use Slim::Music::VirtualLibraries;
use Slim::Plugin::ExtendedBrowseModes::Plugin;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

use constant AUDIOBOOKS_MENUS => [{
	name    => 'PLUGIN_EXTENDED_BROWSEMODES_AUDIOBOOKS',
	params  => { library_id => -1 },
	feed    => 'albums',
	id      => 'myMusicAlbumsAudiobooks',
	weight  => 14,
	enabled => 0,
},{
	name    => 'PLUGIN_EXTENDED_BROWSEMODES_AUTHORS',
	params  => { library_id => -1 },
	feed    => 'artists',
	id      => 'myMusicArtistsAudiobooks',
	weight  => 15,
	enabled => 0,
}];

my $prefs = preferences('plugin.extendedbrowsemodes');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_EXTENDED_BROWSEMODES');
}

sub prefs {
	return ( $prefs, qw(enableLosslessPreferred enableAudioBooks audioBooksGenres) );
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/ExtendedBrowseModes/settings/browsemodes.html');
}

sub handler {
	my ($class, $client, $params) = @_;

	my $serverPrefs = $class->getServerPrefs($client);

	if ($params->{'saveSettings'}) {
		my $menus = $prefs->get('additionalMenuItems');

		for (my $i = 1; defined $params->{"id$i"}; $i++) {

			if ( $params->{"delete$i"} ) {
				Slim::Menu::BrowseLibrary->deregisterNode($params->{"id$i"});
				my $serverPrefs = preferences('server');

				# remove prefs related to this menu item
				foreach my $clientPref ( $serverPrefs->allClients ) {
					$clientPref->remove('disabled_' . $params->{"id$i"});
				}
				$serverPrefs->remove('disabled_' . $params->{"id$i"});

				$menus = [ grep { $_->{id} ne $params->{"id$i"} } @$menus ];
				next;
			}

			my ($menu) = $params->{"id$i"} eq '_new_' ? {} : grep { $_->{id} eq $params->{"id$i"} } @$menus;

			if ( $class->needsClient && $serverPrefs ) {
				$serverPrefs->set('disabled_' . $params->{"id$i"}, $params->{"enabled$i"} ? 0 : 1);
			}

			delete $menu->{enabled} if $serverPrefs;

			next unless $params->{"name$i"} && $params->{"feed$i"} && ($params->{"roleid$i"} || $params->{"releasetype$i"} || $params->{"genreid$i"} || $params->{"libraryid$i"});

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
				Slim::Menu::BrowseLibrary->deregisterNode($params->{"id$i"});

				my $oldId = $menu->{id} = $params->{"id$i"};
				$menu->{id} =~ s/^(?:myMusicAlbums|myMusicArtists)//;

				# use the timestamp part of the id to make the sort order stick
				my ($ts)  = $menu->{id};
				$ts =~ s/\D//g;

				if ( $feedType eq 'albums' ) {
					$menu->{id}     = 'myMusicAlbums' . $menu->{id} if $menu->{id} !~ /^myMusic/;
					$menu->{weight} = "25.$ts" * 1;
				}
				else {
					$menu->{id}     = 'myMusicArtists' . $menu->{id} if $menu->{id} !~ /^myMusic/;
					$menu->{weight} = "15.$ts" * 1;
				}

				# need to migrate the enabled flag
				my $serverPrefs = preferences('server');

				# remove prefs related to this menu item
				foreach my $clientPref ( $serverPrefs->allClients ) {
					my $oldPref = $clientPref->get('disabled_' . $oldId);
					$clientPref->remove('disabled_' . $oldId);
					$clientPref->set('disabled_' . $menu->{id}, $oldPref);
				}
				$serverPrefs->remove('disabled_' . $oldId);
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

			if ($params->{"releasetype$i"}) {
				$menu->{params}->{release_type} = $params->{"releasetype$i"};
			}
			else {
				delete $menu->{params}->{release_type};
			}

			if ($params->{"genreid$i"}) {
				$menu->{params}->{genre_id} = $params->{"genreid$i"};
			}
			else {
				delete $menu->{params}->{genre_id};
			}

			if ($params->{"libraryid$i"}) {
				$menu->{params}->{library_id} = $params->{"libraryid$i"};
			}
			else {
				delete $menu->{params}->{library_id};
			}
		}

		if ($params->{pref_enableAudioBooks} && !$prefs->get('enableAudioBooks') && $params->{pref_audioBooksGenres}) {
			$params->{'needsAudioBookUpdate'} = 1;
		}
		elsif (!$params->{pref_enableAudioBooks} && $prefs->get('enableAudioBooks')) {
			my $libraryId = Slim::Music::VirtualLibraries->getRealId(Slim::Plugin::ExtendedBrowseModes::Libraries::AUDIOBOOK_LIBRARY_ID);
			my %ids = map {
				Slim::Menu::BrowseLibrary->deregisterNode($_->{id});
				$_->{id} => 1;
			} @{AUDIOBOOKS_MENUS()};

			$menus = [ grep {
				!($ids{$_->{id}} && $_->{params}->{library_id} && $_->{params}->{library_id} eq $libraryId)
			} @$menus ];
		}

		$prefs->set('additionalMenuItems', $menus);
	}

	$params->{genre_list} = [ sort map { $_->name } Slim::Schema->search('Genre')->all ];
	$params->{roles} = [ Slim::Schema::Contributor->contributorRoles ];
	$params->{release_types} = Slim::Schema::Album->releaseTypes;

	$class->SUPER::handler($client, $params);
}

sub getServerPrefs {}


sub beforeRender {
	my ($class, $params, $client) = @_;

	$params->{libraries} = {};

	if ($params->{'needsAudioBookUpdate'}) {
		my $menus = $prefs->get('additionalMenuItems');
		my $libraryId = Slim::Music::VirtualLibraries->getRealId(Slim::Plugin::ExtendedBrowseModes::Libraries::AUDIOBOOK_LIBRARY_ID);

		foreach my $audioBookMenu (@{Storable::dclone(AUDIOBOOKS_MENUS)}) {
			if (!grep { $_->{id} eq $audioBookMenu->{id} } @$menus) {
				$audioBookMenu->{params}->{library_id} = $libraryId;
				$audioBookMenu->{name} = string($audioBookMenu->{name});
				push @$menus, $audioBookMenu;
			}
		}

		$prefs->set('additionalMenuItems', $menus);
	}

	my $serverPrefs = $class->getServerPrefs($client);

	my %ids;
	$params->{menu_items} = [ map {
		$ids{$_->{id}}++;
		$_->{enabled} = $serverPrefs ? ($serverPrefs->get('disabled_' . $_->{id}) ? 0 : 1) : 1;
		$_;
	} @{Storable::dclone($prefs->get('additionalMenuItems'))}, { id => '_new_' } ];

	unshift @{$params->{menu_items}}, map { {
		name => $_->{name},
		id   => $_->{id},
		enabled => $serverPrefs ? ($serverPrefs->get('disabled_' . $_->{id}) ? 0 : 1) : 1,
	} } sort {
		$a->{weight} <=> $b->{weight}
	# don't allow to disable some select browse menus
	} grep {
		!$ids{$_->{id}}
	} @{Slim::Menu::BrowseLibrary->_getNodeList()}, {
		id => Slim::Plugin::ExtendedBrowseModes::Plugin->tag,
		name => Slim::Plugin::ExtendedBrowseModes::Plugin->getDisplayName,
		weight => Slim::Plugin::ExtendedBrowseModes::Plugin->weight,
	} if $class->needsClient;

	my $libraries = Slim::Music::VirtualLibraries->getLibraries();
	while (my ($k, $v) = each %$libraries) {
		$params->{libraries}->{$k} = $v->{name};
	}

	# we always set the genres to the localized default if empty
	$params->{prefs}->{audioBooksGenres} ||= $params->{prefs}->{pref_audioBooksGenres} ||= string('PLUGIN_EXTENDED_BROWSEMODES_AUDIOBOOK_GENRES');
}

1;

__END__
