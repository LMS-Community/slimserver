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

use constant SLIM_SERVICE => 0;
use constant SCANNER      => 0;
use constant RESIZER      => 0;
use constant TRANSCODING  => ( grep { /--notranscoding/ } @ARGV ) ? 0 : 1;
use constant PERFMON      => ( grep { /--perfwarn/ } @ARGV ) ? 1 : 0;
use constant DEBUGLOG     => ( grep { /--no(?:debug|info)log/ } @ARGV ) ? 0 : 1;
use constant INFOLOG      => ( grep { /--noinfolog/ } @ARGV ) ? 0 : 1;
use constant STATISTICS   => ( grep { /--nostatistics/ } @ARGV ) ? 0 : 1;
use constant SB1SLIMP3SYNC=> ( grep { /--nosb1slimp3sync/ } @ARGV ) ? 0 : 1;
use constant WEBUI        => ( grep { /--noweb/ } @ARGV ) ? 0 : 1;
use constant IMAGE        => ( grep { /--noimage/ } @ARGV ) ? 0 : 1;
use constant VIDEO        => ( grep { /--novideo/ } @ARGV ) ? 0 : 1;
use constant ISWINDOWS    => ( $^O =~ /^m?s?win/i ) ? 1 : 0;
use constant ISMAC        => ( $^O =~ /darwin/i ) ? 1 : 0;
use constant LOCALFILE    => ( grep { /--localfile/ } @ARGV ) ? 1 : 0;

use Config;
my %check_inc;
$ENV{PERL5LIB} = join $Config{path_sep}, grep { !$check_inc{$_}++ } @INC;

# This package section is used for the windows service version of the application, 
# as built with ActiveState's PerlSvc
package PerlSvc;

our %Config = (
	DisplayName => 'Logitech Media Server',
	Description => "Logitech Media Server - streaming media server",
	ServiceName => "squeezesvc",
	StartNow    => 0,
);

sub Startup {
	# Tell PerlSvc to bundle these modules
	if (0) {
		require 'auto/Compress/Raw/Zlib/autosplit.ix';
	}
	
	# added to workaround a problem with 5.8 and perlsvc.
	# $SIG{BREAK} = sub {} if RunningAsService();
	main::initOptions();
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

	main::initLogging();

	if ((defined $Username) && ((defined $Password) && length($Password) != 0)) {
		my @infos;
		my ($host, $user);

		# use the localhost '.' by default, unless user has defined "domain\username"
		if ($Username =~ /(.+)\\(.+)/) {
			$host = $1;
			$user = $2;
		}
		else {
			$host = '.';
			$user = $Username;
		}

		# configure user to be used to run the server
		my $grant = PerlSvc::extract_bound_file('grant.exe');
		if ($host && $user && $grant && !`$grant add SeServiceLogonRight $user`) {
			$Config{UserName} = "$host\\$user";
			$Config{Password} = $Password;
		}
	}
}

sub Interactive {
	main::main();	
}

sub Remove {
	# add your additional remove messages or functions here
	main::initLogging();
}

sub Help {	
	main::showUsage();
	main::initLogging();
}

package main;

use FindBin qw($Bin);
use lib $Bin;

our @argv;

BEGIN {
	# With EV, only use select backend
	# I have seen segfaults with poll, and epoll is not stable
	$ENV{LIBEV_FLAGS} = 1;

	# set the AnyEvent model to our subclassed version when PERFMON is enabled
	$ENV{PERL_ANYEVENT_MODEL} = 'PerfMonEV' if main::PERFMON;
	$ENV{PERL_ANYEVENT_MODEL} ||= 'EV';
	
	# By default, tell Audio::Scan not to get artwork to save memory
	# Where needed, this is locally changed to 0.
	$ENV{AUDIO_SCAN_NO_ARTWORK} = 1;

	# save argv
	@argv = @ARGV;
        
	use Slim::bootstrap;
	use Slim::Utils::OSDetect;

	Slim::bootstrap->loadModules();
};

use File::Slurp;
use Getopt::Long;
use File::Spec::Functions qw(:ALL);
use POSIX qw(setsid);
use Time::HiRes;
use EV;
use AnyEvent;

