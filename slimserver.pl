#!/usr/bin/perl -w

# SlimServer Copyright (C) 2001-2006 Sean Adams, Slim Devices Inc.
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
use warnings;

# This package section is used for the windows service version of the application, 
# as built with ActiveState's PerlSvc
package PerlSvc;

our %Config = (
	DisplayName => 'SlimServer',
	Description => "Slim Devices' SlimServer Music Server",
	ServiceName => "slimsvc",
);

sub Startup {

	# added to workaround a problem with 5.8 and perlsvc.
	# $SIG{BREAK} = sub {} if RunningAsService();
	main::init();
	
	# here's where your startup code will go
	while (ContinueRun() && !main::idle()) { }

	main::stopServer();
}

sub Install {

	my($Username,$Password);

	use Getopt::Long;

	Getopt::Long::GetOptions(
		'username=s' => \$Username,
		'password=s' => \$Password,
	);

	if ((defined $Username) && ((defined $Password) && length($Password) != 0)) {
		$Config{UserName} = $Username;
		$Config{Password} = $Password;
	}
}

sub Interactive {
	main::main();	
}

sub Remove {
	# add your additional remove messages or functions here
}

sub Help {	
	main::showUsage();
	# add your additional help messages or functions here
	$Config{DisplayName};
}

package main;

use FindBin qw($Bin);
use lib $Bin;

BEGIN {
	use Slim::bootstrap;
	use Slim::Utils::OSDetect;

	Slim::bootstrap->loadModules();

	# Bug 2659 - maybe. Remove old versions of modules that are now in the $Bin/lib/ tree.
	if (!Slim::Utils::OSDetect::isDebian()) {

		unlink("$Bin/CPAN/MP3/Info.pm");
		unlink("$Bin/CPAN/DBIx/ContextualFetch.pm");
	}
};

use File::Slurp;
use Getopt::Long;
use File::Spec::Functions qw(:ALL);
use POSIX qw(:signal_h :errno_h :sys_wait_h setsid);
use Socket qw(:DEFAULT :crlf);
use Time::HiRes;

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

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::PerfMon;
use Slim::Buttons::Common;
use Slim::Buttons::Home;
use Slim::Buttons::Power;
use Slim::Buttons::Search;
use Slim::Buttons::ScreenSaver;
use Slim::Utils::PluginManager;
use Slim::Buttons::Synchronize;
use Slim::Buttons::Input::Text;
use Slim::Buttons::Input::Time;
use Slim::Buttons::Input::List;
use Slim::Buttons::Input::Choice;
use Slim::Buttons::Input::Bar;
use Slim::Buttons::Settings;
use Slim::Player::Client;
use Slim::Control::Request;
use Slim::Display::Lib::Fonts;
use Slim::Web::HTTP;
use Slim::Hardware::IR;
use Slim::Music::Info;
use Slim::Music::Import;
use Slim::Music::MusicFolderScan;
use Slim::Music::PlaylistFolderScan;
use Slim::Utils::OSDetect;
use Slim::Player::Playlist;
use Slim::Player::Sync;
use Slim::Player::Source;
use Slim::Utils::Cache;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner;
use Slim::Utils::Scheduler;
use Slim::Networking::Select;
use Slim::Networking::UDP;
use Slim::Web::Setup;
use Slim::Control::Stdio;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;
use Slim::Utils::MySQLHelper;
use Slim::Networking::Slimproto;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Firmware;
use Slim::Utils::UPnPMediaServer;

our @AUTHORS = (
	'Sean Adams',
	'Vidur Apparao',
	'Dean Blackketter',
	'Kevin Deane-Freeman',
	'Andy Grundman',
	'Amos Hayes',
	'Christopher Key',
	'Mark Langston',
	'Eric Lyons',
	'Scott McIntyre',
	'Robert Moser',
	'Dave Nanian',
	'Jacob Potter',
	'Sam Saffron',
	'Roy M. Silvernail',
	'Adrian Smith',
	'Richard Smith',
	'Max Spicer',
	'Dan Sully',
	'Richard Titmuss',
);

our $VERSION     = '7.0a1';
our $REVISION    = undef;
our $audiodir    = undef
our $playlistdir = undef;
our $httpport    = undef;

