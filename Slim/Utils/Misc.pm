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
use Fcntl qw(:seek);
use POSIX qw(strftime setlocale LC_TIME LC_CTYPE);
use Sys::Hostname;
use Socket qw(inet_ntoa inet_aton);
use Symbol qw(qualify_to_ref);
use URI;
use URI::file;

use Slim::Music::Info;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

if ($] > 5.007) {
	require Encode;
	require File::BOM;
}

use base qw(Exporter);

our @EXPORT = qw(assert bt msg msgf watchDog);
our $log    = "";
our $watch  = 0;

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

# Cache our user agent string.
my $userAgentString;

# Find out what code page we're in, so we can properly translate file/directory encodings.
our $locale = '';
our $utf8_re_bits;

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

	# Create a regex for looks_like_utf8()
	$utf8_re_bits = join "|", map { latin1toUTF8(chr($_)) } (127..255);
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

	# Reduce all the x86 architectures down to i386, so we only need one
	# directory per *nix OS.
	my $arch = $Config::Config{'archname'};

	   $arch =~ s/^i[3456]86-([^-]+).*$/i386-$1/;

	my $path;
	my @paths = (
		catdir($Bin, 'Bin', $arch),
		catdir($Bin, 'Bin', $^O),
		catdir($Bin, 'Bin'),
	);

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

		$::d_paths && msg("Checking for $executable in $path\n");

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

sub fileURLFromWinShortcut {
	my $shortcut = shift;

	return fixPath(pathFromWinShortcut($shortcut));
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
		if ($path !~ /[\/\\]\.\.[\/\\]/) {
			$file = $uri->file();
		} 

	} else {
		msg("pathFromFileURL: $url isn't a file URL...\n");
		bt();
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

	my $uri  = URI::file->new($path);
	$uri->host('');
	return $uri->as_string;
}

# Unicode / Encoding functions.

sub utf8decode {
	my $string = shift;

	# Bail early if it's just ascii
	if (looks_like_ascii($string)) {
		return $string;
	}

	my $orig = $string;

	if ($string && $] > 5.007 && !Encode::is_utf8($string)) {

		$string = Encode::decode('utf8', $string, Encode::FB_QUIET());

	} elsif ($string && $] > 5.007) {

		Encode::_utf8_on($string);
	}

	if ($string && $] > 5.007 && !looks_like_utf8($string)) {

		$string = $orig;
	}

	return $string;
}

sub utf8encode {
	my $string = shift;

	# Bail early if it's just ascii
	if (looks_like_ascii($string)) {
		return $string;
	}

	my $orig = $string;

	# Don't try to encode a string which isn't utf8
	# 
	# If the incoming string already is utf8, turn off the utf8 flag.
	if ($string && $] > 5.007 && !Encode::is_utf8($string)) {

		$string = Encode::encode('utf8', $string, Encode::FB_QUIET());

	} elsif ($string && $] > 5.007) {

		Encode::_utf8_off($string);
	}

	# Check for doubly encoded strings - and revert back to our original
	# string if that's the case.
	if ($string && $] > 5.007 && !looks_like_utf8($string)) {

		$string = $orig;
	}

	return $string;
}

sub utf8off {
	my $string = shift;

	if ($string && $] > 5.007) {
		Encode::_utf8_off($string);
	}

	return $string;
}

sub utf8on {
	my $string = shift;

	if ($string && $] > 5.007 && looks_like_utf8($string)) {
		Encode::_utf8_on($string);
	}

	return $string;
}

sub looks_like_ascii {
	use bytes;

	return 1 if $_[0] !~ /([^\x00-\x7F])/;
}

sub looks_like_latin1 {
	use bytes;

	return 1 if $_[0] !~ /([^\x00-\xFF])/;
}

sub looks_like_utf8 {
	use bytes;

	return 1 if $_[0] =~ /($utf8_re_bits)/o;
}

sub latin1toUTF8 {
	my $data = shift;

	if ($] > 5.007) {

		$data = eval { Encode::encode('utf8', $data, Encode::FB_QUIET()) } || $data;

	} else {

		$data =~ s/([\x80-\xFF])/chr(0xC0|ord($1)>>6).chr(0x80|ord($1)&0x3F)/eg;
	}

	return $data;
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

sub encodingFromString {

	my $encoding = 'raw';

	# Don't copy a potentially large string - just read it from the stack.
	if (looks_like_ascii($_[0])) {

		$encoding = 'ascii';

	} elsif (looks_like_utf8($_[0])) {
	
		$encoding = 'utf8';

	} elsif (looks_like_latin1($_[0])) {
	
		$encoding = 'iso-8859-1';
	}

	return $encoding;
}

