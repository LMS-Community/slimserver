package Slim::Music::Import;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Utils::Misc;
# background scanning and cache prefilling of music information to speed up UI...

# Total of how many file scanners are running
my %importsRunning;
my $scantime;

# TODO make this into a hash of import functions.
sub startScan {
		
	$::d_info && msg("Clearing ID3 cache\n");
	Slim::Music::Info::clearCache();
	
	$::d_info && msg("Starting background scanning.\n");
	$scantime = Time::HiRes::time();
	if (Slim::Music::iTunes::useiTunesLibrary()) { 
		Slim::Music::iTunes::startScan();
	}

	if (Slim::Music::MoodLogic::useMoodLogic()) { 
		Slim::Music::MoodLogic::startScan();
	}

	Slim::Music::MusicFolderScan::startScan();
}


sub addImport {
	my $import = shift;
	$::d_info && msg("Adding $import Scan\n");
	$importsRunning{$import} = Time::HiRes::time();;
}

sub delImport {
	my $import = shift;
	if (exists $importsRunning{$import}) { 
		$::d_info && msg("Completing $import Scan in ".(Time::HiRes::time() - $importsRunning{$import})." seconds\n");
		delete $importsRunning{$import};
	}
	if (scalar keys %importsRunning == 0) {
		Slim::Music::Info::clearStaleCacheEntries();
		Slim::Music::Info::reBuildCaches();
		my $now = Time::HiRes::time();
		$scantime = $now - $scantime;
		$::d_info && msg("Finished background scanning at ".$scantime." seconds.\n");
		Slim::Music::Info::saveDBCache();
	}
}

sub stillScanning {
	return scalar keys %importsRunning;
}


1;
__END__

