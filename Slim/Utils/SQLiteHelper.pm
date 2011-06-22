package Slim::Utils::SQLiteHelper;

# $Id$

=head1 NAME

Slim::Utils::SQLiteHelper

=head1 SYNOPSIS

Slim::Utils::SQLiteHelper->init

=head1 DESCRIPTION

Currently only used for SN

=head1 METHODS

=cut

use strict;

use Digest::MD5 qw(md5_hex);
use File::Basename;
use File::Copy ();
use File::Path;
use File::Slurp;
use File::Spec::Functions qw(:ALL);
use JSON::XS::VersionOneAndTwo;
use Time::HiRes qw(sleep);

use Slim::Utils::ArtworkCache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::SQLHelper;
use Slim::Utils::Prefs;
use Slim::Utils::Progress;
use Slim::Utils::Strings ();

my $log = logger('database.info');

my $prefs = preferences('server');

sub storageClass { 'DBIx::Class::Storage::DBI::SQLite' };

sub default_dbsource { 'dbi:SQLite:dbname=%s' }

# Remember if the main server is running or not, to avoid LWP timeout delays
my $serverDown = 0;
use constant MAX_RETRIES => 5;

# Scanning flag is set during scanning	 
my $SCANNING = 0;

sub init {
	my ( $class, $dbh ) = @_;
	
	# Make sure we're running the right version of DBD::SQLite
	if ( $DBD::SQLite::VERSION lt 1.30 ) {
		die "DBD::SQLite version 1.30 or higher required\n";
	}
	
	if ( main::SLIM_SERVICE ) {
		# Create new empty database every time we startup on SN
		require File::Slurp;
		require FindBin;
		
		my $text = File::Slurp::read_file( "$FindBin::Bin/SQL/slimservice/slimservice-sqlite.sql" );
		
		$text =~ s/\s*--.*$//g;
		for my $sql ( split (/;/, $text) ) {
			next unless $sql =~ /\w/;
			$dbh->do($sql);
		}
	}
	
	# Reset dbsource pref if it's not for SQLite
	if ( $prefs->get('dbsource') !~ /^dbi:SQLite/ ) {
		$prefs->set( dbsource => default_dbsource() );
		$prefs->set( dbsource => $class->source() );
	}
	
	if ( !main::SLIM_SERVICE && !main::SCANNER ) {
		# Event handler for notifications from scanner process
		Slim::Control::Request::addDispatch(
			['scanner', 'notify', '_msg'],
			[0, 0, 0, \&_notifyFromScanner]
		);
	}
	
	if ( main::SCANNER ) {
		# At init time we need to notify the main process
		# to unlock the database so we can access it
		$class->updateProgress('unlock');
	}
}

sub source {
	my $source;
	
	if ( main::SLIM_SERVICE ) {
		my $config = SDI::Util::SNConfig::get_config();
		my $db = ( $config->{database}->{sqlite_path} || '.' ) . "/slimservice.$$.db";
		
		unlink $db if -e $db;
		
		$source = "dbi:SQLite:dbname=$db";
	}
	else {
		$source = sprintf( $prefs->get('dbsource'), catfile( $prefs->get('librarycachedir'), 'squeezebox.db' ) );
	}
	
	return $source;
}

