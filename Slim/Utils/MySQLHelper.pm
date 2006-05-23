package Slim::Utils::MySQLHelper;

# $Id$

# Helper class for bringing up the MySQL server, and installing the system
# tables, etc.

use strict;
use base qw(Class::Data::Inheritable);
use DBI;
use File::Path;
use File::Slurp;
use File::Spec::Functions qw(:ALL);
use Template;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::SQLHelper;

INIT {
        my $class = __PACKAGE__;

        for my $accessor (qw(confFile mysqlDir pidFile socketFile needSystemTables)) {

                $class->mk_classdata($accessor);
        }
}

sub init {
	my $class = shift;

	for my $dir (Slim::Utils::OSDetect::dirsFor('MySQL')) {

		if (-r catdir($dir, 'my.tt')) {
			$class->mysqlDir($dir);
			last;
		}
	}

	my $cacheDir = Slim::Utils::Prefs::get('cachedir');

	$class->socketFile( catdir($cacheDir, 'slimserver-mysql.sock') ),
	$class->pidFile(    catdir($cacheDir, 'slimserver-mysql.pid') );

	$class->confFile( $class->createConfig($cacheDir) );

	if ($class->needSystemTables) {
		$class->createSystemTables;
	}

	$class->startServer;

	return 1;
}

sub createConfig {
	my ($class, $cacheDir) = @_;

	my $ttConf = catdir($class->mysqlDir, 'my.tt');
	my $output = catdir($cacheDir, 'my.cnf');

	my %config = (
		'basedir' => $class->mysqlDir,
		'datadir' => catdir($cacheDir, 'MySQL'),
		'socket'  => $class->socketFile,
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

	my $template = Template->new({ 'ABSOLUTE' => 1 });
           $template->process($ttConf, \%config, $output) || die $template->error;

	$class->confFile($output);
}

sub startServer {
	my $class = shift;

	if (Slim::Utils::OSDetect::isDebian()) {
		$::d_mysql && msg("startMySQLServer: Not starting MySQL server on Debian..\n");
		return 1;
	}

	if ($class->pidFile && $class->serverIsRunning) {
		errorMsg("startMySQLServer: MySQL is already running!\n");
		return 0;
	}

	my $mysqld = Slim::Utils::Misc::findbin('mysqld') || do {
		errorMsg("startMySQLServer: Couldn't find a executable for 'mysqld'! This is a fatal error. Exiting.\n");
		exit;
	};

	# Create the command we're going to run, sending output to the logfile
	# if it exists - otherwise, to /dev/null
	my $command = sprintf('%s --defaults-file=%s --pid-file=%s 2>%s &',
		$mysqld,
		$class->confFile,
		$class->pidFile,
		$::logfile ? $::logfile : (Slim::Utils::OSDetect::OS() eq 'win' ? 'nul' : '/dev/null'),
	);

	$::d_mysql && msg("MySQLHelper: startServer() running: [$command]\n");

	system($command);

	# Give MySQL time to get going..
	eval {
		local $SIG{'ALRM'} = sub { die "alarm\n" };
		alarm 30;

		while (1) {
			last if -r $class->pidFile;
		}

		alarm 0;
	};

	if ($@) {
		errorMsg("MySQLHelper: startServer() - server didn't startup in 30 seconds!\n");
		exit;
	}

	return 1;
}

sub stopServer {
	my $class = shift;

	my $pid = $class->pid || do {
		errorMsg("MySQLHelper: stopServer called with an invalid pid!\n");
		return 0;
	};

	$::d_mysql && msg("MySQLHelper: stopServer() Killing pid: [$pid]\n");

	my $ret = kill('TERM', $pid);

	# Wait for the PID file to go away.
	eval {
		local $SIG{'ALRM'} = sub { die "alarm\n" };
		alarm 30;

		while (1) {
			last if !-r $class->pidFile;
		}

		alarm 0;
	};

	if ($@) {
		errorMsg("MySQLHelper: stopServer() - server didn't shutdown in 30 seconds!\n");
		exit;
	}

	$class->pid(0);

	return $ret;
}

sub pid {
	my $class = shift;

	if (!$class->pidFile || !-r $class->pidFile) {
		return 0;
	}

	chomp(my $pid = read_file($class->pidFile));

	return $pid;
}

sub serverIsRunning {
	my $class = shift;

	my $pid = $class->pid;

	if ($pid && kill(0, $pid)) {
		return 1;
	}

	return 0;
}

sub createSystemTables {
	my $class = shift;

	# We need to bring up MySQL to set the initial system tables, then
	# bring it down again.
	$class->startServer;

	my $sqlFile = catdir($class->mysqlDir, 'system.sql');
	my $ranOk   = 0;

	# Connect to the database - doesn't matter what user and no database,
	# in order to setup the system tables. We need to use the mysql_socket
	# here, as mysql won't bring up the network port until the tables are installed.
	my $dsn = sprintf('dbi:mysql:mysql_socket=%s', $class->socketFile);

	my $dbh = DBI->connect($dsn) or do {
		errorMsg("MySQLHelper: createSystemTables() Couldn't connect to database: [$dsn] - [$DBI::errstr]\n");
		exit;
	};

	#
	if (Slim::Utils::SQLHelper->executeSQLFile('mysql', $dbh, $sqlFile)) {

		$ranOk = 1;

		$class->createDatabase($dbh);
	}

	# Bring the server down again.
	$dbh->disconnect;
	$class->stopServer;

	if ($ranOk) {

		$class->needSystemTables(0);

	} else {

		errorMsg("MySQLHelper: createSystemTables() - couldn't run executeSQLFile on [$sqlFile]!\n");
		errorMsg("MySQLHelper: createSystemTables() - this is a fatal error. Exiting.\n");
		exit;
	}
}

sub createDatabase {
	my $class  = shift;
	my $dbh    = shift;

	my $source = Slim::Utils::Prefs::get('dbsource');

	# Set a reasonable default. :)
	my $dbname = 'slimserver';

	if ($source =~ /database=(\w+)/) {
		$dbname = $1;
	}

	eval { $dbh->do("CREATE DATABASE $dbname") };

	if ($@) {
		errorMsg("MySQLHelper: createDatabase() - Couldn't create database with name: [$dbname] - [$DBI::errstr]\n");
		errorMsg("MySQLHelper: createDatabase() - this is a fatal error. Exiting.\n");
		exit;
	}
}

# Shut down MySQL when the server is done..
END {
	__PACKAGE__->stopServer() if __PACKAGE__->pidFile;
}

1;

__END__
