package Slim::Music::MusicFolderScan;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Utils::Misc;
# background scanning and cache prefilling of music information to speed up UI...

my @dummylist;
my $stillScanning=0;

sub startScan {
	if (!defined(Slim::Utils::Prefs::get('audiodir')) or not -d Slim::Utils::Prefs::get("audiodir")) {
		$::d_info && msg("Skipping music folder scan - audiodir is undefined.\n");
	}
	else {
		if ($stillScanning) {
			$::d_info && msg("Scan already in progress. Aborting\n");
			Slim::Utils::Scan::stopAddToList(\@dummylist);
		}
		$stillScanning=1;
		$::d_info && msg("Starting music folder scan\n");
		Slim::Utils::Scan::addToList(\@dummylist, Slim::Utils::Prefs::get('audiodir'), 1, 0, \&doneScanning, 0);
		Slim::Music::Import::startImport('folder');
	}
}

sub doneScanning {
	$::d_info && msg("finished background scan of music folder.\n");
	$stillScanning=0;
	@dummylist = ();
	Slim::Music::Import::endImport('folder');
}

sub stillScanning {
	return $stillScanning;
}

1;
__END__

