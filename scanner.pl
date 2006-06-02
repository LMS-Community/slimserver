#!/usr/bin/perl -w

# SlimServer Copyright (C) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

use strict;
use warnings;

use FindBin qw($Bin);
use lib $Bin;

BEGIN {
	use Slim::bootstrap;
	use Slim::Utils::OSDetect;

	Slim::bootstrap->loadModules([qw(Time::HiRes DBD::mysql DBI XML::Parser YAML::Syck)], []);
};

use Getopt::Long;
use File::Spec::Functions qw(:ALL);

use Slim::Music::Import;
use Slim::Music::Info;
use Slim::Music::MusicFolderScan;
use Slim::Music::PlaylistFolderScan;
use Slim::Utils::Misc;
use Slim::Utils::MySQLHelper;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner;
use Slim::Utils::Strings qw(string);

sub main {

	our ($d_startup, $d_info, $d_remotestream, $d_parse, $d_scan, $d_sql, $d_itunes, $d_server, $d_import);
	our ($rescan, $playlists, $wipe, $itunes, $musicmagic, $force, $cleanup, $prefsFile, $progress);

	our $LogTimestamp = 1;

	GetOptions(
		'force'       => \$force,
		'cleanup'     => \$cleanup,
		'rescan'      => \$rescan,
		'wipe'        => \$wipe,
		'playlists'   => \$playlists,
		'itunes'      => \$itunes,
		'musicmagic'  => \$musicmagic,
		'd_info'      => \$d_info,
		'd_server'    => \$d_server,
		'd_import'    => \$d_import,
		'd_parse'     => \$d_parse,
		'd_scan'      => \$d_scan,
		'd_sql'       => \$d_sql,
		'd_startup'   => \$d_startup,
		'd_itunes'    => \$d_itunes,
		'prefsfile=s' => \$prefsFile,
		'progress'    => \$progress,
	);

	if (!$rescan && !$wipe && !$playlists && !$musicmagic && !$itunes && !scalar @ARGV) {
		usage();
		exit;
	}

	# Bring up strings, database, etc.
	initializeFrameworks();

	if (!$force && Slim::Music::Import->stillScanning) {

		msg("Import: There appears to be an existing scanner running.\n");
		msg("Import: If this is not the case, run with --force\n");
		msg("Exiting!\n");
		exit;
	}

	# Start up the file scanner code
	Slim::Utils::Scanner->init;

	if ($playlists) {

		Slim::Music::PlaylistFolderScan->init;
		Slim::Music::Import->scanPlaylistsOnly(1);

	} else {

		Slim::Music::PlaylistFolderScan->init;
		Slim::Music::MusicFolderScan->init;
	}

	# Various importers - should these be hardcoded?
	if ($itunes) {
		initClass('Plugins::iTunes::Importer');
	}

	if ($musicmagic) {
		initClass('Plugins::MusicMagic::Importer');
	}

	#$::d_server && msg("SlimServer checkDataSource...\n");
	#checkDataSource();

	$::d_server && msg("SlimServer done init...\n");

	# Start our transaction for the entire scan - this will enable an
	# atomic commit at the end.
	Slim::Schema->storage->dbh->{'AutoCommit'} = 0;
	Slim::Schema->storage->txn_begin;

	eval {

		if ($wipe) {
			Slim::Music::Info::wipeDBCache();
		}

		if ($cleanup) {
			Slim::Music::Import->cleanupDatabase(1);
		}

		# We've been passed an explict path or URL - deal with that.
		if (scalar @ARGV) {

			for my $url (@ARGV) {

				Slim::Utils::Scanner->scanPathOrURL({ 'url' => $url });
			}

		} else {

			# Otherwise just use our Importers to scan.
			Slim::Music::Import->resetImporters;
			Slim::Music::Import->startScan;
		}

		Slim::Schema->rs('MetaInformation')->update_or_create({
			'name'  => 'lastRescanTime',
			'value' => time,
		});

		Slim::Schema->storage->txn_commit;
	};

	if ($@) {
		my $error = $@;

		errorMsg("scanner - while running txn_commit: [$error]\n");

		eval { Slim::Schema->storage->txn_rollback };

		if ($@ && $error ne $@) {
			errorMsg("scanner: Rollback failed: [$@]\n");
		}
	}
}

sub initializeFrameworks {

	$::d_server && msg("SlimServer OSDetect init...\n");
	Slim::Utils::OSDetect::init();

	$::d_server && msg("SlimServer OS Specific init...\n");

	# initialize slimserver subsystems
	$::d_server && msg("SlimServer settings init...\n");

	Slim::Utils::Prefs::init();
	Slim::Utils::Prefs::load($::prefsFile);

	Slim::Utils::Prefs::set('prefsWriteDelay', 0);

	Slim::Utils::Prefs::checkServerPrefs();

	Slim::Utils::Prefs::makeCacheDir();	

	$::d_server && msg("SlimServer strings init...\n");
	Slim::Utils::Strings::init(catdir($Bin,'strings.txt'), "EN");

	# $::d_server && msg("SlimServer MySQL init...\n");
	# Slim::Utils::MySQLHelper->init();

	$::d_server && msg("SlimServer Info init...\n");
	Slim::Music::Info::init();
}

sub usage {
	print <<EOF;
Usage: $0 [debug options] [--rescan] [--wipe] [--itunes] [--musicmagic] <path or URL>

Command line options:

	--force       Force a scan, even if we think a scan is already taking place.
	--cleanup     Run a database cleanup job at the end of the scan
	--rescan      Look for new files since the last scan.
	--wipe        Wipe the DB and start from scratch
	--playlists   Only scan files in your playlistdir.
	--itunes      Run the iTunes Importer.
	--musicmagic  Run the MusicMagig Importer.
	--progress    Show a progress bar of the scan.
	--prefsfile   Specify an alternate prefs file.

Debug flags:

	--d_info      Miscellaneous Info
	--d_server    Initialization phase
	--d_import    Show Import Stages
	--d_parse     Playlist parsing, etc.
	--d_scan      Show the files that are being scanned.
	--d_sql       Show all SQL statements being executed. (Lots of output)
	--d_itunes    iTunes debugging / XML file parsing.

Examples:

	$0 --rescan /Users/dsully/Music

	$0 http://www.somafm.com/groovesalad.pls

EOF

}

sub initClass {
	my $class = shift;

	eval "use $class";

	if ($@) {
		errorMsg("Couldn't load $class: $@\n");
	} else {
		$class->initPlugin;
	}
}

sub cleanup {

	$::d_server && msg("SlimServer cleaning up.\n");

	# Make sure to flush anything in the database to disk.
	if ($INC{'Slim/Schema.pm'}) {
		Slim::Schema->forceCommit;
		Slim::Schema->disconnect;
	}
}

main();

__END__
