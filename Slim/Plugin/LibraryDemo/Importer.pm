package Slim::Plugin::LibraryDemo::Importer;

# Logitech Media Server Copyright 2001-2014 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Music::VirtualLibraries;
use Slim::Utils::Log;

my $library_id;

sub initPlugin {
	my $class = shift;

	$library_id ||= Slim::Music::VirtualLibraries->registerLibrary({
		id => 260370,
	});

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
			SELECT '$library_id', tracks.id 
			FROM tracks 
			WHERE tracks.secs > 600
	} );
	
	Slim::Utils::Log::logError('virtual library done');
}

1;