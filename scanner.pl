#!/usr/bin/perl

# Logitech Media Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

require 5.008_001;
use strict;

use FindBin qw($Bin);
use lib $Bin;

use constant SLIM_SERVICE => 0;
use constant SCANNER      => 1;
use constant RESIZER      => 0;
use constant TRANSCODING  => 0;
use constant PERFMON      => 0;
use constant DEBUGLOG     => ( grep { /--nodebuglog/ } @ARGV ) ? 0 : 1;
use constant INFOLOG      => ( grep { /--noinfolog/ } @ARGV ) ? 0 : 1;
use constant STATISTICS   => ( grep { /--nostatistics/ } @ARGV ) ? 0 : 1;
use constant SB1SLIMP3SYNC=> 0;
use constant IMAGE        => ( grep { /--noimage/ } @ARGV ) ? 0 : 1;
use constant VIDEO        => ( grep { /--novideo/ } @ARGV ) ? 0 : 1;
use constant MEDIASUPPORT => IMAGE || VIDEO;
use constant WEBUI        => 0;
use constant ISWINDOWS    => ( $^O =~ /^m?s?win/i ) ? 1 : 0;
use constant ISMAC        => ( $^O =~ /darwin/i ) ? 1 : 0;
use constant HAS_AIO      => 0;
use constant LOCALFILE    => 0;

# Tell PerlApp to bundle these modules
if (0) {
	require 'auto/Compress/Raw/Zlib/autosplit.ix';
}

BEGIN {
	use Slim::bootstrap;
	use Slim::Utils::OSDetect;

	Slim::bootstrap->loadModules([qw(version Time::HiRes DBI HTML::Parser XML::Parser::Expat YAML::XS)], []);
	
	# By default, tell Audio::Scan not to get artwork to save memory
	# Where needed, this is locally changed to 0.
	$ENV{AUDIO_SCAN_NO_ARTWORK} = 1;
};

# Force XML::Simple to use XML::Parser for speed. This is done
# here so other packages don't have to worry about it. If we
# don't have XML::Parser installed, we fall back to PurePerl.
# 
# Only use XML::Simple 2.15 an above, which has support for pass-by-ref
use XML::Simple qw(2.15);

eval {
	local($^W) = 0;      # Suppress warning from Expat.pm re File::Spec::load()
	require XML::Parser; 
};

if (!$@) {
	$XML::Simple::PREFERRED_PARSER = 'XML::Parser';
}

use Getopt::Long;
use File::Path;
use File::Spec::Functions qw(:ALL);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Music::Import;
use Slim::Music::Info;
use Slim::Music::PlaylistFolderScan;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::PluginManager;
use Slim::Utils::Progress;
use Slim::Utils::Scanner;
use Slim::Utils::Strings qw(string);
use Slim::Media::MediaFolderScan;

if ( INFOLOG || DEBUGLOG ) {
    require Data::Dump;
	require Slim::Utils::PerlRunTime;
}

our $VERSION     = '7.8.1';
our $REVISION    = undef;
our $BUILDDATE   = undef;

our $prefs;
our $progress;
our $pidfile;

my $sqlHelperClass = Slim::Utils::OSDetect->getOS()->sqlHelperClass();
eval "use $sqlHelperClass";
die $@ if $@;