sub on_connect_do {
	my $class = shift;
	
	my $sql = [
		'PRAGMA synchronous = OFF',
		#'PRAGMA journal_mode = WAL', # XXX WAL mode needs more work
		'PRAGMA journal_mode = MEMORY',
		'PRAGMA foreign_keys = ON',
	];
	
	# Wweak some memory-related pragmas if dbhighmem is enabled
	if ( $prefs->get('dbhighmem') ) {
		# Default cache_size is 2000 pages, a page is normally 1K but may be different
		# depending on the OS/filesystem.  So default is usually 2MB.
		# Highmem we will try 20M
		push @{$sql}, 'PRAGMA cache_size = 20000';
		
		# Default temp_store is to create disk files to save memory
		# Highmem we'll let it use memory
		push @{$sql}, 'PRAGMA temp_store = MEMORY';
	}
	
	if ( !main::SCANNER ) {
		# Use exclusive locking only in the main process
		push @{$sql}, 'PRAGMA locking_mode = EXCLUSIVE';
	}
	
	# We create this even if main::STATISTICS is not false so that the SQL always works
	# Track Persistent data is in another file
	my $persistentdb = $class->_dbFile('squeezebox-persistent.db');
	push @{$sql}, "ATTACH '$persistentdb' AS persistentdb";
	#push @{$sql}, 'PRAGMA persistentdb.journal_mode = WAL'; # XXX
	push @{$sql}, 'PRAGMA persistentdb.journal_mode = MEMORY';
	
	return $sql;
}

my $hasICU;
my $currentICU = '';
my $loadedICU = {};
sub collate { 
	# Use ICU if built into DBD::SQLite
	if ( !defined $hasICU ) {
		$hasICU = (DBD::SQLite->can('compile_options') && grep /ENABLE_ICU/, DBD::SQLite::compile_options());
	}
	
	if ($hasICU) {
		my $lang = $prefs->get('language');

		my $collation = Slim::Utils::Strings::getLocales()->{$lang};
		
		if ( $currentICU ne $collation ) {	
			if ( !$loadedICU->{$collation} ) {
				if ( !Slim::Schema->hasLibrary() ) {
					# XXX for i.e. ContributorTracks many_to_many
					return "COLLATE $collation ";
				}
				
				# Point to our custom small ICU collation data file
				$ENV{ICU_DATA} = Slim::Utils::OSDetect::dirsFor('strings');

				my $dbh = Slim::Schema->dbh;
                
				my $qcoll = $dbh->quote($collation);
				my $qpath = $dbh->quote($ENV{ICU_DATA});

				# Win32 doesn't always like to read the ICU_DATA env var, so pass it here too
				my $sql = main::ISWINDOWS
					? "SELECT icu_load_collation($qcoll, $qcoll, $qpath)"
					: "SELECT icu_load_collation($qcoll, $qcoll)";

				eval { $dbh->do($sql) };
				if ( $@ ) {
					$log->error("SQLite ICU collation $collation failed: $@");
					$hasICU = 0;
					return 'COLLATE perllocale ';
				}
				
				main::DEBUGLOG && $log->is_debug && $log->debug("Loaded ICU collation for $collation");
				
				$loadedICU->{$collation} = 1;
			}
			
			$currentICU = $collation;
		}
		
		return "COLLATE $currentICU ";
	}
	
	# Fallback to built-in perllocale collation to sort using Unicode Collation Algorithm
	# on systems with a properly installed locale.
	return 'COLLATE perllocale ';
}

=head2 randomFunction()

Returns RANDOM(), SQLite-specific random function

=cut

sub randomFunction { 'RANDOM()' }

=head2 prepend0( $string )

Returns SQLite-specific syntax '0 || $string'

=cut

sub prepend0 { '0 || ' . $_[1] }

=head2 append0( $string )

Returns SQLite-specific syntax '$string || 0'

=cut

sub append0 {  $_[1] . ' || 0' }

=head2 concatFunction()

Returns ' || ', SQLite's concat operator.

=cut

sub concatFunction { ' || ' }

=head2 sqlVersion( $dbh )

Returns the version of MySQL that the $dbh is connected to.

=cut

sub sqlVersion {
	my $class = shift;
	my $dbh   = shift || return 0;
	
	return 'SQLite';
}

=head2 sqlVersionLong( $dbh )

Returns the long version string, i.e. 5.0.22-standard

=cut

sub sqlVersionLong {
	my $class = shift;
	my $dbh   = shift || return 0;
	
	return 'DBD::SQLite ' . $DBD::SQLite::VERSION . ' (sqlite ' . $dbh->{sqlite_version} . ')';
}

=head2 canCacheDBHandle( )

