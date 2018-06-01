package Slim::Utils::SQLiteHelper;

# $Id$

=head1 NAME

Slim::Utils::SQLiteHelper

=head1 SYNOPSIS

Slim::Utils::SQLiteHelper->init

=head1 DESCRIPTION

=head1 METHODS

=cut

use strict;

use Digest::MD5 qw(md5_hex);
use File::Basename;
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

$prefs->setChange( \&setCacheSize, 'dbhighmem' ) unless main::SCANNER;

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
	if ( $DBD::SQLite::VERSION lt 1.34 ) {
		die "DBD::SQLite version 1.34 or higher required\n";
	}
	
	# Reset dbsource pref if it's not for SQLite
	#                                              ... or if it's using the long filename Windows doesn't like
	if ( $prefs->get('dbsource') !~ /^dbi:SQLite/ || $prefs->get('dbsource') !~ /library\.db/ ) {
		$prefs->set( dbsource => default_dbsource() );
		$prefs->set( dbsource => $class->source() );
	}
	
	if ( !main::SCANNER ) {
		# Event handler for notifications from scanner process
		Slim::Control::Request::addDispatch(
			['scanner', 'notify', '_msg'],
			[0, 0, 0, \&_notifyFromScanner]
		);
	}
}

sub source {
	my $source;

	my $dbFile = catfile( $prefs->get('librarycachedir'), 'library.db' );

	# we need to migrate long 7.6.0 file names to shorter 7.6.1 filenames: Perl/Windows can't handle the long version
	_migrateDBFile(catfile( $prefs->get('librarycachedir'), 'squeezebox.db' ), $dbFile);
	
	$source = sprintf( $prefs->get('dbsource'), $dbFile );
	
	return $source;
}

sub on_connect_do {
	my $class = shift;
	
	my $sql = [
		'PRAGMA synchronous = OFF',
		'PRAGMA journal_mode = WAL',
		'PRAGMA foreign_keys = ON',
		'PRAGMA wal_autocheckpoint = ' . (main::SCANNER ? 10000 : 200),
		# Default cache_size is 2000 pages, a page is normally 1K but may be different
		# depending on the OS/filesystem.  So default is usually 2MB.
		# Highmem we will try 20M (high) or 500M (max)
		'PRAGMA cache_size = ' . $class->_cacheSize,
	];
	
	# Default temp_store is to create disk files to save memory
	# Highmem we'll let it use memory
	push @{$sql}, 'PRAGMA temp_store = MEMORY' if $prefs->get('dbhighmem');
	
	# We create this even if main::STATISTICS is not false so that the SQL always works
	# Track Persistent data is in another file
	my $persistentdb = $class->_dbFile('persist.db');

	# we need to migrate long 7.6.0 file names to shorter 7.6.1 filenames: Windows can't handle the long version
	_migrateDBFile($class->_dbFile('squeezebox-persistent.db'), $persistentdb);

	push @{$sql}, "ATTACH '$persistentdb' AS persistentdb";
	push @{$sql}, 'PRAGMA persistentdb.journal_mode = WAL';
	push @{$sql}, 'PRAGMA persistentdb.cache_size = ' . $class->_cacheSize;
	
	return $sql;
}

sub setCacheSize {
	my $cache_size = __PACKAGE__->_cacheSize;
	
	return unless Slim::Schema->hasLibrary;
	
	my $dbh = Slim::Schema->dbh;
	$dbh->do("PRAGMA cache_size = $cache_size");
	$dbh->do("PRAGMA persistentdb.cache_size = $cache_size");
}

sub _cacheSize {
	my $high = $prefs->get('dbhighmem');

	return 2000 if !$high;
	
	# scanner doesn't take advantage of a huge buffer
	return 20000 if main::SCANNER || $high == 1;
	
	# maximum memory usage for large collections and lots of memory
	return 500_000;
}