sub main {

	our ($rescan, $playlists, $wipe, $force, $cleanup, $prefsFile, $priority);
	our ($quiet, $dbtype, $logfile, $logdir, $logconf, $debug, $help, $nodebuglog, $noinfolog, $nostatistics, $noimages, $novideo);

	our $LogTimestamp = 1;
	
	my $changes = 0;

	$prefs = preferences('server');

	$prefs->readonly;

	GetOptions(
		'force'        => \$force,
		'cleanup'      => \$cleanup,
		'rescan'       => \$rescan,
		'wipe'         => \$wipe,
		'playlists'    => \$playlists,
		'prefsfile=s'  => \$prefsFile,
		'pidfile=s'    => \$pidfile,
		# prefsdir parsed by Slim::Utils::Prefs
		'noimage'      => \$noimages,
		'novideo'      => \$novideo,
		'nodebuglog'   => \$nodebuglog,
		'noinfolog'    => \$noinfolog,
		'nostatistics' => \$nostatistics,
		'progress'     => \$progress,
		'priority=i'   => \$priority,
		'logfile=s'    => \$logfile,
		'logdir=s'     => \$logdir,
		'logconfig=s'  => \$logconf,
		'debug=s'      => \$debug,
		'quiet'        => \$quiet,
		'dbtype=s'     => \$dbtype,
		'LogTimestamp!'=> \$LogTimestamp,
		'help'         => \$help,
	);

	save_pid_file();
	
	# If dbsource has been changed via settings, it overrides the default
	if ( $prefs->get('dbtype') ) {
		$dbtype ||= $prefs->get('dbtype') =~ /SQLite/ ? 'SQLite' : 'MySQL';
	}
	
	if ( $dbtype ) {
		# For testing SQLite, can specify a different database type
		$sqlHelperClass = "Slim::Utils::${dbtype}Helper";
		eval "use $sqlHelperClass";
		die $@ if $@;
	}
	
	# Start a fresh scanner.log on every scan
	if ( my $file = Slim::Utils::Log->scannerLogFile() ) {
		unlink $file if -e $file;
	}

	Slim::Utils::Log->init({
		'logconf' => $logconf,
		'logdir'  => $logdir,
		'logfile' => $logfile,
		'logtype' => 'scanner',
		'debug'   => $debug,
	});

	if ($help || (!$rescan && !$wipe && !$playlists)) {
		usage();
		exit;
	}
	
	# Start/stop profiler during runtime (requires Devel::NYTProf)
	# and NYTPROF env var set to 'start=no'
	if ( $ENV{NYTPROF} && $INC{'Devel/NYTProf.pm'} && $ENV{NYTPROF} =~ /start=no/ ) {
		$SIG{USR1} = sub {
			DB::enable_profile();
			warn "Profiling enabled...\n";
		};
	
		$SIG{USR2} = sub {
			DB::disable_profile();
			warn "Profiling disabled...\n";
		};
	}
	

	# Redirect STDERR to the log file.
	if (!$progress) {
		tie *STDERR, 'Slim::Utils::Log::Trapper';
	}

	STDOUT->autoflush(1);

	my $log = logger('server');
	
	($REVISION, $BUILDDATE) = Slim::Utils::Misc::parseRevision();

	$log->error("Starting Logitech Media Server scanner (v$VERSION, $REVISION, $BUILDDATE) perl $]");

	# Bring up strings, database, etc.
	initializeFrameworks($log);

	# Set priority, command line overrides pref
	if (defined $priority) {
		Slim::Utils::Misc::setPriority($priority);
	} else {
		Slim::Utils::Misc::setPriority( $prefs->get('scannerPriority') );
	}
	
	# Load appropriate DB module
	my $dbModule = $sqlHelperClass =~ /MySQL/ ? 'DBD::mysql' : 'DBD::SQLite';
	Slim::bootstrap::tryModuleLoad($dbModule);
	if ( $@ ) {
		logError("Couldn't load $dbModule [$@]");
		exit;
	}
	
	if ( $sqlHelperClass ) {
		main::INFOLOG && $log->info("Server SQL init...");
		$sqlHelperClass->init();
	}

	if (!$force && Slim::Music::Import->stillScanning) {

		msg("Import: There appears to be an existing scanner running.\n");
		msg("Import: If this is not the case, run with --force\n");
		msg("Exiting!\n");
		exit;
	}
	
	# pull in the memory usage module if requested.
	if (main::INFOLOG && logger('server.memory')->is_info) {
		
		Slim::bootstrap::tryModuleLoad('Slim::Utils::MemoryUsage');

		if ($@) {

			logError("Couldn't load Slim::Utils::MemoryUsage: [$@]");

		} else {

			Slim::Utils::MemoryUsage->init();
		}
	}
	
	main::INFOLOG && $log->info("Cache init...");
	Slim::Utils::Cache->init();

	if ($playlists) {

		Slim::Music::PlaylistFolderScan->init;
		Slim::Music::Import->scanPlaylistsOnly(1);

	} else {

		Slim::Media::MediaFolderScan->init;
		Slim::Music::PlaylistFolderScan->init;
	}
	
	# Load any plugins that define import modules
	# useCache is 0 so scanner does not modify the plugin cache file
	Slim::Utils::PluginManager->init( 'import', 0 );
	Slim::Utils::PluginManager->load('import');

	checkDataSource();

	main::INFOLOG && $log->info("Scanner done init...\n");
	
	# Perform pre-scan steps specific to the database type, i.e. SQLite needs to copy to a new file
	$sqlHelperClass->beforeScan();

	# Take the db out of autocommit mode - this makes for a much faster scan.
	# Scanner::Local will commit every few operations
	Slim::Schema->dbh->{'AutoCommit'} = 0;

	my $scanType = 'SETUP_STANDARDRESCAN';

	if ($wipe) {
		$scanType = 'SETUP_WIPEDB';

	} elsif ($playlists) {
		$scanType = 'SETUP_PLAYLISTRESCAN';
	}

	# Flag the database as being scanned.
	Slim::Music::Import->setIsScanning($scanType);

	if ($cleanup) {
		Slim::Music::Import->cleanupDatabase(1);
	}

	if ($wipe) {

		eval { Slim::Schema->wipeAllData; };

		if ($@) {
			logError("Failed when calling Slim::Schema->wipeAllData: [$@]");
			logError("This is a fatal error. Exiting");
			exit(-1);
		}
	}

	# Don't wrap the below in a transaction - we want to have the server
	# periodically update the db. This is probably better than a giant
	# commit at the end, but is debatable.
	# 
	# NB: Slim::Schema::throw_exception really isn't right now - it's just
	# printing an error and bt(). Once the server can handle & log
	# exceptions properly, it should croak(), so the exception is
	# propagated to the higher levels.
	#

	# Use our Importers to scan.
	eval {

		if ($wipe) {
			Slim::Music::Import->resetImporters;
		}

		$changes = Slim::Music::Import->runScan;
	};

	if ($@) {

		logError("Failed when running main scan: [$@]");
		logError("Skipping post-process & Not updating lastRescanTime!");

	} else {

		# Run mergeVariousArtists, artwork scan, etc.
		eval { Slim::Music::Import->runScanPostProcessing; }; 

		if ($@) {

			logError("Failed when running scan post-process: [$@]");
			logError("Not updating lastRescanTime!");

		} else {

			if ($changes) {
				Slim::Music::Import->setLastScanTime;
				Slim::Music::Import->setLastScanTimeIsDST();
			}

			# Notify server we are done scanning
			$sqlHelperClass->afterScan();
		}
	}

	# Wipe templates if they exist.
	rmtree( catdir($prefs->get('cachedir'), 'templates') );
	
	# Cleanup after we're done, we can't rely on this being called from a sig handler
	cleanup();
	
	# To debug scanner memory usage, uncomment this line and kill -USR2 the scanner process
	# after it's finished scanning.
	# while (1) { sleep 1 }
}

