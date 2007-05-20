package Slim::Utils::Misc;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::Misc

=head1 SYNOPSIS

use Slim::Utils::Misc qw(msg errorMsg);

msg("This is a log message\n");

=head1 EXPORTS

assert, bt, msg, msgf, watchDog, errorMsg, specified

=head1 DESCRIPTION

L<Slim::Utils::Misc> serves as a collection of miscellaneous utility 
 functions useful throughout slimserver and third party plugins.

=cut

use strict;
use Exporter::Lite;

our @EXPORT = qw(assert bt msg msgf watchDog errorMsg specified);

use Config;
use Cwd ();
use File::Spec::Functions qw(:ALL);
use File::Which ();
use FindBin qw($Bin);
use Log::Log4perl;
use Net::IP;
use POSIX qw(strftime);
use Scalar::Util qw(blessed);
use Time::HiRes;
use URI;
use URI::Escape;
use URI::file;

# These must be 'required', as they use functions from the Misc module!
require Slim::Music::Info;
require Slim::Player::ProtocolHandlers;
require Slim::Utils::DateTime;
require Slim::Utils::OSDetect;
require Slim::Utils::Strings;
require Slim::Utils::Unicode;

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

{
	if ($^O =~ /Win32/) {
		require Win32;
		require Win32::API;
		require Win32::File;
		require Win32::FileOp;
		require Win32::Process;
		require Win32::Service;
		require Win32::Shortcut;
	}
}

# Cache our user agent string.
my $userAgentString;

my %pathToFileCache = ();
my %fileToPathCache = ();

=head1 METHODS

=head2 findbin( $executable)

	Little bit of magic to find the executable program given by the string $executable.

=cut

sub findbin {
	my $executable = shift;

	my $log = logger('os.paths');

	$log->debug("Looking for executable: [$executable]");

	# Reduce all the x86 architectures down to i386, so we only need one
	# directory per *nix OS.
	my $arch = $Config::Config{'archname'};

	   $arch =~ s/^i[3456]86-([^-]+).*$/i386-$1/;

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

		push @paths, (split(/:/, $ENV{'PATH'}), qw(/usr/bin /usr/local/bin /usr/libexec /sw/bin /usr/sbin));

	} else {

		push @paths, 'C:\Perl\bin';

		# Don't add .exe on - we may be looking for a .bat file.
		if ($executable !~ /\.\w{3}$/) {

			$executable .= '.exe';
		}
	}

	for my $path (@paths) {

		$path = catdir($path, $executable);

		$log->debug("Checking for $executable in $path");

		if (-x $path) {

			$log->info("Found binary $path for $executable");

			return $path;
		}
	}

	# Couldn't find it in the environment? Look on disk..
	# XXXX - why only windows? Security issue?
	if (Slim::Utils::OSDetect::OS() eq "win" && (my $path = File::Which::which($executable))) {

		$log->info("Found binary $path for $executable");

		return $path;

	} else {

		$log->warn("Didn't find binary for $executable");

		return undef;
	}
}

=head2 setPriority( $priority )

Set the priority for the server. $priority should be -20 to 20

=cut

sub setPriority {
	my $priority = shift || return;

	# For *nix, including OSX, set whatever priority the user gives us.
	# For win32, translate the priority to a priority class and use that

	if (Slim::Utils::OSDetect::OS() eq 'win') {

		my ($priorityClass, $priorityClassName) = _priorityClassFromPriority($priority);

		my $getCurrentProcess = Win32::API->new('kernel32', 'GetCurrentProcess', ['V'], 'N');
		my $setPriorityClass  = Win32::API->new('kernel32', 'SetPriorityClass',  ['N', 'N'], 'N');

		if (blessed($setPriorityClass) && blessed($getCurrentProcess)) {

			my $processHandle = eval { $getCurrentProcess->Call(0) };

			if (!$processHandle || $@) {

				logError("Can't get process handle ($^E) [$@]");
				return;
			};

			logger('server')->info("SlimServer changing process priority to $priorityClassName");

			eval { $setPriorityClass->Call($processHandle, $priorityClass) };

			if ($@) {
				logError("Couldn't set priority to $priorityClassName ($^E) [$@]");
			}
		}

	} else {

		logger('server')->info("SlimServer changing process priority to $priority");

		eval { setpriority (0, 0, $priority); };

		if ($@) {
			logError("Couldn't set priority to $priority [$@]");
		}
	}
}

=head2 getPriority( )

Get the current priority of the server.

