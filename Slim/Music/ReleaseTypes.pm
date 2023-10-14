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

use constant STEPS => 3;

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
			WHERE title_count > %s AND
				title_count <= %s AND
				duration < %s
		)
	);

	# Step 2: Singles - 0 < tracks <= 1, 1400s
	$dbh->do(sprintf($updateSQL, 'SINGLE', 0, 1, 1400));
	$progress->update('.');

	# Step 3: EPs - 1 < tracks <= 3, 2000s
	$dbh->do(sprintf($updateSQL, 'EP', 1, 5, 2000));

	$progress->final(STEPS);

	Slim::Music::Import->endImporter($class);
}

1;