sub initializeFrameworks {
	my $log = shift;

	main::INFOLOG && $log->info("Server OSDetect init...");

	Slim::Utils::OSDetect::init();
	Slim::Utils::OSDetect::getOS->initSearchPath();

	# initialize Server subsystems
	main::INFOLOG && $log->info("Server settings init...");

	Slim::Utils::Prefs::init();

	Slim::Utils::Prefs::makeCacheDir();	

	main::INFOLOG && $log->info("Server strings init...");

	Slim::Utils::Strings::init(catdir($Bin,'strings.txt'), "EN");

	main::INFOLOG && $log->info("Server Info init...");

	Slim::Music::Info::init();

	# Bug 16188 - create dummy protocol entries for all protocol handlers known to the main server
	# this ensures that when we scan a url for one of these protocols we treat it as a valid remote entry

	for my $handler(@{$prefs->get('registeredhandlers') || []}) {

		if (!defined Slim::Player::ProtocolHandlers->handlerForProtocol($handler)) {
			Slim::Player::ProtocolHandlers->registerHandler( $handler => 1 );
		}
	}
}

sub usage {
	print <<EOF;
Usage: $0 [debug options] [--rescan] [--wipe]

Command line options:

	--force        Force a scan, even if we think a scan is already taking place.
	--cleanup      Run a database cleanup job at the end of the scan
	--rescan       Look for new files since the last scan.
	--wipe         Wipe the DB and start from scratch
	--playlists    Only scan files in your playlistdir.
	--progress     Show a progress bar of the scan.
	--dbtype TYPE  Force database type (valid values are MySQL or SQLite)
	--prefsdir     Specify alternative preferences directory.
	--priority     set process priority from -20 (high) to 20 (low)
	--logfile      Send all debugging messages to the specified logfile.
	--logdir       Specify folder location for log file
	--logconfig    Specify pre-defined logging configuration file
	--noimage      Disable scanning for images.
	--novideo      Disable scanning for videos.
	--nodebuglog   Disable all debug-level logging (compiled out).
	--noinfolog    Disable all debug-level & info-level logging (compiled out).
	--nostatistics Disable the TracksPersistent table used to keep to statistics across rescans (compiled out).
	--debug        various debug options
	--quiet        keep silent
	
Examples:

	$0 --rescan

EOF

}

my $cleanupDone;
sub cleanup {
	
	# cleanup() is called at the end of main() and possibly again from a sig handler
	# We only want it to run once.
	return if $cleanupDone;	
	$cleanupDone = 1;
	
	Slim::Utils::PluginManager->shutdownPlugins();

	# Make sure to flush anything in the database to disk.
	if ($INC{'Slim/Schema.pm'} && Slim::Schema->storage) {
		Slim::Music::Import->setIsScanning(0);

		Slim::Schema->forceCommit;
		
		Slim::Schema->disconnect;
	}
	
	# Notify server we are exiting
	$sqlHelperClass->exitScan();
	
	$sqlHelperClass->cleanup;

	remove_pid_file();
}

sub checkDataSource {
	my $mediadirs = Slim::Utils::Misc::getMediaDirs();
	my $modified = 0;

	foreach my $audiodir (@$mediadirs) {
		if (defined $audiodir && $audiodir =~ m|[/\\]$|) {
			$audiodir =~ s|[/\\]$||;
			$modified++;
		}
	}

	$prefs->set('mediadirs', $mediadirs) if $modified;

	return if !Slim::Schema::hasLibrary();
	
	$sqlHelperClass->checkDataSource();
}

sub save_pid_file {
	if (defined $pidfile) {
		logger('')->info("Scanner saving pid file.");
		File::Slurp::write_file($pidfile, $$);
	}
}

sub remove_pid_file {
	if (defined $pidfile) {
		unlink $pidfile;
	}
}

sub END {
	Slim::bootstrap::theEND();
}

sub idleStreams {}

main();

__END__