=cut

sub getPriority {

	if (Slim::Utils::OSDetect::OS() eq 'win') {

		my $getCurrentProcess = Win32::API->new('kernel32', 'GetCurrentProcess', ['V'], 'N');
		my $getPriorityClass  = Win32::API->new('kernel32', 'GetPriorityClass',  ['N'], 'N');

		if (blessed($getPriorityClass) && blessed($getCurrentProcess)) {

			my $processHandle = eval { $getCurrentProcess->Call(0) };

			if (!$processHandle || $@) {

				logError("Can't get process handle ($^E) [$@]");
				return;
			};

			my $priorityClass = eval { $getPriorityClass->Call($processHandle) };

			if ($@) {
				logError("Can't get priority class ($^E) [$@]");
			}

			return _priorityFromPriorityClass($priorityClass);
		}

	} else {

		my $priority = eval { getpriority (0, 0) };

		if ($@) {
			logError("Can't get priority [$@]");
		}

		return $priority;
	}
}

# Translation between win32 and *nix priorities
# is as follows:
# -20  -  -16  HIGH
# -15  -   -6  ABOVE NORMAL
#  -5  -    4  NORMAL
#   5  -   14  BELOW NORMAL
#  15  -   20  LOW

sub _priorityClassFromPriority {
	my $priority = shift;

	# ABOVE_NORMAL_PRIORITY_CLASS and BELOW_NORMAL_PRIORITY_CLASS aren't
	# provided by Win32::Process so their values have been hardcoded.

	if ($priority <= -16 ) {
		return (Win32::Process::HIGH_PRIORITY_CLASS(), "HIGH");
	} elsif ($priority <= -6) {
		return (0x00008000, "ABOVE_NORMAL");
	} elsif ($priority <= 4) {
		return (Win32::Process::NORMAL_PRIORITY_CLASS(), "NORMAL");
	} elsif ($priority <= 14) {
		return (0x00004000, "BELOW_NORMAL");
	} else {
		return (Win32::Process::IDLE_PRIORITY_CLASS(), "LOW");
	}
}

sub _priorityFromPriorityClass {
	my $priorityClass = shift;

	if ($priorityClass == 0x00000100) { # REALTIME
		return -20;
	} elsif ($priorityClass == Win32::Process::HIGH_PRIORITY_CLASS()) {
		return -16;
	} elsif ($priorityClass == 0x00008000) {
		return -6;
	} elsif ($priorityClass == 0x00004000) {
		return 5;
	} elsif ($priorityClass == Win32::Process::IDLE_PRIORITY_CLASS()) {
		return 15;
	} else {
		return 0;
	}
}

=head2 pathFromWinShortcut( $path )

Return the filepath for a given Windows Shortcut

=cut

sub pathFromWinShortcut {
	my $fullpath = pathFromFileURL(shift);

	my $path = "";
	my $log  = logger('os.files');

	if (Slim::Utils::OSDetect::OS() ne "win") {

		logWarning("Windows shortcuts not supported on non-windows platforms!");

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

			$log->error("Error: Bad path in $fullpath - path was: [$path]");
		}

	} else {

		$log->error("Error: Shortcut $fullpath is invalid");
	}

	$log->info("Got path $path from shortcut $fullpath");

	return $path;
}

=head2 fileURLFromWinShortcut( $shortcut)

	Special case to convert a windows shortcut to a normalised file:// url.

=cut

sub fileURLFromWinShortcut {
	my $shortcut = shift;

	return fixPath(pathFromWinShortcut($shortcut));
}

=head2 pathFromFileURL( $url, [ $noCache ])

	Given a file::// style url, return the filepath to the caller

	If the option $noCache argument is set, the result is  not cached

=cut

sub pathFromFileURL {
	my $url     = shift;
	my $noCache = shift || 0;

	if (!$noCache && $fileToPathCache{$url}) {
		return $fileToPathCache{$url};
	}

	if ($url !~ /^file:\/\//i) {

		logWarning("Path isn't a file URL: $url");

		return $url;
	}

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

	my $uri  = URI->new($url);
	my $file = undef;

	# TODO - FIXME - this isn't mac or dos friendly with the path...
	# Use File::Spec::rel2abs ? or something along those lines?
	#
	# file URLs must start with file:/// or file://localhost/ or file://\\uncpath
	my $path = $uri->path;
	my $log  = logger('os.files');

	if (Slim::Utils::Log->isInitialized) {

		$log->info("Got $path from file url $url");
	}

	# only allow absolute file URLs and don't allow .. in files...
	if ($path !~ /[\/\\]\.\.[\/\\]/) {

		$file = fixPathCase($uri->file);
	}

	if (Slim::Utils::Log->isInitialized) {

		if (!defined($file))  {
			$log->warn("Bad file: url $url");
		} else {
			$log->info("Extracted: $file from $url");
		}
	}

	if (!$noCache && scalar keys %fileToPathCache > 32) {
		%fileToPathCache = ();
	}

	if (!$noCache) {
		$fileToPathCache{$url} = $file;
	}

	return $file;
}

