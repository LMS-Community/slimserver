package Slim::Utils::Misc;

# $Id: Misc.pm,v 1.37 2004/04/29 17:51:34 vidur Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Which;
use Fcntl;
use Slim::Music::Info;
use Slim::Utils::OSDetect;
use POSIX qw(strftime setlocale LC_TIME);
use Net::hostent;              # for OO version of gethostbyaddr
use Sys::Hostname;
use Socket;
use Symbol qw(qualify_to_ref);
use URI;
use URI::file;

if ($] > 5.007) {
	require Encode;
}

use FindBin qw($Bin);

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK @EXPORT_FAIL);
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(assert bt msg msgf watchDog);    # we export these so it's less typing to use them
@EXPORT_OK = qw(assert bt msg msgf watchDog);    # we export these so it's less typing to use them

BEGIN {
        if ($^O =~ /Win32/) {
                *EWOULDBLOCK = sub () { 10035 };
                *EINPROGRESS = sub () { 10036 };
        } else {
                require Errno;
                import Errno qw(EWOULDBLOCK EINPROGRESS);
        }
}

sub blocking {   
	my $sock = shift;
 	return $sock->blocking(@_) unless $^O =~ /Win32/;
	my $nonblocking = $_[0] ? "0" : "1";
	my $retval = ioctl($sock, 0x8004667e, \$nonblocking);
	if (!defined($retval) && $] >= 5.008) {
		$retval = "0 but true";
	}
	return $retval;
}

sub findbin {
	my $executable = shift;
	
	my @paths;
	my $path;
	
	push @paths, catdir( $Bin, 'Bin', $Config::Config{archname});
	push @paths, catdir( $Bin, 'Bin', $^O);
	push @paths, catdir( $Bin, 'Bin');
		
	if (Slim::Utils::OSDetect::OS() ne "win") {
		push @paths, (split(/:/, $ENV{'PATH'}),'/usr/bin','/usr/local/bin','/sw/bin');
	} else {
		$executable .= '.exe';
	}
	
	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @paths, $ENV{'HOME'} . "/Library/SlimDevices/bin/";
		push @paths, "/Library/SlimDevices/bin/";
		push @paths, $ENV{'HOME'} . "/Library/iTunes/Scripts/iTunes-LAME.app/Contents/Resources/";
	}

	foreach my $path (@paths) {
		$path = catdir($path, $executable);
		if (-x $path) {
			$::d_paths && msg("Found binary $path for $executable\n");
			return $path;
		}
	}
		
	if (Slim::Utils::OSDetect::OS() eq "win") {
		$path =  File::Which::which($executable);
	} else {
		$path = undef;
	}
	
	$::d_paths && msg("Found binary $path for $executable\n");

	return $path;	
}

sub pathFromWinShortcut {
	my $fullpath = shift;
	$fullpath = pathFromFileURL($fullpath);
	my $path = "";
	if (Slim::Utils::OSDetect::OS() eq "win") {
		require Win32::Shortcut;
		my $shortcut = Win32::Shortcut->new($fullpath);
		if (defined($shortcut)) {
			$path = $shortcut->Path();
			# the following pattern match throws out the path returned from the
			# shortcut if the shortcut is contained in a child directory of the path
			# to avoid simple loops, loops involving more than one shortcut are still
			# possible and should be dealt with somewhere, just not here.
			if (defined($path) && !$path eq "" && $fullpath !~ /^\Q$path\E/i) {
				#collapse shortcuts to shortcuts into a single hop
				if (Slim::Music::Info::isWinShortcut($path)) {
					$path = pathFromWinShortcut($path);
				}
				return $path;
			} else {
				$::d_files && msg("Bad path in $fullpath\n");
				$::d_files && defined($path) && msg("Path was $path\n");
			}
		} else {
			$::d_files && msg("Shortcut $fullpath is invalid\n");
		}
	} else {
		$::d_files && msg("Windows shortcuts not supported on non-windows platforms\n");
	}
	
	return "";
}
	
