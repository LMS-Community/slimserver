package Slim::Utils::MySQLHelper;

# $Id$

# Helper class for bringing up the MySQL server, and installing the system
# tables, etc.

use strict;
use base qw(Class::Data::Inheritable);
use DBI;
use File::Path;
use File::Spec::Functions qw(:ALL);
use Proc::Background;
use Template;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::SQLHelper;

INIT {
        my $class = __PACKAGE__;

        for my $accessor (qw(confFile mysqlDir pidFile socketFile needSystemTables processObj)) {

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

	# MySQL on Windows wants forward slashes.
	if (Slim::Utils::OSDetect::OS() eq 'win') {

		for my $key (keys %config) {
			$config{$key} =~ s/\\/\//g;
		}
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

	if ($class->pidFile && $class->processObj && $class->processObj->alive) {
		errorMsg("startMySQLServer: MySQL is already running!\n");
		return 0;
	}

	my $mysqld = Slim::Utils::Misc::findbin('mysqld') || do {
		errorMsg("startMySQLServer: Couldn't find a executable for 'mysqld'! This is a fatal error. Exiting.\n");
		exit;
	};

	# Create the command we're going to run, sending output to the logfile
	# if it exists - otherwise, to /dev/null
	my $command = sprintf('%s --defaults-file=%s --pid-file=%s %s',
		$mysqld,
		$class->confFile,
		$class->pidFile,
		Slim::Utils::OSDetect::OS() eq 'win' ? '' : ($::logfile ? "2>$::logfile" : '2>/dev/null'),
	);

	$::d_mysql && msg("MySQLHelper: startServer() running: [$command]\n");

	# This works for both Windows & *nix
	my $proc = Proc::Background->new($command);

	# Give MySQL time to get going..
	eval {
		local $SIG{'ALRM'} = sub { die "alarm\n" };
		alarm 10;

		while (1) {
			last if -r $class->pidFile;
		}

		alarm 0;
	};

	if ($@) {
		errorMsg("MySQLHelper: startServer() - server didn't startup in 30 seconds!\n");
		exit;
	}

	$class->processObj($proc);

	return 1;
}

sub stopServer {
	my $class = shift;

	$::d_mysql && msgf("MySQLHelper: stopServer() Killing pid: [%d]\n", $class->processObj->pid);

	$class->processObj->die;

	# Wait for the PID file to go away.
	eval {
		local $SIG{'ALRM'} = sub { die "alarm\n" };
		alarm 30;

		while (1) {
			last if !-r $class->pidFile;
			last if !$class->processObj->alive;
		}

		alarm 0;
	};

	if ($@) {
		errorMsg("MySQLHelper: stopServer() - server didn't shutdown in 30 seconds!\n");
		exit;
	}

	# The pid file may be left around..
	unlink($class->pidFile);

	$class->processObj(undef);
}

sub createSystemTables {
	my $class = shift;

	# We need to bring up MySQL to set the initial system tables, then
	# bring it down again.
	$class->startServer;

	my $sqlFile = catdir($class->mysqlDir, 'system.sql');
	my $ranOk   = 0;
	my $dsn     = '';

	# Connect to the database - doesn't matter what user and no database,
	# in order to setup the system tables. 
	#
	# We need to use the mysql_socket on *nix platforms here, as mysql
	# won't bring up the network port until the tables are installed.
	#
	# On Windows, TCP is the default.

	if (Slim::Utils::OSDetect::OS() eq 'win') {

		$dsn = Slim::Utils::Prefs::get('dbsource');
		$dsn =~ s/;database=.+;?//;

	} else {

		$dsn = sprintf('dbi:mysql:mysql_socket=%s', $class->socketFile);
	}

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
