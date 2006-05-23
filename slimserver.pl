#!/usr/bin/perl -w

# SlimServer Copyright (C) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

require 5.006_000;
use strict;
use warnings;
#use diagnostics;  # don't use this as it slows down regexp parsing dramatically
#use utf8;

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

use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin";
use File::Spec::Functions qw(:ALL);
use POSIX qw(:signal_h :errno_h :sys_wait_h setsid);
use Socket qw(:DEFAULT :crlf);

use lib $Bin;

BEGIN {
	use bootstrap;
	use Slim::Utils::OSDetect;

	bootstrap->loadModules();

	# Bug 2659 - maybe. Remove old versions of modules that are now in the $Bin/lib/ tree.
	unlink("$Bin/CPAN/MP3/Info.pm");
	unlink("$Bin/CPAN/DBIx/ContextualFetch.pm");
	unlink("$Bin/CPAN/XML/Simple.pm");
};

use Time::HiRes;

# Force XML::Simple to use XML::Parser for speed. This is done
# here so other packages don't have to worry about it. If we
# don't have XML::Parser installed, we fall back to PurePerl.
use XML::Simple;

eval {
	local($^W) = 0;      # Suppress warning from Expat.pm re File::Spec::load()
	require XML::Parser; 
};

if (!$@) {
	$XML::Simple::PREFERRED_PARSER = 'XML::Parser';
}

use Slim::Utils::Misc;
use Slim::Utils::PerfMon;
use Slim::Display::Animation;
use Slim::Display::Display;
use Slim::Hardware::VFD;
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
use Slim::Player::Client;
#use Slim::Control::Command;
use Slim::Control::Request;
use Slim::Display::Display;
use Slim::Display::Graphics;
use Slim::Web::HTTP;
use Slim::Hardware::IR;
use Slim::Music::Info;
use Slim::Music::Import;
use Slim::Utils::OSDetect;
use Slim::Player::Playlist;
use Slim::Player::Sync;
use Slim::Player::Source;
use Slim::Utils::Prefs;
use Slim::Networking::SliMP3::Protocol;
use Slim::Networking::Select;
use Slim::Web::Setup;
use Slim::Control::Stdio;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;
use Slim::Networking::Slimproto;
use Slim::Networking::SimpleAsyncHTTP;

use vars qw($VERSION $REVISION @AUTHORS);

@AUTHORS = (
	'Sean Adams',
	'Vidur Apparao',
	'Dean Blackketter',
	'Kevin Deane-Freeman',
	'Amos Hayes',
	'Mark Langston',
	'Eric Lyons',
	'Scott McIntyre',
	'Robert Moser',
	'Dave Nanian',
	'Jacob Potter',
	'Sam Saffron',
	'Roy M. Silvernail',
	'Richard Smith',
	'Max Spicer',
	'Dan Sully',
);

$VERSION  = '6.5b1';

# old preferences settings, only used by the .slim.conf configuration.
# real settings are stored in the new preferences file:  .slim.pref
our ($audiodir, $playlistdir, $httpport);

our (
	$d_artwork,
	$d_cli,
	$d_client,
	$d_control,
	$d_command,
	$d_datamodel,
	$d_directstream,
	$d_display,
	$d_factorytest,
	$d_favorites,
	$d_files,
	$d_firmware,
	$d_formats,
	$d_graphics,
	$d_http,
	$d_http_async,
	$d_http_verbose,
	$d_info,
	$d_ir,
	$d_irtm,
	$d_itunes,
	$d_itunes_verbose,
	$d_import,
	$d_mdns,
	$d_memory,
	$d_moodlogic,
	$d_mp3,
	$d_musicmagic,
	$d_os,
	$d_parse,
	$d_paths,
	$d_playlist,
	$d_plugins,
	$d_protocol,
	$d_prefs,
	$d_remotestream,
	$d_scan,
	$d_server,
	$d_select,
	$d_slimproto,
	$d_slimproto_v,
	$d_source,
	$d_source_v,
	$d_sql,
	$d_stdio,
	$d_stream,
	$d_stream_v,
	$d_sync,
	$d_sync_v,
	$d_time,
	$d_ui,
	$d_usage,

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
	$localClientNetAddr,
	$localStreamAddr,
	$newVersion,
	$LogTimestamp,
	$pidfile,
	$prefsfile,
	$priority,
	$quiet,
	$nosetup,
	$noserver,
	$stdio,
	$stop,
	$perfmon,
);

