#!/usr/bin/perl -w

# Slim Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
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
use strict;  # _NOPERL2EXE_
#use diagnostics;  # don't use this as it slows down regexp parsing dramatically
#use utf8;

# This package section is used for the windows service version of the application, 
# as built with ActiveState's PerlSvc

package PerlSvc;

our $Name = 'slimsvc';
our $DisplayName = 'Slim Server';

sub Startup {

	# added to workaround a problem with 5.8 and perlsvc.
    $SIG{BREAK} = sub {} if RunningAsService();

	main::init();
	
	main::start();
	
   # here's where your startup code will go
    while (ContinueRun() && !main::idle()) {
    }
}

sub Install {
    # add your additional install messages or functions here
}

sub Remove {
    # add your additional remove messages or functions here
}

sub Help {
    # add your additional help messages or functions here
    $DisplayName . $Name;
}

package main;

BEGIN {   
	if ($^O =~ /Win32/) {   
		if ($] < 5.008) {   
			#add numbers not supplied in Errno prior to 5.8   
			*Errno::EWOULDBLOCK = sub () { 10035 };   
			*Errno::EINPROGRESS = sub () { 10036 };   
			push @Errno::EXPORT_OK, qw(EWOULDBLOCK EINPROGRESS);   
		}   
		#provide non-blocking support for Windows   
		*IO::Socket::blocking = sub {   
			my ($self, $blocking) = @_;   
			my $nonblocking = $blocking ? "0" : "1";   
			my $retval = ioctl($self, 0x8004667e, \$nonblocking);   
			if (!defined($retval) && $] >= 5.008) {   
				$retval = "0 but true";   
			}   
			return $retval;   
		};   
		# suppress "variable only used once" warning:
		*IO::Socket::blocking = *IO::Socket::blocking;
	}   
} 


use Config;
use Getopt::Long;
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
use FileHandle;
use POSIX qw(:signal_h :errno_h :sys_wait_h);
use Socket qw(:DEFAULT :crlf);

use lib (@INC, $Bin, catdir($Bin,'CPAN'), catdir($Bin,'CPAN','arch',$Config::Config{archname}) );
use Time::HiRes;

use Slim::Utils::Misc;

use Slim::Display::Animation;
use Slim::Buttons::Browse;
use Slim::Buttons::BrowseMenu;
use Slim::Buttons::Home;
use Slim::Buttons::Power;
use Slim::Buttons::ScreenSaver;
use Slim::Buttons::MoodWheel;
use Slim::Buttons::InstantMix;
use Slim::Player::Client;
use Slim::Control::Command;
use Slim::Control::CLI;
use Slim::Networking::Discovery;
use Slim::Display::Display;
use Slim::Web::HTTP;
use Slim::Hardware::IR;
use Slim::Music::Info;
use Slim::Music::iTunes;
use Slim::Music::MusicFolderScan;
use Slim::Utils::OSDetect;
use Slim::Player::Playlist;
use Slim::Player::Sync;
use Slim::Player::Source;
use Slim::Utils::Prefs;
use Slim::Networking::Protocol;
use Slim::Networking::Select;
use Slim::Utils::Scheduler;
use Slim::Web::Setup;
use Slim::Control::Stdio;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;
use Slim::Music::MoodLogic;
use Slim::Networking::Slimproto;

use vars qw($VERSION
		@AUTHORS);

@AUTHORS = (
	'Sean Adams',
	'Dean Blackketter',
	'Kevin Deane-Freeman',
	'Amos Hayes',
	'Mark Langston',
	'Eric Lyons',
	'Scott McIntyre',
	'Robert Moser',
	'Richard Smith',
	'Sam Saffron',
	'Daniel Sully',
);

$VERSION = '5.0';

# old preferences settings, only used by the .slim.conf configuration.
# real settings are stored in the new preferences file:  .slim.pref
use vars qw(
	    $mp3dir
	    $httpport
);

