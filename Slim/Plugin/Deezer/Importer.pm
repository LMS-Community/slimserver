package Slim::Plugin::Deezer::Importer;

# Logitech Media Server Copyright 2003-2022 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::OnlineLibraryBase);

use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Progress;
use Slim::Utils::Strings qw(string);

use constant ACCOUNTS_URL  => '/api/deezer/v1/opml/library/getAccounts';
use constant ALBUMS_URL    => '/api/deezer/v1/opml/library/myAlbums';
use constant ARTISTS_URL   => '/api/deezer/v1/opml/library/myArtists';
use constant PLAYLISTS_URL => '/api/deezer/v1/opml/library/myPlaylists';
use constant FINGERPRINT_URL => '/api/deezer/v1/opml/library/fingerprint';

my $cache = Slim::Utils::Cache->new();
my $log = logger('plugin.deezer');

my ($http, $accounts);

sub isImportEnabled {
	my ($class) = @_;

	if ($class->SUPER::isImportEnabled) {
		require Slim::Networking::SqueezeNetwork::Sync;

		$http ||= Slim::Networking::SqueezeNetwork::Sync->new({ timeout => 120 });

		my $response = $http->get(Slim::Networking::SqueezeNetwork::Sync->url(ACCOUNTS_URL));

		if ($response->code != 200) {
			$log->error('Failed to get Deezer accounts: ' . $response->error);
			return;
		}

		$accounts = eval { from_json($response->content) } || [];

		return 1 if scalar @$accounts;

		$cache->set('deezer_library_fingerprint', -1, 30 * 86400);

		main::INFOLOG && $log->is_info && $log->info("No Premium Deezer account found - skipping import");
	}

	return 0;
}

sub startScan { if (main::SCANNER) {
	my ($class) = @_;
	require Slim::Networking::SqueezeNetwork::Sync;

	$http ||= Slim::Networking::SqueezeNetwork::Sync->new({ timeout => 120 });

	if (ref $accounts && scalar @$accounts) {
		$class->initOnlineTracksTable();

		if (!Slim::Music::Import->scanPlaylistsOnly()) {
			$class->scanAlbums($accounts);
			$class->scanArtists($accounts);
		}

		if (!$class->ignorePlaylists) {
			$class->scanPlaylists($accounts);
		}

		my $response = $http->get(Slim::Networking::SqueezeNetwork::Sync->url(FINGERPRINT_URL));
		$cache->set('deezer_library_fingerprint', ($response->content || ''), 30 * 86400);

		$class->deleteRemovedTracks();
	}
	elsif (ref $accounts) {
		$cache->set('deezer_library_fingerprint', -1, 30 * 86400);
	}

	Slim::Music::Import->endImporter($class);
} }

sub scanAlbums { if (main::SCANNER) {
	my ($class, $accounts) = @_;

	my $progress;

	foreach my $account (@$accounts) {
		if ($progress) {
			$progress->total($progress->total + 1);
		}
		else {
			$progress = Slim::Utils::Progress->new({
				'type'  => 'importer',
				'name'  => 'plugin_deezer_albums',
				'total' => 1,
				'every' => 1,
			});
		}

		main::INFOLOG && $log->is_info && $log->info("Reading albums for $account...");
		$progress->update(string('PLUGIN_DEEZER_PROGRESS_READ_ALBUMS', $account));

		my $accountName = "deezer:$account" if scalar @$accounts > 1;

		my $albumsResponse = $http->get(Slim::Networking::SqueezeNetwork::Sync->url(sprintf(ALBUMS_URL, $account)));
		my $albums = eval { from_json($albumsResponse->content) } || [];

		$@ && $log->error($@);

		$progress->total($progress->total + scalar @$albums);

		main::INFOLOG && $log->is_info && $log->info(sprintf("Importing album tracks for %s albums...", scalar @$albums));
		main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($albums));
		foreach my $album (@$albums) {
			if (!ref $album) {
				$log->error("Invalid data: $album");
				next;
			}

			$progress->update($account . string('COLON') . ' ' . $album->{title});
			Slim::Schema->forceCommit;

			my $tracks = delete $album->{tracks};

			$class->storeTracks([
				map { _prepareTrack($_, $album) } @$tracks
			], undef, $accountName);

			_cacheArtistPictureUrl({
				id => $album->{artist_id},
				image => $album->{artistImage}
			});
		}

		Slim::Schema->forceCommit;
	}

	$progress->final() if $progress;
} }