sub init {

	# initialize the process and daemonize, etc...
	srand();

	autoflush STDERR;
	autoflush STDOUT;

	my $revision = catdir($Bin, 'revision.txt');

	# The revision file may not exist for svn copies.
	if (-e $revision) {

		open(REV, $revision);
		chomp($REVISION = <REV>);
		close(REV);

	} else {

		$REVISION = 'trunk';

	}

	if ($diag) { 
		eval "use diagnostics";
	}

	$::d_server && msg("SlimServer OSDetect init...\n");
	Slim::Utils::OSDetect::init();

	$::d_server && msg("SlimServer OS Specific init...\n");

	$SIG{CHLD} = 'IGNORE';
	$SIG{PIPE} = 'IGNORE';
	$SIG{TERM} = \&sigterm;
	$SIG{INT}  = \&sigint;

	if (Slim::Utils::OSDetect::OS() ne 'win') {
		$SIG{HUP} = \&initSettings;
	}		

	if (defined(&PerlSvc::RunningAsService) && PerlSvc::RunningAsService()) {
		$SIG{QUIT} = \&ignoresigquit; 
	} else {
		$SIG{QUIT} = \&sigquit;
	}

	$SIG{__WARN__} = sub { msg($_[0]) };
	
	# Uncomment to enable crash debugging.
	#$SIG{__DIE__} = \&Slim::Utils::Misc::bt;

	# background if requested
	if (Slim::Utils::OSDetect::OS() ne 'win' && $daemon) {

		$::d_server && msg("SlimServer daemonizing...\n");
		daemonize();

	} else {

		save_pid_file();

		if (defined $logfile) {

			my $logfilename = $logfile;

			if (substr($logfile, 0, 1) ne "|") {
				$logfilename = ">>" . $logfile;
			}

			if ($stdio) {

				open(STDERR, $logfilename) || die "Can't write to $logfilename: $!";

			} else {

				open(STDOUT, $logfilename) || die "Can't write to $logfilename: $!";
				open(STDERR, '>&STDOUT')   || die "Can't dup stdout: $!";
			}
		}
	};

	# Change UID/GID after the pid & logfiles have been opened.
	$::d_server && msg("SlimServer settings effective user and group if requested...\n");
	changeEffectiveUserAndGroup();

	Slim::Utils::Misc::setPriority($priority);

	# do platform specific environment setup
	# we have some special directories under OSX.
	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		mkdir $ENV{'HOME'} . "/Library/SlimDevices";
		mkdir $ENV{'HOME'} . "/Library/SlimDevices/Plugins";
		mkdir $ENV{'HOME'} . "/Library/SlimDevices/Graphics";
		mkdir $ENV{'HOME'} . "/Library/SlimDevices/html";
		mkdir $ENV{'HOME'} . "/Library/SlimDevices/IR";
		mkdir $ENV{'HOME'} . "/Library/SlimDevices/bin";
		
		unshift @INC, $ENV{'HOME'} . "/Library/SlimDevices";
		unshift @INC, "/Library/SlimDevices/";
	}

	# initialize slimserver subsystems
	$::d_server && msg("SlimServer settings init...\n");
	initSettings();

	$::d_server && msg("SlimServer strings init...\n");
	Slim::Utils::Strings::init(catdir($Bin,'strings.txt'), "EN");

	$::d_server && msg("SlimServer Setup init...\n");
	Slim::Web::Setup::initSetup();

	# initialize all player UI subsystems
	$::d_server && msg("SlimServer setting language...\n");
	Slim::Utils::Strings::setLanguage(Slim::Utils::Prefs::get("language"));

	$::d_server && msg("SlimServer IR init...\n");
	Slim::Hardware::IR::init();
		
	$::d_server && msg("SlimServer Request init...\n");
	Slim::Control::Request::init();
	
	$::d_server && msg("SlimServer IR init...\n");
	Slim::Hardware::IR::init();
	
	$::d_server && msg("SlimServer Buttons init...\n");
	Slim::Buttons::Common::init();

	$::d_server && msg("SlimServer Graphics init...\n");
	Slim::Display::Graphics::init();

	if ($stdio) {
		$::d_server && msg("SlimServer Stdio init...\n");
		Slim::Control::Stdio::init(\*STDIN, \*STDOUT);
	}

	$::d_server && msg("Old SLIMP3 Protocol init...\n");
	Slim::Networking::SliMP3::Protocol::init();

	$::d_server && msg("Slimproto Init...\n");
	Slim::Networking::Slimproto::init();

	$::d_server && msg("mDNS init...\n");
	Slim::Networking::mDNS->init;

	$::d_server && msg("SlimServer HTTP init...\n");
	Slim::Web::HTTP::init();

	$::d_server && msg("mDNS startAdvertising...\n");
	Slim::Networking::mDNS->startAdvertising;

	$::d_server && msg("Source conversion init..\n");
	Slim::Player::Source::init();

	$::d_server && msg("SlimServer Info init...\n");
	Slim::Music::Info::init();

	$::d_server && msg("SlimServer Plugins init...\n");
	Slim::Utils::PluginManager::init();

	$::d_server && msg("SlimServer checkDataSource...\n");
	checkDataSource();

	# regular server has a couple more initial operations.
	$::d_server && msg("SlimServer persist playlists...\n");

	if (Slim::Utils::Prefs::get('persistPlaylists')) {

		Slim::Control::Request::subscribe(
			\&Slim::Player::Playlist::modifyPlaylistCallback, 
			[['playlist']]
		);
	}

	checkVersion();

	# otherwise, get ready to loop
	$lastlooptime = Time::HiRes::time();
			
	$::d_server && msg("SlimServer done init...\n");
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
		$::d_time && msg("finished adjustalltimers: " . Time::HiRes::time() . "\n");
	} 

	$lastlooptime = $now;

	my $select_time = 0; # default to not waiting in select

	# empty IR queue
	if (!Slim::Hardware::IR::idle()) {

	# undefined if there are no timers, 0 if overdue, otherwise delta to next timer
	$select_time = Slim::Utils::Timers::nextTimer();
	
	# loop through once a second, at a minimum
	if (!defined($select_time) || $select_time > 1) { $select_time = 1 };

		# handle notifications once IR queue is empty
		Slim::Control::Request::checkNotifications();

		# set timeout to wait in select based on when next timer is due, or once per second
		$select_time = Slim::Utils::Timers::nextTimer();

		if (!defined($select_time) || $select_time > 1) {
			$select_time = 1
		}

		$::d_time && msg("select_time: $select_time\n");
	}

	# call select and process any IO
	Slim::Networking::Select::select($select_time);

	# check the timers for any new tasks
	Slim::Utils::Timers::checkTimers();	

	return $::stop;
}