Is it permitted to cache the DB handle for the period that the DB is open?

=cut

sub canCacheDBHandle {
	return 1;
}

=head2 checkDataSource()

Called to check the database, this is used to replace with a newer
scanner database if available.

=cut

sub checkDataSource {
	my $class = shift;
	
	# XXX remove for WAL
	my $scannerdb = $class->_dbFile('squeezebox-scanner.db');
	
	if ( -e $scannerdb ) {
		my $dbh = Slim::Schema->dbh;
		
		logWarning('Scanner database found, checking for a newer scan...');
		
		eval {
			$dbh->do( 'ATTACH ' . $dbh->quote($scannerdb) . ' AS scannerdb' );
			
			my ($isScanning)  = $dbh->selectrow_array("SELECT value FROM scannerdb.metainformation WHERE name = 'isScanning'");
			my ($lastMain)    = $dbh->selectrow_array("SELECT value FROM metainformation WHERE name = 'lastRescanTime'");
			my ($lastScanner) = $dbh->selectrow_array("SELECT value FROM scannerdb.metainformation WHERE name = 'lastRescanTime'");
			
			$lastMain ||= 0;
			
			$dbh->do( 'DETACH scannerdb' );
			
			if ( $isScanning ) {
				logWarning('A scan is currently in progress or the scanner crashed, ignoring scanner database');
				return;
			}
			
			main::DEBUGLOG && $log->is_debug && $log->debug("Last main scan: $lastMain / last scannerdb scan: $lastScanner");
			
			if ( $lastScanner > $lastMain ) {
				logWarning('Scanner database contains a newer scan, using it');
				$class->replace_with('squeezebox-scanner.db');
				return;
			}
			else {
				logWarning('Scanner database is older, removing it');
				unlink $scannerdb;
			}
		};
		
		if ( $@ ) {
			logWarning("Scanner database corrupted ($@), ignoring");
			
			eval { $dbh->do('DETACH scannerdb') };
		}
	}
	# XXX end WAL
}

=head2 replace_with( $from )

Replace database with newly scanned file, and reconnect.

=cut

sub replace_with {
	my ( $class, $from ) = @_;
	
	my $src = $class->_dbFile($from);
	my $dst = $class->_dbFile();
	
	if ( -e $src ) {
		Slim::Schema->disconnect;
		
		# XXX use sqlite_backup_from_file instead
		
		if ( !File::Copy::move( $src, $dst ) ) {
			die "Unable to replace_with from $src to $dst: $!";
		}
	
		main::INFOLOG && $log->is_info && $log->info("Database moved from $src to $dst");
	
		# Reconnect
		Slim::Schema->init;
	}
	else {
		die "Unable to replace_with: $src does not exist";
	}
}

=head2 beforeScan()

Called before a scan is started.  We copy the database to a new file and switch our $dbh over to it.

=cut

sub beforeScan {
	my $class = shift;

    # XXX remove for WAL
	my $to = 'squeezebox-scanner.db';
	
	my ($driver, $source, $username, $password) = Slim::Schema->sourceInformation;
	
	my ($dbname) = $source =~ /dbname=([^;]+)/;
	my $dbbase = File::Basename::basename($dbname);
	
	my $dest = $dbname;
	$dest   =~ s/$dbbase/$to/;
	$source =~ s/$dbbase/$to/;
	
	if ( -e $dbname ) {
		Slim::Schema->disconnect;
		
		# XXX use sqlite_backup_to_file instead
		
		if ( !File::Copy::copy( $dbname, $dest ) ) {
			die "Unable to copy_and_switch from $dbname to $dest: $!";
		}
		
		# Inform slimserver process that we are about to begin scanning
		# so it can switch into 'dirty' mode.  Doesn't bother to check if 
		# SC is running, if it's not running this message doesn't matter.
		$class->updateProgress('start');
		
		main::INFOLOG && $log->is_info && $log->info("Database copied from $dbname to $dest");
		
		# Reconnect to the new database
		Slim::Schema->init( $source );
	}
	else {
		die "Unable to copy_and_switch: $dbname does not exist";
	}
    # XXX end WAL
}

