package Slim::Utils::Misc;

# $Id: Misc.pm,v 1.11 2003/10/09 04:19:51 dean Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Which;
use Fcntl;
use Slim::Music::Info;
use Slim::Utils::OSDetect;
use POSIX qw(strftime);
use Net::hostent;              # for OO version of gethostbyaddr
use Sys::Hostname;
use Socket;

use FindBin qw($Bin);

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK @EXPORT_FAIL);
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(assert bt msg msgf watchDog);    # we export these so it's less typing to use them
@EXPORT_OK = qw(assert bt msg msgf watchDog);    # we export these so it's less typing to use them

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
	
	push @paths, catdir( $Bin, 'bin', $Config::Config{archname});
	push @paths, catdir( $Bin, 'bin', $^O);
		
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
	my($url) = shift;
	my $file;
	my $path;
	
	# TODO - FIXME - this isn't mac or dos friendly with the path...
	# file URLs must start with file:/// or file://localhost/
	if ($url =~ /^file:\/\/(\/|localhost\/)(.*)/i || $url =~ /^file:(\/\/|\/\/\/)([a-zA-Z]:.*)/i)  {
		$path = $2;
		if ($path !~ /^[a-zA-Z]:/) { $path = '/' . $path; };
		$path =~ s/(.*)#.*$/$1/;
		my $mp3dir = Slim::Utils::Prefs::get("mp3dir");
		$::d_files && msg("Got $path from file url $url\n");
		# only allow absolute file URLs and don't allow .. in files...
		# make sure they are in the mp3dir or are already in the library...		
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
		 
	# the only kind of absolute file we like is one in 
	# the music directory or the playlist directory...
	my $mp3dir = Slim::Utils::Prefs::get("mp3dir");
	my $savedplaylistdir = Slim::Utils::Prefs::get("playlistdir");
	
	if ($mp3dir && $file =~ /^\Q$mp3dir\E/) {
			$fixed = $file;
	} elsif ($savedplaylistdir && $file =~ /^\Q$savedplaylistdir\E/) {
			$fixed = $file;
	} elsif (Slim::Music::Info::isURL($file)) {
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
			$file =~ s/\Q$mp3dir\E//;
			$fixed = catfile($mp3dir, $file);
	}
	
	$::d_paths && ($file ne $fixed) && msg("*****fixed: " . $file . " to " . $fixed . "\n");
	$::d_paths && ($file ne $fixed) && ($base) && msg("*****base: " . $base . "\n");
	return $fixed;  
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
	} elsif (Slim::Music::Info::isITunesPlaylistURL($item)) {
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
	my $curdir = Slim::Utils::Prefs::get('mp3dir');
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
		
		if (Slim::Music::Info::isITunesPlaylistURL($v[0])) {
			$curdir = shift @v;
		} else {
			$curdir = Slim::Utils::Prefs::get('playlistdir');
		}

		$virtual = catdir(@v);
		#we are already doing a virtual path starting with __playlists so don't recurse
		$recursion = 1;
		
	} else {
		$curdir = Slim::Utils::Prefs::get('mp3dir');
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

# optimization for pre-cached itunes playlists.
		if (Slim::Music::Info::isITunesPlaylistURL($curdir)) {
			my $listref = Slim::Music::Info::cachedPlaylist($curdir);
			if ($listref) {
				return @{$listref}[$level];
			}
			
		} 
		
		if (Slim::Music::Info::isPlaylist($curdir)) {
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
				next if (Slim::Music::Info::isList($curdir));
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
		next if (Slim::Music::Info::isDir($curdir));
		if (Slim::Music::Info::isWinShortcut($curdir)) {
			if (defined($Slim::Utils::Scan::playlistCache{$curdir})) {
				$curdir = $Slim::Utils::Scan::playlistCache{$curdir}
			} else {
				$curdir = pathFromWinShortcut($curdir);
			}
		}
		#continue traversing if curdir is a list
		next if (Slim::Music::Info::isList($curdir));
		#otherwise stop traversing, non-list items cannot be traversed
		last;
	}
	$::d_paths && msg("became: $curdir\n");
	if (!$recursion && $virtual =~ /\.(?:m3u|pls|cue)$/ && $virtual !~ /^__playlists/ && !-e $curdir) {
		#Not a real file, could be a naked saved playlist
		return virtualToAbsolute(catdir('__playlists',$virtual),1);
	}
	return $curdir;
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
	$::d_files && msg("directory: $dirname contains " . scalar(@diritems) . " items\n");
	
	return sort(@diritems);
}

# the following functions cleanup the date and time, specifically:
# remove the leading zeros for single digit dates and hours
# where a | is specified in the format

sub longDateF {
	my $time = shift || Time::HiRes::time();
	my $date = strftime Slim::Utils::Prefs::get('longdateFormat'), localtime($time);
	$date =~ s/\|0*//;
	return $date;
}

sub shortDateF {
	my $time = shift || Time::HiRes::time();
	my $date = strftime Slim::Utils::Prefs::get('shortdateFormat'),  localtime($time);
	$date =~ s/\|0*//;
	return $date;
}

sub timeF {
	my $ltime = shift || Time::HiRes::time();
	my $time = strftime Slim::Utils::Prefs::get('timeFormat'),  localtime($ltime);
	# remove leading zero if another digit follows
	$time =~ s/\|0?(\d+)/$1/;
	return $time;
}

sub assert {
	my $exp = shift;
	defined($exp) && $exp && return;

	msg("OOPS! An error has occurred in the Slim Server which may cause \n");
	msg("incorrect behvior or an eventual crash. The information below\n");
	msg("indicates where the error occurred. For help, please contact\n"); 
	msg("support\@slimdevices.com, and include the following error message:\n");
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
	my $entry = strftime "%Y-%m-%d %H:%M:%S ", localtime;
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

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
