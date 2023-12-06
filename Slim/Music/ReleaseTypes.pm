package Slim::Music::ReleaseTypes;

# Logitech Media Server Copyright 2001-2023 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Music::Import;
use Slim::Schema;

use constant STEPS => 4;

# Let's use Apple's definition of EP/Single:
# https://diymusician.cdbaby.com/releasing-music/what-is-an-ep/#:~:text=EP%20stands%20for%20“extended%20play%2C”%20but%20the%20format,long%20playing%20—%20or%20“full%20length”%20—%20albums
use constant EP_CONDITION => '((title_count <= 3 AND max_duration >= 600) OR (title_count >= 4 AND title_count <= 6 AND max_duration < 600)) AND duration < 1800';
use constant SINGLE_CONDITION => 'title_count <= 3 AND duration < 1800 AND max_duration < 600';

my $prefs = preferences('server');
my $log = logger('database.info');

sub init {
	my $class = shift;

	Slim::Music::Import->addImporter( $class, {
		type   => 'post',
		weight => 90,
		use    => $prefs->get('cleanupReleaseTypes'),
	} );
}

# called by the scanner module
sub startScan {
	my $class = shift;

	my $progress = Slim::Utils::Progress->new({
		'type'  => 'importer',
		'name'  => 'releasetypes',
		'total' => STEPS,
		'bar'   => 1
	});

	my $dbh = Slim::Schema->dbh;

	# Step 1: create album list with track counts, duration etc.
	my $temp = (main::DEBUGLOG && $log->is_debug) ? '' : 'TEMPORARY';
	$dbh->do('DROP TABLE IF EXISTS release_type_helper');
	$dbh->do( qq(
		CREATE $temp TABLE release_type_helper AS
			SELECT album,
				COUNT(1) AS title_count,
				SUM(secs) AS duration,
				MAX(secs) AS max_duration,
				albums.compilation,
				discc
			FROM tracks
				JOIN albums ON albums.id = album
			WHERE release_type = 'ALBUM' AND
				(discc <= 1 OR discc IS NULL) AND
				(compilation != 1 OR compilation IS NULL)
			GROUP BY album
	) );

	$progress->update('.');

	my $updateSQL = q(
		UPDATE albums
			SET release_type = '%s'
		WHERE id IN (
			SELECT album
			FROM release_type_helper
			WHERE %s
		)
	);

	# Step 2: Singles
	$dbh->do(sprintf($updateSQL, 'SINGLE', SINGLE_CONDITION));
	$progress->update('.');

	# Step 3: EPs
	$dbh->do(sprintf($updateSQL, 'EP', EP_CONDITION));
	$progress->update('.');

	# Step 4: "EP" in the title
	$dbh->do( q(
		UPDATE albums
			SET release_type = 'EP'
		WHERE release_type = 'ALBUM' AND title REGEXP '[^\w.]+EP\b'
	) );

	$dbh->do('DROP TABLE IF EXISTS release_type_helper');

	$progress->final(STEPS);

	Slim::Music::Import->endImporter($class);
}

1;