=head2 fileURLFromPath( $path)

	Create file:// url from a supplied $path

=cut

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

=head2 crackURL( $string )

Split a URL $string into (host, port, path)

This relies on the schemes as specified by any registered handlers.

Otherwise we could use L<URI>

=cut

sub crackURL {
	my ($string) = @_;

	my $urlstring = join('|', Slim::Player::ProtocolHandlers->registeredHandlers);

	$string =~ m|[$urlstring]://(?:([^\@:]+):?([^\@]*)\@)?([^:/]+):*(\d*)(\S*)|i;
	
	my ($user, $pass, $host, $port, $path) = ($1, $2, $3, $4, $5);

	$path ||= '/';
	$port ||= 80;

	my $log = logger('os.paths');

	$log->debug("Cracked: $string with [$host],[$port],[$path]");
	$log->debug("   user: [$user]") if $user;
	$log->debug("   pass: [$pass]") if $pass;

	return ($host, $port, $path, $user, $pass);
}

=head2 fixPathCase( $path )

	fixPathCase makes sure that we are using the actual casing of paths in
	a case-insensitive but case preserving filesystem.

=cut

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
		

=head2 fixPath( $file, $base)

	fixPath takes relative file paths and puts the base path in the beginning
	to make them full paths, if possible.
	URLs are left alone

=cut

# there's not really a better way to do this..
sub fixPath {
	my $file = shift;
	my $base = shift;

	if (!defined($file)) {
		return;
	}

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
	my $audiodir = $prefs->get('audiodir');
	my $savedplaylistdir = $prefs->get('playlistdir');

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

		# Don't map drive letters when running as a service.
		if (Slim::Utils::OSDetect::OS() eq "win" && !$PerlSvc::VERSION) {

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

		# Fixes Bug: 2757, but breaks a lot more: 3681, 3682 & 3683
		if (-l $fixed) {

			#$fixed = readlink($fixed);
		}
	}

	if ($file ne $fixed) {

		logger('os.paths')->info("Fixed: $file to $fixed");

		if ($base) {
			logger('os.paths')->info("Base: $base");
		}
	}

	if (Slim::Music::Info::isFileURL($fixed)) {
		return $fixed;
	} else {
		return fileURLFromPath($fixed);
	}
}

sub stripRel {
	my $file = shift;
	
	logger('os.paths')->info("Original: $file");

	while ($file =~ m#[\/\\]\.\.[\/\\]#) {
		$file =~ s#[^\/\\]+[\/\\]\.\.[\/\\]##sg;
	}
	
	logger('os.paths')->info("Stripped: $file");

	return $file;
}

=head2 inAudioFolder( $)

	Check if argument is an item contained in the music folder tree

=cut

sub inAudioFolder {
	return _checkInFolder(shift, 'audiodir');
}

=head2 inPlaylistFolder( $)

	Check if argument is an item contained in the playlist folder tree

=cut

sub inPlaylistFolder {
	return _checkInFolder(shift, 'playlistdir');
}

sub _checkInFolder {
	my $path = shift || return;
	my $pref = shift;

	# Fully qualify the path - and strip out any url prefix.
	$path = fixPath($path) || return 0;
	$path = pathFromFileURL($path) || return 0;

	my $checkdir = $prefs->get($pref);

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

=head2 readDirectory( $dirname, [ $validRE ])

	Return the contents of a directory $dirname as an array.  Optionally return only 
	those items that match a regular expression given by $validRE

=cut

sub readDirectory {
	my $dirname  = shift;
	my $validRE  = shift || Slim::Music::Info::validTypeExtensions();
	my @diritems = ();
	my $log      = logger('os.files');

	my $ignore = $prefs->get('ignoreDirRE') || '';

	opendir(DIR, $dirname) || do {

		logError("opendir on [$dirname] failed: $!");

		return @diritems;
	};

	$log->info("Reading directory: $dirname");

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

		# call idle streams to service timers - used for blocking animation.
		if (scalar @diritems % 3) {
			main::idleStreams();
		}

		push @diritems, $item;
	}

	closedir(DIR);

	$log->info("Directory contains " . scalar(@diritems) . " items");

	return sort(@diritems);
}

