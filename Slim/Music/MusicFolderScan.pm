package Slim::Music::MusicFolderScan;

# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Utils::Misc;
# background scanning and cache prefilling of music information to speed up UI...

my @dummylist;
my $stillScanning;

sub startScan {
	my $savecache = shift;
	
	if (Slim::Music::iTunes::useiTunesLibrary()) { 
		return;
	}

	if (Slim::Music::MoodLogic::useMoodLogic()) { 
		return;
	}

	# Optionally don't clear the caches...
	if (!$savecache) {
		$::d_info && msg("Clearing ID3 cache\n");
		Slim::Music::Info::clearCache();
	}

	if (!defined(Slim::Utils::Prefs::get("mp3dir")) or not -d Slim::Utils::Prefs::get("mp3dir")) {
		$::d_info && msg("Skipping pre-scan - mp3dir is undefined.\n");
		return 0;
	}

	if ($stillScanning) {
		$::d_info && msg("Scan already in progress. Aborting\n");
		Slim::Utils::Scan::stopAddToList(\@dummylist);
	}

	$stillScanning=1;
	Slim::Utils::Scan::addToList(\@dummylist, Slim::Utils::Prefs::get("mp3dir"), 1, 0, \&doneScanning, 0);
}

sub doneScanning {
	$::d_info && msg("finished background scan of music folder.\n");
	$stillScanning=0;
	@dummylist = ();
}

sub stillScanning {
	return $stillScanning;
}

1;
__END__

