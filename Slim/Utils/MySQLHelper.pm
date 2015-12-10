package Slim::Utils::MySQLHelper;

# $Id$

=head1 NAME

Slim::Utils::MySQLHelper

=head1 SYNOPSIS

Slim::Utils::MySQLHelper->init

=head1 DESCRIPTION

Helper class for launching MySQL, installing the system tables, etc.

=head1 METHODS

=cut

use strict;
use base qw(Class::Data::Inheritable);
use DBI;
use DBI::Const::GetInfoType;
use File::Path;
use File::Slurp;
use File::Spec::Functions qw(:ALL);
use Proc::Background;
use Time::HiRes qw(sleep);

{
	if (main::ISWINDOWS) {
		require Win32::Service;
	}
}

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::SQLHelper;
use Slim::Utils::Prefs;

{
        my $class = __PACKAGE__;

        for my $accessor (qw(confFile mysqlDir pidFile socketFile needSystemTables processObj)) {

                $class->mk_classdata($accessor);
        }
}

my $log = logger('database.mysql');

my $prefs = preferences('server');

use constant SERVICENAME => 'SqueezeMySQL';

sub storageClass {'DBIx::Class::Storage::DBI::mysql'};

sub default_dbsource { 'dbi:mysql:hostname=127.0.0.1;port=9092;database=%s' }

=head2 init()

Initializes the entire MySQL subsystem - creates the config file, and starts the server.

=cut

sub init {
	my $class = shift;
	
	# Reset dbsource pref if it's not for MySQL
	if ( $prefs->get('dbsource') !~ /^dbi:mysql/ ) {
		$prefs->set( dbsource => default_dbsource() );
		$prefs->set( dbsource => $class->source() );
	}

	# Check to see if our private port is being used. If not, we'll assume
	# the user has setup their own copy of MySQL.
	if ($prefs->get('dbsource') !~ /port=9092/) {

		main::INFOLOG && $log->info("Not starting MySQL - looks to be user/system configured.");
		Slim::Utils::OSDetect::getOS->initMySQL($class);
		
		return 1;
	}

	for my $dir (Slim::Utils::OSDetect::dirsFor('MySQL')) {

		if (-r catdir($dir, 'my.tt')) {
			$class->mysqlDir($dir);
			last;
		}
	}

	my $cacheDir = $prefs->get('librarycachedir');

	$class->socketFile( catdir($cacheDir, 'squeezebox-mysql.sock') ),
	$class->pidFile(    catdir($cacheDir, 'squeezebox-mysql.pid') );

	$class->confFile( $class->createConfig($cacheDir) );

	if ($class->needSystemTables) {

		main::INFOLOG && $log->info("Creating system tables..");

		$class->createSystemTables;
	}

	# The DB server might already be up.. if it didn't get shutdown last
	# time. That's ok.
	if (!$class->dbh) {

		# Bring MySQL up as a service on Windows.
		if (main::ISWINDOWS) {

			$class->startServer(1);

		} else {

			$class->startServer;
		}
	}

	return 1;
}

=head2 createConfig( $cacheDir )

Creates a MySQL config file from the L<my.tt> template in the MySQL directory.

=cut