our (
	$cachedir,
	$user,
	$group,
	$cliaddr,
	$cliport,
	$daemon,
	$diag,
	$httpaddr,
	$lastlooptime,
	$logfile,
	$logdir,
	$logconf,
	$debug,
	$LogTimestamp,
	$localClientNetAddr,
	$localStreamAddr,
	$newVersion,
	$pidfile,
	$prefsfile,
	$priority,
	$quiet,
	$nosetup,
	$noserver,
	$noupnp,
	$stdio,
	$stop,
	$perfmon,
	$perfwarn,
	$d_startup, # Needed for Slim::bootstrap
);

sub init {

	# initialize the process and daemonize, etc...
	srand();

	autoflush STDERR;
	autoflush STDOUT;

	# The revision file may not exist for svn copies.
	$REVISION = eval { File::Slurp::read_file(
		catdir(Slim::Utils::OSDetect::dirsFor('revision'), 'revision.txt')
	) } || 'TRUNK';

	if ($diag) { 
		eval "use diagnostics";
	}

	msg("SlimServer OSDetect init...\n");
	Slim::Utils::OSDetect::init();

	# initialize slimserver subsystems
	msg("SlimServer settings init...\n");
	initSettings();

	# Now that the user might have changed - open the log files.
	Slim::Utils::Log->init({
		'logconf' => $logconf,
		'logdir'  => $logdir,
		'logfile' => $logfile,
		'logtype' => 'server',
		'debug'   => $debug,
	});

	# Load a log handler for prefs now.
	Slim::Utils::Prefs::loadLogHandler();

	my $log = logger('server');

	$log->info("SlimServer OS Specific init...");

	if (Slim::Utils::OSDetect::OS() ne 'win') {
		$SIG{'HUP'} = \&initSettings;
	}		

	if (Slim::Utils::Misc::runningAsService()) {
		$SIG{'QUIT'} = \&Slim::bootstrap::ignoresigquit; 
	} else {
		$SIG{'QUIT'} = \&Slim::bootstrap::sigquit;
	}

	$SIG{__WARN__} = sub { msg($_[0]) };
	
	# Uncomment to enable crash debugging.
	#$SIG{__DIE__} = \&Slim::Utils::Misc::bt;

	# background if requested
	if (Slim::Utils::OSDetect::OS() ne 'win' && $daemon) {

		$log->info("SlimServer daemonizing...");
		daemonize();

	} else {

		save_pid_file();
	}

	# Change UID/GID after the pid & logfiles have been opened.
	$log->info("SlimServer settings effective user and group if requested...");
	changeEffectiveUserAndGroup();

	# Set priority, command line overrides pref
	if (defined $priority) {
		Slim::Utils::Misc::setPriority($priority);
	} else {
		Slim::Utils::Misc::setPriority( Slim::Utils::Prefs::get("serverPriority") );
	}

	$log->info("SlimServer strings init...");
	Slim::Utils::Strings::init();

	# initialize all player UI subsystems
	$log->info("SlimServer setting language...");
	Slim::Utils::Strings::setLanguage(Slim::Utils::Prefs::get("language"));

	$log->info("SlimServer MySQL init...");
	Slim::Utils::MySQLHelper->init();
	
	$log->info("Firmware init...");
	Slim::Utils::Firmware->init;

	$log->info("SlimServer Info init...");
	Slim::Music::Info::init();

	$log->info("SlimServer IR init...");
	Slim::Hardware::IR::init();

	$log->info("SlimServer Request init...");
	Slim::Control::Request::init();
	
	$log->info("SlimServer Buttons init...");
	Slim::Buttons::Common::init();

	$log->info("SlimServer Graphic Fonts init...");
	Slim::Display::Lib::Fonts::init();

	if ($stdio) {
		$log->info("SlimServer Stdio init...");
		Slim::Control::Stdio::init(\*STDIN, \*STDOUT);
	}

	$log->info("UDP init...");
	Slim::Networking::UDP::init();

	$log->info("Slimproto Init...");
	Slim::Networking::Slimproto::init();

	$log->info("mDNS init...");
	Slim::Networking::mDNS->init;

	$log->info("Async Networking init...");
	Slim::Networking::Async->init;
	
	$log->info("Cache init...");
	Slim::Utils::Cache->init();

	if (!$noupnp) {
		$log->info("UPnP init...");
		Slim::Utils::UPnPMediaServer::init();
	}

	$log->info("Source conversion init..");
	Slim::Player::Source::init();

	$log->info("SlimServer Plugins init...");
	Slim::Utils::PluginManager::init();

	$log->info("mDNS startAdvertising...");
	Slim::Networking::mDNS->startAdvertising;

	# Reinitialize logging, as plugins may have been added.
	if (Slim::Utils::Log->needsReInit) {

		Slim::Utils::Log->reInit;
	}

	$log->info("SlimServer checkDataSource...");
	checkDataSource();

	# regular server has a couple more initial operations.
	$log->info("SlimServer persist playlists...");

	if (Slim::Utils::Prefs::get('persistPlaylists')) {

		Slim::Control::Request::subscribe(
			\&Slim::Player::Playlist::modifyPlaylistCallback, [['playlist']]
		);
	}

	checkVersion();

	$log->info("SlimServer HTTP init...");
	Slim::Web::HTTP::init();

	if (!$nosetup) {

		$log->info("SlimServer Web Settings init...");
		Slim::Web::Setup::initSetup();
	}

	# otherwise, get ready to loop
	$lastlooptime = Time::HiRes::time();

	$log->info("SlimServer done init...");
}

