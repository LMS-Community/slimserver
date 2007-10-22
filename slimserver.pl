#!/usr/bin/perl -w

# SqueezeCenter Copyright (C) 2001-2007 Logitech.
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
	DisplayName => 'SqueezeCenter',
	Description => "SqueezeCenter Music Server",
	ServiceName => "squeezesvc",
);

sub Startup {
	# Tell PerlSvc to bundle these modules
	if (0) {
		require Encode::CN;
		require Encode::JP;
		require Encode::KR;
		require Encode::TW;
	}

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
use Slim::Utils::Prefs;
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
use Slim::Utils::Scanner;
use Slim::Utils::Scheduler;
use Slim::Networking::Async::DNS;
use Slim::Networking::Select;
use Slim::Networking::SqueezeNetwork;
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
use Slim::Control::Jive;

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
	'Ben Klaas',
);

my $prefs        = preferences('server');

our $VERSION     = '7.0';
our $REVISION    = undef;
our $audiodir    = undef;
our $playlistdir = undef;
our $httpport    = undef;

our (
	$inInit,
	$cachedir,
	$user,
	$group,
	$cliaddr,
	$cliport,
	$daemon,
	$diag,
	$help,
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
	$checkstrings,
	$d_startup, # Needed for Slim::bootstrap
);

sub init {
	$inInit = 1;

	# initialize the process and daemonize, etc...
	srand();

	# The revision file may not exist for svn copies.
	$REVISION = eval { File::Slurp::read_file(
		catdir(Slim::Utils::OSDetect::dirsFor('revision'), 'revision.txt')
	) } || 'TRUNK';

	if ($diag) { 
		eval "use diagnostics";
	}

	msg("SqueezeCenter OSDetect init...\n");
	Slim::Utils::OSDetect::init();

	# open the log files
	Slim::Utils::Log->init({
		'logconf' => $logconf,
		'logdir'  => $logdir,
		'logfile' => $logfile,
		'logtype' => 'server',
		'debug'   => $debug,
	});

	# initialize SqueezeCenter subsystems
	msg("SqueezeCenter settings init...\n");
	initSettings();

	# Redirect STDERR to the log file.
	tie *STDERR, 'Slim::Utils::Log::Trapper';

	my $log = logger('server');

	$log->info("SqueezeCenter OS Specific init...");

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

		$log->info("SqueezeCenter daemonizing...");
		daemonize();

	} else {

		save_pid_file();
	}

	# Change UID/GID after the pid & logfiles have been opened.
	$log->info("SqueezeCenter settings effective user and group if requested...");
	changeEffectiveUserAndGroup();

	# Set priority, command line overrides pref
	if (defined $priority) {
		Slim::Utils::Misc::setPriority($priority);
	} else {
		Slim::Utils::Misc::setPriority( $prefs->get('serverPriority') );
	}

	$log->info("SqueezeCenter strings init...");
	Slim::Utils::Strings::init();

	$log->info("SqueezeCenter MySQL init...");
	Slim::Utils::MySQLHelper->init();
	
	$log->info("Async DNS init...");
	Slim::Networking::Async::DNS->init;
	
	$log->info("Firmware init...");
	Slim::Utils::Firmware->init;

	$log->info("SqueezeCenter Info init...");
	Slim::Music::Info::init();

	$log->info("SqueezeCenter IR init...");
	Slim::Hardware::IR::init();

	$log->info("SqueezeCenter Request init...");
	Slim::Control::Request::init();
	
	$log->info("SqueezeCenter Buttons init...");
	Slim::Buttons::Common::init();

	$log->info("SqueezeCenter Graphic Fonts init...");
	Slim::Display::Lib::Fonts::init();

	if ($stdio) {
		$log->info("SqueezeCenter Stdio init...");
		Slim::Control::Stdio::init(\*STDIN, \*STDOUT);
	}

	$log->info("UDP init...");
	Slim::Networking::UDP::init();

	$log->info("Slimproto Init...");
	Slim::Networking::Slimproto::init();

	$log->info("mDNS init...");
	Slim::Networking::mDNS->init;

	$log->info("Cache init...");
	Slim::Utils::Cache->init();
	
	if ( $prefs->get('sn_email') && $prefs->get('sn_sync') ) {
		$log->info("SqueezeNetwork Sync Init...");
		Slim::Networking::SqueezeNetwork->init();
	}

	unless ( $noupnp || $prefs->get('noupnp') ) {
		$log->info("UPnP init...");
		Slim::Utils::UPnPMediaServer::init();
	}

	$log->info("SqueezeCenter HTTP init...");
	Slim::Web::HTTP::init();

	$log->info("Source conversion init..");
	Slim::Player::Source::init();

	if (!$nosetup) {

		$log->info("SqueezeCenter Web Settings init...");
		Slim::Web::Setup::initSetup();
	}

	$log->info("SqueezeCenter Jive init...");
	Slim::Control::Jive->init();

	$log->info("SqueezeCenter Plugins init...");
	Slim::Utils::PluginManager->init();

	# Reinitialize logging, as plugins may have been added.
	if (Slim::Utils::Log->needsReInit) {

		Slim::Utils::Log->reInit;
	}

	$log->info("SqueezeCenter checkDataSource...");
	checkDataSource();

	# regular server has a couple more initial operations.
	$log->info("SqueezeCenter persist playlists...");

	if ($prefs->get('persistPlaylists')) {

		Slim::Control::Request::subscribe(
			\&Slim::Player::Playlist::modifyPlaylistCallback, [['playlist']]
		);
	}

	checkVersion();

	$log->info("SqueezeCenter HTTP enable...");
	Slim::Web::HTTP::init2();

	# advertise once we are ready...
	$log->info("mDNS startAdvertising...");
	Slim::Networking::mDNS->startAdvertising;

	# otherwise, get ready to loop
	$lastlooptime = Time::HiRes::time();
	
	$inInit = 0;

	$log->info("SqueezeCenter done init...");
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
	# No idle processing during startup
	return if $inInit;
	
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

	# call select and process any IO
	Slim::Networking::Select::select($select_time);

	# check the timers for any new tasks
	Slim::Utils::Timers::checkTimers();

	return $::stop;
}

