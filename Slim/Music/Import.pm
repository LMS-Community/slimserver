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

# Force a rescan of all the importers (TODO: Make importers pluggable)
sub startScan {
		
	$::d_info && msg("Clearing ID3 cache\n");
	Slim::Music::Info::clearCache();
	$scantime = Time::HiRes::time();
	
	$::d_info && msg("Starting background folder, itunes and moodlogic scanning.\n");
	Slim::Music::MusicFolderScan::startScan();
	Slim::Music::iTunes::startScan();
	Slim::Music::MoodLogic::startScan();
}

sub startup {
	$::d_info && msg("Starting itunes and/or moodlogic background scanners.\n");

	Slim::Music::iTunes::checker();
	Slim::Music::MoodLogic::checker();
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