sub _migrateDBFile {
	my ($src, $dst) = @_;
	
	return if -f $dst || !-r $src;
	
	require File::Copy;
	
	main::DEBUGLOG && $log->is_debug && $log->debug("trying to rename $src to $dst");
	
	if ( !File::Copy::move( $src, $dst ) ) {
		$log->error("Unable to rename $src to $dst: $!. Please remove it manually.");
	}
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
		
		if ( $collation && $currentICU ne $collation ) {	
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
		
		return "COLLATE $currentICU " if $currentICU;
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

Called to check the database.

=cut

sub checkDataSource {
	# No longer needed with WAL mode
}

=head2 beforeScan()

Called before a scan is started.

=cut

sub beforeScan {
	# No longer needed with WAL mode
}

=head2 afterScan()

Called after a scan is finished. Notifies main server to copy back the scanner file.

=cut

sub afterScan {
	my $class = shift;
	
	$class->updateProgress('end');
}

=head2 optimizeDB()

Called during the Slim::Schema->optimizeDB call to run some DB specific cleanup tasks

=cut

sub optimizeDB {
	my $class = shift;
	
	# only run VACUUM in the scanner, or if no player is active
	return if !main::SCANNER && grep { $_->power() } Slim::Player::Client::clients();
	
	$class->vacuum('library.db');
	$class->vacuum('persist.db');
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
my %postConnectHandlers;

sub postConnect {
	my ( $class, $dbh ) = @_;
	
	$dbh->func( 'MD5', 1, sub { md5_hex( $_[0] ) }, 'create_function' );
	
	# http://search.cpan.org/~adamk/DBD-SQLite-1.33/lib/DBD/SQLite.pm#Transaction_and_Database_Locking
	$dbh->{sqlite_use_immediate_transaction} = 1;
	
	# Reset collation load state
	$currentICU = '';
	$loadedICU = {};
	
	# Check if the DB has been optimized (stats analysis)
	if ( !main::SCANNER ) {
		# Check for the presence of the sqlite_stat1 table
		my ($count) = eval { $dbh->selectrow_array( "SELECT COUNT(*) FROM sqlite_stat1 WHERE tbl = 'tracks' OR tbl = 'images' OR tbl = 'videos'", undef, () ) };
		
		if (!$count) {
			my ($table) = eval { $dbh->selectrow_array('SELECT name FROM sqlite_master WHERE type="table" AND name="tracks"') };
			
			if ($table) {
				$log->error('Optimizing DB because of missing or empty sqlite_stat1 table');			
				Slim::Schema->optimizeDB();
			}
		}
	}
	
	foreach (keys %postConnectHandlers) {
		$_->postDBConnect($dbh);
	}
}

=head2

Allow plugins and others to register handlers which should be called from postConnect

=cut

sub addPostConnectHandler {
	my ( $class, $handler ) = @_;
	
	if ($handler && $handler->can('postDBConnect')) {
		$postConnectHandlers{$handler}++
	}
	
	# if we register for the first time, re-initialize the dbh object
	if ( $postConnectHandlers{$handler} == 1 ) {
		Slim::Schema->disconnect;
		Slim::Schema->init;
	}
}

sub updateProgress {
	my $class = shift;
	
	return if $serverDown > MAX_RETRIES;
	
	require LWP::UserAgent;
	require HTTP::Request;
	
	my $log = logger('scan.scanner');
	
	# Scanner does not have an event loop, so use sync HTTP here.
	# Don't use Slim::Utils::Network, as it comes with too much overhead.
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
			Slim::Utils::Progress->clear;
			
			# let the user know we aborted the scan
			my $progress = Slim::Utils::Progress->new( { 
				type  => 'importer',
				name  => 'failure',
				total => 1,
				every => 1, 
			} );
			$progress->update('SCAN_ABORTED');
			
			Slim::Music::Import->setIsScanning(0);
			
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

=head2 vacuum()

VACUUM a given database.

If the $optional parameter is passed, the VACUUM will only happen if there's a certain fragmentation.

=cut

sub vacuum {
	my ( $class, $db, $optional ) = @_;

	my $dbFile = catfile( $prefs->get('librarycachedir'), ($db || 'library.db') );
	
	return unless -f $dbFile;

	main::DEBUGLOG && $log->is_debug && $log->debug("Start VACUUM $db");
	
	my $source = sprintf( $class->default_dbsource(), $dbFile );

	# this can't be run from the schema_cleanup.sql, as VACUUM doesn't work inside a transaction
	my $dbh = DBI->connect($source);

	if ($optional) {
		my $pages = $dbh->selectrow_array('PRAGMA page_count;');
		my $free  = $dbh->selectrow_array('PRAGMA freelist_count;');
		my $frag  = ($pages && $free) ? $free / $pages : 0;

		main::DEBUGLOG && $log->is_debug && $log->debug("$dbFile: Pages: $pages; Free: $free; Fragmentation: $frag");

		# don't skip this vacuum if fragmentation is higher than 10%;
		$optional = 0 if $frag > 0.1;
	}

	if ( !$optional ) {
		$dbh->do('PRAGMA temp_store = MEMORY') if $prefs->get('dbhighmem');
		$dbh->do('VACUUM');
	}
	$dbh->disconnect;

	main::DEBUGLOG && $log->is_debug && $log->debug("VACUUM $db done!");
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

	# If user aborted the scan, return an abort message
	if ( Slim::Music::Import->hasAborted ) {
		$request->addResult( abort => 1 );
		$request->setStatusDone();

		Slim::Music::Import->setAborted(0);		
		return;
	}
	
	if ( $msg eq 'start' ) {
		# Scanner has started
		$SCANNING = 1;
		
		if ( Slim::Utils::OSDetect::getOS->canAutoRescan && $prefs->get('autorescan') ) {
			require Slim::Utils::AutoRescan;
			Slim::Utils::AutoRescan->shutdown;
		}
		
		Slim::Music::Import->setIsScanning('SETUP_WIPEDB');
		
		# XXX if scanner doesn't report in with regular progress within a set time period
		# assume scanner is dead.  This is hard to do, as scanner may block for an indefinite
		# amount of time with slow network filesystems, or a large amount of files.
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
			$SCANNING = 0;
		}
		else {
			# XXX handle players with track objects that are now outdated?
			
			# Reconnect to the database to zero out WAL files
			Slim::Schema->disconnect;
			Slim::Schema->init;
			
			# Close ArtworkCache to zero out WAL file, it'll be reopened when needed
			Slim::Utils::ArtworkCache->new->close;
		}

		Slim::Music::Import->setIsScanning(0);
			
		# Clear caches, like the vaObj, etc after scanning has been finished.
		Slim::Control::Request::notifyFromArray( undef, [ 'rescan', 'done' ] );
	}
	
	$request->setStatusDone();
}

1;