sub main {
	# command line options
	initOptions();

	# all other initialization
	init();

	while (!idle()) {}

	stopServer();
}

sub idle {
	my ($queuedIR, $queuedNotifications);

	my $now = Time::HiRes::time();

	# check for time travel (i.e. If time skips backwards for DST or clock drift adjustments)
	if ($now < $lastlooptime) {

		Slim::Utils::Timers::adjustAllTimers($now - $lastlooptime);

		logger('server.timers')->debug("Finished adjustAllTimers: " . Time::HiRes::time());
	} 

	$lastlooptime = $now;

	my $select_time = 0; # default to not waiting in select

	# empty IR queue
	if (!Slim::Hardware::IR::idle()) {

		# empty notifcation queue
		if (!Slim::Control::Request::checkNotifications()) {

			my $timer_due = Slim::Utils::Timers::nextTimer();		

			if (!defined($timer_due) || $timer_due > 0) {

				# run scheduled task if no timers overdue
				if (!Slim::Utils::Scheduler::run_tasks()) {

					# set select time if no scheduled task
					$select_time = $timer_due;

					if (!defined $select_time || $select_time > 1) {
						$select_time = 1
					}
				}
			}
		}
	}

	# $log->debug("select_time: $select_time");

	# call select and process any IO
	Slim::Networking::Select::select($select_time);

	# check the timers for any new tasks
	Slim::Utils::Timers::checkTimers();

	return $::stop;
}

sub idleStreams {
	my $timeout = shift || 0;
	
	# No idle stream processing in child web procs
	return if $Slim::Web::HTTP::inChild;

	my $select_time = 0;
	my $check_timers = 1;
	my $to;

	if ($timeout) {
		$select_time = Slim::Utils::Timers::nextTimer();
		if ( !defined($select_time) || $select_time > $timeout ) {
			$check_timers = 0;
			$select_time = $timeout;
		}
	}

	logger('server.timers')->debug("select_time: $select_time, checkTimers: $check_timers");

	Slim::Networking::Select::select($select_time, 1);

	if ( $check_timers ) {
		Slim::Utils::Timers::checkTimers();
	}
}

sub showUsage {
	print <<EOF;
Usage: $0 [--audiodir <dir>] [--playlistdir <dir>] [--diag] [--daemon] [--stdio] [--logfile <logfilepath>]
          [--user <username>]
          [--group <groupname>]
          [--httpport <portnumber> [--httpaddr <listenip>]]
          [--cliport <portnumber> [--cliaddr <listenip>]]
          [--priority <priority>]
          [--prefsfile <prefsfilepath> [--pidfile <pidfilepath>]]
          [--perfmon] [--perfwarn=<threshold>]
          [--d_various]

    --help           => Show this usage information.
    --audiodir       => The path to a directory of your MP3 files.
    --playlistdir    => The path to a directory of your playlist files.
    --cachedir       => Directory for SlimServer to save cached music and web data
    --diag           => Use diagnostics, shows more verbose errors.  Also slows down library processing considerably
    --logfile        => Specify a file for error logging.
    --noLogTimestamp => Don't add timestamp to log output
    --daemon         => Run the server in the background.
                        This may only work on Unix-like systems.
    --stdio          => Use standard in and out as a command line interface 
                        to the server
    --user           => Specify the user that server should run as.
                        Only usable if server is started as root.
                        This may only work on Unix-like systems.
    --group          => Specify the group that server should run as.
                        Only usable if server is started as root.
                        This may only work on Unix-like systems.
    --httpport       => Activate the web interface on the specified port.
                        Set to 0 in order disable the web server.
    --httpaddr       => Activate the web interface on the specified IP address.
    --cliport        => Activate the command line interface TCP/IP interface
                        on the specified port. Set to 0 in order disable the 
                        command line interface server.
    --cliaddr        => Activate the command line interface TCP/IP 
                        interface on the specified IP address.
    --prefsfile      => Specify the path of the the preferences file
    --pidfile        => Specify where a process ID file should be stored
    --quiet          => Minimize the amount of text output
    --playeraddr     => Specify the _server's_ IP address to use to connect 
                        to Slim players
    --priority       => set process priority from -20 (high) to 20 (low)
    --streamaddr     => Specify the _server's_ IP address to use to connect
                        to streaming audio sources
    --nosetup        => Disable setup via http.
    --noserver       => Disable web access server settings, but leave player settings accessible. Settings changes arenot preserved.
    --noupnp         => Disable UPnP subsystem
    --perfmon        => Enable internal server performance monitoring
    --perfwarn       => Generate log messages if internal tasks take longer than specified threshold

Commands may be sent to the server through standard in and will be echoed via
standard out.  See complete documentation for details on the command syntax.
EOF
}