use vars qw(
		$d_cli
		$d_control
		$d_command
		$d_display
		$d_factorytest
		$d_files
		$d_http
		$d_info
		$d_ir
		$d_itunes
		$d_moodlogic
		$d_mdns
		$d_os
		$d_perf
		$d_parse
		$d_paths
		$d_playlist
		$d_plugins
		$d_protocol
		$d_prefs
		$d_remotestream
		$d_scan
		$d_server
		$d_select
		$d_scheduler
		$d_slimproto
		$d_slimproto_v
		$d_source
		$d_stdio
		$d_stream
		$d_stream_v
		$d_sync
		$d_time
		$d_ui
		$d_usage

	    $user
	    $group
	    $cliaddr
	    $cliport
	    $daemon
	    $httpaddr
	    $lastlooptime
	    $logfile
	    $loopcount
	    $loopsecond
	    $localClientNetAddr
	    $localStreamAddr
        $newVersion
	    $pidfile
	    $prefsfile
	    $priority
	    $quiet
	    $nosetup
	    $stdio
	    $stop
	);

sub init {
	srand();

	autoflush STDERR;
	autoflush STDOUT;

	$::d_server && msg("Slim Server OSDetect init...\n");
	Slim::Utils::OSDetect::init();

	$::d_server && msg("Slim Server Strings init...\n");
	Slim::Utils::Strings::init(catdir($Bin,'strings.txt'), "EN");


	$::d_server && msg("Slim Server OS Specific init...\n");
	$SIG{CHLD} = 'IGNORE';
	$SIG{PIPE} = 'IGNORE';
	if (Slim::Utils::OSDetect::OS() ne 'win') {
		$SIG{INT} = \&sigint;
		$SIG{HUP} = \&initSettings;
	}		
	$SIG{TERM} = \&sigint;
	$SIG{QUIT} = \&sigint;
	
	# we have some special directories under OSX.
	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		mkdir $ENV{'HOME'} . "/Library/SlimDevices";
		mkdir $ENV{'HOME'} . "/Library/SlimDevices/Plugins";
		mkdir $ENV{'HOME'} . "/Library/SlimDevices/html";
		mkdir $ENV{'HOME'} . "/Library/SlimDevices/IR";
		mkdir $ENV{'HOME'} . "/Library/SlimDevices/bin";
		
		unshift @INC, $ENV{'HOME'} . "/Library/SlimDevices";
		unshift @INC, "/Library/SlimDevices/";
	}
	
	unshift @INC, catdir($Bin,'CPAN','arch',$Config::Config{archname});
	
	$::d_server && msg("Slim Server settings init...\n");
	initSettings();

	$::d_server && msg("Slim Server setting language...\n");
	Slim::Utils::Strings::setLanguage(Slim::Utils::Prefs::get("language"));

	$::d_server && msg("Slim Server IR init...\n");
	Slim::Hardware::IR::init();
	
	$::d_server && msg("Slim Server Buttons init...\n");
	Slim::Buttons::Common::init();

	if ($priority) {
		$::d_server && msg("Slim Server - changing process priority to $priority\n");
		eval { setpriority (0, 0, $priority); };
		msg("setpriority failed error: $@\n") if $@;
	}
}

