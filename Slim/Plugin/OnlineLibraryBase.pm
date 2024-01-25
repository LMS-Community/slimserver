package Slim::Plugin::OnlineLibraryBase;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

use strict;
use Tie::Cache::LRU;

use Slim::Schema;
use Slim::Utils::Log;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner::Local;

tie my %artistsMap, 'Tie::Cache::LRU', 128;

use constant IS_SQLITE => (Slim::Utils::OSDetect->getOS()->sqlHelperClass() =~ /SQLite/ ? 1 : 0);

my $log = logger('scan.scanner');

sub initPlugin { if (main::SCANNER) {
	my ($class, $args) = @_;

	# don't run importer if we're doing a singledir scan
	return if main::SCANNER && $ARGV[-1] && 'onlinelibrary' ne $ARGV[-1];

	return if !$class->isImportEnabled();

	$args ||= {};

	Slim::Music::Import->addImporter($class, {
		'type'         => 'file',
		'weight'       => 200,
		'use'          => 1,
		'playlistOnly' => 1,
		'onlineLibraryOnly' => 1,
		%$args,
	});

	return 1;
} }

sub initOnlineTracksTable { if (main::SCANNER && !$main::wipe) {
	my $dbh = Slim::Schema->dbh();

	my $createTemporary = (main::DEBUGLOG && $log->is_debug) ? '' : 'TEMPORARY';

	main::INFOLOG && $log->is_info && $log->info("Re-build temporary table for online tracks");
	$dbh->do('DROP TABLE IF EXISTS online_tracks');
	$dbh->do(qq{
		CREATE $createTemporary TABLE online_tracks (url TEXT PRIMARY KEY);
	});
} }

sub deleteRemovedTracks { if (main::SCANNER && !$main::wipe) {
	my ($class) = @_;

	my $dbh = Slim::Schema->dbh;
	my $trackUriPrefix = $class->trackUriPrefix;

	my $inOnlineLibraryCount = 0;
	($inOnlineLibraryCount) = $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM online_tracks AS t1
	} );

	my $playlistOnly = Slim::Music::Import->scanPlaylistsOnly() ? ' AND content_type = "ssp"' : '';

	my $notInOnlineLibrarySQL = qq{
		SELECT DISTINCT(url)
		FROM            tracks
		WHERE           url LIKE '$trackUriPrefix%' $playlistOnly
			AND url NOT IN (
				SELECT url FROM online_tracks
			)
	} . (IS_SQLITE ? '' : ' ORDER BY url');

	$log->error("Get removed online tracks count") unless main::SCANNER && $main::progress;
	# only remove missing tracks when looking for audio tracks
	my $notInOnlineLibraryCount = 0;
	($notInOnlineLibraryCount) = $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $notInOnlineLibrarySQL ) AS t1
	} );

	# let's not continue if we don't have any tracks any more, but had before - this most likely is due to some failure
	if (!$inOnlineLibraryCount && $notInOnlineLibraryCount) {
		main::INFOLOG && $log->is_info && $log->info("We don't have any online tracks in the library any more, but had $notInOnlineLibraryCount before - let's skip the deletion. It's likely due to some failure.");
		return;
	}

	my $changes = 0;
	my $paths;

	Slim::Utils::Scanner::Local->deleteTracks($dbh, \$changes, \$paths, '', {
		name  => 'online music library tracks',
		count => $notInOnlineLibraryCount,
		progressName => 'online_library_deleted',
		sql   => $notInOnlineLibrarySQL,
	}, {
		types    => 'audio',
		no_async => 1,
		progress => 1,
	}) if $notInOnlineLibraryCount;

	return $changes;
} }

sub trackUriPrefix { 'unknown://' }

# Helper method for importer plugins to see whether they are enabled or not
sub isImportEnabled {
	my ($class) = @_;

	if ( Slim::Music::Import->isOnlineLibrarySupportEnabled() ) {
		my $pluginData = Slim::Utils::PluginManager->dataForPlugin($class);

		if ($pluginData && ref $pluginData && $pluginData->{name} && ($pluginData->{onlineLibrary} || '') eq 'true') {
			my $enabled = preferences('plugin.onlinelibrary')->get('enable_' . $pluginData->{name});
			return $enabled ? 1 : 0;
		}
	}

	return 0;
}

sub ignorePlaylists {
	return preferences('plugin.onlinelibrary')->get('disablePlaylistImport') ? 1 : 0;
}