sub idleStreams {
	my $timeout = shift || 0;
	my $streamOnly = shift; # set for select to only check streaming sockets

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

	$::d_time && msg("idleStreams: select_time: $select_time, checkTimers: $check_timers\n");

	Slim::Networking::Select::select($select_time, $streamOnly);

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
                        no effect on non-Unix platforms
    --streamaddr     => Specify the _server's_ IP address to use to connect
                        to streaming audio sources
    --nosetup        => Disable setup via http.
    --noserver       => Disable web access server settings, but leave player settings accessible. Settings changes arenot preserved.
    --perfmon        => Enable internal server performance monitoring
    --perfwarn       => Generate log messages if internal tasks take longer than specified threshold

The following are debugging flags which will print various information 
to the console via stderr:

    --d_artwork      => Display information on artwork display
    --d_cli          => Display debugging information for the 
                        command line interface interface
    --d_client       => Display per-client debugging.
    --d_command      => Display internal command execution
    --d_control      => Low level player control information
    --d_datamodel    => Data model search and field mapping debugging
    --d_directstream => Debugging info on direct streaming 
    --d_display      => Show what (should be) on the player's display 
    --d_factorytest  => Information used during factory testing
    --d_favorites    => Information about favorite tracks
    --d_files        => Files, paths, opening and closing
    --d_firmware     => Information during Squeezebox firmware updates 
    --d_formats      => Information about importing data from various file formats
    --d_graphics     => Information bitmap graphic display 
    --d_http         => HTTP activity
    --d_http_async   => AsyncHTTP activity
    --d_http_verbose => Even more HTTP activity 
    --d_info         => MP3/ID3 track information
    --d_import       => Information on external data import
    --d_ir           => Infrared activity
    --d_irtm         => Infrared activity diagnostics
    --d_itunes       => iTunes synchronization information
    --d_itunes_verbose => verbose iTunes Synchronization information
    --d_mdns         => Multicast DNS aka Zeroconf aka Rendezvous information
    --d_memory       => Turns on memory debugging interface - developers only.
    --d_moodlogic    => MoodLogic synchronization information
    --d_musicmagic   => MusicMagic synchronization information
    --d_mp3          => MP3 frame detection
    --d_os           => Operating system detection information
    --d_paths        => File path processing information
    --d_parse        => Playlist parsing information
    --d_playlist     => High level playlist and control information
    --d_plugins      => Show information about plugins
    --d_protocol     => Client protocol information
    --d_prefs        => Preferences file information
    --d_remotestream => Information about remote HTTP streams and playlists
    --d_scan         => Information about scanning directories and filelists
    --d_select       => Information about the select process
    --d_server       => Basic server functionality
    --d_slimproto    => Slimproto debugging information
    --d_slimproto_v  => Slimproto verbose debugging information
    --d_source       => Information about source audio files and conversion
    --d_source_v     => Verbose information about source audio files
    --d_sql          => Verbose SQL debugging
    --d_stdio        => Standard I/O command debugging
    --d_startup      => Startup/Bootstrap debugging for \@INC
    --d_stream       => Information about player streaming protocol 
    --d_stream_v     => Verbose information about player streaming protocol 
    --d_sync         => Information about multi player synchronization
    --d_sync_v       => Verbose information about multi player synchronization
    --d_time         => Internal timer information
    --d_ui           => Player user interface information
    --d_usage        => Display buffer usage codes on the player's display
    
Commands may be sent to the server through standard in and will be echoed via
standard out.  See complete documentation for details on the command syntax.
EOF
}