sub createConfig {
	my ($class, $cacheDir) = @_;
	
	my $highmem = $prefs->get('dbhighmem') || 0;
	
	my $ttConf = catdir($class->mysqlDir, $highmem ? 'my-highmem.tt' : 'my.tt');
	my $output = catdir($cacheDir, 'my.cnf');

	my %config = (
		'basedir'  => $class->mysqlDir,
		'language' => Slim::Utils::OSDetect::dirsFor('mysql-language') || $class->mysqlDir,
		'datadir'  => catdir($cacheDir, 'MySQL'),
		'socket'   => $class->socketFile,
		'pidFile'  => $class->pidFile,
		'errorLog' => catdir($cacheDir, 'mysql-error-log.txt'),
		'bindAddress' => $prefs->get('bindAddress'),
		'port'     => 9092,
	);

	# If there's no data dir setup - that also means we need to create the system tables.
	if (!-d $config{'datadir'}) {

		mkpath($config{'datadir'});

		$class->needSystemTables(1);
	}

	# Or we've created a data dir, but the system tables didn't get setup..
	if (!-d catdir($config{'datadir'}, 'mysql')) {

		$class->needSystemTables(1);
	}

	# MySQL on Windows wants forward slashes.
	if (main::ISWINDOWS) {

		for my $key (keys %config) {
			$config{$key} =~ s/\\/\//g;
		}
	}

	main::INFOLOG && $log->info("createConfig() Creating config from file: [$ttConf] -> [$output].");

	open(TEMPLATE, "< $ttConf") or die "Couldn't open $ttConf for reading: $!\n";
	open(OUTPUT, "> $output") or die "Couldn't open $output for writing: $!\n";
	
	while (defined (my $line = <TEMPLATE>)) {
		$line =~ s/\[%\s*(\w+)\s*%\]/$config{$1}/;
		print OUTPUT $line;
	}
	
	close OUTPUT;
	close TEMPLATE;

	# Bug: 3847 possibly - set permissions on the config file.
	# Breaks all kinds of other things.
	# chmod(0664, $output);

	return $output;
}

=head2 startServer()

Bring up our private copy of MySQL server.

This is a no-op if you are using a pre-configured copy of MySQL.

=cut

sub startServer {
	my $class   = shift;
	my $service = shift || 0;

	my $isRunning = 0;

	if ($service) {

		my %status = ();

		Win32::Service::GetStatus('', SERVICENAME, \%status);

		if ($status{'CurrentState'} == 0x04) {

			$isRunning = 1;
		}

	} elsif ($class->pidFile && $class->processObj && $class->processObj->alive) {

		$isRunning = 1;
	}

	if ($isRunning) {

		main::INFOLOG && $log->info("MySQL is already running!");

		return 0;
	}

	my $mysqld = Slim::Utils::Misc::findbin('mysqld') || do {

		$log->logdie("FATAL: Couldn't find a executable for 'mysqld'! Exiting.");
	};

	my $confFile = $class->confFile;
	my $process  = undef;

	# Bug: 3461
	$mysqld   = Slim::Utils::OSDetect::getOS->decodeExternalHelperPath($mysqld);
	$confFile = Slim::Utils::OSDetect::getOS->decodeExternalHelperPath($confFile);

	my @commands = ($mysqld, sprintf('--defaults-file=%s', $confFile));

	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("About to start MySQL as a %s with command: [%s]\n",
			($service ? 'service' : 'process'), join(' ', @commands),
		));
	}

	if (main::ISWINDOWS && $service) {

		my %status = ();

		Win32::Service::GetStatus('', SERVICENAME, \%status);

		# Attempt to install the service, if it isn't.
		# NB mysqld fails immediately if install is not allowed by user account so don't add this to @commands
		if (scalar keys %status == 0) {

			system( sprintf "%s --install %s %s", $commands[0], SERVICENAME, $commands[1] );
		}
		
		# if MySQL service is still in the process of starting or stopping,
		# wait a few seconds, or SC will fail miserably
		my $maxWait = 30;
		
		while ($status{CurrentState} != 0x04 && $status{CurrentState} != 0x01 && $maxWait-- > 0) {
			
			sleep 1;
			Win32::Service::GetStatus('', SERVICENAME, \%status);

			if (main::DEBUGLOG && $log->is_debug) {
				if ($status{CurrentState} == 0x02) {
					$log->debug('Wait while MySQL is starting...');
				}
				elsif ($status{CurrentState} == 0x03) {
					$log->debug('Wait while MySQL is stopping...');
				}
			}
		}

		Win32::Service::StartService('', SERVICENAME);

		Win32::Service::GetStatus('', SERVICENAME, \%status);

		if (scalar keys %status == 0 || ($status{'CurrentState'} != 0x02 && $status{'CurrentState'} != 0x04)) {

			logWarning("Couldn't install MySQL as a service! Will run as a process!");
			$service = 0;
		}
	}

	# Catch Unix users, and Windows users when we couldn't run as a service.
	if (!$service) {

		$process = Proc::Background->new(@commands);
	}

	my $dbh = undef;

	# Give MySQL time to get going..
	for (my $i = 0; $i < 300; $i++) {

		# If we can connect, the server is up.
		if ($dbh = $class->dbh) {
			$dbh->disconnect;
			last;
		}

		sleep 0.1;
	}

	if ($@) {

		$log->logdie("FATAL: Server didn't startup in 30 seconds! Exiting!");
	}

	$class->processObj($process);

	return 1;
}