sub scanArtists { if (main::SCANNER) {
	my ($class, $accounts) = @_;

	my $progress;

	foreach my $account (@$accounts) {
		if ($progress) {
			$progress->total($progress->total + 1);
		}
		else {
			$progress = Slim::Utils::Progress->new({
				'type'  => 'importer',
				'name'  => 'plugin_deezer_artists',
				'total' => 1,
				'every' => 1,
			});
		}

		main::INFOLOG && $log->is_info && $log->info("Reading artists for $account...");
		$progress->update(string('PLUGIN_DEEZER_PROGRESS_READ_ARTISTS', $account));

		my $artistsResponse = $http->get(Slim::Networking::SqueezeNetwork::Sync->url(sprintf(ARTISTS_URL, $account)));
		my $artists = eval { from_json($artistsResponse->content) } || [];

		$@ && $log->error($@);

		$progress->total($progress->total + scalar @$artists);

		main::INFOLOG && $log->is_info && $log->info(sprintf("Importing artist tracks for %s artists...", scalar @$artists));
		main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($artists));
		foreach my $artist (@$artists) {
			if (!ref $artist) {
				$log->error("Invalid artist data: $artist");
				next;
			}

			my $name = $artist->{name};

			$progress->update($account . string('COLON') . ' ' . $name);
			Slim::Schema->forceCommit;

			Slim::Schema::Contributor->add({
				'artist' => $class->normalizeContributorName($name),
				'extid'  => 'deezer:artist:' . $artist->{id},
			});

			_cacheArtistPictureUrl($artist);
		}

		Slim::Schema->forceCommit;
	}

	$progress->final() if $progress;
} }

sub scanPlaylists { if (main::SCANNER) {
	my ($class, $accounts) = @_;

	my $dbh = Slim::Schema->dbh();
	my $insertTrackInTempTable_sth = $dbh->prepare_cached("INSERT OR IGNORE INTO online_tracks (url) VALUES (?)") if main::SCANNER && !$main::wipe;

	my $progress = Slim::Utils::Progress->new({
		'type'  => 'importer',
		'name'  => 'plugin_deezer_playlists',
		'total' => 0,
		'every' => 1,
	});

	main::INFOLOG && $log->is_info && $log->info("Removing playlists...");
	$progress->update(string('PLAYLIST_DELETED_PROGRESS'), $progress->done);
	my $deletePlaylists_sth = $dbh->prepare_cached("DELETE FROM tracks WHERE url LIKE 'deezer://%.dzl'");
	$deletePlaylists_sth->execute();

	foreach my $account (@$accounts) {
		$progress->update(string('PLUGIN_DEEZER_PROGRESS_READ_PLAYLISTS', $account), $progress->done);

		main::INFOLOG && $log->is_info && $log->info("Reading playlists for $account...");
		my $playlistsResponse = $http->get(Slim::Networking::SqueezeNetwork::Sync->url(sprintf(PLAYLISTS_URL, $account)));
		my $playlists = eval { from_json($playlistsResponse->content) } || [];

		$@ && $log->error($@);

		$progress->total($progress->total + @$playlists);

		my $prefix = 'Deezer' . string('COLON') . ' ';

		main::INFOLOG && $log->is_info && $log->info(sprintf("Importing tracks for %s playlists...", scalar @$playlists));
		foreach my $playlist (@{$playlists || []}) {
			next unless $playlist->{id} && $playlist->{tracks} && ref $playlist->{tracks} && ref $playlist->{tracks} eq 'ARRAY';

			$progress->update($account . string('COLON') . ' ' . $playlist->{title});
			Slim::Schema->forceCommit;

			my $url = 'deezer://' . $playlist->{id} . '.dzl';

			my $playlistObj = Slim::Schema->updateOrCreate({
				url        => $url,
				playlist   => 1,
				integrateRemote => 1,
				attributes => {
					TITLE        => $prefix . $playlist->{title},
					COVER        => $playlist->{cover},
					AUDIO        => 1,
					EXTID        => $url,
					CONTENT_TYPE => 'ssp'
				},
			});

			my @trackIds;
			foreach (@{$playlist->{tracks}}) {
				$cache->set('deezer_meta_' . $_->{id}, {
					artist    => $_->{artist},
					album     => $_->{album},
					title     => $_->{title},
					cover     => $_->{cover},
					duration  => $_->{duration},
					type      => 'mp3',
				}, time + 360 * 86400);

				push @trackIds, sprintf("deezer://%s.mp3", $_->{id});
			}

			$playlistObj->setTracks(\@trackIds) if $playlistObj && scalar @trackIds;
			$insertTrackInTempTable_sth && $insertTrackInTempTable_sth->execute($url);
		}

		Slim::Schema->forceCommit;
	}

	$progress->final();
	Slim::Schema->forceCommit;
} }