sub initOptions {
    $LogTimestamp=1;
	if (!GetOptions(
		'user=s'			=> \$user,
		'group=s'			=> \$group,
		'cliaddr=s'			=> \$cliaddr,
		'cliport=s'			=> \$cliport,
		'daemon'			=> \$daemon,
		'diag'				=> \$diag,
		'httpaddr=s'		=> \$httpaddr,
		'httpport=s'		=> \$httpport,
		'logfile=s'			=> \$logfile,
		'LogTimestamp!'	        => \$LogTimestamp,
		'audiodir=s'		=> \$audiodir,
		'playlistdir=s'		=> \$playlistdir,
		'cachedir=s'		=> \$cachedir,
		'pidfile=s'			=> \$pidfile,
		'playeraddr=s'		=> \$localClientNetAddr,
		'priority=i'		=> \$priority,
		'stdio'				=> \$stdio,
		'streamaddr=s'		=> \$localStreamAddr,
		'prefsfile=s'		=> \$prefsfile,
		'quiet'				=> \$quiet,
		'nosetup'			=> \$nosetup,
		'noserver'			=> \$noserver,
		'd_artwork'			=> \$d_artwork,
		'd_cli'				=> \$d_cli,
		'd_client'			=> \$d_client,
		'd_command'			=> \$d_command,
		'd_control'			=> \$d_control,
		'd_datamodel'		=> \$d_datamodel,
		'd_directstream'	=> \$d_directstream,
		'd_display'			=> \$d_display,
		'd_factorytest'		=> \$d_factorytest,
		'd_favorites'		=> \$d_favorites,
		'd_files'			=> \$d_files,
		'd_firmware'		=> \$d_firmware,
		'd_formats'			=> \$d_formats,
		'd_graphics'		=> \$d_graphics,
		'd_http'			=> \$d_http,
		'd_http_async'		=> \$d_http_async,
		'd_http_verbose'	=> \$d_http_verbose,
		'd_info'			=> \$d_info,
		'd_import'			=> \$d_import,
		'd_ir'				=> \$d_ir,
		'd_irtm'			=> \$d_irtm,
		'd_itunes'			=> \$d_itunes,
		'd_itunes_verbose'	=> \$d_itunes_verbose,
		'd_mdns'			=> \$d_mdns,
		'd_memory'			=> \$d_memory,
		'd_moodlogic'		=> \$d_moodlogic,
		'd_mp3'				=> \$d_mp3,
		'd_musicmagic'		=> \$d_musicmagic,
		'd_os'				=> \$d_os,
		'd_paths'			=> \$d_paths,
		'd_parse'			=> \$d_parse,
		'd_playlist'		=> \$d_playlist,
		'd_plugins'			=> \$d_plugins,
		'd_protocol'		=> \$d_protocol,
		'd_prefs'			=> \$d_prefs,
		'd_remotestream'	=> \$d_remotestream,
		'd_scan'			=> \$d_scan,
		'd_select'			=> \$d_select,
		'd_server'			=> \$d_server,
		'd_slimproto'		=> \$d_slimproto,
		'd_slimproto_v'		=> \$d_slimproto_v,
		'd_source'			=> \$d_source,
		'd_source_v'		=> \$d_source_v,
		'd_sql'				=> \$d_sql,
		'd_stdio'			=> \$d_stdio,
		'd_startup'			=> \$d_startup,
		'd_stream'			=> \$d_stream,
		'd_stream_v'		=> \$d_stream_v,
		'd_sync'			=> \$d_sync,
		'd_sync_v'			=> \$d_sync_v,
		'd_time'			=> \$d_time,
		'd_ui'				=> \$d_ui,
		'd_usage'			=> \$d_usage,
		'perfmon'		=> \$perfmon,
	)) {
		showUsage();
		exit(1);
	};

	if ($perfwarn) {
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

	# make sure we are using the actual case of the directories
	# and that they do not end in / or \

	if (defined(Slim::Utils::Prefs::get("playlistdir")) && Slim::Utils::Prefs::get("playlistdir") ne '') {

		$playlistdir = Slim::Utils::Prefs::get("playlistdir");
		$playlistdir =~ s|[/\\]$||;

		$playlistdir = Slim::Utils::Misc::fixPath($playlistdir);
		$playlistdir = Slim::Utils::Misc::pathFromFileURL($playlistdir);

		Slim::Utils::Prefs::set("playlistdir",$playlistdir);
	}

	if (defined(Slim::Utils::Prefs::get("audiodir")) && Slim::Utils::Prefs::get("audiodir") ne '') {

		$audiodir = Slim::Utils::Prefs::get("audiodir");
		$audiodir =~ s|[/\\]$||;

		$audiodir = Slim::Utils::Misc::fixPath($audiodir);
		$audiodir = Slim::Utils::Misc::pathFromFileURL($audiodir);

		Slim::Utils::Prefs::set("audiodir",$audiodir);
	}
	
	if (defined(Slim::Utils::Prefs::get("cachedir")) && Slim::Utils::Prefs::get("cachedir") ne '') {

		$cachedir = Slim::Utils::Prefs::get("cachedir");
		$cachedir =~ s|[/\\]$||;

		$cachedir = Slim::Utils::Misc::fixPath($cachedir);
		$cachedir = Slim::Utils::Misc::pathFromFileURL($cachedir);

		Slim::Utils::Prefs::set("cachedir",$cachedir);
	}

	Slim::Utils::Prefs::makeCacheDir();	
}

sub daemonize {
	my ($pid, $log, $logfilename);
	
	if (!defined($pid = fork)) { die "Can't fork: $!"; }
	
	if ($pid) {
		save_pid_file($pid);
		# don't clean up the pidfile!
		$pidfile = undef;
		exit;
	}

	$log = $logfile ? $logfile : '/dev/null';

	open(STDIN, '/dev/null') || die "Can't read /dev/null: $!";

	# check for log file being pipe, e.g. multilog
	$logfilename = $log;

	if (substr($log, 0, 1) ne "|") {
		$logfilename = ">>" . $log;
	}

	open(STDOUT, $logfilename) || die "Can't write to $logfilename: $!";

	# Bug: 1625 - There appears to be a bad interaction with the iTunes
	# Update plugin / Mac::Applescript::Glue , and setting the process
	# name after we fork. So don't do it on Mac. The System Preferences
	# start/stop still works.
	#
        # Also don't do it for *nix - as startup scripts have problems (FC5)
        # when our process name gets changed.
	if (Slim::Utils::OSDetect::OS() eq 'win') {
		$0 = "slimserver";
	}

	if (!setsid) { die "Can't start a new session: $!"; }
	if (!open STDERR, '>&STDOUT') { die "Can't dup stdout: $!"; }
}

sub changeEffectiveUserAndGroup {

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
	# warn if there's no audiodir preference
	# FIXME put the strings in strings.txt
	if (!(defined Slim::Utils::Prefs::get("audiodir") && 
		-d Slim::Utils::Prefs::get("audiodir")) && !$quiet && !Slim::Music::Import->countImporters()) {

		msg("Your data source needs to be configured. Please open your web browser,\n");
		msg("go to the following URL, and click on the \"Server Settings\" link.\n\n");
		msg(string('SETUP_URL_WILL_BE') . "\n\t" . Slim::Utils::Prefs::homeURL() . "\n");

	} else {

		if (defined(Slim::Utils::Prefs::get("audiodir")) && Slim::Utils::Prefs::get("audiodir") =~ m|[/\\]$|) {
			$audiodir = Slim::Utils::Prefs::get("audiodir");
			$audiodir =~ s|[/\\]$||;
			Slim::Utils::Prefs::set("audiodir",$audiodir);
		}
		my $ds = Slim::Music::Info::getCurrentDataStore();

		if ($ds->count('track') == 0) {

			# Let's go through Command rather than calling
			# Slim::Music::Import::startScan() directly...
			#Slim::Control::Request::executeRequest(undef, ['rescan']);
		}
	}
}

sub checkVersion {
	unless (Slim::Utils::Prefs::get("checkVersion")) {
		$::newVersion = undef;
		return;
	}

	my $lastTime = Slim::Utils::Prefs::get('checkVersionLastTime');

	if ($lastTime) {
		my $delta = Time::HiRes::time() - $lastTime;
		if (($delta > 0) && ($delta < Slim::Utils::Prefs::get('checkVersionInterval'))) {

			$::d_time && msgf("checking version in %s seconds\n",
				($lastTime + Slim::Utils::Prefs::get('checkVersionInterval') + 2 - Time::HiRes::time())
			);

			Slim::Utils::Timers::setTimer(0, $lastTime + Slim::Utils::Prefs::get('checkVersionInterval') + 2, \&checkVersion);
			return;
		}
	}

	$::d_time && msg("checking version now.\n");
	my $url  = "http://update.slimdevices.com/update/?version=$VERSION&lang=" . Slim::Utils::Strings::getLanguage();

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&checkVersionCB, \&checkVersionError);
	$http->get($url); # will call checkVersionCB when complete

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
		# msg("CheckVersionCB: '" . $::newVersion . "' (Error code $http->{code})\n"); # temp
	}
	else {
		$::newVersion = 0;
		msg(sprintf(Slim::Utils::Strings::string('CHECKVERSION_PROBLEM'), $http->{code}) . "\n");
	}
}