sub initOptions {
	$LogTimestamp = 1;

	if (!GetOptions(
		'user=s'        => \$user,
		'group=s'       => \$group,
		'cliaddr=s'     => \$cliaddr,
		'cliport=s'     => \$cliport,
		'daemon'        => \$daemon,
		'diag'          => \$diag,
		'httpaddr=s'    => \$httpaddr,
		'httpport=s'    => \$httpport,
		'logfile=s'     => \$logfile,
		'logdir=s'      => \$logdir,
		'logconfig=s'   => \$logconf,
		'debug=s'       => \$debug,
		'LogTimestamp!' => \$LogTimestamp,
		'audiodir=s'    => \$audiodir,
		'playlistdir=s'	=> \$playlistdir,
		'cachedir=s'    => \$cachedir,
		'pidfile=s'     => \$pidfile,
		'playeraddr=s'  => \$localClientNetAddr,
		'priority=i'    => \$priority,
		'stdio'	        => \$stdio,
		'streamaddr=s'  => \$localStreamAddr,
		'prefsfile=s'   => \$prefsfile,
		'quiet'	        => \$quiet,
		'nosetup'       => \$nosetup,
		'noserver'      => \$noserver,
		'noupnp'        => \$noupnp,
		'perfmon'       => \$perfmon,
		'perfwarn=f'    => \$perfwarn, 
		'd_startup'     => \$d_startup, # Needed for Slim::bootstrap
	)) {
		showUsage();
		exit(1);
	}

	if (defined $perfwarn) {
		# enable performance monitoring and set warning thresholds on performance monitors
		$perfmon = 1;
		$Slim::Networking::Select::responseTime->setWarnHigh($perfwarn);
		$Slim::Networking::Select::selectTask->setWarnHigh($perfwarn);
		$Slim::Utils::Timers::timerTask->setWarnHigh($perfwarn);
		$Slim::Utils::Scheduler::schedulerTask->setWarnHigh($perfwarn);
		$Slim::Control::Request::requestTask->setWarnHigh($perfwarn);
	}
}

