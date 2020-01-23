package Slim::Plugin::OnlineLibraryBase;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

use strict;

use Slim::Schema;
use Slim::Utils::Log;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner::Local;

use constant IS_SQLITE => (Slim::Utils::OSDetect->getOS()->sqlHelperClass() =~ /SQLite/ ? 1 : 0);

my $log = logger('scan.scanner');

sub initPlugin {
	my ($class, $args) = @_;

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
}

sub initOnlineTracksTable { if (main::SCANNER && !$main::wipe) {
	my $dbh = Slim::Schema->dbh();

	main::INFOLOG && $log->is_info && $log->info("Re-build temporary table for Spotify tracks");
	$dbh->do('DROP TABLE IF EXISTS online_tracks');
	$dbh->do(qq{
		CREATE TEMPORARY TABLE online_tracks (url TEXT PRIMARY KEY);
	});
} }

sub deleteRemovedTracks { if (main::SCANNER && !$main::wipe) {
	my ($class) = @_;

	my $dbh = Slim::Schema->dbh;
	my $trackUriPrefix = $class->trackUriPrefix;

	my $inOnlineLibrarySQL = qq{
		SELECT DISTINCT(url)
		FROM            tracks
		WHERE           url LIKE '$trackUriPrefix%'
			AND url NOT IN (
				SELECT url FROM online_tracks
			)
	} . (IS_SQLITE ? '' : ' ORDER BY url');

	$log->error("Get removed online tracks count") unless main::SCANNER && $main::progress;
	# only remove missing tracks when looking for audio tracks
	my $notInOnlineLibraryCount = 0;
	($notInOnlineLibraryCount) = $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $inOnlineLibrarySQL ) AS t1
	} );

	my $changes = 0;
	my $paths;

	Slim::Utils::Scanner::Local->deleteTracks($dbh, \$changes, \$paths, '', {
		name  => 'online music library tracks',
		count => $notInOnlineLibraryCount,
		progressName => 'online_library_deleted',
		sql   => $inOnlineLibrarySQL,
	}, {
		types    => 'audio',
		no_async => 1,
		progress => 1,
	});

	return $changes;
} }

sub trackUriPrefix { 'unknown://' }

# Helper method for importer plugins to see whether they are enabled or not
sub isImportEnabled {
	my ($class) = @_;

	if ( main::SCANNER 
		? (preferences('plugin.state')->get('OnlineLibrary') || '') eq 'enabled' 
		: Slim::Utils::PluginManager->isEnabled('Slim::Plugin::OnlineLibrary::Plugin') 
	) {
		my $pluginData = Slim::Utils::PluginManager->dataForPlugin($class);

		if ($pluginData && ref $pluginData && $pluginData->{name} && ($pluginData->{onlineLibrary} || '') eq 'true') {
			my $enabled = preferences('plugin.onlinelibrary')->get('enable_' . $pluginData->{name});
			return $enabled ? 1 : 0;
		}
	}

	return 1;
}

1;