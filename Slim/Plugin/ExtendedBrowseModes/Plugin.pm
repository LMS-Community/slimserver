package Slim::Plugin::ExtendedBrowseModes::Plugin;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::OPMLBased);
use Digest::MD5 qw(md5_hex);

use Slim::Menu::BrowseLibrary;
use Slim::Music::VirtualLibraries;
use Slim::Plugin::ExtendedBrowseModes::Libraries;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Text;

my $prefs = preferences('plugin.extendedbrowsemodes');
my $serverPrefs = preferences('server');

$prefs->init({
	additionalMenuItems => [{
		name    => string('PLUGIN_EXTENDED_BROWSEMODES_BROWSE_BY_COMPOSERS'),
		params  => { role_id => 'COMPOSER' },
		feed    => 'artists',
		id      => 'myMusicArtistsComposers',
		weight  => 12,
		enabled => 1,
	},{
		name    => string('PLUGIN_EXTENDED_BROWSEMODES_BROWSE_BY_CLASSICAL_MUSIC_BY_CONDUCTOR'),
		params  => { role_id => 'CONDUCTOR', genre_id => 'Classical' },
		feed    => 'artists',
		id      => 'myMusicArtistsConductors',
		weight  => 13,
		enabled => 0,
	},{
		name    => string('PLUGIN_EXTENDED_BROWSEMODES_BROWSE_BY_JAZZ_COMPOSERS'),
		params  => { role_id => 'COMPOSER', genre_id => 'Jazz' },
		feed    => 'artists',
		id      => 'myMusicArtistsJazzComposers',
		weight  => 13,
		enabled => 0,
	}],
	enableLosslessPreferred => 0,
});

$prefs->setChange( \&initMenus, 'additionalMenuItems' );
Slim::Control::Request::subscribe( sub { initMenus(@_) }, [['library'], ['changed']] );
Slim::Control::Request::subscribe( sub { initMenus(@_) }, [['rescan'], ['done']] );

$prefs->setChange( sub {
	__PACKAGE__->initLibraries($_[0], $_[1] || 0);
	__PACKAGE__->initLibraries('enableNoAudioBooks', $_[1] || 0) if $_[0] eq 'enableAudioBooks';
}, 'enableLosslessPreferred', 'enableAudioBooks' );

sub initPlugin {
	my ( $class ) = @_;

	if ( main::WEBUI ) {
		require Slim::Plugin::ExtendedBrowseModes::Settings;
		require Slim::Plugin::ExtendedBrowseModes::PlayerSettings;
		Slim::Plugin::ExtendedBrowseModes::Settings->new;
		Slim::Plugin::ExtendedBrowseModes::PlayerSettings->new;
	}

	$class->initMenus();
	Slim::Plugin::ExtendedBrowseModes::Libraries->initLibraries();

	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => 'selectVirtualLibrary',
		node   => 'myMusic',
		menu   => 'browse',
		weight => 100,
	);
}

sub handleFeed {
	my ($client, $cb, $args) = @_;

	my @items;
	my $libraries = Slim::Music::VirtualLibraries->getLibraries();

	my $currentLibrary = Slim::Music::VirtualLibraries->getLibraryIdForClient($client);

	my $bullet = "\x{2022} ";

	while (my ($k, $v) = each %$libraries) {
		my $count = Slim::Utils::Misc::delimitThousands(Slim::Music::VirtualLibraries->getTrackCount($k));

		my $libraryPrefix = '';
		if ($currentLibrary eq $k) {
			$libraryPrefix = $bullet;
			$currentLibrary = '';
		}

		my $name = Slim::Music::VirtualLibraries->getNameForId($k, $client);

		push @items, {
			name => $libraryPrefix . $name . sprintf(" ($count %s)", cstring($client, 'SONGS')),
			sortName => $name,
			type => 'outline',
			items => [{
				name => cstring($client, 'PLUGIN_EXTENDED_BROWSEMODES_USE_X', $name),
				url  => \&setLibrary,
				passthrough => [{
					library_id => $k,
				}],
				nextWindow => $args->{isControl} ? 'myMusic' : 'parent',
			},{
				name => cstring($client, 'DELETE'),
				url  => \&unregisterLibrary,
				passthrough => [{
					library_id => $k,
				}],
				nextWindow => $args->{isControl} ? 'myMusic' : 'parent',
			}]
		};
	}

	@items = sort { $a->{sortName} cmp $b->{sortName} } @items;

	# hard-coded item to reset the library view
	push @items, {
		name => ($currentLibrary ? "\x{2022} " : '') . cstring($client, 'PLUGIN_EXTENDED_BROWSEMODES_ALL_LIBRARY'),
		url  => \&setLibrary,
		passthrough => [{
			library_id => 0,
		}],
		nextWindow => $args->{isControl} ? 'myMusic' : 'parent',
	};

	$cb->({
		items => \@items,
	});
}