sub initSettings {

	Slim::Utils::Prefs::init();

	Slim::Utils::Prefs::load($prefsfile, $nosetup || $noserver);
	Slim::Utils::Prefs::checkServerPrefs();

	# upgrade splitchars => splitList
	if (my $splitChars = Slim::Utils::Prefs::get('splitchars')) {

		Slim::Utils::Prefs::delete("splitchars");

		# Turn the old splitchars list into a space separated list.
		my $splitList = join(' ', map { $_ } (split /\s+/, $splitChars)); 

		Slim::Utils::Prefs::set("splitList", $splitList);
	}
	
	# options override existing preferences
	if (defined($audiodir)) {
		Slim::Utils::Prefs::set("audiodir", $audiodir);
	}

	if (defined($playlistdir)) {
		Slim::Utils::Prefs::set("playlistdir", $playlistdir);
	}
	
	if (defined($cachedir)) {
		Slim::Utils::Prefs::set("cachedir", $cachedir);
	}
	
	if (defined($httpport)) {
		Slim::Utils::Prefs::set("httpport", $httpport);
	}

	if (defined($cliport)) {
		Slim::Utils::Prefs::set("cliport", $cliport);
	}

	# Bug: 583 - make sure we are using the actual case of the directories
	# and that they do not end in / or \
	# 
	# Bug: 3760 - don't strip the trailing slash before going to fixPath
	if (defined(Slim::Utils::Prefs::get("playlistdir")) && Slim::Utils::Prefs::get("playlistdir") ne '') {

		$playlistdir = Slim::Utils::Prefs::get("playlistdir");
		$playlistdir = Slim::Utils::Misc::fixPath($playlistdir);
		$playlistdir = Slim::Utils::Misc::pathFromFileURL($playlistdir);
		$playlistdir =~ s|[/\\]$||;

		Slim::Utils::Prefs::set("playlistdir",$playlistdir);
	}

	if (defined(Slim::Utils::Prefs::get("audiodir")) && Slim::Utils::Prefs::get("audiodir") ne '') {

		$audiodir = Slim::Utils::Prefs::get("audiodir");
		$audiodir = Slim::Utils::Misc::fixPath($audiodir);
		$audiodir = Slim::Utils::Misc::pathFromFileURL($audiodir);
		$audiodir =~ s|[/\\]$||;

		Slim::Utils::Prefs::set("audiodir",$audiodir);
	}
	
	if (defined(Slim::Utils::Prefs::get("cachedir")) && Slim::Utils::Prefs::get("cachedir") ne '') {

		$cachedir = Slim::Utils::Prefs::get("cachedir");
		$cachedir = Slim::Utils::Misc::fixPath($cachedir);
		$cachedir = Slim::Utils::Misc::pathFromFileURL($cachedir);
		$cachedir =~ s|[/\\]$||;

		Slim::Utils::Prefs::set("cachedir",$cachedir);
	}

	Slim::Utils::Prefs::makeCacheDir();	
}

sub daemonize {
	my ($pid, $log);

	if (!defined($pid = fork())) {

		die "Can't fork: $!";
	}

	if ($pid) {
		save_pid_file($pid);

		# don't clean up the pidfile!
		$pidfile = undef;
		exit;
	}

	if (!setsid) {
		die "Can't start a new session: $!";
	}

	open STDOUT, '>>/dev/null';

	if (!open STDERR, '>&STDOUT') {
		die "Can't dup stdout: $!";
	}
}

sub changeEffectiveUserAndGroup {

	# Windows doesn't have getpwnam, and the uid is always 0.
	if ($^O eq 'MSWin32') {
		return;
	}

	# Don't allow the server to be started as root.
	# MySQL can't be run as root, and it's generally a bad idea anyways.
	#
	# See if there's a slimserver user we can switch to.
	if ($> == 0 && !$user) {

		my $testUser = 'slimserver';
		my $uid      = getpwnam($testUser);

		if ($> == 0 && (!defined $uid || $uid == 0)) {

			# Don't allow the server to be started as root.
			# MySQL can't be run as root, and it's generally a bad idea anyways.
			print "* Error: SlimServer must not be run as root! Exiting! *\n";
			exit;

		} else {

			$user = $testUser;
		}
	}

	# Do we want to change the effective user or group?
	if (defined($user) || defined($group)) {

		# Can only change effective UID/GID if root
		if ($> != 0) {
			my $uname = getpwuid($>);
			print STDERR "Current user is $uname\n";
			print STDERR "Must run as root to change effective user or group.\n";
			die "Aborting";
		}

		# Change effective group ID if necessary
		# Need to do this while still root, so do group first
		if (defined($group)) {

			my $gid = getgrnam($group);

			if (!defined $gid) {
				die "Group $group not found.\n";
			}

			$) = $gid;

			# $) is a space separated list that begins with the effective gid then lists
			# any supplementary group IDs, so compare against that.  On some systems
			# no supplementary group IDs are present at system startup or at all.
			if ( $) !~ /^$gid\b/) {
				die "Unable to set effective group(s) to $group ($gid) is: $): $!\n";
			}
		}

		# Change effective user ID if necessary
		if (defined($user)) {

			my $uid = getpwnam($user);

			if (!defined ($uid)) {
				die "User $user not found.\n";
			}

			$> = $uid;

			if ($> != $uid) {
				die "Unable to set effective user to $user, ($uid)!\n";
			}
		}
	}
}

