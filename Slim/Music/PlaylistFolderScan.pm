package Slim::Music::PlaylistFolderScan;

# $Id
#
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Utils::Misc;

my @dummylist = ();
my $stillScanning = 0;

sub init {

	Slim::Music::Import::addImporter('PLAYLIST', {
		'scan' => \&startScan
	});

	# Enable Folder scan only if playlistdir is set and is a valid directory
	my $enabled  = 0;
	my $playlistDir = Slim::Utils::Prefs::get('playlistdir');

	if (defined $playlistDir && -d $playlistDir) {

		$enabled = 1;
	}

	Slim::Music::Import::useImporter('PLAYLIST', $enabled);
}

sub startScan {

	my $playlistDir = Slim::Utils::Prefs::get('playlistdir');

	if (!defined $playlistDir || !-d $playlistDir) {
		$::d_info && msg("Skipping playlist folder scan - playlistdir is undefined.\n");
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

	$::d_info && msg("Starting playlist folder scan\n");
	Slim::Utils::Scan::addToList(\@dummylist, $playlistDir, 1, 0, \&doneScanning, 0);
}

sub doneScanning {
	#If scan aborted, $stillScanning will already be false.
	return unless $stillScanning;

	$::d_info && msg("finished background scan of playlist folder.\n");

	$stillScanning = 0;
	@dummylist = ();
	Slim::Music::Import::endImporter('PLAYLIST');
}

sub stillScanning {
	return $stillScanning;
}

1;

__END__