sub initLibraries {
	my ($class, $pref, $newValue) = @_;

	my $library = $pref;
	$library =~ s/^enable//;

	if ( defined $newValue && !$newValue ) {
		Slim::Music::VirtualLibraries->unregisterLibrary(lcfirst($library));
	}

	if ( $prefs->get($pref) ) {
		Slim::Plugin::ExtendedBrowseModes::Libraries->initLibraries();

		# if we were called on a onChange event, re-build the library
		Slim::Music::VirtualLibraries->rebuild($library) if $newValue;
	}
}

sub setLibrary {
	my ($client, $cb, $params, $args) = @_;

	if (!$client) {
		$cb->({
			items => [{
				name => string('NO_PLAYER_FOUND'),
			}]
		});
		return;
	}

	$serverPrefs->client($client)->set('libraryId', $args->{library_id});
	$serverPrefs->client($client)->remove('libraryId') unless $args->{library_id};

	$cb->({
		items => [{
			name => cstring($client, 'PLUGIN_EXTENDED_BROWSEMODES_USING_X', (Slim::Music::VirtualLibraries->getNameForId($args->{library_id}, $client) || cstring($client, 'PLUGIN_EXTENDED_BROWSEMODES_ALL_LIBRARY'))),
			showBriefly => 1,
		}]
	});

	# pre-cache totals
	Slim::Utils::Timers::setTimer(__PACKAGE__, Time::HiRes::time() + 0.1, sub {
		Slim::Schema->totals($client);
	});
}

sub unregisterLibrary {
	my ($client, $cb, $params, $args) = @_;

	Slim::Music::VirtualLibraries->unregisterLibrary($args->{library_id});

	$cb->({
		items => [{
			name => cstring($client, 'PLUGIN_EXTENDED_BROWSEMODES_DELETED'),
			showBriefly => 1,
		}]
	});
}

sub condition {
	my ($class, $client) = @_;

	return unless Slim::Music::VirtualLibraries->hasLibraries();

	return !$client || !$serverPrefs->client($_[1])->get('disabled_selectVirtualLibrary');
}

sub getDisplayName { 'VIRTUALLIBRARIES' }

