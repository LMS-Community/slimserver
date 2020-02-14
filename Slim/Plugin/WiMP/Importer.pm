package Slim::Plugin::WiMP::Importer;

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
use constant PLAYLISTS_URL => '/api/wimp/v1/opml/library/myPlaylists?account=%s';
use constant NEEDS_UPDATE_URL => '/api/wimp/v1/opml/library/needsUpdate';

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

		my $newMetadata = {};
		$newMetadata = $class->scanAlbums($accounts, $newMetadata);
		$newMetadata = $class->scanPlaylists($accounts, $newMetadata);

		$cache->set('tidal_library_metadata', $newMetadata, 30 * 86400);

		$class->deleteRemovedTracks();
	}

	Slim::Music::Import->endImporter($class);
} }

sub scanAlbums { if (main::SCANNER) {
	my ($class, $accounts, $newMetadata) = @_;

	my $progress;

	foreach my $account (@$accounts) {
		$progress ||= Slim::Utils::Progress->new({
			'type'  => 'importer',
			'name'  => 'plugin_tidal_albums',
			'total' => 1,
			'every' => 1,
		});

		main::INFOLOG && $log->is_info && $log->info("Reading albums...");
		$progress->update(string('PLUGIN_TIDAL_PROGRESS_READ_ALBUMS', $account));

		my $albumsResponse = $http->get(Slim::Networking::SqueezeNetwork::Sync->url(sprintf(ALBUMS_URL, $account)));
		my $albums = eval { from_json($albumsResponse->content) } || [];

		$@ && $log->error($@);

		$progress->total($progress->total + scalar @$albums);
		my $lastAdded = 0;

		main::INFOLOG && $log->is_info && $log->info(sprintf("Importing album tracks for %s albums...", scalar @$albums));
		foreach my $album (@$albums) {
			$progress->update($account . string('COLON') . ' ' . $album->{title});
			main::SCANNER && Slim::Schema->forceCommit;

			$lastAdded = max($lastAdded, $album->{added});
			my $tracks = delete $album->{tracks};

			$class->storeTracks([
				map { _prepareTrack($_, $album) } @$tracks
			]);
		}

		$newMetadata->{$account} ||= [];
		push @{$newMetadata->{$account}}, $lastAdded;

		main::SCANNER && Slim::Schema->forceCommit;
	}

	$progress->final() if $progress;

	return $newMetadata;
} }

sub scanPlaylists { if (main::SCANNER) {
	my ($class, $accounts, $newMetadata) = @_;

	my $dbh = Slim::Schema->dbh();
	my $insertTrackInTempTable_sth = $dbh->prepare_cached("INSERT OR IGNORE INTO online_tracks (url) VALUES (?)") if main::SCANNER && !$main::wipe;

	my $progress = Slim::Utils::Progress->new({
		'type'  => 'importer',
		'name'  => 'plugin_tidal_playlists',
		'total' => 1,
		'every' => 1,
	});

	main::INFOLOG && $log->is_info && $log->info("Removing playlists...");
	$progress->update(string('PLAYLIST_DELETED_PROGRESS'));
	my $deletePlaylists_sth = $dbh->prepare_cached("DELETE FROM tracks WHERE url LIKE 'wimp://%.tdl'");
	$deletePlaylists_sth->execute();

	foreach my $account (@$accounts) {
		$progress->total($progress->total + 1);
		$progress->update(string('PLUGIN_TIDAL_PROGRESS_READ_PLAYLISTS', $account));
		my $lastAdded = 0;

		main::INFOLOG && $log->is_info && $log->info("Reading playlists...");
		my $playlistsResponse = $http->get(Slim::Networking::SqueezeNetwork::Sync->url(sprintf(PLAYLISTS_URL, $account)));
		my $playlists = eval { from_json($playlistsResponse->content) } || [];

		$@ && $log->error($@);

		$progress->total($progress->total + @$playlists);

		my $prefix = 'TIDAL' . string('COLON') . ' ';

		main::INFOLOG && $log->is_info && $log->info(sprintf("Importing tracks for %s playlists...", scalar @$playlists));
		foreach my $playlist (@{$playlists || []}) {
			next unless $playlist->{uuid} && $playlist->{tracks} && ref $playlist->{tracks} && ref $playlist->{tracks} eq 'ARRAY';

			$progress->update($account . string('COLON') . ' ' . $playlist->{title});
			main::SCANNER && Slim::Schema->forceCommit;

			my $url = 'wimp://' . $playlist->{uuid} . '.tdl';
			$lastAdded = max($lastAdded, str2time($playlist->{created}), str2time($playlist->{lastUpdated}));

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
					type      => $_->{flac} ? 'FLAC' : 'MP3',
				}, time + 360 * 86400);

				push @trackIds, $_->{url};
			}

			$playlistObj->setTracks(\@trackIds) if $playlistObj && scalar @trackIds;
			$insertTrackInTempTable_sth && $insertTrackInTempTable_sth->execute($url);
		}

		$newMetadata->{$account} ||= [];
		push @{$newMetadata->{$account}}, $lastAdded;
		$newMetadata->{$account}->[1] = $lastAdded;

		main::SCANNER && Slim::Schema->forceCommit;
	}

	$progress->final();
	main::SCANNER && Slim::Schema->forceCommit;

	return $newMetadata;
} }

sub trackUriPrefix { 'wimp://' }

# This code is not run in the scanner, but in LMS
sub needsUpdate { if (!main::SCANNER) {
	my ($class, $cb) = @_;

	require Async::Util;

	# we send mysb the metadata of the latest scan and let it do the heavy lifting
	my $metadata = $cache->get('tidal_library_metadata') || {};

	Slim::Networking::SqueezeNetwork->new(
		sub {
			my $http = shift;

			my $response = eval { from_json($http->content) } || {};
			$@ && $log->error('Failed to get TIDAL metadata: ' . $@);
			$cb->($response->{needsUpdate});
		},
		sub {
			my $http = shift;
			$log->error('Failed to get TIDAL metadata: ' . $http->error);
			$cb->();
		}
	)->post(Slim::Networking::SqueezeNetwork->url(NEEDS_UPDATE_URL), to_json($metadata));
} }

sub _prepareTrack {
	my ($track, $album) = @_;

	my $splitChar = substr(preferences('server')->get('splitList'), 0, 1);
	my $ct = Slim::Music::Info::typeFromPath($track->{url});

	return {
		url          => $track->{url},
		TITLE        => $track->{title},
		ARTIST       => $track->{artist}->{name},
		ARTIST_EXTID => 'wimp:artist:' . $track->{artist}->{id},
		TRACKARTIST  => join($splitChar, map { $_->{name} } @{ $track->{artists} }),
		ALBUM        => $album->{title},
		ALBUM_EXTID  => 'wimp:album:' . $album->{id},
		TRACKNUM     => $track->{trackNumber},
		GENRE        => 'TIDAL',
		DISC         => $track->{volumeNumber},
		DISCC        => $track->{numberOfVolumes} || 1,
		SECS         => $track->{duration},
		YEAR         => substr($album->{releaseDate} || '', 0, 4),
		COVER        => $album->{cover},
		AUDIO        => 1,
		EXTID        => $track->{url},
		TIMESTAMP    => $album->{added},
		CONTENT_TYPE => $ct,
		LOSSLESS     => $ct eq 'flc' ? 1 : 0,
	};
}

1;