sub storeTracks {
	my ($class, $tracks, $libraryId, $accountId) = @_;

	return unless $tracks && ref $tracks;

	my $dbh = Slim::Schema->dbh();
	my $checkComment_sth           = $dbh->prepare_cached("SELECT id FROM comments WHERE track = ? AND value = ?") if $accountId;
	my $insertAccountInComment_sth = $dbh->prepare_cached("INSERT OR IGNORE INTO comments (track, value) VALUES (?, ?)") if $accountId;
	my $insertTrackInLibrary_sth   = $dbh->prepare_cached("INSERT OR IGNORE INTO library_track (library, track) VALUES (?, ?)") if $libraryId;
	my $insertTrackInTempTable_sth = $dbh->prepare_cached("INSERT OR IGNORE INTO online_tracks (url) VALUES (?)") if main::SCANNER && !$main::wipe;

	my @roles = Slim::Schema::Contributor->contributorRoles;
	my $c = 0;

	foreach my $track (@$tracks) {
		my $url = delete $track->{url} || next;

		# try to map artists to the identical, but potentially slightly differently spelled local version (eg. Beatles vs. The Beatles)
		foreach my $role (@roles) {
			$track->{$role} = $class->normalizeContributorName($track->{$role}) if $track->{$role};
		}

		my $trackObj = Slim::Schema->updateOrCreate({
			url             => $url,
			attributes      => $track,
			integrateRemote => 1,
		});

		if ($checkComment_sth) {
			$checkComment_sth->execute($trackObj->id, $accountId);
			my $data = $checkComment_sth->fetchall_arrayref([0]);

			if (!$data || !ref $data || !scalar @$data) {
				$insertAccountInComment_sth->execute($trackObj->id, $accountId);
			}
		}

		if ($insertTrackInLibrary_sth) {
			$insertTrackInLibrary_sth->execute($libraryId, $trackObj->id);
		}

		if ($insertTrackInTempTable_sth) {
			$insertTrackInTempTable_sth->execute($url);
		}

		if (!main::SCANNER && ++$c % 20 == 0) {
			main::idle();
		}
	}

	main::idle() if !main::SCANNER;
}

sub normalizeContributorName {
	my ($class, $artist) = @_;

	return $artist unless $artist;

	if (my $artist2 = Slim::Utils::Text::ignoreCase($artist, 1)) {
		if (my $normalized = $artistsMap{$artist2}) {
			$artist = $normalized;
		}
		else {
			my $dbh = Slim::Schema->dbh();
			my $checkContributor_sth = $dbh->prepare_cached("SELECT name FROM contributors WHERE namesearch = ?");

			$checkContributor_sth->execute($artist2);
			my $contributor = $checkContributor_sth->fetchall_arrayref([0]);

			if ($contributor && ref $contributor && scalar @$contributor) {
				$artistsMap{$artist2} = $artist = $contributor->[0]->[0];
			}
			else {
				$artistsMap{$artist2} = $artist;
			}
		}
	}

	return $artist;
}

sub getLibraryStats {
	my ($class) = @_;
	my $prefix = $class->trackUriPrefix();
	$prefix =~ s/:.*/:/g;

	my $totals;
	my $dbh = Slim::Schema->dbh();

	foreach (
		['tracks', "SELECT COUNT(1) FROM tracks WHERE extid LIKE ? AND content_type != 'ssp'"],
		['albums', "SELECT COUNT(1) FROM albums WHERE extid LIKE ?"],
		['artists', "SELECT COUNT(1) FROM contributors WHERE extid LIKE ?"],
		['playlists', "SELECT COUNT(1) FROM tracks WHERE extid LIKE ? AND content_type = 'ssp'"],
		['playlistTracks', "SELECT COUNT(1) FROM playlist_track WHERE track LIKE ?"]
	) {
		my $count_sth = $dbh->prepare_cached($_->[1]);
		$count_sth->execute("$prefix%");
		my ($count) = $count_sth->fetchrow_array();
		$count_sth->finish;

		$totals->{$_->[0]} = $count || 0;
	}

	return $totals;
}

sub libraryMetaId {
	my ($class, $libraryMeta) = @_;
	$libraryMeta ||= {};
	return ($libraryMeta->{total} || '') . '|' . ($libraryMeta->{lastAdded} || '') . '|' . ($libraryMeta->{hash} || '');
}

1;