sub initMenus {
	my @additionalStaticMenuItems = ({
		name         => 'PLUGIN_EXTENDED_BROWSEMODES_COMPILATIONS',
		params       => {
			mode => 'vaalbums',
			# we need to inject the latest VA ID
			artist_id => Slim::Schema->variousArtistsObject->id,
		},
		feed         => 'albums',
		id           => 'myMusicAlbumsVariousArtists',
		weight       => 22,
		static       => 1,		# this menu is not user-defined
		enabled      => 1,
	},{
		name         => 'PLUGIN_EXTENDED_BROWSEMODES_BROWSEFS',
		params       => {
			mode => 'filesystem',
		},
		feed         => \&_browseFS,
		id           => 'myMusicFileSystem',
		icon         => 'plugins/ExtendedBrowseModes/html/icon_folder.png',
		weight       => 75,
		static       => 1,
		nocache      => 1,
	},{
		name         => 'PLUGIN_EXTENDED_BROWSEMODES_RANDOM_ALBUMS',
		params       => {
			mode => 'randomalbums',
			sort => 'random',
		},
		feed         => \&_randomAlbums,
		id           => 'myMusicRandomAlbums',
		icon         => 'plugins/ExtendedBrowseModes/html/randomalbums.png',
		weight       => 21,
		static       => 1,
		nocache      => 1,
	});

	if (main::STATISTICS) {
		push @additionalStaticMenuItems, {
			name         => 'PLUGIN_EXTENDED_BROWSEMODES_TOP_TRACKS',
			params       => {
				mode   => 'toptracks',
				'sort' => 'sql=tracks_persistent.playcount DESC, tracks_persistent.lastplayed DESC, tracks.album, tracks.disc, tracks.tracknum',
				search => 'sql=tracks_persistent.playcount >= %s',
			},
			feed         => \&_hitlist,
			id           => 'myMusicTopTracks',
			icon         => 'plugins/ExtendedBrowseModes/html/icon_charts.png',
			weight       => 68,
			static       => 1,
			nocache      => 1,
		},{
			name         => 'PLUGIN_EXTENDED_BROWSEMODES_FLOP_TRACKS',
			params       => {
				mode   => 'floptracks',
				'sort' => 'sql=tracks_persistent.playcount ASC, tracks_persistent.lastplayed ASC, tracks.album, tracks.disc, tracks.tracknum',
				search => 'sql=tracks_persistent.playcount <= %s OR tracks_persistent.playcount IS NULL',
			},
			feed         => \&_hitlist,
			id           => 'myMusicFlopTracks',
			icon         => 'plugins/ExtendedBrowseModes/html/icon_charts.png',
			weight       => 69,
			static       => 1,
			nocache      => 1,
		};
	}

	foreach (@{$prefs->get('additionalMenuItems') || []}, @additionalStaticMenuItems) {
		__PACKAGE__->registerBrowseMode($_);
	}
}

sub registerBrowseMode {
	my ($class, $item) = @_;

	# create string token if it doesn't exist already
	my $nameToken = $class->registerCustomString($item->{name});

	# remove menu item before adding it back in - we might have changed its definition
	Slim::Menu::BrowseLibrary->deregisterNode($item->{id});

	foreach my $clientPref ( $serverPrefs->allClients ) {
		$clientPref->init({
			'disabled_' . $item->{id} => $item->{enabled} ? 0 : 1
		});
	}

	my $icon = $item->{icon};

	# replace feed placeholders
	my $feed;
	if ( ref $item->{feed} eq 'CODE' ) {
		$feed = $item->{feed};
	}
	elsif ( $item->{feed} =~ /\balbums$/ ) {
		$feed = \&Slim::Menu::BrowseLibrary::_albums;
		$icon = 'html/images/albums.png';
	}
	else {
		$feed = \&Slim::Menu::BrowseLibrary::_artists;
		$icon = 'html/images/artists.png';
	}

	my %params = map {
		my $v = Slim::Plugin::ExtendedBrowseModes::Libraries->valueToId($item->{params}->{$_}, $_);
		{ $_ => $v };
	} keys %{ $item->{params} || {} };

	Slim::Menu::BrowseLibrary->registerNode({
		type         => 'link',
		name         => $nameToken,
		params       => \%params,
		feed         => $feed,
		icon         => $icon,
		jiveIcon     => $icon,
		homeMenuText => $nameToken,
		condition    => $item->{condition} || \&Slim::Menu::BrowseLibrary::isEnabledNode,
		id           => $item->{id},
		weight       => $item->{weight},
		cache        => $item->{nocache} ? 0 : 1,
	});
}

sub registerCustomString {
	my ($class, $string) = @_;

	if ( !Slim::Utils::Strings::stringExists($string) ) {
		my $token = uc(Slim::Utils::Text::ignoreCase($string, 1));

		$token =~ s/\s/_/g;
		$token = 'PLUGIN_EXTENDED_BROWSEMODES_' . $token;

		Slim::Utils::Strings::storeExtraStrings([{
			strings => { EN => $string},
			token   => $token,
		}]) if !Slim::Utils::Strings::stringExists($token);

		return $token;
	}

	return $string;
}

sub _browseFS {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();

	Slim::Menu::BrowseLibrary::_generic($client, $callback, $args, 'readdirectory', ['folder:/', 'filter:foldersonly'],
		sub {
			my $results = shift;
			my $items = $results->{'fsitems_loop'};

			foreach (@$items) {
				if ($_->{'isfolder'}) {
					my $url = Slim::Utils::Misc::fileURLFromPath($_->{path});
					$url =~ s/^file/tmp/;
					$url .= '/' unless $url =~ m|/$|;

					$_->{'url'}         = \&Slim::Menu::BrowseLibrary::_bmf;
					$_->{'passthrough'} = [ { searchTags => [ "url:$url" ] } ];
					$_->{'itemActions'} = {
						info => {
							command     => ['folderinfo', 'items'],
							fixedParams => {url =>  $url},
						},
					};
				}
			}
			return { items => $items, sorted => 1 }, undef;
		},
	);
}

