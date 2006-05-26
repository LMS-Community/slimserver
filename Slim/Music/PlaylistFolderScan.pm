package Slim::Music::PlaylistFolderScan;

# $Id
#
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Class::Data::Inheritable);

use Slim::Utils::Misc;

{

	__PACKAGE__->mk_classdata('stillScanning');
}

sub init {
	my $class = shift;

	Slim::Music::Import->addImporter($class, {
		'playlistOnly' => 1,
	});

	# Enable Folder scan only if playlistdir is set and is a valid directory
	my $enabled  = 0;
	my $playlistDir = Slim::Utils::Prefs::get('playlistdir');

	if (defined $playlistDir && -d $playlistDir) {

		$enabled = 1;
	}

	Slim::Music::Import->useImporter($class, $enabled);
}

sub startScan {
	my $class       = shift;
	my $playlistDir = shift || Slim::Utils::Prefs::get('playlistdir');

	if (!defined $playlistDir || !-d $playlistDir) {
		$::d_info && msg("Skipping playlist folder scan - playlistdir is undefined.\n");
		doneScanning();
		return;
	}

	if ($class->stillScanning) {

		$::d_info && msg("Scan already in progress. Restarting\n");

		$class->stillScanning(0);
	} 

	$class->stillScanning(1);

	$::d_info && msg("Starting playlist folder scan\n");

	Slim::Utils::Scanner->scanDirectory({
		'url' => $playlistDir,
	});

	$class->doneScanning;
}

sub doneScanning {
	my $class = shift;

	# If scan aborted, $stillScanning will already be false.
	return if !$class->stillScanning;

	$::d_info && msg("finished background scan of playlist folder.\n");

	$class->stillScanning(0);

	Slim::Music::Import->endImporter('PLAYLIST');
}

1;

__END__