sub source {
	return sprintf($prefs->get('dbsource'), 'slimserver');
}

sub on_connect_do {
	return [ 'SET NAMES UTF8' ];
}

sub collate {
	my $class = shift;
	
	my $lang = $prefs->get('language');
	
	my $collation
		= $lang eq 'CS' ? 'utf8_czech_ci'
		: $lang eq 'SV' ? 'utf8_swedish_ci'
		: $lang eq 'DA' ? 'utf8_danish_ci'
		: $lang eq 'ES' ? 'utf8_spanish_ci'
		: $lang eq 'PL' ? 'utf8_polish_ci'
		: 'utf8_general_ci';
	
	return "COLLATE $collation ";
}

=head2 randomFunction()

Returns RAND(), MySQL-specific random function

=cut

sub randomFunction { 'RAND()' }

=head2 prepend0( $string )

Returns concat( '0', $string )

=cut

sub prepend0 { "concat('0', " . $_[1] . ")" }

=head2 append0( $string )

Returns concat( $string, '0' )

=cut

sub append0 { "concat(" . $_[1] . ", '0')" }

=head2 concatFunction()

Returns 'concat', used in a string comparison to see if something has already been concat()'ed

=cut

sub concatFunction { 'concat' }

=head2 stopServer()

Bring down our private copy of MySQL server.

This is a no-op if you are using a pre-configured copy of MySQL.

Or are running MySQL as a Windows service.

=cut

sub stopServer {
	my $class = shift;
	my $dbh   = shift || $class->dbh;

	if (main::ISWINDOWS) {

		my %status = ();
		
		Win32::Service::GetStatus('', SERVICENAME, \%status);

		if (scalar keys %status != 0 && ($status{'CurrentState'} == 0x02 || $status{'CurrentState'} == 0x04)) {

			main::INFOLOG && $log->info("Running service shutdown.");

			if (Win32::Service::StopService('', SERVICENAME)) {

				return;
			}
			
			$log->warn("Running service shutdown failed!");
		}
	}

	# We have a running server & handle. Shut it down internally.
	if ($dbh) {

		main::INFOLOG && $log->info("Running shutdown.");

		$dbh->func('shutdown', 'admin');
		$dbh->disconnect;

		if ($class->_checkForDeadProcess) {
			return;
		}
	}

	# If the shutdown failed, try to find the pid
	my @pids = ();

	if (ref($class->processObj)) {
		push @pids, $class->processObj->pid;
	}

	if (-f $class->pidFile) {
		chomp(my $pid = read_file($class->pidFile));
		push @pids, $pid;
	}

	for my $pid (@pids) {

		next if !$pid || !kill(0, $pid);

		main::INFOLOG && $log->info("Killing pid: [$pid]");

		kill('TERM', $pid);

		# Wait for the PID file to go away.
		last if $class->_checkForDeadProcess;

		# Try harder.
		kill('KILL', $pid);

		last if $class->_checkForDeadProcess;

		if (kill(0, $pid)) {

			$log->logdie("FATAL: Server didn't shutdown in 20 seconds!");
		}
	}

	# The pid file may be left around..
	unlink($class->pidFile);
}

sub _checkForDeadProcess {
	my $class = shift;

	for (my $i = 0; $i < 100; $i++) {

		if (!-r $class->pidFile) {

			$class->processObj(undef);
			return 1;
		}

		sleep 0.1;
	}

	return 0;
}