sub idleStreams {
	my $timeout = shift || 0;
	
	# No idle processing during startup
	return if $inInit;
	
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
          [--prefsdir <prefspath> [--pidfile <pidfilepath>]]
          [--perfmon] [--perfwarn=<threshold> | --perfwarn <warn options>]
          [--checkstrings] [--debug]

    --help           => Show this usage information.
    --audiodir       => The path to a directory of your MP3 files.
    --playlistdir    => The path to a directory of your playlist files.
    --cachedir       => Directory for SqueezeCenter to save cached music and web data
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
    --prefsdir       => Specify the location of the preferences directory
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
    --checkstrings   => Enable reloading of changed string files for plugin development
    --debug          => Enable debugging for the specified comma separated categories

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
		'help'          => \$help,
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
		# prefsdir is parsed by Slim::Utils::Prefs prior to initOptions being run
		'quiet'	        => \$quiet,
		'nosetup'       => \$nosetup,
		'noserver'      => \$noserver,
		'noupnp'        => \$noupnp,
		'perfmon'       => \$perfmon,
		'perfwarn=s'    => \$perfwarn,  # content parsed by Health plugin if loaded
		'checkstrings'  => \$checkstrings,
		'd_startup'     => \$d_startup, # Needed for Slim::bootstrap
	)) {
		showUsage();
		exit(1);
	}
	if ($help) {
		showUsage();
		exit(1);
	}
}