=head2 findAndScanDirectoryTree($params)

Finds and scans a directory tree, starting from a variety of datums as defined by $params. Returns
the top level object, the items in the directory and their numbers.

$params is a hash with the following keys, by order of priority:
#obj: a track object (of content type 'dir')
#id: a track id
#url: a url
	

=cut

sub findAndScanDirectoryTree {
	my $params = shift;
	
	# Find the db entry that corresponds to the requested directory.
	# If we don't have one - that means we're starting out from the root audiodir.
	my $topLevelObj;
		
	if (blessed($params->{'obj'})) {

		$topLevelObj = $params->{'obj'};

	} elsif (defined($params->{'id'})) {

		$topLevelObj = Slim::Schema->find('Track', $params->{'id'});

	} else {
		
		my $url = $params->{'url'};
		
		# make sure we have a valid URL...
		if (!defined $url) {
			$url = Slim::Utils::Misc::fileURLFromPath($prefs->get('audiodir'));
		}

		$topLevelObj = Slim::Schema->rs('Track')->objectForUrl({
			'url'      => $url,
			'create'   => 1,
			'readTags' => 1,
			'commit'   => 1,
		});
	}

	if (!blessed($topLevelObj) || !$topLevelObj->can('path') || !$topLevelObj->can('id')) {

		logError("Couldn't find a topLevelObj!");

		return ();
	}

	# Check for changes - these can be adds or deletes.
	# Do a realtime scan - don't send anything to the scheduler.
	my $path    = $topLevelObj->path;
	my $fsMTime = (stat($path))[9] || 0;
	my $dbMTime = $topLevelObj->timestamp || 0;

	if ($fsMTime != $dbMTime) {

		logger('scan.scanner')->info("mtime db: $dbMTime : " . localtime($dbMTime));
		logger('scan.scanner')->info("mtime fs: $fsMTime : " . localtime($fsMTime));

		# Update the mtime in the db.
		$topLevelObj->timestamp($fsMTime);
		$topLevelObj->update;

		# Do a quick directory scan.
		Slim::Utils::Scanner->scanDirectory({
			'url'       => $path,
			'recursive' => 0,
		});

		# Bug: 3841 - check for new artwork
		# But don't search at the root level.
		if ($path ne $prefs->get('audiodir')) {

			Slim::Music::Artwork->findArtwork($topLevelObj);
		}
	}

	# Now read the raw directory and return it. This should always be really fast.
	my $items = [ Slim::Music::Info::sortFilename( readDirectory($path) ) ];
	my $count = scalar @$items;

	return ($topLevelObj, $items, $count);
}

=head2 userAgentString( )

Utility functions for strings we send out to the world.

=cut

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
		$prefs->get('language'),
		Slim::Utils::Unicode::currentLocale(),
	);

	return $userAgentString;
}

=head2 settingsDiagString( )

	

=cut

sub settingsDiagString {

	my $osDetails = Slim::Utils::OSDetect::details();
	
	my @diagString;

	# We masquerade as iTunes for radio stations that really want it.
	push @diagString, sprintf("%s%s %s - %s - %s - %s - %s",

		Slim::Utils::Strings::string('SERVER_VERSION'),
		Slim::Utils::Strings::string('COLON'),
		$::VERSION,
		$::REVISION,
		$osDetails->{'osName'},
		$prefs->get('language'),
		Slim::Utils::Unicode::currentLocale(),
	);
	
	push @diagString, sprintf("%s%s %s",

		Slim::Utils::Strings::string('SERVER_IP_ADDRESS'),
		Slim::Utils::Strings::string('COLON'),
		Slim::Utils::Network::serverAddr(),
	);

	# Also display the Perl version and MySQL version
	push @diagString, sprintf("%s%s %s %s",
	
		Slim::Utils::Strings::string('PERL_VERSION'),
		Slim::Utils::Strings::string('COLON'),
		$Config{'version'},
		$Config{'archname'},
	);
	
	my $mysqlVersion = Slim::Utils::MySQLHelper->mysqlVersionLong( Slim::Schema->storage->dbh );
	push @diagString, sprintf("%s%s %s",
	
		Slim::Utils::Strings::string('MYSQL_VERSION'),
		Slim::Utils::Strings::string('COLON'),
		$mysqlVersion,
	);

	return wantarray ? @diagString : join ( ', ', @diagString );
}