sub encodingFromFileHandle {
	my $fh = shift;

	# If we didn't get a filehandle, not much we can do.
	if (!ref($fh) || !$fh->can('seek')) {

		msg("Warning: Not a filehandle in encodingFromFileHandle()\n");
		bt();

		return;
	}

	local $/ = undef;

	# Save the old position (if any)
	# And find the file size.
	#
	# These must be seek() and not sysseek(), as File::BOM uses seek(),
	# and they'll get confused otherwise.
	my $pos  = tell($fh);
	my $size = seek($fh, 0, SEEK_END);

	# Don't do any translation.
	binmode($fh, ":raw");

	# Try to find a BOM on the file - otherwise check the string
	#
	# Although get_encoding_from_filehandle tries to determine if
	# the handle is seekable or not - the Protocol handlers don't
	# implement a seek() method, and even if they did, File::BOM
	# internally would try to read(), which doesn't mix with
	# sysread(). So skip those m3u files entirely.
	my $enc = '';

	# Explitly check for IO::String - as it does have a seek() method!
	if ($] > 5.007 && ref($fh) && ref($fh) ne 'IO::String' && $fh->can('seek')) {
		$enc = File::BOM::get_encoding_from_filehandle($fh);
	}

	# File::BOM got something - let's get out of here.
	return $enc if $enc;

	# Seek to the beginning of the file.
	seek($fh, 0, SEEK_SET);

	#
	read($fh, my $string, $size);

	# Seek back to where we started.
	seek($fh, $pos, SEEK_SET);

	return encodingFromString($string);
}

# Handle either a filename or filehandle
sub encodingFromFile {
	my $file = shift;

	my $encoding = $locale;

	if (ref($file) && $file->can('seek')) {

		$encoding = encodingFromFileHandle($file);

	} elsif (-r $file) {

		my $fh = new FileHandle;
		$fh->open($file) or do {
			msg("Couldn't open file: [$file] : $!\n");
			return $encoding;
		};

		$encoding = encodingFromFileHandle($fh);

		$fh->close();

	} else {

		msg("Warning: Not a filename or filehandle encodingFromFile( $file )\n");
		bt();
	}

	return $encoding;
}

########

sub anchorFromURL {
	my $url = shift;

	if ($url =~ /#(.*)$/) {
		return $1;
	}
	return undef;
}

sub stripAnchorFromURL {
	my $url = shift;

	if ($url =~ /^(.*)#[\d\.]+-.*$/) {
		return $1;
	}

	return $url;
}

#################################################################################
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

	return '' unless $path;
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
		$base = pathFromFileURL($base);
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

			if (Slim::Utils::OSDetect::OS() eq "win") {

				# rel2abs will convert ../../ paths correctly only for windows
				$fixed = fixPath(rel2abs($file,$base));

			} else {

				$fixed = fixPath(stripRel(catfile($base, $file)));
			}
		}
	} elsif (file_name_is_absolute($file)) {
		$fixed = $file;
	} else {
		$file =~ s/\Q$audiodir\E//;
		$fixed = catfile($audiodir, $file);
	}

	# I hate Windows.
	# A playlist or the like can have a completely different case than
	# what we get from the filesystem. Fix that all up so we don't create
	# duplicate entries in the database.
	if (Slim::Utils::OSDetect::OS() eq "win" && !Slim::Music::Info::isFileURL($fixed)) {

		$fixed = fixPathCase($fixed);
	}

	$::d_paths && ($file ne $fixed) && msg("*****fixed: " . $file . " to " . $fixed . "\n");
	$::d_paths && ($file ne $fixed) && ($base) && msg("*****base: " . $base . "\n");

	if (Slim::Music::Info::isFileURL($fixed)) {
		return $fixed;
	} else {
		return fileURLFromPath($fixed);
	}
}

sub stripRel {
	my $file = shift;
	
	while ($file =~ m#[\/\\]\.\.[\/\\]#) {
		$file =~ s#\w+[\/\\]\.\.[\///]##isg;
	}
	
	$::d_paths && msg("stripRel result: $file\n");
	return $file;
}