sub pathFromFileURL {
	my $url = shift;
	my $file;
	
	my $uri = URI->new($url);

	# TODO - FIXME - this isn't mac or dos friendly with the path...
	# Use File::Spec::rel2abs ? or something along those lines?
	#
	# file URLs must start with file:/// or file://localhost/ or file://\\uncpath
	if ($uri->scheme() && $uri->scheme() eq 'file') {

		my $path = $uri->path();

		$::d_files && msg("Got $path from file url $url\n");

		# only allow absolute file URLs and don't allow .. in files...
		# make sure they are in the audiodir or are already in the library...		
		if (($path !~ /\.\.[\/\\]/) || Slim::Music::Info::isCached($url)) {
			$file = Slim::Web::HTTP::unescape($path);
		} 
	}

	if (!defined($file))  {
		$::d_files && msg("bad file: url $url\n");
	} else {
		$::d_files && msg("extracted: $file from $url\n");
	}

	return $file;
}

sub fileURLFromPath {
	my $path = shift;
	my $uri  = URI->new($path);

	return sprintf('file://%s', $uri->path());
}

sub anchorFromURL {
	my $url = shift;

	if ($url =~ /#(.*)$/) {
		return $1;
	}
	return undef;
}


##################################################################################
#
# split a URL into (host, port, path)
#
sub crackURL {
	my ($string) = @_;

	$string =~ m|http://(?:([^\@:]+):?([^\@]*)\@)?([^:/]+):*(\d*)(\S*)|i;
	
	my $user = $1;
	my $password = $2;
	my $host = $3;
	my $port = $4;
	my $path = $5;
	
	$path = '/' unless $path;

	$port = 80 unless $port;
	
	$::d_files && msg("cracked: $string with [$host],[$port],[$path]\n");
	$::d_files && $user && msg("   user: [$user]\n");
	$::d_files && $password && msg("   password: [$password]\n");
	
	return ($host, $port, $path, $user, $password);
}

# test code for crackURL
if (0) {
	$::d_files = 1;
	crackURL('http://10.0.1.201');
	crackURL('http://tank');
	crackURL('http://10.0.1.201/');
	crackURL('http://tank/');
	crackURL('http://10.0.1.201/foo.html');
	crackURL('http://tank/foo.html');
	crackURL('http://10.0.1.201:9090/foo.html');
	crackURL('http://tank:9090/foo.html');
	crackURL('http://dean:pass@10.0.1.201/foo.html');
	crackURL('http://dean:pass@tank/foo.html');
	crackURL('http://dean:pass@10.0.1.201:9090/foo.html');
	crackURL('http://dean:pass@tank:9090/foo.html');
	crackURL('http://dean@10.0.1.201/foo.html');
	crackURL('http://dean@tank/foo.html');
	crackURL('http://dean@10.0.1.201:9090/foo.html');
	crackURL('http://dean@tank:9090/foo.html');
	crackURL('http://dean:@10.0.1.201/foo.html');
	crackURL('http://dean:@tank/foo.html');
	crackURL('http://dean:@10.0.1.201:9090/foo.html');
	crackURL('http://dean:@tank:9090/foo.html');
	$::d_files = 0;
	exit(0);
}

# there's not really a better way to do this..
# fixPath takes relative file paths and puts the base path in the beginning
# to make them full paths, if possible.
# URLs are left alone
        
sub fixPath {
	my $file = shift;
	my $base = shift;

	my $fixed;
			   
	if (!defined($file) || $file eq "") { return; }   
	
	if (Slim::Music::Info::isURL($file)) { 
		return $file;
	} 

	if (Slim::Music::Info::isFileURL($base)) { $base=Slim::Utils::Misc::pathFromFileURL($base); } 
		 
	# the only kind of absolute file we like is one in 
	# the music directory or the playlist directory...
	my $audiodir = Slim::Utils::Prefs::get("audiodir");
	my $savedplaylistdir = Slim::Utils::Prefs::get("playlistdir");

	if ($audiodir && $file =~ /^\Q$audiodir\E/) {
			$fixed = $file;
	} elsif ($savedplaylistdir && $file =~ /^\Q$savedplaylistdir\E/) {
			$fixed = $file;
	} elsif (Slim::Music::Info::isURL($file) && (!defined($audiodir) || ! -r catfile($audiodir, $file))) {
			$fixed = $file;
	} elsif ($base) {
		if (file_name_is_absolute($file)) {
			if (Slim::Utils::OSDetect::OS() eq "win") {
				my ($volume) = splitpath($file);
				if (!$volume) {
					($volume) = splitpath($base);
					$file = $volume . $file;
				}
			}
			$fixed = fixPath($file);
		} else {
			$fixed = fixPath(catfile($base, $file));
		}
	} elsif (file_name_is_absolute($file)) {
			$fixed = $file;
	} else {
			$file =~ s/\Q$audiodir\E//;
			$fixed = catfile($audiodir, $file);
	}
	
	$::d_paths && ($file ne $fixed) && msg("*****fixed: " . $file . " to " . $fixed . "\n");
	$::d_paths && ($file ne $fixed) && ($base) && msg("*****base: " . $base . "\n");
	if (Slim::Music::Info::isFileURL($fixed)) {
		return $fixed;
	} else {
		return Slim::Utils::Misc::fileURLFromPath($fixed);  
	}
}