sub start {

	$::d_server && msg("Slim Server starting up...\n");

	$::d_server && msg("Slim Server daemonizing...\n");
	# background if requested
	if (Slim::Utils::OSDetect::OS() ne 'win' && $daemon) {
		daemonize();
	} else {
		save_pid_file();
		
		if (defined $logfile) {
			if ($stdio) {
				if (!open STDERR, ">>$logfile") { die "Can't write to $logfile: $!";}
			} else {
				if (!open STDOUT, ">>$logfile") { die "Can't write to $logfile: $!";}
				if (!open STDERR, '>&STDOUT') { die "Can't dup stdout: $!"; }
			}
		}
	};
	
	$::d_server && msg("Slim Server Stdio init...\n");
	if ($stdio) {
		Slim::Control::Stdio::init(\*STDIN, \*STDOUT);
	}

	$::d_server && msg("Old SLIMP3 Protocol init...\n");
	Slim::Networking::Protocol::init();
	$::d_server && msg("Slimproto Init...\n");
	Slim::Networking::Slimproto::init();
	$::d_server && msg("Slim Server Info init...\n");
	Slim::Music::Info::init();
	$::d_server && msg("Slim Server HTTP init...\n");
	Slim::Web::HTTP::init();
	$::d_server && msg("Slim Server CLI init...\n");
	Slim::Control::CLI::init();
	$::d_server && msg("Slim Server History load...\n");
	Slim::Web::History::load();
	$::d_server && msg("Source conversion init..\n");
	Slim::Player::Source::init();
	
	$::d_server && msg("Slim Server persist playlists...\n");
	if (Slim::Utils::Prefs::get('persistPlaylists')) {
		Slim::Control::Command::setExecuteCallback(\&Slim::Player::Playlist::modifyPlaylistCallback);
	}
	
	$::d_server && msg("Slim Server iTunes init...\n");

# start scanning based on a timer...
# Currently, it's set to one item (directory or song) scanned per second.
	if (Slim::Music::iTunes::useiTunesLibrary()) {
		Slim::Music::iTunes::startScan();
	} elsif (Slim::Music::MoodLogic::useMoodLogic()) {
		Slim::Music::MoodLogic::startScan();
	} else {
		Slim::Music::MusicFolderScan::startScan(1);
	}
	
	$lastlooptime = Time::HiRes::time();
	$loopcount = 0;
	$loopsecond = int($lastlooptime);
	
	checkVersion();
	
	$::d_server && msg("Slim Server done start...\n");
}

sub main {
	initOptions();

	init();
	start();
	
	while (!idle()) {}
	
	stopServer();
}

sub idle {

	my $select_time;

	my $now = Time::HiRes::time();
	my $to;

	if ($::d_perf) {
		if (int($now) == $loopsecond) {
			$loopcount++;
		} else {
			msg("Idle loop speed: $loopcount iterations per second\n");
			$loopcount = 0;
			$loopsecond = int($now);
		}
		$to = watchDog();
	}
	
	# check for time travel (i.e. If time skips backwards for DST or clock drift adjustments)
	if ($now < $lastlooptime) {
		Slim::Utils::Timers::adjustAllTimers($now - $lastlooptime);
		$::d_time && msg("finished adjustalltimers: " . Time::HiRes::time() . "\n");
	} 
	$lastlooptime = $now;

	# check the timers for any new tasks		
	Slim::Utils::Timers::checkTimers();	
	if ($::d_perf) { $to = watchDog($to, "checkTimers"); }

	# handle client protocol activity
	Slim::Networking::Protocol::idle();
	if ($::d_perf) { $to = watchDog($to, "Protocol::idle"); }

	Slim::Networking::Slimproto::idle();
	if ($::d_perf) { $to = watchDog($to, "Slimproto::idle"); }
	
	# handle queued IR activity
	Slim::Hardware::IR::idle();
	if ($::d_perf) { $to = watchDog($to, "IR::idle"); }
	
	# check the timers for any new tasks		
	Slim::Utils::Timers::checkTimers();	
	if ($::d_perf) { $to = watchDog($to, "checkTimers"); }

	my $tasks = Slim::Utils::Scheduler::run_tasks();
	if ($::d_perf) { $to = watchDog($to, "run_tasks"); } 
	
	# if background tasks are running, don't wait in select.
	if (!$tasks) {
		# undefined if there are no timers, 0 if overdue, otherwise delta to next timer
		$select_time = Slim::Utils::Timers::nextTimer();
		
		# loop through once a second, at a minimum
		if (!defined($select_time) || $select_time > 1) { $select_time = 1 };
		
		$::d_time && msg("select_time: ". (defined($select_time) ? $select_time : "UNDEF")."\n");

		Slim::Networking::Select::select($select_time);
	}
	
	# handle HTTP and command line interface activity, including:
	#   opening sockets, 
	#   reopening sockets if the port has changed, 
	#   and handling HTTP traffic
	Slim::Web::HTTP::idle();
	
	if ($::d_perf) { $to = watchDog($to, "http::idle"); }

	Slim::Control::CLI::idle();
	if ($::d_perf) { $to = watchDog($to, "cli::idle"); }

	return $::stop;
}