sub virtualToAbsolute {
	my ($virtual, $recursion) = @_;

	my $curdir  = Slim::Utils::Prefs::get('audiodir') || return $virtual;

	if (!defined $virtual) {
		$virtual = ""
	}
	
	if (Slim::Music::Info::isURL($virtual)) {
		return $virtual;
	}
	
	if (file_name_is_absolute($virtual)) {
		$::d_paths && msg("virtualToAbsolute: $virtual is already absolute.\n");
		return $virtual;
	}

	# Always unescape ourselves
	$virtual = Slim::Web::HTTP::unescape($virtual);

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
			my $listref = Slim::Music::Info::cachedPlaylist(fileURLFromPath($curdir));
			if ($listref) {
				return @{$listref}[$level];
			}
		} 
		
		if (Slim::Music::Info::isPlaylist(fileURLFromPath($curdir))) {
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
				next if (Slim::Music::Info::isList(fileURLFromPath($curdir)));
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

		next if (Slim::Music::Info::isDir(fileURLFromPath($curdir)));

		if (Slim::Music::Info::isWinShortcut(fileURLFromPath($curdir))) {
			if (defined($Slim::Utils::Scan::playlistCache{fileURLFromPath($curdir)})) {
				$curdir = $Slim::Utils::Scan::playlistCache{fileURLFromPath($curdir)}
			} else {
				$curdir = pathFromWinShortcut(fileURLFromPath($curdir));
			}
		}
		#continue traversing if curdir is a list
		next if (Slim::Music::Info::isList(fileURLFromPath($curdir)));
		#otherwise stop traversing, non-list items cannot be traversed
		last;
	}
	
	$::d_paths && msg("became: $curdir\n");
	
	if (Slim::Music::Info::isFileURL($curdir)) {
		return $curdir;
	} else {
		return fileURLFromPath($curdir);  
	}
}

sub inPlaylistFolder {
	my $path = shift || return;

	# Fully qualify the path - and strip out any url prefix.
	$path = fixPath($path) || return 0;
	$path = virtualToAbsolute($path) || return 0;
	$path = pathFromFileURL($path) || return 0;

	my $playlistdir = Slim::Utils::Prefs::get("playlistdir");

	if ($playlistdir && $path =~ /^\Q$playlistdir\E/) {
		return 1;
	} else {
		return 0;
	}
}

my %_ignoredItems = (

	# always ignore . and ..
	'.' => 1,
	'..' => 1,

	# Items we should ignore on a mac volume
	'Icon' => 1,
	'TheVolumeSettingsFolder' => 1,
	'TheFindByContentFolder' => 1,
	'Network Trash Folder' => 1,
	'Desktop' => 1,
	'Desktop Folder' => 1,
	'Temporary Items' => 1,
	'.Trashes' => 1,
	'.AppleDB' => 1,
	'.AppleDouble' => 1,
	'.Metadata' => 1,
	'.DS_Store' => 1,

	# Items we should ignore on a linux vlume
	'lost+found' => 1,

	# Items we should ignore  on a Windows volume
	'System Volume Information' => 1,
	'RECYCLER' => 1,
	'Recycled' => 1,
);