sub ascendVirtual {
	my $curVP = shift;
	my @components = splitdir($curVP);
	
	pop @components;
	
	if ((@components == 0) || (@components == 1 && $components[0] eq '')) {
		return '';
	} else {
		return catdir(@components);
	}
}

sub descendVirtual {
	my $curVP = shift;
	my $item = shift;
	my $itemindex = shift;
	my $component;
	my $curAP;

	$curAP = virtualToAbsolute($curVP);

	if (!defined($curVP)) {
		$curVP = "";
	}

	$::d_paths && msg("descendVirtual(curVP = $curVP, item = $item, itemindex = $itemindex, curAP = $curAP)\n");
	
	if (Slim::Music::Info::isPlaylist($curAP)) {
		$component = $itemindex;
	} elsif (Slim::Music::Info::isITunesPlaylistURL($item) || Slim::Music::Info::isMoodLogicPlaylistURL($item)) {
		$component = $item;
	} elsif (Slim::Music::Info::isURL($item)) {
		$component = Slim::Web::HTTP::unescape((split(m|/|,$item))[-1]);
	} else {
		$component = (splitdir($item))[-1];
	}

	# On MacOS, catdir works a little differently. Since absolute paths *don't* start
	# with the path separator, catdir('','foo') will return something unexpected like
	# 'Macintosh HD:foo'.	I guess this is a bug in catdir...
	my $ret;
	if (!defined($curVP) || $curVP eq '') {
		$ret=$component;
	} else {
		$ret=catdir($curVP,$component);
	}
	$::d_paths && msg("descendVirtual returning catdir($curVP, $component) == $ret\n");
	return $ret;
}

