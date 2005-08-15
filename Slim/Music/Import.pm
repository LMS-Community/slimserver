package Slim::Music::Import;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

# background scanning and cache prefilling of music information to speed up UI...

# Total of how many file scanners are running
our %importsRunning;
our %Importers = ();
our %artwork   = ();
our $dbCleanup = 0;

our $playlistOnlyScan = 0;

# Force a rescan of all the importers (TODO: Make importers pluggable)
sub startScan {
	my $import = shift;

	# Only start if the database has been initialized
	return unless defined Slim::Music::Info::getCurrentDataStore();
	
	# Check Import scanners
	foreach my $importer (keys %Importers) {

		# These importers all implement 'playlist only' scanning.
		# See bug: 1892
		if (Slim::Music::Import::scanPlaylistsOnly() && $importer !~ /(?:PLAYLIST|MUSICMAGIC|ITUNES|MOODLOGIC)/go) {
			next;
		}

		if (exists $Importers{$importer}->{'scan'} && $Importers{$importer}->{'use'}) {

			if (!defined $import || (defined $import && ($importer eq $import))) {

				$importsRunning{$importer} = Time::HiRes::time();

				# rescan each enabled Import, or scan the newly enabled Import
				$::d_import && msgf("Import: Starting %s scan\n", string($importer));

				&{$Importers{$importer}->{'scan'}};
			}
		}
	}
}

sub cleanupDatabase {
	my $value = shift;

	if (defined $value) {
		$dbCleanup = $value;
	}

	return $dbCleanup;
}

sub scanPlaylistsOnly {
	my $value = shift;

	if (defined $value) {
		$playlistOnlyScan = $value;
	}

	return $playlistOnlyScan;
}

sub deleteImporter {
	my $import = shift;
	
	delete $Importers{$import};
}

# addImporter takes hash ref of named function refs.
sub addImporter {
	my $import = shift;
	my $params = shift;

	$Importers{$import} = $params;

	$::d_import && msgf("Import: Adding %s Scan\n", string($import));
}

sub countImporters {
	my $count = 0;

	for my $import (keys %Importers) {
		
		# Don't count Folder Scan for this since we use this as a test to see if any other importers are in use
		next if $import eq "FOLDER";
		
		$count++ if $Importers{$import}->{'use'};
	}

	return $count;
}

sub resetSetupGroups {

	walkImporterListForFunction('setup');
}

sub resetImporters {

	walkImporterListForFunction('reset');
}

sub walkImporterListForFunction {
	my $function = shift;

	for my $importer (keys %Importers) {

		if (defined $Importers{$importer}->{$function}) {
			&{$Importers{$importer}->{$function}};
		}
	}
}

sub importers {
	return \%Importers;
}

sub useImporter {
	my $import   = shift;
	my $newValue = shift;
	
	if (defined $newValue && exists $Importers{$import}) {
		$Importers{$import}->{'use'} = $newValue;
	} else {
		return exists $Importers{$import} ? $Importers{$import} : 0;
	}
}

sub endImporter {
	my $import = shift;

	if (exists $importsRunning{$import}) { 
		$::d_import && msgf("Import: Completed %s Scan in %s seconds.\n", string($import), int(Time::HiRes::time() - $importsRunning{$import}));
		delete $importsRunning{$import};
	}

	if (scalar keys %importsRunning == 0) {

		if (Slim::Utils::Prefs::get('lookForArtwork')) {

			$::d_import && msg("Adding task for artScan().\n");

			Slim::Utils::Scheduler::add_task(\&artScan);
		}

		my $ds = Slim::Music::Info::getCurrentDataStore();

		# Set this back to 0.
		scanPlaylistsOnly(0);

		# Auto-identify VA/Compilation albums
		if (Slim::Utils::Prefs::get('variousArtistAutoIdentification')) {

			$::d_import && msg("Adding task for mergeVariousArtistsAlbums().\n");

			Slim::Utils::Scheduler::add_task(sub { $ds->mergeVariousArtistsAlbums });
		}

		$::d_import && msg("Import: Finished background scanning.\n");

		Slim::Music::Info::saveDBCache();

		# Only do this on rescan.
		if (cleanupDatabase()) {

			# Don't re-enter
			cleanupDatabase(0);

			$ds->cleanupStaleEntries();
		}
	}
}

sub stillScanning {
	my $imports = scalar keys %importsRunning;

	if ($::d_import) {
		msg("Import: Scanning with $imports import plugins\n");
		use Data::Dumper;
		print Dumper(\%importsRunning) if $imports;
	}

	return $imports;
}

sub artwork {
	my $album = shift;
	my $track = shift;

	my $key   = $album->id() || 1;

	if (defined $track) {

		$artwork{$key} = $track->id();

	} else {

		return exists $artwork{$key};
	}
}

sub artScan {
	my @albums = keys %artwork;
	my $album  = $albums[0] || return 0;

	my $ds     = Slim::Music::Info::getCurrentDataStore();
	my $track  = $ds->objectForId('track', $artwork{$album}); 

	# Make sure we have an object for the url, and it has a thumbnail.
	if ($track && $track->coverArt('thumb')) {
		
		$ds->setAlbumArtwork($track);
	}

	delete $artwork{$album};

	if (!%artwork) { 
		$::d_artwork && msg("Completed Artwork Scan\n");
		$ds->forceCommit();
		return 0;
	}

	return 1;
}

1;

__END__