sub idleStreams {
	Slim::Networking::Select::select(0);
}

sub showUsage {
	print <<EOF;
Usage: $0 [--mp3dir <dir>] [--daemon] [--stdio] [--logfile <logfilepath>]
          [--user <username>]
          [--group <groupname>]
          [--httpport <portnumber> [--httpaddr <listenip>]]
          [--cliport <portnumber> [--cliaddr <listenip>]]
          [--priority <priority>]
          [--prefsfile <prefsfilepath> [--pidfile <pidfilepath>]]
          [--d_various]

    --help           => Show this usage information.
    --mp3dir         => The path to a directory of your MP3 files.
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
    --prefsfile      => Specify where the preferences file should be stored
    --pidfile        => Specify where a process ID file should be stored
    --quiet          => Minimize the amount of text output
    --playeraddr     => Specify the _server's_ IP address to use to connect 
                        to Slim players
    --priority       => set process priority from -20 (high) to 20 (low)
                        no effect on non-Unix platforms
    --streamaddr     => Specify the _server's_ IP address to use to connect
                        to streaming audio sources
    --nosetup        => Disable setup via http.

The following are debugging flags which will print various information 
to the console via stderr:

    --d_cli          => Display debugging information for the 
                        command line interface interface
    --d_command      => Display internal command execution
    --d_control      => Low level player control information
    --d_display      => Show what (should be) on the player's display 
    --d_factorytest  => Information used during factory testing
    --d_files        => Files, paths, opening and closing
    --d_http         => HTTP activity
    --d_info         => MP3/ID3 track information
    --d_ir           => Infrared activity
    --d_itunes       => iTunes synchronization information
    --d_moodlogic    => MoodLogic synchronization information
    --d_mdns         => Multicast DNS aka Zeroconf aka Rendezvous information
    --d_os           => Operating system detection information
    --d_paths        => File path processing information
    --d_perf         => Performance information
    --d_parse        => Playlist parsing information
    --d_playlist     => High level playlist and control information
    --d_plugins      => Show information about plugins
    --d_protocol     => Client protocol information
    --d_prefs        => Preferences file information
    --d_remotestream => Information about remote HTTP streams and playlists
    --d_scan         => Information about scanning directories and filelists
	--d_select		 => Information about the select process
    --d_server       => Basic server functionality
    --d_scheduler    => Internal scheduler information
    --d_slimproto    => Slimproto debugging information
    --d_slimproto_v  => Slimproto verbose debugging information
    --d_source       => Information about source audio files and conversion
    --d_stdio        => Standard I/O command debugging
    --d_stream       => Information about player streaming protocol 
    --d_stream_v     => Verbose information about player streaming protocol 
    --d_sync         => Information about multi player synchronization
    --d_time         => Internal timer information
    --d_ui           => Player user interface information
    --d_usage        => Display buffer usage codes on the player's display
    
Commands may be sent to the server through standard in and will be echoed via
standard out.  See complete documentation for details on the command syntax.
EOF

}

