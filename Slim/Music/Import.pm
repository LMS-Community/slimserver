package Slim::Music::Import;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Music::Info;
use Slim::Music::MusicFolderScan;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

# background scanning and cache prefilling of music information to speed up UI...

# Total of how many file scanners are running
our %importsRunning;
our %Importers = ();
our %artwork   = ();

# Force a rescan of all the importers (TODO: Make importers pluggable)
sub startScan {
	my $import = shift;

	# Only start if the database has been initialized
	return unless defined Slim::Music::Info::getCurrentDataStore();
	
	# Don't rescan folders if we are only enabling an Import.
	unless (defined $import) {

		$::d_info && msg("Clearing tag cache\n");
		Slim::Music::Info::clearCache();

		$::d_info && msg("Starting background scanning.\n");
		$importsRunning{'folder'} = Time::HiRes::time();

		Slim::Music::MusicFolderScan::startScan();
	}

	# Check Import scanners
	foreach my $importer (keys %Importers) {

		if (exists $Importers{$importer}->{'scan'} && $Importers{$importer}->{'use'}) {

			if (!defined $import || (defined $import && ($importer eq $import))) {

				$importsRunning{$importer} = Time::HiRes::time();

				# rescan each enabled Import, or scan the newly enabled Import
				$::d_info && msgf("Starting %s scan\n", string($importer));

				&{$Importers{$importer}->{'scan'}};
			}
		}
	}
	Slim::Music::Info::generatePlaylists() unless stillScanning();
}

sub deleteImporter {
	my $import = shift;
	
	delete $Importers{$import};
}

sub addImporter {
	my $import = shift;
	my $scanFuncRef = shift;
	my $mixerFuncRef = shift;
	my $setupFuncRef = shift;
	my $mixerLinkRef = shift;

	$Importers{$import} = {
		'mixer' => $mixerFuncRef,
		'scan'  => $scanFuncRef,
		'setup' => $setupFuncRef,
		'mixerlink' => $mixerLinkRef,
	};

	$::d_info && msgf("Adding %s Scan\n", string($import));
}

sub countImporters {
	my $count = 0;

	for my $import (keys %Importers) {
		$count++ if $Importers{$import}->{'use'};
	}

	return $count;
}

sub resetSetupGroups {

	for my $importer (keys %Importers) {

		if (exists $Importers{$importer}->{'setup'}) {
			&{$Importers{$importer}->{'setup'}};
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
		$::d_info && msgf("Completing %s Scan in %s seconds.\n", string($import), (Time::HiRes::time() - $importsRunning{$import}));
		delete $importsRunning{$import};
	}

	if (scalar keys %importsRunning == 0) {

		if (Slim::Utils::Prefs::get('lookForArtwork')) {

			Slim::Utils::Scheduler::add_task(\&artScan);
		}

		$::d_info && msg("Finished background scanning.\n");
		Slim::Music::Info::saveDBCache();
	}
}

sub stillScanning {
	my $imports = scalar keys %importsRunning;

	$::d_info && msg("Scanning with $imports import plugins\n");

	return $imports;
}

sub artwork {
	my $cacheItem = shift;
	my $url = shift;

	if (defined $url) {
		$artwork{$cacheItem} = $url;
	} else {
		return exists $artwork{$cacheItem};
	}
}

sub artScan {
	my @albums = keys %artwork;
	my $album  = $albums[0] || return 0;

	my $url    = $artwork{$album};
	my $ds     = Slim::Music::Info::getCurrentDataStore();
	my $track  = $ds->objectForUrl($url); 

	# Make sure we have an object for the url, and it has a thumbnail.
	if (defined $track && $track->coverArt('thumb')) {

		my $thumb = Slim::Utils::Misc::pathFromFileURL($url);
		
		$::d_artwork && Slim::Utils::Misc::msg("Caching $thumb for $album\n");

		$ds->setAlbumArtwork($album, $thumb);
	}

	delete $artwork{$album};

	if (!%artwork) { 
		$::d_artwork && Slim::Utils::Misc::msg("Completed Artwork Scan\n");
		$ds->forceCommit();
		return 0;
	}

	return 1;
}

1;

__END__
