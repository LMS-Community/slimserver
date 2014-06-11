package Slim::Plugin::LibraryDemo::Importer;

# Logitech Media Server Copyright 2001-2014 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Music::VirtualLibraries;
use Slim::Utils::Log;

my $library_id;

my $libraries = [{
	id => 'demoLongTracks',
	name => 'Longish tracks only',
	sql => qq{
		INSERT OR IGNORE INTO library_track (library, track)
			SELECT '%s', tracks.id 
			FROM tracks 
			WHERE tracks.secs > 600
	}
},{
	id => 'demoFLACOnly',
	name => 'FLAC files only',
	sql => qq{
		INSERT OR IGNORE INTO library_track (library, track)
			SELECT '%s', tracks.id 
			FROM tracks 
			WHERE tracks.content_type = 'flc'
	}
},{
	id => 'loveThisDemo',
	name => 'Love is in the air (and in album/track titles)',
	sql => qq{
		INSERT OR IGNORE INTO library_track (library, track)
			SELECT '%s', tracks.id
			FROM tracks 
			JOIN albums ON tracks.album = albums.id 
			WHERE tracks.titlesearch LIKE '%%LOVE%%' OR albums.titlesearch LIKE '%%LOVE%%'
	}
}];

sub initPlugin {
	my $class = shift;

	foreach ( @$libraries ) {
		Slim::Music::VirtualLibraries->registerLibrary({
			id => $_->{id},
			name => $_->{name}
		});
	}

	Slim::Music::Import->addImporter($class, {
		'type'         => 'post',
		'weight'       => 95,
		'use'          => 1,
	});

	return 1;
}

sub startScan {
	my $dbh = Slim::Schema->dbh;

	Slim::Utils::Log::logError('creating virtual library');

	foreach ( @$libraries ) {
		$dbh->do( sprintf($_->{sql}, Slim::Music::VirtualLibraries->getRealId($_->{id})) );
	}
	
	Slim::Utils::Log::logError('virtual library done');
}

1;