sub virtualToAbsolute {
	my $virtual = shift;
	my $recursion = shift;
	my $curdir = Slim::Utils::Prefs::get('audiodir');
	my $playdir = Slim::Utils::Prefs::get('playlistdir');
	if (!defined($virtual)) { $virtual = "" };
	
	if (Slim::Music::Info::isURL($virtual)) {
		return $virtual;
	}
	
	if (file_name_is_absolute($virtual)) {
		$::d_paths && msg("virtualToAbsolute: $virtual is already absolute.\n");
		return $virtual;
	}

	$::d_paths && msg("virtualToAbsolute: " . ($virtual ? $virtual : 'UNDEF') . "\n");
		
	if ($virtual && $virtual =~ /^__playlists/) {
		# get rid of the leading __playlists
		my @v = splitdir($virtual);
		shift @v;
		
		if (Slim::Music::Info::isITunesPlaylistURL($v[0]) || Slim::Music::Info::isMoodLogicPlaylistURL($v[0])) {
			$curdir = shift @v;
		} else {
			$curdir = Slim::Utils::Prefs::get('playlistdir');
		}

		$virtual = catdir(@v);
		#we are already doing a virtual path starting with __playlists so don't recurse
		$recursion = 1;
		
	} else {
		$curdir = Slim::Utils::Prefs::get('audiodir');
	}
	
	my @levels = ();
	if (defined($virtual)) {
		@levels = splitdir($virtual);
	}

	my $level;

	if ($::d_paths) {
		foreach $level (@levels) {
			msg("    $level\n");
		}
	}

	my @items;
	foreach	$level (@levels) {
		next if $level eq "";
# this was breaking songinfo and other pages when using windows .lnk files.
#		last if $level eq "..";

# optimization for pre-cached itunes/moodlogic playlists.
		if (Slim::Music::Info::isITunesPlaylistURL($curdir) || Slim::Music::Info::isMoodLogicPlaylistURL($curdir)) {
			my $listref = Slim::Music::Info::cachedPlaylist(Slim::Utils::Misc::fileURLFromPath($curdir));
			if ($listref) {
				return @{$listref}[$level];
			}
			
		} 
		
		if (Slim::Music::Info::isPlaylist(Slim::Utils::Misc::fileURLFromPath($curdir))) {
			@items = ();
			Slim::Utils::Scan::addToList(\@items,$curdir, 0, 0);
			if (scalar(@items)) {
				if (defined $items[$level]) {
					$curdir = $items[$level];
				} else {
					last;
				}
				#continue traversing if the item was found in the list
				#and the item found is itself a list
				next if (Slim::Music::Info::isList(Slim::Utils::Misc::fileURLFromPath($curdir)));
				#otherwise stop traversing, curdir is either the playlist
				#if no entry found or the located entry in the playlist
				last;
			}
		} else {
			if (Slim::Music::Info::isURL($curdir)) {
				#URLs always use / as separator
				$curdir .= '/' . Slim::Web::HTTP::escape($level);
			} else {
				$curdir = catdir($curdir,$level);
			}
		}
		next if (Slim::Music::Info::isDir(Slim::Utils::Misc::fileURLFromPath($curdir)));
		if (Slim::Music::Info::isWinShortcut(Slim::Utils::Misc::fileURLFromPath($curdir))) {
			if (defined($Slim::Utils::Scan::playlistCache{Slim::Utils::Misc::fileURLFromPath($curdir)})) {
				$curdir = $Slim::Utils::Scan::playlistCache{Slim::Utils::Misc::fileURLFromPath($curdir)}
			} else {
				$curdir = pathFromWinShortcut(Slim::Utils::Misc::fileURLFromPath($curdir));
			}
		}
		#continue traversing if curdir is a list
		next if (Slim::Music::Info::isList(Slim::Utils::Misc::fileURLFromPath($curdir)));
		#otherwise stop traversing, non-list items cannot be traversed
		last;
	}
	$::d_paths && msg("became: $curdir\n");
	if (!$recursion && $virtual =~ /\.(?:m3u|pls|cue)$/ && $virtual !~ /^__playlists/ && !-e $curdir) {
		#Not a real file, could be a naked saved playlist
		return virtualToAbsolute(catdir('__playlists',$virtual),1);
	}
	if (Slim::Music::Info::isFileURL($curdir)) {
		return $curdir;
	} else {
		return Slim::Utils::Misc::fileURLFromPath($curdir);  
	}
}

sub inPlaylistFolder {
	my $path = shift;
	$path = fixPath($path);
	$path = virtualToAbsolute($path);
    my $playlistdir = Slim::Utils::Prefs::get("playlistdir");
    if ($playlistdir && $path =~ /^\Q$playlistdir\E/) {
    	return 1;
    } else {
    	return 0;
    }
}

sub readDirectory {
	my $dirname = shift;
	my @diritems = ();
	
	$::d_files && msg("reading directory: $dirname\n");

	if (!-d $dirname) { 
		$::d_files && msg("no such dir: $dirname\n");
		return @diritems;
	}
	opendir(DIR, $dirname) || warn "opendir failed: " . $dirname . ": $!\n";
	foreach my $dir ( readdir(DIR) ) {

		# Ignore items starting with a period on non-windows machines
		next if $dir =~ /^\./ && (Slim::Utils::OSDetect::OS() ne 'win');

		if (-d catdir($dirname, $dir)) {
			# always ignore . and ..
			next if $dir eq '.';
			next if $dir eq '..';

			# Bad names on a mac or a mac server
			next if $dir eq 'Icon';  					
			next if $dir eq 'TheVolumeSettingsFolder';
			next if $dir eq 'Network Trash Folder';
	
			# Bad names on a windows server
			next if $dir eq 'Recycled';  					
			next if $dir eq 'RECYCLER';  					
			next if $dir eq 'System Volume Information';
			
			# Bad names on a linux machine
			next if $dir eq 'lost+found';
		}
		
		# Ignore our special named files and directories
		next if $dir =~ /^__/;  
		
		my $ignore = Slim::Utils::Prefs::get('ignoreDirRE');
		if (defined($ignore) && $ignore ne '') {
			next if $dir =~ /$ignore/;
		}

		push @diritems, $dir;
	}
	
	closedir(DIR);
	
	$::d_files && msg("directory: $dirname contains " . scalar(@diritems) . " items\n");
	
	return sort(@diritems);
}