sub initSettings {

	Slim::Utils::Prefs::init();

	# options override existing preferences
	if (defined($audiodir)) {
		$prefs->set('audiodir', $audiodir);
	}

	if (defined($playlistdir)) {
		$prefs->set('playlistdir', $playlistdir);
	}
	
	if (defined($cachedir)) {
		$prefs->set('cachedir', $cachedir);
	}
	
	if (defined($httpport)) {
		$prefs->set('httpport', $httpport);
	}

	if (defined($cliport)) {
		preferences('plugin.cli')->set('cliport', $cliport);
	}

	# Bug: 583 - make sure we are using the actual case of the directories
	# and that they do not end in / or \
	# 
	# Bug: 3760 - don't strip the trailing slash before going to fixPath

	# FIXME - can these be done at pref set time rather than here which is once per startup
	if (defined($prefs->get('playlistdir')) && $prefs->get('playlistdir') ne '') {

		$playlistdir = $prefs->get('playlistdir');
		$playlistdir = Slim::Utils::Misc::fixPath($playlistdir);
		$playlistdir = Slim::Utils::Misc::pathFromFileURL($playlistdir);
		$playlistdir =~ s|[/\\]$||;

		$prefs->set('playlistdir',$playlistdir);
	}

	if (defined($prefs->get('audiodir')) && $prefs->get('audiodir') ne '') {

		$audiodir = $prefs->get('audiodir');
		$audiodir = Slim::Utils::Misc::fixPath($audiodir);
		$audiodir = Slim::Utils::Misc::pathFromFileURL($audiodir);
		$audiodir =~ s|[/\\]$||;

		$prefs->set('audiodir',$audiodir);
	}
	
	if (defined($prefs->get('cachedir')) && $prefs->get('cachedir') ne '') {

		$cachedir = $prefs->get('cachedir');
		$cachedir = Slim::Utils::Misc::fixPath($cachedir);
		$cachedir = Slim::Utils::Misc::pathFromFileURL($cachedir);
		$cachedir =~ s|[/\\]$||;

		$prefs->set('cachedir',$cachedir);
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
}

sub changeEffectiveUserAndGroup {

	# Windows doesn't have getpwnam, and the uid is always 0.
	if ($^O eq 'MSWin32') {
		return;
	}

	# If we're not root and need to change user and group then die with a
	# suitable message, else there's nothing more to do, so return.
	if ($> != 0) {

		if (defined($user) || defined($group)) {

			my $uname = getpwuid($>);
			print STDERR "Current user is $uname\n";
			print STDERR "Must run as root to change effective user or group.\n";
			die "Aborting";

		} else {

			return;

		}

	}

	my ($uid, $pgid, @sgids, $gid);

	# Don't allow the server to be started as root.
	# MySQL can't be run as root, and it's generally a bad idea anyways.
	# Try starting as 'slimserver' instead.
	if (!defined($user)) {
		$user = 'slimserver';
		print STDERR "SqueezeCenter must not be run as root!  Trying user $user instead.\n";
	}


	# Get the uid and primary group id for the $user.
	($uid, $pgid) = (getpwnam($user))[2,3];

	if (!defined ($uid)) {
		die "User $user not found.\n";
	}


	# Get the supplementary groups to which $user belongs

	setgrent();

	while (my @grp = getgrent()) {
		if ($grp[3] =~ m/\b$user\b/){ push @sgids, $grp[2] }
	}

	endgrent();

	# If a group was specified, get the gid of it and add it to the 
	# list of supplementary groups.
	if (defined($group)) {
		$gid = getgrnam($group);

		if (!defined $gid) {
			die "Group $group not found.\n";
		} else {
			push @sgids, $gid;
		}
	}

	# Check that we're definately not trying to start as root, e.g. if
	# we were passed '--user root' or any other used with uid 0.
	if ($uid == 0) {
		print STDERR "SqueezeCenter must not be run as root! Exiting!\n";
		die "Aborting";
	}


	# Change effective group. Need to do this while still root, so do group first

	# $) is a space separated list that begins with the effective gid then lists
	# any supplementary group IDs, so compare against that.  On some systems
	# no supplementary group IDs are present at system startup or at all.

	# We need to pass $pgid twice because setgroups only gets called if there's 
	# more than one value.  For example, if we did:
	# $) = "1234"
	# then the effective primary group would become 1234, but we'd retain any 
	# previously set supplementary groups.  To become a member of just 1234, the 
	# correct way is to do:
	# $) = "1234 1234"

	undef $!;
	$) = "$pgid $pgid " . join (" ", @sgids);

	if ( $! ) {
		die "Unable to set effective group(s) to $group ($gid) is: $): $!\n";
	}

	# Finally, change effective user id.

	undef $!;
	$> = $uid;

	if ( $! ) {
		die "Unable to set effective user to $user, ($uid)!\n";
	}

	logger('server')->info("Running as uid: $> / gid: $)");
}