sub initOptions {
	if (!GetOptions(
		'user=s'   			=> \$user,
		'group=s'   		=> \$group,
		'cliaddr=s'   		=> \$cliaddr,
		'cliport=s'   		=> \$cliport,
		'daemon'   			=> \$daemon,
		'httpaddr=s'   		=> \$httpaddr,
		'httpport=s'   		=> \$httpport,
		'logfile=s'   		=> \$logfile,
		'mp3dir=s' 			=> \$mp3dir,
		'pidfile=s' 		=> \$pidfile,
		'playeraddr=s'		=> \$localClientNetAddr,
		'priority=i'        => \$priority,
		'stdio'				=> \$stdio,
		'streamaddr=s'		=> \$localStreamAddr,
		'prefsfile=s' 		=> \$prefsfile,
		'quiet'   			=> \$quiet,
		'nosetup'			=> \$nosetup,
		'd_cli'				=> \$d_cli,
		'd_command'			=> \$d_command,
		'd_control'			=> \$d_control,
		'd_display'			=> \$d_display,
		'd_factorytest'		=> \$d_factorytest,
		'd_files'			=> \$d_files,
		'd_http'			=> \$d_http,
		'd_info'			=> \$d_info,
		'd_ir'				=> \$d_ir,
		'd_itunes'			=> \$d_itunes,
		'd_moodlogic'		=> \$d_moodlogic,
		'd_mdns'			=> \$d_mdns,
		'd_os'				=> \$d_os,
		'd_paths'			=> \$d_paths,
		'd_perf'			=> \$d_perf,
		'd_parse'			=> \$d_parse,
		'd_playlist'		=> \$d_playlist,
		'd_plugins'			=> \$d_plugins,
		'd_protocol'		=> \$d_protocol,
		'd_prefs'			=> \$d_prefs,
		'd_remotestream'	=> \$d_remotestream,
		'd_scan'			=> \$d_scan,
		'd_scheduler'		=> \$d_scheduler,
		'd_select'			=> \$d_select,
		'd_server'			=> \$d_server,
		'd_slimproto'		=> \$d_slimproto,
		'd_slimproto_v'		=> \$d_slimproto_v,
		'd_source'			=> \$d_source,
		'd_stdio'			=> \$d_stdio,
		'd_stream'			=> \$d_stream,
		'd_stream_v'		=> \$d_stream_v,
		'd_sync'			=> \$d_sync,
		'd_time'			=> \$d_time,
		'd_ui'				=> \$d_ui,
		'd_usage'			=> \$d_usage,
	)) {
		showUsage();
		exit(1);
	};
}

sub initSettings {	
	Slim::Utils::Prefs::load($prefsfile, $nosetup);
	Slim::Utils::Prefs::checkServerPrefs();
	Slim::Buttons::Home::updateMenu();
	Slim::Web::Setup::initSetup();
	
	#options override existing preferences
	if (defined($mp3dir)) {
		Slim::Utils::Prefs::set("mp3dir", $mp3dir);
	}
	
	if (defined($httpport)) {
		Slim::Utils::Prefs::set("httpport", $httpport);
	}

	if (defined($cliport)) {
		Slim::Utils::Prefs::set("cliport", $cliport);
	}

	# warn if there's no mp3dir preference
	# FIXME put the strings in strings.txt
	if (!(defined Slim::Utils::Prefs::get("mp3dir") && 
				-d Slim::Utils::Prefs::get("mp3dir")) && 
				!$quiet && 
				!Slim::Music::iTunes::useiTunesLibrary()) {
		msg("Your MP3 directory needs to be configured. Please open your web browser,\n");
		msg("go to the following URL, and click on the \"Server Settings\" link.\n\n");
		msg(string('SETUP_URL_WILL_BE') . "\n\t" . Slim::Web::HTTP::HomeURL() . "\n");
	} else {
		if (Slim::Utils::Prefs::get("mp3dir") =~ m|[/\\]$|) {
			$mp3dir = Slim::Utils::Prefs::get("mp3dir");
			$mp3dir =~ s|[/\\]$||;
			Slim::Utils::Prefs::set("mp3dir",$mp3dir);
		}
	}
}