# the following functions cleanup the date and time, specifically:
# remove the leading zeros for single digit dates and hours
# where a | is specified in the format

sub longDateF {
	my $time = shift || Time::HiRes::time();
	my $date = localeStrftime(Slim::Utils::Prefs::get('longdateFormat'), $time);
	$date =~ s/\|0*//;
	return $date;
}

sub shortDateF {
	my $time = shift || Time::HiRes::time();
	my $date = localeStrftime(Slim::Utils::Prefs::get('shortdateFormat'),  $time);
	$date =~ s/\|0*//;
	return $date;
}

sub timeF {
	my $ltime = shift || Time::HiRes::time();
	my $time = localeStrftime(Slim::Utils::Prefs::get('timeFormat'),  $ltime);
	# remove leading zero if another digit follows
	$time =~ s/\|0?(\d+)/$1/;
	return $time;
}

sub localeStrftime {
      my $format = shift;
      my $ltime = shift;
      
      (my $language = Slim::Utils::Prefs::get('language')) =~ tr/A-Z/a-z/;
      (my $country = $language) =~ tr/a-z/A-Z/;
      
      my $serverlocale = $language . "_" . $country;

      my $saved_locale = setlocale(LC_TIME, $serverlocale);
      my $time = strftime $format, localtime($ltime);
      if ($] > 5.007) {
            Encode::_utf8_on($time);
      }
      setlocale(LC_TIME, "");
      return $time;
}

sub fracSecToMinSec {
	my $seconds = shift;

	my ($min, $sec, $frac, $fracrounded);

	$min = ($seconds/60)%60;
	$sec = $seconds%60;
	$sec = "0$sec" if length($sec) < 2;
	
	# We want to round the last two decimals but we
    # always round down to avoid overshooting EOF on last track
    $fracrounded = int($seconds * 100) + 100;
    $frac = substr($fracrounded, -2, 2);
									
	return "$min:$sec.$frac";
}

sub assert {
	my $exp = shift;
	defined($exp) && $exp && return;

	bt();
}

sub bt {
	my $frame = 1;

    my $msg = "Backtrace:\n\n";

	my $assertfile = '';
	my $assertline = 0;

	while( my ($package, $filename, $line, $subroutine, $hasargs, 
			$wantarray, $evaltext, $is_require) = caller($frame++) ) {
		$msg.=sprintf("   frame %d: $subroutine ($filename line $line)\n", $frame - 2);
		if ($subroutine=~/assert$/) {
			$assertfile = $filename;
			$assertline = $line;			
		}
    }
        
	if ($assertfile) {
		open SRC, $assertfile;
		my $line;
		my $line_n=0;
		$msg.="\nHere's the problem. $assertfile, line $assertline:\n\n";
		while ($line=<SRC>) {
			$line_n++;
			if (abs($assertline-$line_n) <=10) {
				$msg.="$line_n\t$line";
			}
		}
	}
	
	$msg.="\n";

	&msg($msg);
}

sub watchDog {
	if (!$::d_perf) {return;}
	
	my $lapse = shift;
	my $warn = shift;
	my $now = Time::HiRes::time();
	
	if (!defined($lapse)) { return $now; };
	
	my $delay = $now - $lapse;
	
	if (($delay) > 0.5) {
		msg("*****Watchpup: $warn took too long: $delay (now: $now)\n");
	}
	
	return $now;
}

$Slim::Utils::Misc::log = "";

sub msg {
	my $entry = strftime "%Y-%m-%d %H:%M:%S.", localtime;
	my $now = int(Time::HiRes::time() * 10000);
	$entry .= (substr $now, -4) . " ";
	$entry .= shift;
	print STDERR $entry;
	
	if (Slim::Utils::Prefs::get('livelog')) {
		 $Slim::Utils::Misc::log .= $entry;
		 $Slim::Utils::Misc::log = substr($Slim::Utils::Misc::log, -Slim::Utils::Prefs::get('livelog'));
	}
}

