package Slim::Plugin::LibraryDemo::Importer;

# Logitech Media Server Copyright 2001-2014 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Log;

sub initPlugin {
	my $class = shift;

	Slim::Music::Import->addImporter($class, {
		'type'         => 'post',
		'weight'       => 85,
		'use'          => 1,
	});

	return 1;
}

sub startScan {
	my $dbh = Slim::Schema->dbh;

	Slim::Utils::Log::logError('creating virtual library');

	$dbh->do( qq{
		INSERT OR IGNORE INTO library_track (library, track)
			SELECT 260370, tracks.id 
			FROM tracks 
			WHERE tracks.secs > 600
	} );
	
	Slim::Utils::Log::logError('virtual library done');
}

1;