# called only if check version request fails
sub checkVersionError {
	my $http = shift;
	msg(Slim::Utils::Strings::string('CHECKVERSION_ERROR') . "\n" . $http->error . "\n");
}

sub forceStopServer {
	$::stop = 1;
}

#------------------------------------------
#
# Clean up resources and exit.
#
sub stopServer {
	$::d_server && msg("SlimServer shutting down.\n");
	cleanup();
	exit();
}

sub sigint {
	$::d_server && msg("Got sigint.\n");
	cleanup();
	exit();
}

sub sigterm {
	$::d_server && msg("Got sigterm.\n");
	cleanup();
	exit();
}

sub ignoresigquit {
	$::d_server && msg("Ignoring sigquit.\n");
}

sub sigquit {
	$::d_server && msg("Got sigquit.\n");
	cleanup();
	exit();
}

sub cleanup {

	$::d_server && msg("SlimServer cleaning up.\n");

	# Make sure to flush anything in the database to disk.
	my $ds = Slim::Music::Info::getCurrentDataStore();

	if ($ds) {
		$ds->forceCommit;
	}

	Slim::Utils::Prefs::writePrefs() if Slim::Utils::Prefs::writePending();
	Slim::Networking::mDNS->stopAdvertising;
	Slim::Utils::PluginManager::shutdownPlugins();

	if (Slim::Utils::Prefs::get('persistPlaylists')) {
		Slim::Control::Request::unsubscribe(
			\&Slim::Player::Playlist::modifyPlaylistCallback);
	}

	remove_pid_file();
}

sub save_pid_file {
	my $process_id = shift || $$;

	$::d_server && msg("SlimServer saving pid file.\n");

	return unless defined $pidfile;

	open PIDFILE, ">$pidfile" or die "Couldn't open pidfile: [$pidfile] for writing!: $!";
	print PIDFILE "$process_id\n";
	close PIDFILE;
}
 
sub remove_pid_file {
	 if (defined $pidfile) {
	 	unlink $pidfile;
	 }
}
 
sub END {
	$::d_server && msg("Got to the END.\n");
	sigint();
}

# start up the server if we're not running as a service.	
if (!defined($PerlSvc::VERSION)) { 
	main()
};

__END__
