package Slim::Music::Import;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Utils::Misc;
# background scanning and cache prefilling of music information to speed up UI...

# Total of how many file scanners are running
my $totalImportsRunning=0;

sub startScan {
		
	$::d_info && msg("Clearing ID3 cache\n");
	Slim::Music::Info::clearCache();
	Slim::Music::Info::clearPlaylists();
	
	$::d_info && msg("Starting background scanning.\n");
	
	if (Slim::Music::iTunes::useiTunesLibrary()) { 
		Slim::Music::iTunes::startScan();
	}

	if (Slim::Music::MoodLogic::useMoodLogic()) { 
		Slim::Music::MoodLogic::startScan();
	}

	Slim::Music::MusicFolderScan::startScan();
}


sub addImport {
	$totalImportsRunning++;
}

sub delImport {
	$totalImportsRunning--;
	if ($totalImportsRunning==0) {
		Slim::Music::Info::clearStaleCacheEntries();
		$::d_info && msg("Finished background scanning.\n");
		Slim::Music::Info::saveDBCache();
	}
}

sub stillScanning {
	if ($totalImportsRunning==0) { 
		return 0 
	} else { 
		return 1; 
	}
}


1;
__END__

