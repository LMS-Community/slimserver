package Slim::Utils::Misc;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Which ();
use FindBin qw($Bin);
use Fcntl;
use Slim::Music::Info;
use Slim::Utils::OSDetect;
use POSIX qw(strftime setlocale LC_TIME LC_CTYPE);
use Sys::Hostname;
use Socket qw(inet_ntoa inet_aton);
use Symbol qw(qualify_to_ref);
use URI;
use URI::file;

if ($] > 5.007) {
	require Encode;
}

use base qw(Exporter);

our @EXPORT = qw(assert bt msg msgf watchDog);
our $log    = "";

BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };

		require Win32::Shortcut;
		require Win32::OLE::NLS;
		require Win32;

	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}
}

# Find out what code page we're in, so we can properly translate file/directory encodings.
our $locale = '';

{
        if ($^O =~ /Win32/) {

		my $langid = Win32::OLE::NLS::GetUserDefaultLangID();
		my $lcid   = Win32::OLE::NLS::MAKELCID($langid);
		my $linfo  = Win32::OLE::NLS::GetLocaleInfo($lcid, Win32::OLE::NLS::LOCALE_IDEFAULTANSICODEPAGE());

		$locale = "cp$linfo";

	} elsif ($^O =~ /darwin/) {

		# I believe this is correct from reading:
		# http://developer.apple.com/documentation/MacOSX/Conceptual/SystemOverview/FileSystem/chapter_8_section_6.html
		$locale = 'utf8';

	} else {

		my $lc = POSIX::setlocale(LC_CTYPE) || 'C';

		# If the locale is C or POSIX, that's ASCII - we'll set to iso-8859-1
		# Otherwise, normalize the codeset part of the locale.
		if ($lc eq 'C' || $lc eq 'POSIX') {
			$lc = 'iso-8859-1';
		} else {
			$lc = lc((split(/\./, $lc))[1]);
		}

		# Locale can end up with nothing, if it's invalid, such as "en_US"
		if (!defined $lc || $lc =~ /^\s*$/) {
			$lc = 'iso-8859-1';
		}

		# Sometimes underscores can be aliases - Solaris
		$lc =~ s/_/-/g;

		# ISO encodings with 4 or more digits use a hyphen after "ISO"
		$lc =~ s/^iso(\d{4})/iso-$1/;

		# Special case ISO 2022 and 8859 to be nice
		$lc =~ s/^iso-(2022|8859)([^-])/iso-$1-$2/;

		$lc =~ s/utf-8/utf8/gi;

		$locale = $lc;
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
		
	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @paths, $ENV{'HOME'} . "/Library/SlimDevices/bin/";
		push @paths, "/Library/SlimDevices/bin/";
		push @paths, $ENV{'HOME'} . "/Library/iTunes/Scripts/iTunes-LAME.app/Contents/Resources/";
	}

	if (Slim::Utils::OSDetect::OS() ne "win") {
		push @paths, (split(/:/, $ENV{'PATH'}),'/usr/bin','/usr/local/bin','/sw/bin');
	} else {
		$executable .= '.exe';
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
	
	$::d_paths && msgf("Found binary %s for %s\n", defined $path ? $path : 'undef', $executable);

	return $path;	
}

sub pathFromWinShortcut {
	my $fullpath = pathFromFileURL(shift);

	my $path = "";

	if (Slim::Utils::OSDetect::OS() ne "win") {
		$::d_files && msg("Windows shortcuts not supported on non-windows platforms\n");
		return $path;
	}

	my $shortcut = Win32::Shortcut->new($fullpath);
	if (defined($shortcut)) {

		$path = $shortcut->Path();
		# the following pattern match throws out the path returned from the
		# shortcut if the shortcut is contained in a child directory of the path
		# to avoid simple loops, loops involving more than one shortcut are still
		# possible and should be dealt with somewhere, just not here.
		if (defined($path) && !$path eq "" && $fullpath !~ /^\Q$path\E/i) {

			$path = fileURLFromPath($path);

			#collapse shortcuts to shortcuts into a single hop
			if (Slim::Music::Info::isWinShortcut($path)) {
				$path = pathFromWinShortcut($path);
			}

		} else {
			$::d_files && msg("Bad path in $fullpath\n");
			$::d_files && defined($path) && msg("Path was $path\n");
		}

	} else {
		$::d_files && msg("Shortcut $fullpath is invalid\n");
	}

	$::d_files && msg("pathFromWinShortcut: path $path from shortcut $fullpath\n");	

	return $path;
}

sub pathFromFileURL {
	my $url = shift;
	my $file;
	
	assert(Slim::Music::Info::isFileURL($url), "Path isn't a file URL: $url\n");

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
			$file = $uri->file() ;
		} 

	} else {
		msg("pathFromFileURL: $url isn't a file URL...\n");
		bt();
	}

	# convert from the utf8 back to the local codeset.
	if ($file && $] > 5.007) {
		eval { Encode::from_to($file, 'utf8', $locale) };
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
	
	return $path if (Slim::Music::Info::isURL($path));

	# convert from the the local codeset to utf8
	if ($path && $] > 5.007) {
		eval { Encode::from_to($path, $locale, 'utf8') };
	}

	my $uri  = URI::file->new($path);
	$uri->host('');
	return $uri->as_string;
}

sub utf8decode {
	my $string = shift;

	if ($string && $] > 5.007) {
		return Encode::decode('utf8', $string, Encode::FB_QUIET());
	}

	return $string;
}

sub utf8encode {
	my $string = shift;

	if ($string && $] > 5.007) {
		return Encode::encode('utf8', $string, Encode::FB_QUIET());
	}

	return $string;
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

