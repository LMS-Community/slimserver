package Slim::Plugin::WiMP::Importer;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::OnlineLibraryBase);

use Date::Parse qw(str2time);
use Digest::MD5 qw(md5_hex);
use JSON::XS::VersionOneAndTwo;
use List::Util qw(max);

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Progress;
use Slim::Utils::Strings qw(string);

use constant ACCOUNTS_URL  => '/api/wimp/v1/opml/library/getAccounts';
use constant ALBUMS_URL    => '/api/wimp/v1/opml/library/myAlbums?account=%s';
use constant ARTISTS_URL   => '/api/wimp/v1/opml/library/myArtists?account=%s';
use constant ARTIST_URL    => '/api/wimp/v1/opml/library/getArtist?id=%s';
use constant PLAYLISTS_URL => '/api/wimp/v1/opml/library/myPlaylists?account=%s';
use constant FINGERPRINT_URL => '/api/wimp/v1/opml/library/fingerprint';

my $cache = Slim::Utils::Cache->new();
my $log = logger('plugin.tidal');

my $http;

sub startScan { if (main::SCANNER) {
	my ($class) = @_;
	require Slim::Networking::SqueezeNetwork::Sync;

	$http ||= Slim::Networking::SqueezeNetwork::Sync->new({ timeout => 120 });

	my $response = $http->get(Slim::Networking::SqueezeNetwork::Sync->url(ACCOUNTS_URL));

	if ($response->code != 200) {
		$log->error('Failed to get TIDAL accounts: ' . $response->error);
		return;
	}

	my $accounts = eval { from_json($response->content) } || [];

	if (ref $accounts && scalar @$accounts) {
		$class->initOnlineTracksTable();

		if (!Slim::Music::Import->scanPlaylistsOnly()) {
			$class->scanAlbums($accounts);
			$class->scanArtists($accounts);
		}

		if (!$class->ignorePlaylists) {
			$class->scanPlaylists($accounts);
		}

		$response = $http->get(Slim::Networking::SqueezeNetwork::Sync->url(FINGERPRINT_URL));
		$cache->set('tidal_library_fingerprint', ($http->content || ''), 30 * 86400);

		$class->deleteRemovedTracks();
	}
	elsif (ref $accounts) {
		$cache->set('tidal_library_fingerprint', -1, 30 * 86400);
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
				'name'  => 'plugin_tidal_albums',
				'total' => 1,
				'every' => 1,
			});
		}

		main::INFOLOG && $log->is_info && $log->info("Reading albums for $account...");
		$progress->update(string('PLUGIN_TIDAL_PROGRESS_READ_ALBUMS', $account));

		my $accountName = "tidal:$account" if scalar @$accounts > 1;

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
				'name'  => 'plugin_tidal_artists',
				'total' => 1,
				'every' => 1,
			});
		}

		main::INFOLOG && $log->is_info && $log->info("Reading artists for $account...");
		$progress->update(string('PLUGIN_TIDAL_PROGRESS_READ_ARTISTS', $account));

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
				'extid'  => 'wimp:artist:' . $artist->{id},
			});

			_cacheArtistPictureUrl($artist)
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
		'name'  => 'plugin_tidal_playlists',
		'total' => 0,
		'every' => 1,
	});

	main::INFOLOG && $log->is_info && $log->info("Removing playlists...");
	$progress->update(string('PLAYLIST_DELETED_PROGRESS'), $progress->done);
	my $deletePlaylists_sth = $dbh->prepare_cached("DELETE FROM tracks WHERE url LIKE 'wimp://%.tdl'");
	$deletePlaylists_sth->execute();

	foreach my $account (@$accounts) {
		$progress->update(string('PLUGIN_TIDAL_PROGRESS_READ_PLAYLISTS', $account), $progress->done);

		main::INFOLOG && $log->is_info && $log->info("Reading playlists for $account...");
		my $playlistsResponse = $http->get(Slim::Networking::SqueezeNetwork::Sync->url(sprintf(PLAYLISTS_URL, $account)));
		my $playlists = eval { from_json($playlistsResponse->content) } || [];

		$@ && $log->error($@);

		$progress->total($progress->total + @$playlists);

		my $prefix = 'TIDAL' . string('COLON') . ' ';

		main::INFOLOG && $log->is_info && $log->info(sprintf("Importing tracks for %s playlists...", scalar @$playlists));
		foreach my $playlist (@{$playlists || []}) {
			next unless $playlist->{uuid} && $playlist->{tracks} && ref $playlist->{tracks} && ref $playlist->{tracks} eq 'ARRAY';

			$progress->update($account . string('COLON') . ' ' . $playlist->{title});
			Slim::Schema->forceCommit;

			my $url = 'wimp://' . $playlist->{uuid} . '.tdl';

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
				$cache->set('wimp_meta_' . $_->{id}, {
					artist    => $_->{artist}->{name},
					album     => $_->{album},
					title     => $_->{title},
					cover     => $_->{cover},
					duration  => $_->{duration},
					type      => $_->{flac} ? 'FLAC' : 'AAC',
				}, time + 360 * 86400);

				push @trackIds, $_->{url};
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

	my $url = $cache->get('tidal_artist_image' . $id);

	return $url if $url;

	$id =~ s/wimp:artist://;

	my $artistResponse = $http->get(Slim::Networking::SqueezeNetwork::Sync->url(sprintf(ARTIST_URL, $id)));

	my $artist = eval { from_json($artistResponse->content) } || [];

	if (scalar @$artist) {
		$artist = $artist->[0];
		if ($artist && ref $artist) {
			_cacheArtistPictureUrl($artist, 30*86400);
			return $artist->{cover};
		}
	}

	return;
} }