# Load AIO support if available
my $HAS_AIO;
sub HAS_AIO {
	return $HAS_AIO if defined $HAS_AIO;
		
	eval {
		require AnyEvent::AIO;
		IO::AIO::max_poll_time( 0.01 ); # Make AIO play nice if there are a lot of requests (10ms per poll)
		$HAS_AIO = 1;
	};
	
	$HAS_AIO = 0 if !$HAS_AIO;	# Make sure it is defined now.
	
	return $HAS_AIO;
}

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
use Slim::Web::HTTP;
use Slim::Hardware::IR;
use Slim::Menu::TrackInfo;
use Slim::Menu::AlbumInfo;
use Slim::Menu::ArtistInfo;
use Slim::Menu::GenreInfo;
use Slim::Menu::YearInfo;
use Slim::Menu::SystemInfo;
use Slim::Menu::PlaylistInfo;
use Slim::Menu::FolderInfo;
use Slim::Menu::GlobalSearch;
use Slim::Menu::BrowseLibrary;
use Slim::Music::Info;
use Slim::Music::Import;
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
use Slim::Control::Stdio;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;
use Slim::Utils::Update;
use Slim::Networking::Slimproto;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Firmware;
use Slim::Control::Jive;
use Slim::Formats::RemoteMetadata;

if ( SB1SLIMP3SYNC ) {
	require Slim::Player::SB1SliMP3Sync;
}

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
	'Michael Herger',
	'Christopher Key',
	'Ben Klaas',
	'Mark Langston',
	'Eric Lyons',
	'Scott McIntyre',
	'Robert Moser',
	'Felix Müller',
	'Dave Nanian',
	'Jacob Potter',
	'Sam Saffron',
	'Roy M. Silvernail',
	'Adrian Smith',
	'Richard Smith',
	'Max Spicer',
	'Dan Sully',
	'Richard Titmuss',
	'Alan Young'
);

my $prefs        = preferences('server');

our $VERSION     = '7.8.0';
our $REVISION    = undef;
our $BUILDDATE   = undef;
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
	$norestart,
	$noupnp,
	$noweb,
	$notranscoding,
	$nodebuglog,
	$noinfolog,
	$noimages,
	$novideo,
	$nosb1slimp3sync,
	$nostatistics,
	$stdio,
	$stop,
	$perfwarn,
	$failsafe,
	$checkstrings,
	$charset,
	$dbtype,
	$d_startup, # Needed for Slim::bootstrap
);

