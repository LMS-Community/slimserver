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
		$::d_info && msg("Scan already in progress. Restarting\n");
		$stillScanning = 0;
		Slim::Utils::Scan::stopAddToList(\@dummylist);
		@dummylist = ();
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
	#If scan aborted, $stillScanning will already be false.
	return unless $stillScanning;
	
	$::d_info && msg("finished background scan of music folder.\n");

	$stillScanning = 0;
	@dummylist = ();
	Slim::Music::Import::endImporter('FOLDER');
}

sub stillScanning {
	return $stillScanning;
}

1;

__END__
