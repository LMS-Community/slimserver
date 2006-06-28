package Slim::Music::MusicFolderScan;

# $Id
#
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Class::Data::Inheritable);

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Scanner;

{

	__PACKAGE__->mk_classdata('stillScanning');
}

sub init {
	my $class = shift;

	# Enable Folder scan only if audiodir is set and is a valid directory
	my $enabled  = 0;
	my $audioDir = Slim::Utils::Prefs::get('audiodir');

	if (defined $audioDir && -d $audioDir) {

		$enabled = 1;
	}

	Slim::Music::Import->addImporter($class);
	Slim::Music::Import->useImporter($class, $enabled);
}

sub startScan {
	my $class   = shift;
	my $dir     = shift || Slim::Utils::Prefs::get('audiodir');
	my $recurse = shift;

	if (!defined $dir || !-d $dir) {
		$::d_info && msg("Skipping music folder scan - audiodir is undefined. [$dir]\n");
		doneScanning();
		return;
	}

	if ($class->stillScanning) {

		$::d_info && msg("Scan already in progress. Restarting\n");

		$class->stillScanning(0);
	}

	$class->stillScanning(1);

	if (!defined $recurse) {
		$recurse = 1;
	}

	$::d_info && msg("Starting music folder scan in $dir\n");

	Slim::Utils::Scanner->scanDirectory({
		'url'       => $dir,
		'recursive' => $recurse,
		'types'     => 'audio',
	});

	$::d_info && msg("finished background scan of music folder.\n");

	$class->stillScanning(0);

	Slim::Music::Import->endImporter($class);
}

1;

__END__