sub daemonize {
	my $pid ;
	my $uname ;
	my $uid ; 
	my @grp ; 
	use POSIX 'setsid';
	my $log;
	
	if ($logfile) { $log = $logfile } else { $log = '/dev/null' };
	
	if (!open STDIN, '/dev/null') { die "Can't read /dev/null: $!";}
	if (!open STDOUT, ">>$log") { die "Can't write to $log: $!";}
	if (!defined($pid = fork)) { die "Can't fork: $!"; }
	
	if ($pid) {
		save_pid_file($pid);
		# don't clean up the pidfile!
		$pidfile = undef;
		exit;
	}
	
	# Do we want to change the effective user or group?
	if (defined($user) || defined($group)) {
		# Can only change effective UID/GID if root
		if ($> != 0) {
			$uname = getpwuid($>) ;
			print STDERR "Current user is ", $uname, "\n" ;
			print STDERR "Must run as root to change effective user or group.\n" ;
			die "Aborting" ;
		}

		# Change effective group ID if necessary
		# Need to do this while still root, so do group first
		if (defined($group)) {
			@grp = getgrnam($group);
			if (!defined ($grp[0])) {
				print STDERR "Group ", $group, " not found.\n" ;
				die "Aborting" ;
			}

			@) = @grp ;
			if ($)[0] ne $group) {
				print STDERR "Unable to set effective group(s)",
					" to ", $group, " (", @grp, ")!\n" ;
				die "Aborting" ;
			}
		}

		# Change effective user ID if necessary
		if (defined($user)) {
			$uid = getpwnam($user);
			if (!defined ($uid)) {
				print STDERR "User ", $user, " not found.\n" ;
				die "Aborting" ;
			}

			$> = $uid ;
			if ($> != $uid) {
				print STDERR "Unable to set effective user to ",
					$user, " (", $uid, ")!\n" ;
				die "Aborting" ;
			}
		}
	}

	$0 = "slimd";
	
	if (!setsid) { die "Can't start a new session: $!"; }
	if (!open STDERR, '>&STDOUT') { die "Can't dup stdout: $!"; }
}

sub checkVersion {
	if (Slim::Utils::Prefs::get("checkVersion")) {
		my $url = "http://www.slimdevices.com/update/?version=$VERSION&lang=" . Slim::Utils::Strings::getLanguage();
		my $sock = Slim::Web::RemoteStream::openRemoteStream($url);
		if ($sock) {
			my $content;
			my $line;
			while ($line = <$sock>) {
				$content .= $line;
			}
			$::newVersion = $content;
		}
		if ($sock) {
			$sock->close();
		}
		Slim::Utils::Timers::setTimer(0, time() + 60*60*24, \&checkVersion);
	} else {
		$::newVersion = undef;
	}
}

#------------------------------------------
#
# Clean up resources and exit.
#
sub stopServer {
	$::d_server && msg("Slim Server shutting down.\n");
	cleanup();
	exit();
}

sub sigint {
	cleanup();
	exit();
}

sub cleanup {

	$::d_server && msg("Slim Server cleaning up.\n");

	if (Slim::Utils::Prefs::get('usetagdatabase')) {
		Slim::Music::Info::stopCache();
	}
	remove_pid_file();
	Slim::Networking::mDNS::stopAdvertise();
}

sub save_pid_file {
	 my $process_id = shift || $$;


	$::d_server && msg("Slim Server saving pid file.\n");
	 if (defined $pidfile && -e $pidfile) {
	 	die "Process ID file: $pidfile already exists";
	 }
	 
	 if (defined $pidfile and open PIDFILE, ">$pidfile") {
		print PIDFILE "$process_id\n";
		close PIDFILE;
	 }
}
 
sub remove_pid_file {
	 if (defined $pidfile) {
	 	unlink $pidfile;
	 }
}
 
sub END {
	sigint();
}

# start up the server if we're not running as a service.	
if (!defined($PerlSvc::VERSION)) { 
	main()
};



__END__