sub checkDataSource {

	if (!(defined Slim::Utils::Prefs::get("audiodir") && 
		-d Slim::Utils::Prefs::get("audiodir")) && !$quiet && !Slim::Music::Import->countImporters()) {

		msg("\n", 0, 1);
		msg(string('SETUP_DATASOURCE_1') . "\n", 0, 1);
		msg(string('SETUP_DATASOURCE_2') . "\n\n", 0, 1);
		msg(string('SETUP_URL_WILL_BE') . "\n\n\t" . Slim::Utils::Prefs::homeURL() . "\n\n", 0, 1);

	} else {

		if (defined(Slim::Utils::Prefs::get("audiodir")) && Slim::Utils::Prefs::get("audiodir") =~ m|[/\\]$|) {
			$audiodir = Slim::Utils::Prefs::get("audiodir");
			$audiodir =~ s|[/\\]$||;
			Slim::Utils::Prefs::set("audiodir",$audiodir);
		}

		if (Slim::Schema->count('Track', { 'me.audio' => 1 }) == 0) {

			logWarning("No tracks in the database, initiating scan.");

			Slim::Control::Request::executeRequest(undef, ['wipecache']);
		}
	}
}

sub checkVersion {

	if (!Slim::Utils::Prefs::get("checkVersion")) {

		$newVersion = undef;
		return;
	}

	my $lastTime = Slim::Utils::Prefs::get('checkVersionLastTime');
	my $log      = logger('server.timers');

	if ($lastTime) {

		my $delta = Time::HiRes::time() - $lastTime;

		if (($delta > 0) && ($delta < Slim::Utils::Prefs::get('checkVersionInterval'))) {

			$log->info(sprintf("Checking version in %s seconds",
				($lastTime + Slim::Utils::Prefs::get('checkVersionInterval') + 2 - Time::HiRes::time())
			));

			Slim::Utils::Timers::setTimer(0, $lastTime + Slim::Utils::Prefs::get('checkVersionInterval') + 2, \&checkVersion);

			return;
		}
	}

	$log->info("Checking version now.");

	my $url  = "http://update.slimdevices.com/update/?version=$VERSION&lang=" . Slim::Utils::Strings::getLanguage();
	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&checkVersionCB, \&checkVersionError);

	# will call checkVersionCB when complete
	$http->get($url);

	Slim::Utils::Prefs::set('checkVersionLastTime', Time::HiRes::time());
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + Slim::Utils::Prefs::get('checkVersionInterval'), \&checkVersion);
}

# called when check version request is complete
sub checkVersionCB {
	my $http = shift;

	# store result in global variable, to be displayed by browser
	if ($http->{code} =~ /^2\d\d/) {
		$::newVersion = $http->content();
		chomp($::newVersion);
	}
	else {
		$::newVersion = 0;
		logWarning(sprintf(Slim::Utils::Strings::string('CHECKVERSION_PROBLEM'), $http->{code}));
	}
}

# called only if check version request fails
sub checkVersionError {
	my $http = shift;

	logError(Slim::Utils::Strings::string('CHECKVERSION_ERROR') . "\n" . $http->error);
}

sub forceStopServer {
	$::stop = 1;
}

#------------------------------------------
#
# Clean up resources and exit.
#
sub stopServer {

	logger('')->info("SlimServer shutting down.");
	cleanup();
	exit();
}

sub cleanup {

	logger('')->info("SlimServer cleaning up.");

	# Make sure to flush anything in the database to disk.
	if ($INC{'Slim/Schema.pm'}) {
		Slim::Schema->forceCommit;
		Slim::Schema->disconnect;
	}

	Slim::Utils::PluginManager::shutdownPlugins();

	if (Slim::Utils::Prefs::writePending()) {
		Slim::Utils::Prefs::writePrefs();
	}

	Slim::Networking::mDNS->stopAdvertising;

	if (Slim::Utils::Prefs::get('persistPlaylists')) {
		Slim::Control::Request::unsubscribe(
			\&Slim::Player::Playlist::modifyPlaylistCallback);
	}

	Slim::Utils::MySQLHelper->cleanup;

	remove_pid_file();
}

sub save_pid_file {
	my $process_id = shift || $$;

	logger('')->info("SlimServer saving pid file.");

	if (defined $pidfile) {
		File::Slurp::write_file($pidfile, $process_id);
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
 
# start up the server if we're not running as a service.	
if (!defined($PerlSvc::VERSION)) { 
	main()
}

__END__