=head2 afterScan()

Called after a scan is finished. Notifies main server to copy back the scanner file.

=cut

sub afterScan {
	my $class = shift;
	
	# Checkpoint the database
	#$class->pragma('wal_checkpoint'); # XXX
	
	$class->updateProgress('end');
}

=head2 exitScan()

Called as the scanner process exits. Used by main process to detect scanner crashes.

=cut

sub exitScan {
	my $class = shift;
	
	$class->updateProgress('exit');
}

=head2 postConnect()

Called immediately after connect.  Sets up MD5() function.

=cut

sub postConnect {
	my ( $class, $dbh ) = @_;
	
	$dbh->func( 'MD5', 1, sub { md5_hex( $_[0] ) }, 'create_function' );
	
	# Reset collation load state
	$currentICU = '';
	$loadedICU = {};
	
	# Check if the DB has been optimized (stats analysis)
	if ( !main::SCANNER ) {
		# Check for the presence of the sqlite_stat1 table
		my ($count) = eval { $dbh->selectrow_array( "SELECT COUNT(*) FROM sqlite_stat1 WHERE tbl = 'tracks'", undef, () ) };
		
		if (!$count) {
			$log->error('Optimizing DB because of missing or empty sqlite_stat1 table');			
			Slim::Schema->optimizeDB();
		}
	}
}

sub updateProgress {
	my $class = shift;
	
	return if $serverDown > MAX_RETRIES;
	
	require LWP::UserAgent;
	require HTTP::Request;
	
	my $log = logger('scan.scanner');
	
	# Scanner does not have an event loop, so use sync HTTP here
	my $host = ( $prefs->get('httpaddr') || '127.0.0.1' ) . ':' . $prefs->get('httpport');
	
	my $ua = LWP::UserAgent->new(
		timeout => 5,
	);
	
	my $req = HTTP::Request->new( POST => "http://${host}/jsonrpc.js" );
	
	$req->header( 'X-Scanner' => 1 );
	
	# Handle security if necessary
	if ( my $username = $prefs->get('username') ) {
		my $password = $prefs->get('password');
		$req->authorization_basic($username, $password);
	}
	
	$req->content( to_json( {
		id     => 1,
		method => 'slim.request',
		params => [ '', [ 'scanner', 'notify', @_ ] ],
	} ) );
	
	main::INFOLOG && $log->is_info
		&& $log->info( 'Notify to server: ' . Data::Dump::dump(\@_) );
	
	my $res = $ua->request($req);

	if ( $res->is_success ) {
		if ( $res->content =~ /abort/ ) {
			logWarning('Server aborted scan, shutting down');
			exit;
		}
		else {
			main::INFOLOG && $log->is_info && $log->info('Notify to server OK');
		}
		$serverDown = 0;
	}
	else {
		main::INFOLOG && $log->is_info && $log->info( 'Notify to server failed: ' . $res->status_line );
		
		if ( $res->content =~ /timeout|refused/ ) {
			# Server is down, avoid further requests
			$serverDown++;
		}
	}
}

=head2 cleanup()

Shut down when Logitech Media Server is shut down.

=cut

sub cleanup { }

=head2 pragma()

Run a given PRAGMA statement.

=cut

sub pragma {
	my ( $class, $pragma ) = @_;
	
	my $dbh = Slim::Schema->dbh;
	$dbh->do("PRAGMA $pragma");
	
	if ( $pragma =~ /locking_mode/ ) {
		# if changing the locking_mode we need to run a statement on each database to change the lock
		$dbh->do('SELECT 1 FROM metainformation LIMIT 1');
		$dbh->do('SELECT 1 FROM tracks_persistent LIMIT 1');
	}
	
	# Pass the pragma to the ArtworkCache database
	Slim::Utils::ArtworkCache->new->pragma($pragma);
}