# fixPathCase makes sure that we are using the actual casing of paths in
# a case-insensitive but case preserving filesystem.
# currently only implemented for Win32

sub fixPathCase {
	my $path = shift;
	
	if ($^O =~ /Win32/) {
		$path = Win32::GetLongPathName($path);
	}

	return canonpath($path);
}
		
# there's not really a better way to do this..
# fixPath takes relative file paths and puts the base path in the beginning
# to make them full paths, if possible.
# URLs are left alone
        
sub fixPath {
	my $file = shift || return;
	my $base = shift;

	my $fixed;

	if (Slim::Music::Info::isURL($file)) { 

		my $uri = URI->new($file);

		if ($uri->scheme() && $uri->scheme() eq 'file') {

			$uri->host('');
		}

		return $uri->as_string;
	}

	if (Slim::Music::Info::isFileURL($base)) {
		$base = Slim::Utils::Misc::pathFromFileURL($base);
	} 

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
	} elsif (Slim::Music::Info::isPlaylistURL($item)) {
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

	# Always turn the utf8 flag back on - pathFromFileURL 
	# (via virtualToAbsolute) will strip it.
	if ($ret && $] > 5.007) {
		Encode::_utf8_on($ret);
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
		
		if (Slim::Music::Info::isPlaylistURL($v[0])) {
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

	# Always unescape ourselves
	$virtual = Slim::Web::HTTP::unescape($virtual);

	# The incoming may be utf8 - flag it.
	if ($locale eq 'utf8') {
		Encode::_utf8_on($virtual);
	}

	return undef if (!$curdir);
	$curdir = fileURLFromPath($curdir);	
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
		#last if $level eq "..";

		# optimization for pre-cached imported playlists.
		if (Slim::Music::Info::isPlaylistURL($curdir)) {
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
	
	if (!$recursion && $virtual =~ /\.(.+)$/ && 
		exists $Slim::Formats::Parse::playlistInfo{$1} &&  
		$virtual !~ /^__playlists/ && !-e pathFromFileURL($curdir)) {

		# Not a real file, could be a naked saved playlist
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

	my $ignore = Slim::Utils::Prefs::get('ignoreDirRE') || '';

	opendir(DIR, $dirname) || do {
		warn "opendir failed: " . $dirname . ": $!\n";
		return @diritems;
	};

	for my $dir (readdir(DIR)) {

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
		
		if ($ignore ne '') {
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
	my $time = shift || time();
	my $date = localeStrftime(Slim::Utils::Prefs::get('longdateFormat'), $time);
	$date =~ s/\|0*//;
	return $date;
}

sub shortDateF {
	my $time = shift || time();
	my $date = localeStrftime(Slim::Utils::Prefs::get('shortdateFormat'),  $time);
	$date =~ s/\|0*//;
	return $date;
}

sub timeF {
	my $ltime = shift || time();
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
	
	# XXX - we display in utf8 now
	# these strings may come back as utf8, make sure they are latin1 when we display them
	# $time = utf8toLatin1($time);
	
	setlocale(LC_TIME, "");
	return $time;
}

sub fracSecToMinSec {
	my $seconds = shift;

	my ($min, $sec, $frac, $fracrounded);

	$min = int($seconds/60);
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
	my $msg = shift;
	
	defined($exp) && $exp && return;
	
	msg($msg) if $msg;
	
	bt();
}

sub bt {
	my $frame = 1;

	my $msg = "Backtrace:\n\n";

	my $assertfile = '';
	my $assertline = 0;

	while (my ($filename, $line, $subroutine) = (caller($frame++))[1,2,3]) {

		$msg .= sprintf("   frame %d: $subroutine ($filename line $line)\n", $frame - 2);

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

sub msg {
	use bytes;

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
	my $format = shift;

	msg(sprintf($format, @_));
}

sub delimitThousands {
	my $len = shift || return 0; 

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

	my @hostnames = ('localhost', hostname());
	
	foreach my $hostname (@hostnames) {

		next if !$hostname;

		if ($hostname =~ /^\d+(?:\.\d+(?:\.\d+(?:\.\d+)?)?)?$/) {
			push @hostaddr, addrToHost($hostname);
		} else {
			push @hostaddr, hostToAddr($hostname);
		}
	}

	return @hostaddr;
}

sub hostToAddr {
	my $host  = shift;
	my @addrs = (gethostbyname($host))[4];

	my $addr  = defined $addrs[0] ? inet_ntoa($addrs[0]) : $host;

	return $addr;
}

sub addrToHost {
	my $addr = shift;
	my $aton = inet_aton($addr);

	return $addr unless defined $aton;

	my $host = (gethostbyaddr($aton, Socket::AF_INET))[0];

	return $host if defined $host;
	return $addr;
}

sub stillScanning {
	return Slim::Music::Import::stillScanning();
}

sub utf8toLatin1 {
	my $data = shift;

	if ($] > 5.007) {

		$data = eval { Encode::encode('iso-8859-1', $data, Encode::FB_QUIET()) } || $data;

	} else {

		$data =~ s/([\xC0-\xDF])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg; 
		$data =~ s/[\xE2][\x80][\x99]/'/g;
	}

	return $data;
}

# this function based on a posting by Tom Christiansen: http://www.mail-archive.com/perl5-porters@perl.org/msg71350.html
sub at_eol($) { $_[0] =~ /\n\z/ }
sub sysreadline(*;$) { 
	my($handle, $maxnap) = @_;
	$handle = qualify_to_ref($handle, caller());

	return undef unless $handle;

	my $infinitely_patient = @_ == 1;

	my $start_time = Time::HiRes::time();

	# Try to use an existing IO::Select object if we have one.
	my $selector = ${*$handle}{'_sel'} || IO::Select->new($handle);

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
