package Slim::Schema::Manager;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2025 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use warnings;

use File::Spec::Functions qw(catdir);

use DBIx::Migration;
use Slim::Utils::Log;
use Slim::Utils::Progress;
use Slim::Utils::SQLHelper;
use Slim::Utils::OSDetect;

my $log = logger('database.info');

sub wipeDB {
	my ($class, $schemaClass) = @_;

	my $log = logger('scan.import');

	main::INFOLOG && $log->is_info && $log->info("Start schema_clear");

	my ($driver) = $schemaClass->sourceInformation;

	eval {
		Slim::Utils::SQLHelper->executeSQLFile(
			$driver, $schemaClass->storage->dbh, "schema_clear.sql"
		);

		$schemaClass->migrateDB;
	};

	if ($@) {
		logError("Failed to clear & migrate schema: [$@]");
	}

	main::INFOLOG && $log->is_info && $log->info("End schema_clear");
}

sub optimizeDB {
	my ($class, $schemaClass) = @_;

	my $log = logger('scan.import');

	main::INFOLOG && $log->is_info && $log->info("Start schema_optimize");

	my ($driver) = $schemaClass->sourceInformation;

	my $progress = Slim::Utils::Progress->new({
		'type'  => 'importer',
		'name'  => 'dboptimize',
		'total' => 2,
		'bar'   => 1
	});

	eval {
		Slim::Utils::SQLHelper->executeSQLFile(
			$driver, $schemaClass->storage->dbh, "schema_optimize.sql"
		);

		$progress->update();
		$schemaClass->forceCommit;

		# This calls back to OSDetect -> sqlHelper -> optimizeDB
		Slim::Utils::OSDetect->getOS()->sqlHelperClass()->optimizeDB();
	};

	$progress->final(2);

	if ($@) {
		logError("Failed to optimize schema: [$@]");
	}

	main::INFOLOG && $log->is_info && $log->info("End schema_optimize");
}

sub migrateDB {
	my ($class, $schemaClass) = @_;

	my $dbh = $schemaClass->storage->dbh;
	my ($driver, $source, $username, $password) = $schemaClass->sourceInformation;

	# Migrate to the latest schema version - see SQL/$driver/schema_\d+_up.sql
	my $dbix = DBIx::Migration->new({
		dbh   => $dbh,
		dir   => catdir(scalar Slim::Utils::OSDetect::dirsFor('SQL'), $driver),
		debug => $log->is_debug,
	});

	# Hide errors that aren't really errors
	my $cur_handler = $dbh->{HandleError};
	my $new_handler = sub {
		return 1 if $_[0] =~ /no such table/;
		goto $cur_handler;
	};

	local $dbh->{HandleError} = $new_handler;

	my $old = $dbix->version || 0;

	if ($dbix->migrate) {

		my $new = $dbix->version || 0;

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf("Connected to database $source - schema version: [%d]", $new));
		}

		if ($old != $new) {

			if ( $log->is_warn ) {
				$log->warn(sprintf("Migrated database from schema version: %d to version: %d", $old, $new));
			}

			return 1;

		}

	} else {

		# this occurs if a user downgrades Lyrion Music Server to a version with an older schema and which does not include
		# the required downgrade sql scripts - attempt to drop and create the database at current schema version

		if ( $log->is_warn ) {
			$log->warn(sprintf("Unable to downgrade database from schema version: %d - Attempting to recreate database", $old));
		}

		eval { $schemaClass->storage->dbh->do('DROP TABLE IF EXISTS dbix_migration') };

		if ($dbix->migrate) {

			if ( $log->is_warn ) {
				$log->warn(sprintf("Successfully created database at schema version: %d", $dbix->version));
			}

			return 1;

		}

		logError(sprintf("Unable to create database - **** You may need to manually delete the database ****", $old));

	}

	return 0;
}

1;