=head2 createSystemTables()

Create required MySQL system tables. See the L<MySQL/system.sql> file.

=cut

sub createSystemTables {
	my $class = shift;

	# We need to bring up MySQL to set the initial system tables, then bring it down again.
	$class->startServer;

	my $sqlFile = catdir($class->mysqlDir, 'system.sql');

	# Connect to the database - doesn't matter what user and no database,
	# in order to setup the system tables. 
	#
	# We need to use the mysql_socket on *nix platforms here, as mysql
	# won't bring up the network port until the tables are installed.
	#
	# On Windows, TCP is the default.

	my $dbh = $class->dbh or do {

		$log->fatal("FATAL: Couldn't connect to database: [$DBI::errstr]");

		$class->stopServer;

		exit;
	};

	if (Slim::Utils::SQLHelper->executeSQLFile('mysql', $dbh, $sqlFile)) {

		$class->createDatabase($dbh);

		# Bring the server down again.
		$class->stopServer($dbh);

		$dbh->disconnect;

		$class->needSystemTables(0);

	} else {

		$log->logdie("FATAL: Couldn't run executeSQLFile on [$sqlFile]! Exiting!");
	}
}

=head2 dbh()

Returns a L<DBI> database handle, using the dbsource preference setting .

=cut

sub dbh {
	my $class = shift;
	my $dsn   = '';

	if (main::ISWINDOWS) {

		$dsn = $prefs->get('dbsource');
		$dsn =~ s/;database=.+;?//;

	} else {

		$dsn = sprintf('dbi:mysql:mysql_read_default_file=%s', $class->confFile );
	}

	$^W = 0;

	return eval { DBI->connect($dsn, undef, undef, { 'PrintError' => 0, 'RaiseError' => 0 }) };
}

=head2 createDatabase( $dbh )

Creates the initial Logitech Media Server database in MySQL.

'CREATE DATABASE slimserver'

=cut

sub createDatabase {
	my $class  = shift;
	my $dbh    = shift;

	my $source = $prefs->get('dbsource');

	# Set a reasonable default. :)
	my $dbname = 'slimserver';

	if ($source =~ /database=(\w+)/) {
		$dbname = $1;
	}

	eval { $dbh->do("CREATE DATABASE $dbname") };

	if ($@) {

		$log->logdie("FATAL: Couldn't create database with name: [$dbname] - [$DBI::errstr]. Exiting!");
	}
}

=head2 mysqlVersion( $dbh )

Returns the version of MySQL that the $dbh is connected to.

=cut

sub sqlVersion {
	my $class = shift;
	my $dbh   = shift || return 0;

	my $mysqlVersion = $dbh->get_info($GetInfoType{'SQL_DBMS_VER'}) || 0;

	if ($mysqlVersion && $mysqlVersion =~ /^(\d+\.\d+)/) {

        	return $1;
	}

	return $mysqlVersion || 0;
}

=head2 mysqlVersionLong( $dbh )

Returns the long version string, i.e. 5.0.22-standard

=cut

sub sqlVersionLong {
	my $class = shift;
	my $dbh   = shift || return 0;

	my ($mysqlVersion) = $dbh->selectrow_array( 'SELECT version()' );

	return 'MySQL ' . $mysqlVersion || 0;
}

=head2 canCacheDBHandle( )

Is it permitted to cache the DB handle for the period that the DB is open?

=cut

sub canCacheDBHandle {
	return 0;
}

sub checkDataSource { }

sub beforeScan { }

sub afterScan { }

sub exitScan { }

sub optimizeDB { }

sub updateProgress { }

sub postConnect { }
sub addPostConnectHandler {}

sub pragma { }

=head2 cleanup()

Shut down MySQL when the server is shut down.

=cut

sub cleanup {
	my $class = shift;

	if ($class->processObj) {
		$class->stopServer;
	}
}

=head1 SEE ALSO

L<DBI>

L<DBD::mysql>

L<http://www.mysql.com/>

=cut

1;

__END__