sub _dbFile {
	my ( $class, $name ) = @_;
	
	my ($driver, $source, $username, $password) = Slim::Schema->sourceInformation;
	
	my ($dbname) = $source =~ /dbname=([^;]+)/;
	
	return $dbname unless $name;
	
	my $dbbase = basename($dbname);
	$dbname =~ s/$dbbase/$name/;
	
	return $dbname;
}

sub _notifyFromScanner {
	my $request = shift;
	
	my $class = __PACKAGE__;
	
	my $msg = $request->getParam('_msg');
	
	my $log = logger('scan.scanner');
	
	main::INFOLOG && $log->is_info && $log->info("Notify from scanner: $msg");
	
	if ( $msg eq 'unlock' ) {
		$class->pragma('locking_mode = NORMAL');
	}
	
	# If user aborted the scan, return an abort message
	if ( Slim::Music::Import->hasAborted ) {
		$request->addResult( abort => 1 );
		$request->setStatusDone();
		
		Slim::Music::Import->setAborted(0);
		Slim::Music::Import->clearProgressInfo();
		
		return;
	}
	
	if ( $msg eq 'start' ) {
		# Scanner has started
		$SCANNING = 1;
		
		if ( $prefs->get('autorescan') ) {
			Slim::Utils::AutoRescan->shutdown;
		}
		
		Slim::Utils::Progress->clear;
		
		Slim::Music::Import->setIsScanning('SETUP_WIPEDB');
		
		# XXX if scanner doesn't report in with regular progress within a set time period
		# assume scanner is dead.  This is hard to do, as scanner may block for an indefinite
		# amount of time with slow network filesystems, or a large amount of files.
	}
	elsif ( $msg =~ /^progress:([^-]+)-([^-]+)-([^-]+)-([^-]*)-([^-]*)-([^-]+)?/ ) {
		if ( $SCANNING  && Slim::Schema::hasLibrary() ) {
			# update progress
			my ($start, $type, $name, $done, $total, $finish) = ($1, $2, $3, $4, $5, $6);
		
			$done  = 1 if !defined $done;
			$total = 1 if !defined $total;
			
			my $progress = Slim::Schema->rs('Progress')->find_or_create( {
				type => $type,
				name => $name,
			} );
		
			$progress->set_columns( {
				start  => $start,
				total  => $total,
				done   => $done,
				active => $finish ? 0 : 1,
			} );
		
			if ( $finish ) {
				$progress->finish( $finish );
			}
		
			$progress->update;
		}
	}
	elsif ( $msg eq 'end' ) {
		if ( $SCANNING ) {
			# Scanner has finished.
			$SCANNING = 0;
		}
	}
	elsif ( $msg eq 'exit' ) {
		# Scanner is exiting.  If we get this without an 'end' message
		# the scanner aborted and we should throw away the scanner database
		
		if ( $SCANNING ) {
			# XXX remove for WAL
			my $db = $class->_dbFile('squeezebox-scanner.db');
			
			if ( -e $db ) {
				main::INFOLOG && $log->is_info && $log->info("Scanner aborted, removing $db");
				unlink $db;
			}
			# XXX end WAL
			
			$SCANNING = 0;
			
			Slim::Music::Import->setIsScanning(0);
			
			# Reset locking mode
			$class->pragma('locking_mode = EXCLUSIVE');
		}
		else {
			# Replace our database with the scanner database. Note that the locking mode
			# is set to exclusive when we reconnect to squeezebox.db.
			# XXX remove next line for WAL
			$class->replace_with('squeezebox-scanner.db') if Slim::Schema::hasLibrary();
			
			# XXX handle players with track objects that are now outdated?
		
			Slim::Music::Import->setIsScanning(0);
			
			# Clear caches, like the vaObj, etc after scanning has been finished.
			Slim::Schema->wipeCaches;

			Slim::Control::Request::notifyFromArray( undef, [ 'rescan', 'done' ] );
		}
	}
	
	$request->setStatusDone();
}

1;