my $previousArtistId = '';
sub _cacheArtistPictureUrl {
	my ($artist, $ttl) = @_;

	if ($artist->{cover} && $artist->{id} ne $previousArtistId) {
		$cache->set('tidal_artist_image' . 'wimp:artist:' . $artist->{id}, $artist->{cover}, $ttl || 86400);
		$previousArtistId = $artist->{id};
	}
}

sub trackUriPrefix { 'wimp://' }

# This code is not run in the scanner, but in LMS
sub needsUpdate { if (!main::SCANNER) {
	my ($class, $cb) = @_;

	my $oldFingerprint = $cache->get('tidal_library_fingerprint') || return $cb->(1);

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
			$log->error('Failed to get TIDAL metadata: ' . $http->error);
			$cb->();
		}
	)->get(Slim::Networking::SqueezeNetwork->url(FINGERPRINT_URL));
} }

sub _prepareTrack {
	my ($track, $album) = @_;

	my $splitChar = substr(preferences('server')->get('splitList'), 0, 1);
	my $ct = Slim::Music::Info::typeFromPath($track->{url});

	my $trackData = {
		url          => $track->{url},
		TITLE        => $track->{title},
		ARTIST       => $album->{artist}->{name},
		ARTIST_EXTID => 'wimp:artist:' . $album->{artist}->{id},
		ALBUM        => $album->{title},
		ALBUM_EXTID  => 'wimp:album:' . $album->{id},
		TRACKNUM     => $track->{trackNumber},
		GENRE        => 'TIDAL',
		DISC         => $track->{volumeNumber},
		DISCC        => $album->{numberOfVolumes} || 1,
		SECS         => $track->{duration},
		YEAR         => substr($album->{releaseDate} || '', 0, 4),
		COVER        => $album->{cover},
		AUDIO        => 1,
		EXTID        => $track->{url},
		TIMESTAMP    => $album->{added},
		CONTENT_TYPE => $ct,
		LOSSLESS     => $ct eq 'flc' ? 1 : 0,
		RELEASETYPE  => $album->{type},
	};

	my @trackArtists = map { $_->{name} } grep { $_->{name} ne $album->{artist}->{name} } @{ $track->{artists} };
	if (scalar @trackArtists) {
		$trackData->{TRACKARTIST} = join($splitChar, @trackArtists);
	}

	return $trackData;
}

1;