sub getArtistPicture { if (main::SCANNER) {
	my ($class, $id) = @_;
	return $cache->get('deezer_artist_image' . $id);
} }

my $previousArtistId = '';
sub _cacheArtistPictureUrl {
	my ($artist) = @_;

	if ($artist->{image} && $artist->{id} ne $previousArtistId) {
		$cache->set('deezer_artist_image' . 'deezer:artist:' . $artist->{id}, $artist->{image}, 86400);
		$previousArtistId = $artist->{id};
	}
}

sub trackUriPrefix { 'deezer://' }

# This code is not run in the scanner, but in LMS
sub needsUpdate { if (!main::SCANNER) {
	my ($class, $cb) = @_;

	my $oldFingerprint = $cache->get('deezer_library_fingerprint') || return $cb->(1);

	if ($oldFingerprint == -1) {
		return $cb->($oldFingerprint);
	}

	Slim::Networking::SqueezeNetwork->new(
		sub {
			my $http = shift;
			my $newFingerPrint = $http->content || '';

			$cb->($newFingerPrint ne $oldFingerprint);
		},
		sub {
			my $http = shift;
			$log->error('Failed to get Deezer metadata: ' . $http->error);
			$cb->();
		}
	)->get(Slim::Networking::SqueezeNetwork->url(FINGERPRINT_URL));
} }

sub _prepareTrack {
	my ($track, $album) = @_;

	my $url = sprintf("deezer://%s.%s", $track->{id}, $track->{lossless} ? 'flac' : 'mp3');
	my $splitChar = substr(preferences('server')->get('splitList'), 0, 1);

	return {
		url          => $url,
		TITLE        => $track->{title},
		ARTIST       => $album->{artist},
		ARTIST_EXTID => 'deezer:artist:' . $album->{artist_id},
		ALBUM        => $album->{title},
		ALBUM_EXTID  => 'deezer:album:' . $album->{id},
		TRACKNUM     => $track->{trackNumber},
		GENRE        => join($splitChar, @{$album->{genres} || []}),
		SECS         => $track->{duration},
		YEAR         => substr($album->{released} || '', 0, 4),
		COVER        => $album->{cover},
		AUDIO        => 1,
		EXTID        => $url,
		TIMESTAMP    => $album->{added},
		CONTENT_TYPE => $track->{lossless} ? 'flc' : 'mp3',
		RELEASETYPE  => $album->{record_type},
	};
}

1;