sub readDirectory {
	my $dirname  = shift;
	my $validRE  = shift || Slim::Music::Info::validTypeExtensions();
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

	for my $item (readdir(DIR)) {

		next if exists $_ignoredItems{$item};

		# Ignore our special named files and directories
		next if $item =~ /^__/;  

		if ($ignore ne '') {
			next if $item =~ /$ignore/;
		}

		my $fullpath = catdir($dirname, $item);

		# We only want files, directories and symlinks Bug #441
		# Otherwise we'll try and read them, and bad things will happen.
		# symlink must come first so an lstat() is done.
		unless (-l $fullpath || -d _ || -f _) {
			next;
		}

		# Don't bother with file types we don't understand.
		if ($validRE && -f _) {
			next unless $item =~ $validRE;
		}
		elsif ($validRE && -l _ && defined(my $target = readlink($fullpath))) {
			# fix relative/absolute path
			$target = ($target =~ /^\// ? $target : catdir($dirname, $target));

			if (-f $target) {
				next unless $target =~ $validRE;
			}
		}

		push @diritems, $item;
	}

	closedir(DIR);
	
	$::d_files && msg("directory: $dirname contains " . scalar(@diritems) . " items\n");
	
	return sort(@diritems);
}

sub findAndScanDirectoryTree {
	my $levels   = shift;
	my $urlOrObj = shift || Slim::Utils::Misc::fileURLFromPath(Slim::Utils::Prefs::get('audiodir'));

	# Find the db entry that corresponds to the requested directory.
	# If we don't have one - that means we're starting out from the root audiodir.
	my $topLevelObj;
	my $ds = Slim::Music::Info::getCurrentDataStore();

	if (ref $urlOrObj) {

		$topLevelObj = $urlOrObj;

	} elsif (scalar @$levels) {

		$topLevelObj = $ds->objectForId('track', $levels->[-1]);

	} else {

		$topLevelObj = $ds->objectForUrl($urlOrObj, 1, 1, 1) || return;

		push @$levels, $topLevelObj->id;
	}

	if (!defined $topLevelObj || !ref $topLevelObj) {

		msg("Error: Couldn't find a topLevelObj for findAndScanDirectoryTree()\n");

		if (scalar @$levels) {
			msgf("Passed in value was: [%s]\n", $levels->[-1]);
		} else {
			msg("Starting from audiodir! Is it not set?\n");
		}

		return ();
	}

	# Check for changes - these can be adds or deletes.
	# Do a realtime scan - don't send anything to the scheduler.
	my $path    = $topLevelObj->path;
	my $fsMTime = (stat($path))[9] || 0;
	my $dbMTime = $topLevelObj->timestamp || 0;

	if ($fsMTime != $dbMTime) {

		if ($::d_scan) {
			msg("mtime db: $dbMTime : " . localtime($dbMTime) . "\n");
			msg("mtime fs: $fsMTime : " . localtime($fsMTime) . "\n");
		}

		# Update the mtime in the db.
		$topLevelObj->timestamp($fsMTime);

		# Do a quick directory scan.
		Slim::Utils::Scan::addToList([], $path, 0, undef, sub {});
	}

	# Now read the raw directory and return it. This should always be really fast.
	my $items = [ Slim::Music::Info::sortFilename( readDirectory( $topLevelObj->path ) ) ];
	my $count = scalar @$items;

	return ($topLevelObj, $items, $count);
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

	# we can't display japanese or chinese, etc right now.
	unless ($Slim::Player::Client::validClientLanguages{$language}) {
		$language = $Slim::Player::Client::failsafeLanguage;
	}

	(my $country = $language) =~ tr/a-z/A-Z/;

	# This is for when we can display japanese on the display.
	# We might want to consider changing s/JP/JA/ in strings.txt ?
	if ($language eq 'jp') {
		$language = 'ja';
	}
	
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

# Utility functions for strings we send out to the world.
sub userAgentString {

	if (defined $userAgentString) {
		return $userAgentString;
	}

	my $osDetails = Slim::Utils::OSDetect::details();

	# We masquerade as iTunes for radio stations that really want it.
	$userAgentString = sprintf("iTunes/4.7.1 (%s; N; %s; %s; %s; %s) SlimServer/$::VERSION/$::REVISION",

		$osDetails->{'os'},
		$osDetails->{'osName'},
		($osDetails->{'osArch'} || 'Unknown'),
		Slim::Utils::Prefs::get('language'),
		$locale,
	);

	return $userAgentString;
}

sub settingsDiagString {

	my $osDetails = Slim::Utils::OSDetect::details();

	# We masquerade as iTunes for radio stations that really want it.
	my $diagString = sprintf("%s%s %s - %s - %s - %s - %s",

		string('SERVER_VERSION'),
		string('COLON'),
		$::VERSION,
		$::REVISION,
		$osDetails->{'osName'},
		Slim::Utils::Prefs::get('language'),
		$Slim::Utils::Misc::locale,
	);

	return $diagString;
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

	my $host = (gethostbyaddr($aton, Socket::AF_INET()))[0];

	return $host if defined $host;
	return $addr;
}

sub stillScanning {
	return Slim::Music::Import::stillScanning();
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

# Use Tie::Watch to keep track of a variable, and report when it changes.
sub watchVariable {
	my $var = shift;

	unless ($watch) {
		eval "use Tie::Watch";

		if ($@) {
			return;
		} else {
			$watch = 1;
		}
	}

	# See the Tie::Watch manpage for more info.
	Tie::Watch->new(
		-variable => $var,
		-shadow   => 0,

		-clear    => sub {
			msg("In clear callback for $var!\n");
			bt();
		},

		-destroy  => sub {
			msg("In destroy callback for $var!\n");
			bt();
		},

		-fetch   => sub {
			my ($self, $key) = @_;

			my $val  = $self->Fetch($key);
			my $args = $self->Args(-fetch);

			bt();
			msgf("In fetch callback, key=$key, val=%s, args=('%s')\n",
				$self->Say($val), ($args ? join("', '",  @$args) : 'undef')
			);

			return $val;
		},

		-store    => sub {
			my ($self, $key, $new_val) = @_;

			my $val  = $self->Fetch($key);
			my $args = $self->Args(-store);

			$self->Store($key, $new_val);

			bt();
			msgf("In store callback, key=$key, val=%s, new_val=%s, args=('%s')\n",
				$self->Say($val), $self->Say($new_val), ($args ? join("', '",  @$args) : 'undef')
			);

			return $new_val;
		},
	);
}

sub deparseCoderef {
	my $coderef = shift;

	eval "use B::Deparse ()";
	my $deparse = B::Deparse->new('-si8T') unless $@ =~ /Can't locate/;

	eval "use Devel::Peek ()";
	my $peek = 1 unless $@ =~ /Can't locate/;

	return 0 unless $deparse;
		
	my $body = $deparse->coderef2text($coderef) || return 0;
	my $name;

	if ($peek) {
		my $gv = Devel::Peek::CvGV($coderef);
		$name  = join('::', *$gv{'PACKAGE'}, *$gv{'NAME'});
	}

	$name ||= 'ANON';

	return "sub $name $body";
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