sub checkDataSource {

	my $audiodir = $prefs->get('audiodir');

	if (!(defined $audiodir && -d $audiodir) && !$quiet && !Slim::Music::Import->countImporters()) {

		msg("\n", 0, 1);
		msg(string('SETUP_DATASOURCE_1') . "\n", 0, 1);
		msg(string('SETUP_DATASOURCE_2') . "\n\n", 0, 1);
		msg(string('SETUP_URL_WILL_BE') . "\n\n\t" . Slim::Utils::Prefs::homeURL() . "\n\n", 0, 1);

	} else {

		if (defined $audiodir && $audiodir =~ m|[/\\]$|) {
			$audiodir =~ s|[/\\]$||;
			$prefs->set('audiodir',$audiodir);
		}

		if (Slim::Schema->schemaUpdated || Slim::Schema->count('Track', { 'me.audio' => 1 }) == 0) {

			logWarning("Schema updated or tracks in the database, initiating scan.");

			Slim::Control::Request::executeRequest(undef, ['wipecache']);
		}
	}
}

sub checkVersion {

	if (!$prefs->get('checkVersion')) {

		$newVersion = undef;
		return;
	}

	my $lastTime = $prefs->get('checkVersionLastTime');
	my $log      = logger('server.timers');

	if ($lastTime) {

		my $delta = Time::HiRes::time() - $lastTime;

		if (($delta > 0) && ($delta < $prefs->get('checkVersionInterval'))) {

			if ( $log->is_info ) {
				$log->info(sprintf("Checking version in %s seconds",
					($lastTime + $prefs->get('checkVersionInterval') + 2 - Time::HiRes::time())
				));
			}

			Slim::Utils::Timers::setTimer(0, $lastTime + $prefs->get('checkVersionInterval') + 2, \&checkVersion);

			return;
		}
	}

	$log->info("Checking version now.");

	my $url  = "http://update.slimdevices.com/update/?version=$VERSION&lang=" . Slim::Utils::Strings::getLanguage();
	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&checkVersionCB, \&checkVersionError);

	# will call checkVersionCB when complete
	$http->get($url);

	$prefs->set('checkVersionLastTime', Time::HiRes::time());
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $prefs->get('checkVersionInterval'), \&checkVersion);
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

	logger('')->info("SqueezeCenter shutting down.");
	cleanup();
	exit();
}

sub cleanup {

	logger('')->info("SqueezeCenter cleaning up.");

	# Make sure to flush anything in the database to disk.
	if ($INC{'Slim/Schema.pm'}) {
		Slim::Schema->forceCommit;
		Slim::Schema->disconnect;
	}

	Slim::Utils::PluginManager->shutdownPlugins();

	Slim::Utils::Prefs::writeAll();

	Slim::Networking::mDNS->stopAdvertising;

	if ($prefs->get('persistPlaylists')) {
		Slim::Control::Request::unsubscribe(
			\&Slim::Player::Playlist::modifyPlaylistCallback);
	}

	Slim::Utils::MySQLHelper->cleanup;

	remove_pid_file();
}

sub save_pid_file {
	my $process_id = shift || $$;

	logger('')->info("SqueezeCenter saving pid file.");

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