sub init {
	$inInit = 1;
	
	# May get overridden by object-leak or nytprof usage below
	$SIG{USR2} = \&Slim::Utils::Log::logBacktrace;
	
	# Can only have one of NYTPROF and Object-Leak at a time
	if ( $ENV{OBJECT_LEAK} ) {
		require Devel::Leak::Object;
		Devel::Leak::Object->import(qw(GLOBAL_bless));
		$SIG{USR2} = sub {
			Devel::Leak::Object::status();
			warn "Dumping objects...\n";
		};
	}
	
	# initialize the process and daemonize, etc...
	srand();

	($REVISION, $BUILDDATE) = Slim::Utils::Misc::parseRevision();

	my $log = logger('server');

	$log->error("Starting Logitech Media Server (v$VERSION, $REVISION, $BUILDDATE) perl $]");

	if ($diag) { 
		eval "use diagnostics";
	}

	# force a charset from the command line
	$Slim::Utils::Unicode::lc_ctype = $charset if $charset;
	
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

	Slim::Utils::OSDetect::init();

	# initialize server subsystems
	initSettings();

	# Redirect STDERR to the log file.
	tie *STDERR, 'Slim::Utils::Log::Trapper';

	main::INFOLOG && $log->info("OS Specific init...");

	unless (main::ISWINDOWS) {
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
	
	# Start/stop profiler during runtime (requires Devel::NYTProf)
	# and NYTPROF env var set to 'start=no'
	if ( $ENV{NYTPROF} && $INC{'Devel/NYTProf.pm'} && $ENV{NYTPROF} =~ /start=no/ ) {
		$SIG{USR1} = sub {
			DB::enable_profile();
			warn "Profiling enabled...\n";
		};
	
		$SIG{USR2} = sub {
			DB::finish_profile();
			warn "Profiling disabled...\n";
		};
	}

	# background if requested
	if (!main::ISWINDOWS && $daemon) {

		main::INFOLOG && $log->info("Server daemonizing...");
		daemonize();

	} else {

		save_pid_file();
	}
	
	# leave a mark for external tools
	$failsafe ? $prefs->set('failsafe', 1) : $prefs->remove('failsafe');

	# Change UID/GID after the pid & logfiles have been opened.
	unless (Slim::Utils::OSDetect::getOS->dontSetUserAndGroup() || (defined($user) && $> != 0)) {
		main::INFOLOG && $log->info("Server settings effective user and group if requested...");
		changeEffectiveUserAndGroup();		
	}

	# Set priority, command line overrides pref
	if (defined $priority) {
		Slim::Utils::Misc::setPriority($priority);
	} else {
		Slim::Utils::Misc::setPriority( $prefs->get('serverPriority') );
	}
	
	# Generate a UUID for this SC instance on first-run
	if ( !$prefs->get('server_uuid') ) {
		require UUID::Tiny;
		$prefs->set( server_uuid => UUID::Tiny::create_UUID_as_string( UUID::Tiny::UUID_V4() ) );
	}

	main::INFOLOG && $log->info("Server binary search path init...");
	Slim::Utils::OSDetect::getOS->initSearchPath();

	# Find plugins and process any new ones now so we can load their strings
	main::INFOLOG && $log->info("Server PluginManager init...");
	Slim::Utils::PluginManager->init();

	main::INFOLOG && $log->info("Server strings init...");
	Slim::Utils::Strings::init();
	
	# Load appropriate DB module
	my $dbModule = $sqlHelperClass =~ /MySQL/ ? 'DBD::mysql' : 'DBD::SQLite';
	Slim::bootstrap::tryModuleLoad($dbModule);
	if ( $@ ) {
		logError("Couldn't load $dbModule [$@]");
		exit;
	}

	if ( $sqlHelperClass ) {
		main::INFOLOG && $log->info("Server SQL init ($sqlHelperClass)...");
		$sqlHelperClass->init();
	}
	
	main::INFOLOG && $log->info("Async DNS init...");
	Slim::Networking::Async::DNS->init;
	
	main::INFOLOG && $log->info("Async HTTP init...");
	Slim::Networking::Async::HTTP->init;
	Slim::Networking::SimpleAsyncHTTP->init;
	
	main::INFOLOG && $log->info("SqueezeNetwork Init...");
	Slim::Networking::SqueezeNetwork->init();
	
	main::INFOLOG && $log->info("Firmware init...");
	Slim::Utils::Firmware->init;

	main::INFOLOG && $log->info("Server Info init...");
	Slim::Music::Info::init();

	main::INFOLOG && $log->info("Server IR init...");
	Slim::Hardware::IR::init();

	main::INFOLOG && $log->info("Server Request init...");
	Slim::Control::Request::init();
	
	main::INFOLOG && $log->info("Server Queries init...");
	Slim::Control::Queries->init();
	
	main::INFOLOG && $log->info("Server Buttons init...");
	Slim::Buttons::Common::init();

	if ($stdio) {
		main::INFOLOG && $log->info("Server Stdio init...");
		Slim::Control::Stdio::init(\*STDIN, \*STDOUT);
	}

	main::INFOLOG && $log->info("UDP init...");
	Slim::Networking::UDP::init();

	main::INFOLOG && $log->info("Slimproto Init...");
	Slim::Networking::Slimproto::init();

	main::INFOLOG && $log->info("Cache init...");
	Slim::Utils::Cache->init();
	Slim::Schema::RemoteTrack->init();

	unless ( $noupnp || $prefs->get('noupnp') ) {
		main::INFOLOG && $log->info("UPnP init...");
		require Slim::Utils::UPnPMediaServer;
		Slim::Utils::UPnPMediaServer::init();
	}
	
	# Load the relevant importers - necessary to ensure that Slim::Schema::init() is called.
	if (Slim::Utils::Misc::getMediaDirs()) {
		require Slim::Media::MediaFolderScan;
		Slim::Media::MediaFolderScan->init();
	}
	if (Slim::Utils::Misc::getPlaylistDir()) {
		require Slim::Music::PlaylistFolderScan;
		Slim::Music::PlaylistFolderScan->init();
	}
	initClass('Slim::Plugin::iTunes::Importer') if Slim::Utils::PluginManager->isConfiguredEnabled('iTunes');
	initClass('Slim::Plugin::MusicMagic::Importer') if Slim::Utils::PluginManager->isConfiguredEnabled('MusicMagic');

	main::INFOLOG && $log->info("Server HTTP init...");
	Slim::Web::HTTP::init();

	if (main::TRANSCODING) {
		main::INFOLOG && $log->info("Source conversion init..");
		require Slim::Player::TranscodingHelper;
		Slim::Player::TranscodingHelper::init();
	}

	if (WEBUI && !$nosetup) {
		main::INFOLOG && $log->info("Server Web Settings init...");
		require Slim::Web::Setup;
		Slim::Web::Setup::initSetup();
	}
	
	main::INFOLOG && $log->info('Menu init...');
	Slim::Menu::TrackInfo->init();
	Slim::Menu::AlbumInfo->init();
	Slim::Menu::ArtistInfo->init();
	Slim::Menu::GenreInfo->init();
	Slim::Menu::YearInfo->init();
	Slim::Menu::SystemInfo->init();
	Slim::Menu::PlaylistInfo->init();
	Slim::Menu::FolderInfo->init();
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
	
	# Reinitialize logging, as plugins may have been added.
	if (Slim::Utils::Log->needsReInit) {

		Slim::Utils::Log->reInit;
	}

	main::INFOLOG && $log->info("Server checkDataSource...");
	checkDataSource();
	
	if ( Slim::Utils::OSDetect::getOS->canAutoRescan && $prefs->get('autorescan') ) {
		require Slim::Utils::AutoRescan;
		
		main::INFOLOG && $log->info('Auto-rescan init...');
		Slim::Utils::AutoRescan->init();
	}

	main::INFOLOG && $log->info("Library Browser init...");
	Slim::Menu::BrowseLibrary->init();
	
	# regular server has a couple more initial operations.
	main::INFOLOG && $log->info("Server persist playlists...");

	if ($prefs->get('persistPlaylists')) {

		Slim::Control::Request::subscribe(
			\&Slim::Player::Playlist::modifyPlaylistCallback, [['playlist']]
		);
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

	if ( main::PERFMON ) {
		main::INFOLOG && $log->info("Server Perfwarn init...");
		require Slim::Utils::PerfMon;
		Slim::Utils::PerfMon->init($perfwarn);
	}

	Slim::Utils::Timers::setTimer(
		undef,
		time() + 30,
		\&Slim::Utils::Update::checkVersion,
	);

	main::INFOLOG && $log->info("Server HTTP enable...");
	Slim::Web::HTTP::init2();

	# otherwise, get ready to loop
	$lastlooptime = Time::HiRes::time();
	
	$inInit = 0;

	main::INFOLOG && $log->info("Server done init...");
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
			$pendingEvents = Slim::Utils::Scheduler::run_tasks();
		}
	}
	
	# Include pending AIO events or we will end up stalling AIO processing
	if ( $HAS_AIO && !$pendingEvents ) {
		$pendingEvents += IO::AIO::nreqs();
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
Usage: $0 [--diag] [--daemon] [--stdio]
          [--logdir <logpath>]
          [--logfile <logfilepath|syslog>]
          [--user <username>]
          [--group <groupname>]
          [--httpport <portnumber> [--httpaddr <listenip>]]
          [--cliport <portnumber> [--cliaddr <listenip>]]
          [--priority <priority>]
          [--prefsdir <prefspath> [--pidfile <pidfilepath>]]
          [--perfmon] [--perfwarn=<threshold> | --perfwarn <warn options>]
          [--checkstrings] [--charset <charset>]
          [--noweb] [--notranscoding] [--nosb1slimp3sync] [--nostatistics] [--norestart]
          [--noimage] [--novideo]
          [--logging <logging-spec>] [--noinfolog | --nodebuglog]
          [--localfile]

    --help           => Show this usage information.
    --cachedir       => Directory for Logitech Media Server to save cached music and web data
    --diag           => Use diagnostics, shows more verbose errors.
                        Also slows down library processing considerably
    --logdir         => Specify folder location for log file
    --logfile        => Specify a file for error logging.  Specify 'syslog' to log to syslog.
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
    --nodebuglog     => Disable all debug-level logging (compiled out).
    --noinfolog      => Disable all debug-level & info-level logging (compiled out).
    --norestart      => Disable automatic restarts of server (if performed by external script) 
    --nosetup        => Disable setup via http.
    --noserver       => Disable web access server settings, but leave player settings accessible.
                        Settings changes are not preserved.
    --noweb          => Disable web interface. JSON-RPC, Comet, and artwork web APIs are still enabled.
    --nosb1slimp3sync=> Disable support for SliMP3s, SB1s and associated synchronization
    --nostatistics   => Disable the TracksPersistent table used to keep to statistics across rescans (compiled out).
    --notranscoding  => Disable transcoding support.
    --noimage        => Disable scanning for images.
    --novideo        => Disable scanning for videos.
    --noupnp         => Disable UPnP subsystem
    --perfmon        => Enable internal server performance monitoring
    --perfwarn       => Generate log messages if internal tasks take longer than specified threshold
    --failsafe       => Don't load plugins
    --checkstrings   => Enable reloading of changed string files for plugin development
    --charset        => Force a character set to be used, eg. utf8 on Linux devices
                        which don't have full utf8 locale installed
    --dbtype         => Force database type (valid values are MySQL or SQLite)
    --logging        => Enable logging for the specified comma separated categories
    --localfile      => Enable LocalFile protocol handling for locally connected squeezelite service

Commands may be sent to the server through standard in and will be echoed via
standard out.  See complete documentation for details on the command syntax.
EOF
}

sub initOptions {
	my $logging;

	$LogTimestamp = 1;

	my $gotOptions = GetOptions(
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
		'logging=s'     => \$logging,
		'LogTimestamp!' => \$LogTimestamp,
		'cachedir=s'    => \$cachedir,
		'pidfile=s'     => \$pidfile,
		'playeraddr=s'  => \$localClientNetAddr,
		'priority=i'    => \$priority,
		'stdio'	        => \$stdio,
		'streamaddr=s'  => \$localStreamAddr,
		'prefsfile=s'   => \$prefsfile,
		# prefsdir is parsed by Slim::Utils::Prefs prior to initOptions being run
		'quiet'	        => \$quiet,
		'nodebuglog'    => \$nodebuglog,
		'noinfolog'     => \$noinfolog,
		'noimage'       => \$noimages,
		'novideo'       => \$novideo,
		'norestart'     => \$norestart,
		'nosetup'       => \$nosetup,
		'noserver'      => \$noserver,
		'nostatistics'  => \$nostatistics,
		'noupnp'        => \$noupnp,
		'nosb1slimp3sync'=> \$nosb1slimp3sync,
		'notranscoding' => \$notranscoding,
		'noweb'         => \$noweb,
		'failsafe'      => \$failsafe,
		'perfwarn=s'    => \$perfwarn,  # content parsed by PerfMon if set
		'checkstrings'  => \$checkstrings,
		'charset=s'     => \$charset,
		'dbtype=s'      => \$dbtype,
		'd_startup'     => \$d_startup, # Needed for Slim::bootstrap
	);

	# make --logging and --debug synonyms, but prefer --logging
	$debug = $logging if ($logging);

	initLogging();

	if ($help || !$gotOptions) {
		showUsage();
		exit(1);
	}
}

sub initLogging {
	# open the log files
	Slim::Utils::Log->init({
		'logconf' => $logconf,
		'logdir'  => $logdir,
		'logfile' => $logfile,
		'logtype' => 'server',
		'debug'   => $debug,
	});
}

sub initClass {
	my $class = shift;

	Slim::bootstrap::tryModuleLoad($class);

	if ($@) {
		logError("Couldn't load $class: $@");
	} else {
		$class->initPlugin;
	}
}

sub initSettings {

	Slim::Utils::Prefs::init();

	# options override existing preferences
	if (defined($cachedir)) {
		$prefs->set('cachedir', $cachedir);
		$prefs->set('librarycachedir', $cachedir);
	}
	
	if (defined($httpport)) {
		$prefs->set('httpport', $httpport);
	}

	if (defined($cliport)) {
		preferences('plugin.cli')->set('cliport', $cliport);
	}
	
	if (defined($prefs->get('cachedir')) && $prefs->get('cachedir') ne '') {

		$cachedir = $prefs->get('cachedir');
		$cachedir = Slim::Utils::Misc::fixPath($cachedir);
		$cachedir = Slim::Utils::Misc::pathFromFileURL($cachedir);
		$cachedir =~ s|[/\\]$||;
		
		# Make sure cachedir exists
		Slim::Utils::Prefs::makeCacheDir($cachedir);
		
		$prefs->set('cachedir',$cachedir);
		$prefs->set('librarycachedir',$cachedir) unless $prefs->get('librarycachedir');
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

	# Do not attempt to daemonize again.
	@argv = grep { $_ ne '--daemon' } @argv;

	# On Leopard, GD will crash because you can't run CoreServices code in a forked child,
	# so we have to exec as well.
	if ( $^O =~ /darwin/ ) {
		exec $^X . ' "' . $0 . '" ' . join( ' ', @argv );
		exit;
	}
}

sub changeEffectiveUserAndGroup {

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
	# Try starting as 'squeezeboxserver' instead.
	if (!defined($user)) {
		$user = 'squeezeboxserver';
		print STDERR "Logitech Media Server must not be run as root!  Trying user $user instead.\n";
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
		print STDERR "Logitech Media Server must not be run as root! Only do this if you know what you're doing!!\n";
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
	
	# Don't launch an initial scan on SqueezeOS, it will be handled by AutoRescan
	return if Slim::Utils::OSDetect::isSqueezeOS();
	
	# Count entries for all media types, run scan if all are empty
	my $dbh = Slim::Schema->dbh;
	my ($tc, $vc, $ic) = $dbh->selectrow_array( qq{
		SELECT
			(SELECT COUNT(*) FROM tracks where audio = 1) as tc,
			(SELECT COUNT(*) FROM videos) as vc,
			(SELECT COUNT(*) FROM images) as ic
	} );

	if (Slim::Schema->schemaUpdated || (!$tc && !$vc && !$ic)) {

		logWarning("Schema updated or no media found in the database, initiating scan.");

		Slim::Control::Request::executeRequest(undef, ['wipecache']);
	}
}

sub forceStopServer {
	$::stop = 1;
}

#------------------------------------------
#
# Clean up resources and exit.
#
# All server code must direct stop and restart requests here and should
# not attempt to manipulate or interrogate the OS specific code directly.
#
sub canRestartServer {
	return !$::norestart && Slim::Utils::OSDetect->getOS()->canRestartServer();
}

sub restartServer {

	if ( canRestartServer() ) {
		cleanup();
		logger('')->info( 'Logitech Media Server restarting...' );
		
		if ( !Slim::Utils::OSDetect->getOS()->restartServer($0, \@argv) ) {
			logger('')->error("Unable to restart Logitech Media Server");
		}
	}

	# XXX - shouldn't we ignore the restart command if we can't restart?
	else {
		logger('')->error("Unable to restart Logitech Media Server - shutting down.");
		stopServer();
	}

	exit();
}

sub stopServer {

	cleanup();

	logger('')->info( 'Logitech Media Server shutting down.' );
	
	exit();
}

sub cleanup {
	logger('')->info("Logitech Media Server cleaning up.");
	
	$::stop = 1;

	# Make sure to flush anything in the database to disk.
	if ($INC{'Slim/Schema.pm'} && Slim::Schema->storage) {

		if (Slim::Music::Import->stillScanning()) {
			logger('')->info("Cancel running scanner.");
			Slim::Music::Import->abortScan();
		}

		Slim::Schema->forceCommit;
		Slim::Schema->disconnect;
	}

	Slim::Utils::PluginManager->shutdownPlugins();

	Slim::Utils::Prefs::writeAll();

	if ($prefs->get('persistPlaylists')) {
		Slim::Control::Request::unsubscribe(
			\&Slim::Player::Playlist::modifyPlaylistCallback);
	}

	$sqlHelperClass->cleanup;

	remove_pid_file();
}

sub save_pid_file {
	my $process_id = shift || $$;

	logger('')->info("Logitech Media Server saving pid file.");

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