sub msgf {
	my $entry = strftime "%Y-%m-%d %H:%M:%S ", localtime;
	$entry .= sprintf @_;
	
	print STDERR $entry;
	
	if (Slim::Utils::Prefs::get('livelog')) {
		$Slim::Utils::Misc::log .= $entry;
	 	$Slim::Utils::Misc::log = substr($Slim::Utils::Misc::log, -Slim::Utils::Prefs::get('livelog'));
	}
}

sub delimitThousands {
	my $len = shift; 
	my $sep = Slim::Utils::Strings::string('THOUSANDS_SEP');
	0 while $len =~ s/^(-?\d+)(\d{3})/$1$sep$2/;
	return $len;
}

# Check for allowed source IPs, called via CLI.pm and HTTP.pm
sub isAllowedHost {
	my $host = shift;
	my @rules = split /\,/, Slim::Utils::Prefs::get('allowedHosts');

	foreach my $item (@rules)
	{
		if ($item eq $host)
		{
		#If the host matches a specific IP, return valid
			return 1;
		} else {
			my @matched = (0,0,0,0);
			
			#Get each octet
			my @allowedoctets = split /\./, $item;
			my @hostoctets = split /\./, $host;
			for (my $i = 0; $i < 4; ++$i)
			{
				$allowedoctets[$i] =~ s/\s+//g;
				#if the octet is * or a specific match, pass octet match
				if (($allowedoctets[$i] eq "*") || ($allowedoctets[$i] eq $hostoctets[$i]))
			   	{
					$matched[$i] = 1;
				} elsif ($allowedoctets[$i] =~ /-/) {	#Look for a range formatted octet rule
					my ($low, $high) = split /-/,$allowedoctets[$i];
					if (($hostoctets[$i] >= $low) && ($hostoctets[$i] <= $high))
					{
						#if it matches the range, pass octet match
						$matched[$i] = 1;
					}
				} 
			}
			#check if all octets passed
			if (($matched[0] eq '1') && ($matched[1] eq '1') &&
			    ($matched[2] eq '1') && ($matched[3] eq '1'))
			{
				return 1;
			}
		}
	}
	
	# No rules matched, return invalid source
	return 0;
}


sub hostaddr {
	my @hostaddr = ();
	my @hostnames;
	
	push @hostnames, 'localhost';
	push @hostnames, hostname();
	
	foreach my $hostname (@hostnames) {
		next if (!$hostname);

		my $host = gethost($hostname);

		next if (!$host);
		
		foreach my $addr ( @{$host->addr_list} ) {
			push @hostaddr, inet_ntoa($addr) if $addr;
		} 
	}
	return @hostaddr;
}

sub stillScanning {
	return Slim::Music::MusicFolderScan::stillScanning() || Slim::Music::iTunes::stillScanning() || Slim::Music::MoodLogic::stillScanning();
}


# this function based on a posting by Tom Christiansen: http://www.mail-archive.com/perl5-porters@perl.org/msg71350.html
sub at_eol($) { $_[0] =~ /\n\z/ }
sub sysreadline(*;$) { 
	my($handle, $maxnap) = @_;
	$handle = qualify_to_ref($handle, caller());

	return undef unless $handle;

	my $infinitely_patient = @_ == 1;

	my $start_time = Time::HiRes::time();

	my $selector = IO::Select->new();
	$selector->add($handle);

	my $line = '';
	my $result;

SLEEP:
	until (at_eol($line)) {

		unless ($infinitely_patient) {

			if (Time::HiRes::time() > $start_time + $maxnap) {
				return $line;
			} 
		} 

		my @ready_handles;

		unless (@ready_handles = $selector->can_read(.1)) {  # seconds

			unless ($infinitely_patient) {
				my $time_left = $start_time + $maxnap - Time::HiRes::time();
			} 

			next SLEEP;
		}

INPUT_READY:
		while (() = $selector->can_read(0.0)) {

			my $was_blocking = blocking($handle,0);

CHAR:
			while ($result = sysread($handle, my $char, 1)) {
				$line .= $char;
				last CHAR if $char eq "\n";
			} 

			my $err = $!;

			blocking($handle, $was_blocking);

			unless (at_eol($line)) {

				if (!defined($result) && $err != EWOULDBLOCK) { 
					return undef;					
				}
				next SLEEP;
			} 

			last INPUT_READY;
		}
	} 

	return $line;
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
