#!/opt/sdi/bin/perl

# Logitech Media Server Copyright (C) 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

# Sometimes changes are made only in the SN code but that require
# restarting slimservice.  Force slimservice to reload by changing
# this text.

require 5.008_001;
use strict;

use Config;
use Data::Dump qw(dump);
use File::Slurp;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

# Enable SlimService mode
use constant SLIM_SERVICE  => 1;
use constant SCANNER       => 0;
use constant RESIZER       => 0;
use constant TRANSCODING   => 0;
use constant PERFMON       => 0;
use constant DEBUGLOG      => ( grep { /--no(?:debug|info)log/ } @ARGV ) ? 0 : 1;
use constant INFOLOG       => ( grep { /--noinfolog/ } @ARGV ) ? 0 : 1;
use constant SB1SLIMP3SYNC => 0;
use constant STATISTICS    => 0;
use constant WEBUI         => 0;
use constant IMAGE         => 0;
use constant VIDEO         => 0;
use constant ISWINDOWS     => ( $^O =~ /^m?s?win/i ) ? 1 : 0;
use constant ISMAC         => ( $^O =~ /darwin/i ) ? 1 : 0;
use constant LOCALFILE     => 0;

my $sn_config;
our $SN_PATH; # path to squeezenetwork directory

BEGIN {
	my @SlimINC = ($Bin);
	
	# Force poll backend on Linux
	if ( $^O =~ /linux/ ) {
		$ENV{LIBEV_FLAGS} = 2;
	}
	
	# SLIM_SERVICE
	# Get path to SN modules
	if ( -d '/opt/sn/lib' ) {
		# SN Production
		$SN_PATH = '/opt/sn';
	}
	else {
		# Local development
		my $conf = "$FindBin::Bin/slimservice.conf";
		if ( !-e $conf ) {
			die "Please create $conf with the path to the mysqueezebox.com directory\n";
		}
		$SN_PATH = File::Slurp::read_file( $conf );
		chomp $SN_PATH;
	}
	
	# Load SN modules before CPAN modules, to allow for newer modules such as DBD::mysql
	push @SlimINC, $SN_PATH . '/lib';
	
	my $arch = $Config::Config{'archname'};
	   $arch =~ s/^i[3456]86-/i386-/;
	   $arch =~ s/gnu-//;

	# Include custom x86_64 module binaries on production
	push @SlimINC, (
		catdir($SN_PATH,'lib','arch',(join ".", map {ord} (split //, $^V)[0,1]), $arch),
		catdir($SN_PATH,'lib','arch',(join ".", map {ord} (split //, $^V)[0,1]), $arch, 'auto'),
	);
	
	push @SlimINC, (
		catdir($Bin,'CPAN','arch',(join ".", map {ord} (split //, $^V)[0,1]), $arch),
		catdir($Bin,'CPAN','arch',(join ".", map {ord} (split //, $^V)[0,1]), $arch, 'auto'),
		catdir($Bin, 'lib'),
		catdir($Bin, 'CPAN'),
	);

	unshift @INC, @SlimINC;

	require Slim::Utils::OSDetect;
	Slim::Utils::OSDetect::init();

	# Pull in DeploymentDefaults
	require SDI::Util::SNConfig;
	$sn_config = SDI::Util::SNConfig::get_config( $SN_PATH );
	
	require SDI::Service::Model::DBI;
	require SDI::Util::ClassDBIBase;
	SDI::Service::Model::DBI->init( $sn_config );
	
	require SDI::Util::Memcached;
	SDI::Util::Memcached->new( $sn_config->{memcached} );
	
	require SDI::Service::Comet;
	require SDI::Service::Control;
	require SDI::Service::Heartbeat;
	require SDI::Service::JSONRPC;
	require SDI::Service::EventLog;
	require SDI::Service::UPnP;
};

# SlimService doesn't use Bootstrap
use DBI;
use Locale::Hebrew;
use XML::Parser;
use HTML::Parser;
use Compress::LZF ();
use Digest::SHA1;

$SIG{'CHLD'} = 'DEFAULT';
$SIG{'PIPE'} = 'IGNORE';
$SIG{'TERM'} = \&sighandle;
$SIG{'INT'}  = \&sighandle;
$SIG{'QUIT'} = \&sighandle;

use Getopt::Long;
use POSIX qw(:signal_h :errno_h :sys_wait_h setsid);
use Socket qw(:DEFAULT :crlf);
use Time::HiRes;

# Force XML::Simple to use XML::Parser for speed. This is done
# here so other packages don't have to worry about it. If we
# don't have XML::Parser installed, we fall back to PurePerl.
use XML::Simple;
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
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
#use Slim::Web::HTTP;
use Slim::Hardware::IR;
use Slim::Menu::TrackInfo;
use Slim::Menu::AlbumInfo;
use Slim::Menu::ArtistInfo;
use Slim::Menu::GenreInfo;
use Slim::Menu::YearInfo;
use Slim::Menu::SystemInfo;
use Slim::Menu::PlaylistInfo;
use Slim::Menu::GlobalSearch;
use Slim::Music::Info;
#use Slim::Music::Import;
#use Slim::Music::MusicFolderScan;
#use Slim::Music::PlaylistFolderScan;
use Slim::Player::Playlist;
use Slim::Player::Sync;
use Slim::Player::Source;
#use Slim::Utils::Cache;
use Slim::Utils::Scanner;
#use Slim::Utils::Scheduler;
use Slim::Networking::Async::DNS;
use Slim::Networking::Select;
#use Slim::Networking::UDP;
#use Slim::Web::Setup;
use Slim::Control::Stdio;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;
#use Slim::Utils::MySQLHelper;
use Slim::Networking::Slimproto;
use Slim::Networking::SimpleAsyncHTTP;
#use Slim::Utils::Firmware;
#use Slim::Utils::UPnPMediaServer;
use Slim::Control::Jive;
use Slim::Formats::RemoteMetadata;

if ( DEBUGLOG ) {
	require Data::Dump;
	require Slim::Utils::PerlRunTime;
}

my $sqlHelperClass = Slim::Utils::OSDetect->getOS()->sqlHelperClass();
eval "use $sqlHelperClass";
die $@ if $@;

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
my $prefs        = preferences('server');

our $VERSION     = '7.8.0-sn';
our $REVISION    = undef;
our $audiodir    = undef;
our $playlistdir = undef;
our $httpport    = undef;

our $SLIMPROTO_PORT = 3483;

my $profile = 0;

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
	$checkstrings,
	$d_startup, # Needed for Slim::bootstrap
	$sigINTcalled,
	$inInit,
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

	# open the log files
	Slim::Utils::Log->init({
		'logconf' => $logconf,
		'logdir'  => $logdir,
		'logfile' => $logfile,
		'logtype' => 'server',
		'debug'   => $debug,
	});

	# initialize server subsystems
	msg("Server settings init...\n");
	initSettings();

	# Redirect STDERR to the log file.
	tie *STDERR, 'Slim::Utils::Log::Trapper';

	my $log = logger('server');

	main::INFOLOG && $log->info("Server OS Specific init...");

	unless (main::ISWINDOWS) {
		$SIG{'HUP'} = \&initSettings;
	}		

	$SIG{__WARN__} = sub { msg($_[0]) };
	
	# Uncomment to enable crash debugging.
	$SIG{__DIE__} = \&Slim::Utils::Misc::bt;
	
	# Start/stop profiler during runtime (requires Devel::NYTProf)
	# and NYTPROF env var set to 'start=no'
	if ( $INC{'Devel/NYTProf.pm'} && $ENV{NYTPROF} =~ /start=no/ ) {
		$SIG{USR1} = sub {
			DB::enable_profile();
			warn "Profiling enabled...\n";
		};
	
		$SIG{USR2} = sub {
			DB::finish_profile();
			warn "Profiling disabled...\n";
		};
	}
	
	# Dump memory usage to a file if called with a USR1
=pod
	if ($d_memory) {

		require Slim::Utils::MemoryUsage;

		$SIG{'USR1'} = sub {
			Slim::Utils::MemoryUsage->status_memory_usage();
		};
	}

	# Turn profiling on and off

	$SIG{'USR2'} = sub {

		if ($profile) {
			msg("Turning profiling off.\n");
			$profile = 0;
			SDI::Util::Profiler::end();

		} else {

			msg("Turning profiling on.\n");
			$profile = 1;
			SDI::Util::Profiler::init();
		}
	};
=cut

	# Find plugins and process any new ones now so we can load their strings
	main::INFOLOG && $log->info("Server PluginManager init...");
	Slim::Utils::PluginManager->init();

	main::INFOLOG && $log->info("Server strings init...");
	Slim::Utils::Strings::init();
	
	main::INFOLOG && $log->info("Server Info init...");
	Slim::Music::Info::init();

	main::INFOLOG && $log->info("Server IR init...");
	Slim::Hardware::IR::init();

	main::INFOLOG && $log->info("Server Request init...");
	Slim::Control::Request::init();
	
	main::INFOLOG && $log->info("Server Buttons init...");
	Slim::Buttons::Common::init();

	main::INFOLOG && $log->info("Server Graphic Fonts init...");
	Slim::Display::Lib::Fonts::init();

	main::INFOLOG && $log->info("Slimproto Init...");
	Slim::Networking::Slimproto::init();

	main::INFOLOG && $log->info("Async DNS init...");
	Slim::Networking::Async::DNS->init;

	main::INFOLOG && $log->info("Async HTTP init...");
	Slim::Networking::SimpleAsyncHTTP->init;
	
	main::INFOLOG && $log->info('Menu init...');
	Slim::Menu::TrackInfo->init();
	Slim::Menu::AlbumInfo->init();
	Slim::Menu::ArtistInfo->init();
	Slim::Menu::GenreInfo->init();
	Slim::Menu::YearInfo->init();
	Slim::Menu::SystemInfo->init();
	Slim::Menu::PlaylistInfo->init();
	Slim::Menu::GlobalSearch->init();
	
	main::INFOLOG && $log->info('Server Alarms init...');
	Slim::Utils::Alarm->init();

	# load plugins before Jive init so MusicIP hooks to cached artist/genre queries from Jive->init() will take root
	main::INFOLOG && $log->info("Server Load Plugins...");
	Slim::Utils::PluginManager->load();
	
	main::INFOLOG && $log->info("Server Jive init...");
	Slim::Control::Jive->init();
	
	main::INFOLOG && $log->info("Remote Metadata init...");
	Slim::Formats::RemoteMetadata->init();

	if ( SLIM_SERVICE ) {
		# start SlimService specific stuff
		SDI::Service::Heartbeat->init();
		
		SDI::Service::Control->init( $sn_config );
		
		# start Comet handler
		SDI::Service::Comet->init();
		
		# start JSONRPC handler
		SDI::Service::JSONRPC->init();
		
		# start event logging
		SDI::Service::EventLog->init();
		
		# start UPnP support
		SDI::Service::UPnP->init();
	}

	# Reinitialize logging, as plugins may have been added.
	if (Slim::Utils::Log->needsReInit) {

		Slim::Utils::Log->reInit;
	}

	# otherwise, get ready to loop
	$lastlooptime = Time::HiRes::time();
	
	$inInit = 0;

	main::INFOLOG && $log->info("Logitech Media Server done init...");
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

	my $now = EV::now;

	# check for time travel (i.e. If time skips backwards for DST or clock drift adjustments)
	if ( $now < $lastlooptime || ( $now - $lastlooptime > 300 ) ) {		
		# For all clients that support RTC, we need to adjust their clocks
		for my $client ( Slim::Player::Client::clients() ) {
			if ( $client->hasRTCAlarm ) {
				$client->setRTCTime;
			}
		}
	}

	$lastlooptime = $now;
	
	# This flag indicates we have pending IR or request events to handle
	my $pendingEvents = 0;
	
	# process IR queue
	$pendingEvents = Slim::Hardware::IR::idle();
	
	if ( !$pendingEvents ) {
		# empty notifcation queue, only if no IR events are pending
		$pendingEvents = Slim::Control::Request::checkNotifications();
		
		if ( !main::SLIM_SERVICE && !$pendingEvents ) {
			# run scheduled tasks, only if no other events are pending
			# XXX: need a way to not call this unless someone is using Scheduler
			Slim::Utils::Scheduler::run_tasks();
		}
	}
	
	if ( $pendingEvents ) {
		# Some notifications are still pending, run the loop in non-blocking mode
		Slim::Networking::IO::Select::loop( EV::LOOP_NONBLOCK );
	}
	else {
		# No events are pending, run the loop until we get a select event
		Slim::Networking::IO::Select::loop( EV::LOOP_ONESHOT );
	}

	return $::stop;
}

sub idleStreams {
	my $timeout = shift || 0;
	
	# No idle processing during startup
	return if $inInit;
	
	# Loop once without blocking
	Slim::Networking::IO::Select::loop( EV::LOOP_NONBLOCK );
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
    --cachedir       => Directory for Logitech Media Server to save cached music and web data
    --diag           => Use diagnostics, shows more verbose errors.  Also slows down library processing considerably
    --logfile        => Specify a file for error logging.
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
		'httpaddr=s'    => \$httpaddr,
		'httpport=s'    => \$httpport,
		'slimprotoport=s' => \$SLIMPROTO_PORT,
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
}

sub initSettings {

	Slim::Utils::Prefs::init();
	
	$cliport ||= 9090;

	if (defined($cliport)) {
		preferences('plugin.cli')->set('cliport', $cliport);
	}
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

sub forceStopServer {
	$::stop = 1;
}

#------------------------------------------
#
# Clean up resources and exit.
#
sub restartServer {
	stopServer();
}

sub stopServer {

	logger('')->info("Logitech Media Server shutting down.");
	cleanup();
	exit();
}

sub cleanup {

	logger('')->info("Logitech Media Server cleaning up.");

	# Make sure to flush anything in the database to disk.
	if ($INC{'Slim/Schema.pm'}) {
		Slim::Schema->forceCommit;
		Slim::Schema->disconnect;
	}
	
	Slim::Utils::PluginManager->shutdownPlugins();
	
	if ( !SLIM_SERVICE ) {
		Slim::Utils::Prefs::writeAll();
	}

	if ( SLIM_SERVICE ) {
		SDI::Service::Control->cleanup();
	}
}
 
main();

# bootstrap sig handlers
sub sighandle {
	Slim::Utils::Misc::msg("Got a terminating signal.\n");
	SDI::Service::Heartbeat::shut_me_down();
}

sub END {
	SDI::Service::Heartbeat::shut_me_down();
}

package Slim::bootstrap;

sub tryModuleLoad {
	my $module = shift;
	
	eval "use $module";
	die $@ if $@;
}

__END__
