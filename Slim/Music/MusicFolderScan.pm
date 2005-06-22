package Slim::Music::MusicFolderScan;

# $Id
#
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Scan;

# background scanning and cache prefilling of music information to speed up UI...

my @dummylist = ();
my $stillScanning = 0;

sub init {

	Slim::Music::Import::addImporter('FOLDER', {
		'scan' => \&startScan
	});

	# Enable Folder scan only if audiodir is set and is a valid directory
	my $enabled  = 0;
	my $audioDir = Slim::Utils::Prefs::get('audiodir');

	if (defined $audioDir && -d $audioDir) {

		$enabled = 1;
	}

	Slim::Music::Import::useImporter('FOLDER', $enabled);
}

sub startScan {
	my $audioDir = shift || Slim::Utils::Prefs::get('audiodir');
	my $recurse  = shift;

	if (!defined $audioDir || !-d $audioDir) {
		$::d_info && msg("Skipping music folder scan - audiodir is undefined.\n");
		doneScanning();
		return;
	}

	if ($stillScanning) {
		$::d_info && msg("Scan already in progress. Aborting\n");
		Slim::Utils::Scan::stopAddToList(\@dummylist);
	}

	$stillScanning = 1;

	if (!defined $recurse) {
		$recurse = 1;
	}

	$::d_info && msg("Starting music folder scan\n");

	Slim::Utils::Scan::addToList(\@dummylist, $audioDir, $recurse, 0, \&doneScanning, 0);
}

sub startScanNoRecursive {
	my $path = shift;

	startScan($path, 0);
}

sub doneScanning {
	$::d_info && msg("finished background scan of music folder.\n");

	$stillScanning = 0;
	@dummylist = ();
	Slim::Music::Import::endImporter('FOLDER');
}

sub stillScanning {
	return $stillScanning;
}

sub findAndScanDirectoryTree {
	my $levels = shift;

	# Find the db entry that corresponds to the requested directory.
	# If we don't have one - that means we're starting out from the root audiodir.
	my $topLevelObj;
	my $ds = Slim::Music::Info::getCurrentDataStore();

	if (scalar @$levels) {

		$topLevelObj = $ds->objectForId('track', $levels->[-1]);

	} else {

		my $url      = Slim::Utils::Misc::fileURLFromPath(Slim::Utils::Prefs::get('audiodir'));

		$topLevelObj = $ds->objectForUrl($url, 1, 1, 1) || return;

		push @$levels, $topLevelObj->id;
	}

	if (!defined $topLevelObj) {

		msg("Error: Couldn't find a topLevelObj for findAndScanDirectoryTree()\n");

		if (scalar @$levels) {
			msgf("Passed in value was: [%s]\n", $levels->[-1]);
		} else {
			msg("Starting from audiodir! Is it not set?\n");
		}

		return ();
	}

	# Check for changes - these can be adds or deletes.
	# Do a realtime scan - don't send anything to the scheduler.
	my $path    = $topLevelObj->path;
	my $fsMTime = (stat($path))[9] || 0;
	my $dbMTime = $topLevelObj->timestamp || 0;

	if ($fsMTime != $dbMTime) {

		if ($::d_scan) {
			msg("mtime db: $dbMTime : " . localtime($dbMTime) . "\n");
			msg("mtime fs: $fsMTime : " . localtime($fsMTime) . "\n");
		}

		# Do a quick directory scan.
		Slim::Utils::Scan::addToList([], $path, 0, undef, sub {});
	}

	# Now read the raw directory and return it. This should always be really fast.
	my $items = [ Slim::Utils::Misc::readDirectory( $topLevelObj->path ) ];
        my $count = scalar @$items;

	return ($topLevelObj, $items, $count);
}

1;

__END__