# Small wrapper around Slim::Menu::BrowseLibrary::_albums to add the simpleAlbumLink flag.
# We can't use the regular drill-down links in the web UI, as this would call the randomized
# list again, resulting in the wrong album being browsed into.
sub _randomAlbums {
	my ($client, $callback, $args, $pt) = @_;

	Slim::Menu::BrowseLibrary::_albums( $client, sub {
		my ($result) = @_;

		$result->{items} = [
			map {
				$_->{simpleAlbumLink} = 1;
				$_;
			} @{$result->{items}}
		] if $result->{items};

		$callback->(@_);
	}, $args, $pt );
}

# Use Slim::Menu::BrowseLibrary::_tracks to show a list of the most popular/unpopular tracks
my $countCache;
sub _hitlist { if (main::STATISTICS) {
	my ($client, $callback, $args, $pt) = @_;

	if (!$countCache) {
		require Tie::Cache::LRU::Expires;
		tie %$countCache, 'Tie::Cache::LRU::Expires', EXPIRES => 15, ENTRIES => 5;
	}

	# Don't get all tracks if there's a large number. Get the lowest playcount of the
	# top $maxPlaylistLength tracks. That's the minimum playcount we want to display.
	# This can be more than $maxPlaylistLength when there's more than one with that number of plays.
	my $minPlayCount = 1;
	my $totals = Slim::Schema->totals($client);

	if ( $totals->{track} > (my $maxPlaylistLength = $serverPrefs->get('maxPlaylistLength')) ) {

		my $orderBy = 'tracks_persistent.playcount DESC';

		if ($pt->{sort} =~ /sql=([^,]+)/) {
			$orderBy = $1;
			$minPlayCount = 0 if $orderBy =~ /ASC/;
		}

		my $cacheKey = md5_hex($orderBy . Slim::Music::VirtualLibraries->getLibraryIdForClient($client));

		if ( my $playCount = $countCache->{$cacheKey} ) {
			$minPlayCount = $playCount;
		}
		else {
			my $sql = qq{
				SELECT tracks_persistent.playcount
				FROM tracks_persistent
				JOIN tracks ON tracks.urlmd5 = tracks_persistent.urlmd5
			};

			my @p = ($maxPlaylistLength, 1);

			if ( my $libraryId = $pt->{library_id} ) {
				$sql .= qq{
					JOIN library_track ON library_track.track = tracks.id
					WHERE library_track.library = ?
				};
				unshift @p, $libraryId;
			}

			$sql .= qq{
				ORDER BY $orderBy
				LIMIT ?,?
			};

			my ($playCount) = Slim::Schema->dbh->selectrow_array( $sql, undef, @p );

			if ($playCount) {
				$minPlayCount = $playCount;
			};
		}

		$countCache->{$cacheKey} = $minPlayCount;
	}

	$pt->{search} = sprintf($pt->{search}, $minPlayCount) if $pt && $pt->{search};
	$args->{params}->{search} = sprintf($args->{params}->{search}, $minPlayCount) if $args && $args->{params} && $args->{params}->{search};

	Slim::Menu::BrowseLibrary::_tracks( $client, sub {
		my ($result) = @_;

		my $isWeb = $args->{isControl} && !($client && $client->controlledBy);

		$result->{items} = [
			map {
				my $playCount = sprintf(' (%s)', $_->{playcount} || 0);

				if ($isWeb) {
					$_->{web} ||= {};
					$_->{web}->{value} = "$playCount " . Slim::Music::TitleFormatter::infoFormat(undef, 'TRACKNUM. TITLE - ALBUM - ARTIST', 'TITLE', $_);
				}
				$_->{name} .= $playCount;
				$_->{title} .= $playCount;
				$_;
			} @{$result->{items}}
		] if $result->{items};

		$callback->(@_);
	}, $args, $pt );
} }

1;