=head2 assert ( $exp, $msg )

	If $exp is not defined and a true value, then dump the string $msg to the log and call bt()

=cut

sub assert {
	my $exp = shift;
	my $msg = shift;
	
	defined($exp) && $exp && return;
	
	msg($msg) if $msg;
	
	bt();
}

=head2 bt( [ $return ] )

	Useful for tracking the source of a problem during the execution of slimserver.
	use bt() to output in the log a list of function calls leading up to the point 
	where bt() has been used.

	Optional argument $return, if set, will pass the combined message string back to the
	caller instead of to the log.

=cut

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
		my $line_n = 0;
		$msg .= "\nHere's the problem. $assertfile, line $assertline:\n\n";

		while ($line=<SRC>) {
			$line_n++;
			if (abs($assertline-$line_n) <=10) {
				$msg.="$line_n\t$line";
			}
		}
	}
	
	$msg.="\n";

	return $msg if $return;

	msg($msg);
}

=head2 msg( $entry, [ $forceLog ], [ $suppressTimestamp ])

	Outputs an entry to the slimserver log file. 
	$entry is a string for the log.
	optional argument $suppressTimestamp can be set to remove the event timestamp from the long entry.

=cut

sub msg {
	use bytes;
	my $entry = shift;
	my $forceLog = shift || 0;
	my $suppressTimestamp = shift;

	if ( $::LogTimestamp && !$suppressTimestamp ) {

		my $now = substr(int(Time::HiRes::time() * 10000),-4);

		$entry = join("", strftime("[%H:%M:%S.", localtime), $now, "] $entry");
	}

	if (!$::quiet) {

		print STDERR $entry;
	}
}

=head2 msgf( $format, @_)

	uses Perl's sprintf to output the args to the log with the formatting specified by the $format argument.

=cut

sub msgf {
	my $format = shift;

	msg(sprintf($format, @_));
}

=head2 errorMsg( $msg )

	Output formatting for more severe messages in the log

=cut

sub errorMsg {
	my $msg = shift;

	# Force an error message & write to the log.
	msg("ERROR: $msg\n", 1);
}

=head2 delimitThousands( $len)

	Split a numeric string using the style of the server preferred language.

=cut

sub delimitThousands {
	my $len = shift || return 0; 

	my $sep = Slim::Utils::Strings::string('THOUSANDS_SEP');

	0 while $len =~ s/^(-?\d+)(\d{3})/$1$sep$2/;
	return $len;
}

=head2 specified( $i)

	Defined, but does not contain a *

=cut

sub specified {
	my $i = shift;

	return 0 if ref($i) eq 'ARRAY';
	return 0 unless defined $i;
	return $i !~ /\*/;
}

=head2 arrayDiff( $left, $right)

	

=cut

sub arrayDiff {
	my ($left, $right) = @_;

	my %rMap = ();
	my %diff = ();

	map { $rMap{$_}++ } @$right;

	for (@$left) {

		$diff{$_} = 1 if !exists $rMap{$_};
	}

	return \%diff;
}

=head2 shouldCacheURL( $url)

	Bug 3147, don't cache things (HTTP responses, parsed XML)
	that come from file URLs or places on the local network

=cut

sub shouldCacheURL {
	my $url = shift;
	
	# No caching for file:// URLs
	return 0 if Slim::Music::Info::isFileURL($url);
	
	# No caching for local network hosts
	# This is determined by either:
	# 1. No dot in hostname
	# 2. host is a private IP address type
	my $host = URI->new($url)->host;
	
	return 0 if $host !~ /\./;
	
	# If the host doesn't start with a number, cache it
	return 1 if $host !~ /^\d/;
	
	if ( my $ip = Net::IP->new($host) ) {
		return 0 if $ip->iptype eq 'PRIVATE';
	}
	
	return 1;
}

=head2 runningAsService ( )

Returns true if running as a Windows service.

=cut

sub runningAsService {

	if (defined(&PerlSvc::RunningAsService) && PerlSvc::RunningAsService()) {
		return 1;
	}

	return 0;
}

=head1 SEE ALSO

L<Slim::Music::Info>

L<Slim::Utils::Strings>, L<Slim::Utils::Unicode>

L<URI>, L<URI::file>, L<URI::Escape>

=cut

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
