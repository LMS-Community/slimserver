package Slim::Plugin::ExtendedBrowseModes::Settings;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
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
use List::Util qw(max);

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
my $log   = logger('prefs');
my $prefs = preferences('plugin.extendedbrowsemodes');
my $serverPrefs = preferences('server');

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

	# if we're called from the client prefs, we've already saved the client prefs
	if ($params->{'saveSettings'} && !$class->needsClient) {
		# custom role handling
		my $currentRoles = $serverPrefs->get('userDefinedRoles');

		my $id = 20;
		foreach (keys %{ $currentRoles }) {
			$id = max($id, $currentRoles->{$_}->{id});
		}
		$id++;

		my $customTags = {};
		my $changed = 0;

		foreach my $pref (keys %{$params}) {
			if ($pref =~ /(.*)_tag$/) {
				my $key = $1;
				my $tag = uc($params->{$pref});

				if ( $tag ) {
					$customTags->{$tag} = {
						name => $params->{$key . '_name'} || $tag,
						id => $currentRoles->{$tag} ? $currentRoles->{$tag}->{id} : $id++,
						include => $params->{$key . '_include'},
					};
					if ( !$currentRoles->{$tag}
						|| $currentRoles->{$tag}
							&& ( $currentRoles->{$tag}->{name} ne $customTags->{$tag}->{name} || $currentRoles->{$tag}->{include} ne $customTags->{$tag}->{include} ) ) {
						Slim::Utils::Strings::storeExtraStrings([{
							strings => { EN => $customTags->{$tag}->{name}},
							token   => $tag,
						}]);
						$changed = 1;
					}
				}
			}
		}

		foreach my $old (keys %{$currentRoles}) {
			$changed = 1 if !$customTags->{$old};
		}

		if ( $changed ) {
			$serverPrefs->set('userDefinedRoles', $customTags);
		}

		# browse menu handling
		my $menus = $prefs->get('additionalMenuItems');

		for (my $i = 1; defined $params->{"id$i"}; $i++) {

			if ( $params->{"delete$i"} ) {
				Slim::Menu::BrowseLibrary->deregisterNode($params->{"id$i"});

				# remove prefs related to this menu item
				foreach my $clientPref ( $serverPrefs->allClients ) {
					$clientPref->remove('disabled_' . $params->{"id$i"});
				}
				$serverPrefs->remove('disabled_' . $params->{"id$i"});

				$menus = [ grep { $_->{id} ne $params->{"id$i"} } @$menus ];
				next;
			}

			my ($menu) = $params->{"id$i"} eq '_new_' ? {} : grep { $_->{id} eq $params->{"id$i"} } @$menus;

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
				$menu->{id} =~ s/^(?:myMusicAlbums|myMusicArtists|myMusicWorks)//;

				# use the timestamp part of the id to make the sort order stick
				my ($ts)  = $menu->{id};
				$ts =~ s/\D//g;

				if ( $feedType eq 'albums' ) {
					$menu->{id}     = 'myMusicAlbums' . $menu->{id} if $menu->{id} !~ /^myMusic/;
					$menu->{weight} = "25.$ts" * 1;
				}
				elsif ( $feedType eq 'works' ) {
					$menu->{id}     = 'myMusicWorks' . $menu->{id} if $menu->{id} !~ /^myMusic/;
					$menu->{weight} = "20.$ts" * 1;
				}
				else {
					$menu->{id}     = 'myMusicArtists' . $menu->{id} if $menu->{id} !~ /^myMusic/;
					$menu->{weight} = "15.$ts" * 1;
				}

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

	$class->SUPER::handler($client, $params);
}

sub beforeRender {
	my ($class, $params, $client) = @_;

	$params->{genre_list} = [ sort map { $_->name } Slim::Schema->search('Genre')->all ];
	$params->{roles} = [ Slim::Schema::Contributor->contributorRoles ];
	$params->{release_types} = Slim::Schema::Album->releaseTypes;
	$params->{customTags} = $serverPrefs->get('userDefinedRoles');
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

	my $clientPrefs = $serverPrefs->client($client) if $class->needsClient;

	my %ids;
	$params->{menu_items} = [ map {
		$ids{$_->{id}}++;
		$_->{enabled} = $clientPrefs ? ($clientPrefs->get('disabled_' . $_->{id}) ? 0 : 1) : 1;
		$_;
	} @{Storable::dclone($prefs->get('additionalMenuItems'))}, { id => '_new_' } ];

	unshift @{$params->{menu_items}}, map { {
		name => $_->{name},
		id   => $_->{id},
		enabled => $clientPrefs ? ($clientPrefs->get('disabled_' . $_->{id}) ? 0 : 1) : 1,
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
