package Slim::Utils::Misc;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Exporter);

our @EXPORT = qw(assert bt msg msgf watchDog errorMsg specified);

use Cwd ();
use File::Spec::Functions qw(:ALL);
use File::Which ();
use FindBin qw($Bin);
use POSIX qw(strftime);
use Scalar::Util qw(blessed);
use Time::HiRes;
use URI;
use URI::Escape;
use URI::file;

# These must be 'required', as they use functions from the Misc module!
require Slim::Music::Info;
require Slim::Player::ProtocolHandlers;
require Slim::Utils::OSDetect;
require Slim::Utils::Scanner;
require Slim::Utils::Strings;
require Slim::Utils::Unicode;
require Slim::Utils::DateTime;

our $log = "";

our %pathToFileCache = ();
our %fileToPathCache = ();

{
	if ($^O =~ /Win32/) {
		require Win32;
		require Win32::API;
		require Win32::File;
		require Win32::FileOp;
		require Win32::Process;
		require Win32::Shortcut;
	}
}

# Cache our user agent string.
my $userAgentString;

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
		Slim::Utils::OSDetect::dirsFor('Bin'),
	);

	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @paths, $ENV{'HOME'} . "/Library/SlimDevices/bin/";
		push @paths, "/Library/SlimDevices/bin/";
		push @paths, $ENV{'HOME'} . "/Library/iTunes/Scripts/iTunes-LAME.app/Contents/Resources/";
	}

	if (Slim::Utils::OSDetect::OS() ne "win") {

		push @paths, (split(/:/, $ENV{'PATH'}), qw(/usr/bin /usr/local/bin /sw/bin /usr/sbin));

	} else {

		push @paths, 'C:\Perl\bin';

		# Don't add .exe on - we may be looking for a .bat file.
		if ($executable !~ /\.\w{3}$/) {

			$executable .= '.exe';
		}
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

sub setPriority {
	my $priority = shift;

	# By default, set the Windows priority to be high - so we get swapped
	# back in faster, and have a less likely chance of being swapped out
	# in the first place.
	# 
	# For *nix, including OSX, set whatever priority the user gives us.
	if (Slim::Utils::OSDetect::OS() eq 'win') {

		my $getCurrentProcess = Win32::API->new('kernel32', 'GetCurrentProcess', ['V'], 'N');
		my $setPriorityClass  = Win32::API->new('kernel32', 'SetPriorityClass',  ['N', 'N'], 'N');

		if (blessed($setPriorityClass) && blessed($getCurrentProcess)) {

			my $processHandle = eval { $getCurrentProcess->Call(0) };

			if (!$processHandle || $@) {

				errorMsg("setPriority: Can't get process handle ($^E) [$@]\n");
				return;
			};

			eval { $setPriorityClass->Call($processHandle, Win32::Process::NORMAL_PRIORITY_CLASS()) };

			if ($@) {
				errorMsg("setPriority: Couldn't set priority to NORMAL ($^E) [$@]\n");
			}
		}

	} elsif ($priority) {

		$::d_server && msg("SlimServer - changing process priority to $priority\n");
                eval { setpriority (0, 0, $priority); };
	}
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
	my $file = '';

	if ($fileToPathCache{$url}) {
		return $fileToPathCache{$url};
	}
	
	assert(Slim::Music::Info::isFileURL($url), "Path isn't a file URL: $url\n");

	# Bug: 1786
	#
	# Work around a perl bug that exists in 5.8.0, 5.8.1 & 5.8.2? - where
	# a join() can return garbage because it's internal scratch space
	# wasn't properly cleared with a UTF8 string that previously went
	# through it. The call to $uri->file() below contains such a join, and
	# was causing bogus data to be returned on OSX 10.3.x systems.
	#
	# See
	# http://lists.bestpractical.com/pipermail/rt-devel/2004-January/005283.html
	# for some more information.
	if ($] > 5.007 && $] <= 5.008002) {

		$url = Slim::Utils::Unicode::utf8off($url);
	}
	
	# Bug 3589, support win32 backslashes in URLs, file://C:\foo\bar
	$url =~ s/\\/\//g;

	my $uri = URI->new($url);

	# TODO - FIXME - this isn't mac or dos friendly with the path...
	# Use File::Spec::rel2abs ? or something along those lines?
	#
	# file URLs must start with file:/// or file://localhost/ or file://\\uncpath
	if ($uri->scheme() eq 'file') {

		my $path = $uri->path();

		$::d_files && msg("Got $path from file url $url\n");

		# only allow absolute file URLs and don't allow .. in files...
		if ($path !~ /[\/\\]\.\.[\/\\]/) {
			$file = fixPathCase($uri->file);
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

	if (scalar keys %fileToPathCache > 32) {
		%fileToPathCache = ();
	}

	$fileToPathCache{$url} = $file;

	return $file;
}

sub fileURLFromPath {
	my $path = shift;

	if ($pathToFileCache{$path}) {
		return $pathToFileCache{$path};
	}

	return $path if (Slim::Music::Info::isURL($path));

	my $uri  = URI::file->new( fixPathCase($path) );
	   $uri->host('');

	my $file = $uri->as_string;

	if (scalar keys %pathToFileCache > 32) {
		%pathToFileCache = ();
	}

	$pathToFileCache{$path} = $file;

	return $file;
}

########

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

# don't use the external one because it doesn't know about the difference
# between a param and not...
#*unescape = \&URI::Escape::unescape;
sub unescape {
	my $in      = shift;
	my $isParam = shift;

	$in =~ s/\+/ /g if $isParam;
	$in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	return $in;
}

# See http://www.onlamp.com/pub/a/onlamp/2006/02/23/canary_trap.html
sub removeCanary {
	my $string = shift;

	for (my $i = 0;  ++$i <= 5;) {  

		last if $$string =~ s/^=://;

		$$string = unescape($$string);

		last if $$string =~ s/^=://;
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

	my $urlstring = join('|', Slim::Player::ProtocolHandlers->registeredHandlers);

	$string =~ m|[$urlstring]://(?:([^\@:]+):?([^\@]*)\@)?([^:/]+):*(\d*)(\S*)|i;
	
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

# fixPathCase makes sure that we are using the actual casing of paths in
# a case-insensitive but case preserving filesystem.
sub fixPathCase {
	my $path = shift;
	my $orig = $path;

	if ($^O =~ /Win32/) {
		$path = Win32::GetLongPathName($path);
	}

	# abs_path() will resolve any case sensetive filesystem issues (HFS+)
	# But don't for the bogus path we use with embedded cue sheets.
	if ($^O eq 'darwin' && $path !~ m|^/BOGUS/PATH|) {
		$path = Cwd::abs_path($path);
	}

	# Use the original path if we didn't get anything back from
	# GetLongPathName - this can happen if a cuesheet references a
	# non-existant .wav file, which is often the case.
	#
	# At that point, we'd return a bogus value, and start crawling at the
	# top of the directory tree, which isn't what we want.
	return $path || $orig;
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

		my $uri = URI->new($file) || return $file;

		if ($uri->scheme() eq 'file') {

			$uri->host('');
		}

		return $uri->as_string;
	}

	if (Slim::Music::Info::isFileURL($base)) {
		$base = pathFromFileURL($base);
	} 

	# People sometimes use playlists generated on Windows elsewhere.
	# See Bug 236
	if (Slim::Utils::OSDetect::OS() ne 'win') {

		$file =~ s/^[C-Z]://i;
		$file =~ s/\\/\//g;
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

	# I hate Windows & HFS+.
	# A playlist or the like can have a completely different case than
	# what we get from the filesystem. Fix that all up so we don't create
	# duplicate entries in the database.
	if (!Slim::Music::Info::isFileURL($fixed)) {

		if (Slim::Utils::OSDetect::OS() eq "win") {

			my ($volume, $dirs, $file) = splitpath($fixed);

			# Look for UNC paths
			if ($volume && $volume =~ m|^\\|) {

				# And map them to drive letters.
				$volume = Win32::FileOp::Mapped($volume);

				if ($volume && $volume =~ /^[A-Z]:/) {

					$fixed = catfile($volume, $dirs, $file);
				}
			}
		}

		$fixed = canonpath(fixPathCase($fixed));

		# Bug: 2757
		if (-l $fixed) {

			$fixed = readlink($fixed);
		}
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
		$file =~ s#[^\/\\]+[\/\\]\.\.[\/\\]##sg;
	}
	
	$::d_paths && msg("stripRel result: $file\n");
	return $file;
}

sub inAudioFolder {
	return _checkInFolder(shift, 'audiodir');
}

sub inPlaylistFolder {
	return _checkInFolder(shift, 'playlistdir');
}

sub _checkInFolder {
	my $path = shift || return;
	my $pref = shift;

	# Fully qualify the path - and strip out any url prefix.
	$path = fixPath($path) || return 0;
	$path = pathFromFileURL($path) || return 0;

	my $checkdir = Slim::Utils::Prefs::get($pref);

	if ($checkdir && $path =~ /^\Q$checkdir\E/) {
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

		# Ignore special named files and directories
		# __ is a match against our old __history and __mac playlists.
		# ._Foo is a OS X meta file.
		next if $item =~ /^__\S+\.m3u$/;
		next if $item =~ /^\._/;

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

	if (blessed($urlOrObj)) {

		$topLevelObj = $urlOrObj;

	} elsif (scalar @$levels) {

		$topLevelObj = Slim::Schema->find('Track', $levels->[-1]);

	} else {

		$topLevelObj = Slim::Schema->rs('Track')->objectForUrl({
			'url'      => $urlOrObj,
			'create'   => 1,
			'readTags' => 1,
			'commit'   => 1,
		});

		if (blessed($topLevelObj) && $topLevelObj->can('id')) {

			push @$levels, $topLevelObj->id;
		}
	}

	if (!blessed($topLevelObj) || !$topLevelObj->can('path')) {

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
		$topLevelObj->update;

		# Do a quick directory scan.
		Slim::Utils::Scanner->scanDirectory({
			'url'       => $path,
			'recursive' => 0,
		});
	}

	# Now read the raw directory and return it. This should always be really fast.
	my $items = [ Slim::Music::Info::sortFilename( readDirectory($path) ) ];
	my $count = scalar @$items;

	return ($topLevelObj, $items, $count);
}


# Deprecated, use Slim::Utils::DateTime instead
sub longDateF {
	return Slim::Utils::DateTime::longDateF(@_);
}

sub shortDateF {
	return Slim::Utils::DateTime::shortDateF(@_);
}

sub timeF {
	return Slim::Utils::DateTime::timeF(@_);
}

sub fracSecToMinSec {
	return Slim::Utils::DateTime::fracSecToMinSec(@_);
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
		Slim::Utils::Unicode::currentLocale(),
	);

	return $userAgentString;
}

sub settingsDiagString {

	my $osDetails = Slim::Utils::OSDetect::details();

	# We masquerade as iTunes for radio stations that really want it.
	my $diagString = sprintf("%s%s %s - %s - %s - %s - %s",

		Slim::Utils::Strings::string('SERVER_VERSION'),
		Slim::Utils::Strings::string('COLON'),
		$::VERSION,
		$::REVISION,
		$osDetails->{'osName'},
		Slim::Utils::Prefs::get('language'),
		Slim::Utils::Unicode::currentLocale(),
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
	my $return = shift || 0;

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

	return $msg if $return;

	&msg($msg);
}

sub msg {
	use bytes;
	my $entry = shift;
	my $forceLog = shift || 0;

	if ( $::LogTimestamp ) {
		my $now = substr(int(Time::HiRes::time() * 10000),-4);
		$entry = join( "", strftime( "%Y-%m-%d %H:%M:%S.", localtime ),
			$now , ' ' , $entry );
	}

	print STDERR $entry;
	
	if ($forceLog || Slim::Utils::Prefs::get('livelog')) {
		 $Slim::Utils::Misc::log .= $entry;
		 $Slim::Utils::Misc::log = substr($Slim::Utils::Misc::log, -Slim::Utils::Prefs::get('livelog'));
	}
}

sub msgf {
	my $format = shift;

	msg(sprintf($format, @_));
}

sub errorMsg {
	my $msg = shift;

	# Force an error message & write to the log.
	msg("ERROR: $msg\n", 1);
}

sub delimitThousands {
	my $len = shift || return 0; 

	my $sep = Slim::Utils::Strings::string('THOUSANDS_SEP');

	0 while $len =~ s/^(-?\d+)(\d{3})/$1$sep$2/;
	return $len;
}

# defined, but does not contain a *
sub specified {
	my $i = shift;

	return 0 if ref($i) eq 'ARRAY';
	return 0 unless defined $i;
	return $i !~ /\*/;
}


1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
