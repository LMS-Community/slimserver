package Slim::Utils::Misc;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::Misc

=head1 SYNOPSIS

use Slim::Utils::Misc qw(msg errorMsg);

msg("This is a log message\n");

=head1 EXPORTS

assert, bt, msg, msgf, errorMsg, specified

=head1 DESCRIPTION

L<Slim::Utils::Misc> serves as a collection of miscellaneous utility 
 functions useful throughout Logitech Media Server and third party plugins.

=cut

use strict;
use Exporter::Lite;

our @EXPORT = qw(assert msg msgf errorMsg specified);

use File::Basename qw(basename);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use FindBin qw($Bin);
use POSIX qw(strftime);
use Scalar::Util qw(blessed);
use Time::HiRes;
use URI;
use URI::Escape;
use URI::file;
use Digest::SHA1 qw(sha1_hex);

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

my $scannerlog = logger('scan.scanner');
my $ospathslog = logger('os.paths');
my $osfileslog = logger('os.files');

my $canFollowAlias = 0;

if (main::ISWINDOWS) {
	require Win32::File;
	require Slim::Utils::OS::Win32;
}
elsif ($^O =~/darwin/i) {
	# OSX 10.3 doesn't have the modules needed to follow aliases
	$canFollowAlias = Slim::Utils::OS::OSX->canFollowAlias();
}

# Cache our user agent string.
my $userAgentString;

my %pathToFileCache = ();
my %fileToPathCache = ();
my %mediadirsCache  = ();
my %fixPathCache    = ();
my @findBinPaths    = ();

my $MAX_CACHE_ENTRIES = $prefs->get('dbhighmem') ? 512 : 32;

$prefs->setChange( sub { 
	%mediadirsCache = ();
}, 'mediadirs', 'ignoreInAudioScan', 'ignoreInVideoScan', 'ignoreInImageScan');

=head1 METHODS

=head2 findbin( $executable)

	Little bit of magic to find the executable program given by the string $executable.

=cut

sub findbin {
	my $executable = shift;

	main::DEBUGLOG && $ospathslog->is_debug && $ospathslog->debug("Looking for executable: [$executable]");

	if (main::ISWINDOWS && $executable !~ /\.\w{3}$/) {

		$executable .= '.exe';
	}

	for my $search (@findBinPaths) {

		my $path = catdir($search, $executable);

		main::DEBUGLOG && $ospathslog->is_debug && $ospathslog->debug("Checking for $executable in $path");

		if (-x $path) {

			main::INFOLOG && $ospathslog->is_info && $ospathslog->info("Found binary $path for $executable");

			return $path;
		}
	}

	# For Windows we don't include the path in @findBinPaths so now search this
	if (main::ISWINDOWS && (my $path = File::Which::which($executable))) {

		main::INFOLOG && $ospathslog->is_info && $ospathslog->info("Found binary $path for $executable");

		return $path;

	} else {

		main::INFOLOG && $ospathslog->is_info && $ospathslog->info("Didn't find binary for $executable");

		return undef;
	}
}

=head2 addFindBinPaths( $path1, $path2, ... )

Add $path1, $path2 etc to paths searched by findbin

=cut
sub addFindBinPaths {

	while (my $path = shift) {

		# don't register duplicate entries
		if (grep { $_ eq $path } @findBinPaths) {

			main::INFOLOG && $ospathslog->is_info && $ospathslog->info("not adding $path - duplicate entry");

		}
		elsif (-d $path) {

			main::INFOLOG && $ospathslog->is_info && $ospathslog->info("adding $path");

			push @findBinPaths, $path;

		} else {

			main::INFOLOG && $ospathslog->is_info && $ospathslog->info("not adding $path - does not exist");
		}
	}
}

sub getBinPaths {
	return wantarray ? @findBinPaths : \@findBinPaths;
}

=head2 setPriority( $priority )

Set the priority for the server. $priority should be -20 to 20

=cut

sub setPriority {
	Slim::Utils::OSDetect::getOS()->setPriority(shift)
}

=head2 getPriority( )

Get the current priority of the server.

=cut

sub getPriority {
	return Slim::Utils::OSDetect::getOS()->getPriority(shift)
}

=head2 pathFromMacAlias( $path )

Return the filepath for a given Mac Alias

=cut

sub pathFromMacAlias { if (main::ISMAC) {
	my $fullpath = shift;
	my $path = '';

	return $path unless $fullpath && $canFollowAlias;
	
	return Slim::Utils::OS::OSX->pathFromMacAlias($fullpath);
} }

=head2 pathFromFileURL( $url, [ $noCache ])

	Given a file:// style url, return the filepath to the caller

	If the option $noCache argument is set, the result is  not cached
	
	Returns the pathname as a (possibly-encoded) byte-string, not a Unicode (decoded) string

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

	my $canLog = Slim::Utils::Log->isInitialized;
	if ($canLog) {

		main::INFOLOG && $osfileslog->is_info && $osfileslog->info("Got $path from file url $url");
	}

	# only allow absolute file URLs and don't allow .. in files...
	if ($path !~ /[\/\\]\.\.[\/\\]/) {
		$file = $uri->file;
	}

	if ($canLog) {

		if (!defined($file))  {
			$osfileslog->warn("Bad file: url $url");
		} else {
			main::INFOLOG && $osfileslog->is_info && $osfileslog->info("Extracted: $file from $url");
		}
	}

	# Bug 17530, $file is in raw bytes but will have the UTF8 flag enabled.
	# This causes problems if the file is later passed to stat().
	if (utf8::is_utf8($file)) {
		utf8::decode($file);
		utf8::encode($file);
	}

	if (!$noCache) {
		%fileToPathCache = () if scalar keys %fileToPathCache > $MAX_CACHE_ENTRIES;
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
	
	# All paths should be in raw bytes, warn if it appears to be UTF-8
	# XXX remove this later, before release
=pod
	if ( utf8::is_utf8($path) ) {
		my $test = $path;
		utf8::decode($test);
		utf8::encode($test);
		if ( $test ne $path ) {
			logWarning("fileURLFromPath got decoded UTF-8 path: " . Data::Dump::dump($path));
			bt();
		}
	}
=cut
	
	# Bug 15511
	# URI::file->new() will strip trailing space from path. Use a trailing / to defeat this if necessary.
	my $addedSlash;
	if ($path =~ /[\s"]$/) {
		$path .= '/';
		$addedSlash = 1;
	}

	my $uri = URI::file->new($path);
	$uri->host('');

	my $file = $uri->as_string;
	$file =~ s%/$%% if $addedSlash;

	if (scalar keys %pathToFileCache > $MAX_CACHE_ENTRIES) {
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
# XXX - no longer used?
=pod
sub removeCanary {
	my $string = shift;

	for (my $i = 0;  ++$i <= 5;) {  

		last if $$string =~ s/^=://;

		$$string = unescape($$string);

		last if $$string =~ s/^=://;
	}

	return $string;
}
=cut

sub anchorFromURL {
	my $url = shift;

	if ($url =~ /#(.*)$/) {
		return $1;
	}
	return undef;
}

sub stripAnchorFromURL {
	my $url = shift;

	# Bug 4709 - only strip anchor following a file extension
	if ($url =~ /^(.*\..{2,4})#[\d\.]+-.*$/) {
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

	$string =~ m|(?:$urlstring)://(?:([^\@\/:]+):?([^\@\/]*)\@)?([^:/]+):*(\d*)(\S*)|i;
	
	my ($user, $pass, $host, $port, $path) = ($1, $2, $3, $4, $5);

	$path ||= '/';
	$port ||= ((Slim::Networking::Async::HTTP->hasSSL() && $string =~ /^https/) ? 443 : 80);

	if ( main::DEBUGLOG && $ospathslog->is_debug ) {
		$ospathslog->debug("Cracked: $string with [$host],[$port],[$path]");
		$ospathslog->debug("   user: [$user]") if $user;
		$ospathslog->debug("   pass: [$pass]") if $pass;
	}

	return ($host, $port, $path, $user, $pass);
}

=head2 fixPath( $file, $base)

	fixPath takes relative file paths and puts the base path in the beginning
	to make them full paths, if possible.
	URLs are left alone

=cut

# there's not really a better way to do this..
sub fixPath {
	# Only using encode_locale() here as a safety measure because
	# it should be a no-op.
	my $file = Slim::Utils::Unicode::encode_locale($_[0]);

	if (!defined($file)) {
		return;
	}

	my $base = $_[1] && ( $fixPathCache{$_[1]} || Slim::Utils::Unicode::encode_locale($_[1]) );
	
	if (scalar keys %fixPathCache > $MAX_CACHE_ENTRIES) {
		%fixPathCache = ();
	}
	
	$fixPathCache{$_[1]} ||= $base if $base;

	my $fixed;

	if (Slim::Music::Info::isURL($file)) { 
		
		my $uri = URI->new($file) || return $file;

		if ($uri->scheme() eq 'file') {

			$uri->host('');
		}

		return $uri->as_string;
	}
	
	# sometimes a playlist parser would send us invalid data like html/xml code - skip it
	if ( $file =~ /\s*<.*>/ ) {
		return $file;
	}

	if (Slim::Music::Info::isFileURL($base)) {
		$base = pathFromFileURL($base);
	} 

	# People sometimes use playlists generated on Windows elsewhere.
	# See Bug 236
	unless (main::ISWINDOWS) {

		$file =~ s/^[C-Z]://i;
		$file =~ s/\\/\//g;
	}

	# the only kind of absolute file we like is one in 
	# the music directory or the playlist directory...
	my $mediadirs = Slim::Utils::Misc::getMediaDirs();
	my $savedplaylistdir = Slim::Utils::Misc::getPlaylistDir();

	if (scalar @$mediadirs && grep { $file =~ /^\Q$_\E/ } @$mediadirs) {

		$fixed = $file;

	} elsif ($savedplaylistdir && $file =~ /^\Q$savedplaylistdir\E/) {

		$fixed = $file;

	} elsif (Slim::Music::Info::isURL($file) && (!scalar @$mediadirs || !grep {-r catfile($_, $file)} @$mediadirs)) {

		$fixed = $file;

	} elsif ($base) {

		if (file_name_is_absolute($file)) {

			if (main::ISWINDOWS) {

				my ($volume) = splitpath($file);

				if (!$volume) {
					($volume) = splitpath($base);
					$file = $volume . $file;
				}
			}

			$fixed = fixPath($file);

		} else {

			if (main::ISWINDOWS) {

				# rel2abs will convert ../../ paths correctly only for windows
				$fixed = fixPath(rel2abs($file,$base));

			} else {

				$fixed = fixPath(stripRel(catfile($base, $file)));
			}
		}

	} elsif (file_name_is_absolute($file) || !Slim::Music::Info::isFileURL($file)) {

		$fixed = $file;

	} else {

		# XXX - don't know how to handle this case: should we even return an untested value?
		my $audiodir = $mediadirs->[0];
		scalar @$mediadirs > 1 && logBacktrace("Dealing with single audiodir ($audiodir) instead of mediadirs " . Data::Dump::dump($file, $mediadirs));

		$file =~ s/\Q$audiodir\E//;
		$fixed = catfile($audiodir, $file);
	}

	# I hate Windows & HFS+.
	# A playlist or the like can have a completely different case than
	# what we get from the filesystem. Fix that all up so we don't create
	# duplicate entries in the database.
	if (!Slim::Music::Info::isFileURL($fixed)) {

		$fixed = canonpath($fixed);

		# Fixes Bug: 2757, but breaks a lot more: 3681, 3682 & 3683
#		if (-l $fixed) {
#
#			#$fixed = readlink($fixed);
#		}
	}

	if (main::INFOLOG && $file ne $fixed && $ospathslog->is_info) {

		$ospathslog->info("Fixed: $file to $fixed");

		if ($base) {
			$ospathslog->info("Base: $base");
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
	
	main::INFOLOG && $ospathslog->is_info && $ospathslog->info("Original: $file");

	while ($file =~ m#[\/\\]\.\.[\/\\]#) {
		$file =~ s#[^\/\\]+[\/\\]\.\.[\/\\]##sg;
	}
	
	main::INFOLOG && $ospathslog->is_info && $ospathslog->info("Stripped: $file");

	return $file;
}

=head2 getLibraryName()

	Return the library's name, or the host name if none is defined

=cut

sub getLibraryName {
	my $hostname = $prefs->get('libraryname') || '';
	
	if (!$hostname || $hostname =~ /^(?:''|"")$/) {
		$hostname = Slim::Utils::Network::hostName();

		# may return several lines of hostnames, just take the first.	
		$hostname =~ s/\n.*//;
	
		# may return a dotted name, just take the first part
		$hostname =~ s/\..*//;
	}
		
	# Bug 13217, replace Unicode quote with ASCII version (commonly used in Mac server name)
	$hostname =~ s/\x{2019}/'/g;

	return $hostname;
}

=head2 getAudioDir()

	Get the byte-string (native) version of the audiodir

=cut

sub getAudioDir {
	logBacktrace("getAudioDir is deprecated, use getAudioDirs instead");
	return getAudioDirs()->[0];
}

=head2 getPlaylistDir()

	Get the byte-string (native) version of the playlistdir

=cut

sub getPlaylistDir {
	$mediadirsCache{playlist} = Slim::Utils::Unicode::encode_locale($prefs->get('playlistdir')) if !defined $mediadirsCache{playlist};
	return $mediadirsCache{playlist};
}

=head2 getMediaDirs()

	Returns an arrayref of all media directories.

=cut

sub getMediaDirs {
	my $type = shift || '';
	my $filter = shift;
	
	# need to clone the cached value, as the caller might be modifying it
	return [ map { $_ } @{$mediadirsCache{$type}} ] if !$filter && $mediadirsCache{$type};
	
	my $mediadirs = getDirsPref('mediadirs');
	
	if ($type) {
		my $ignoreList = { map { $_, 1 } @{ getDirsPref({
			audio => 'ignoreInAudioScan',
			video => 'ignoreInVideoScan',
			image => 'ignoreInImageScan',
		}->{$type}) } };
		
		$mediadirs = [ grep { !$ignoreList->{$_} } @$mediadirs ];
		$mediadirs = [ grep /^\Q$filter\E$/, @$mediadirs] if $filter;
	}
	
	$mediadirsCache{$type} = [ map { $_ } @$mediadirs ] unless $filter;
	
	return $mediadirs
}

sub getAudioDirs {
	return getMediaDirs('audio', shift);
}

sub getVideoDirs {
	return (main::VIDEO && main::MEDIASUPPORT) ? getMediaDirs('video', shift) : [];
}

sub getImageDirs {
	return (main::IMAGE && main::MEDIASUPPORT) ? getMediaDirs('image', shift) : [];
}

# get list of folders which are disabled for all media
sub getInactiveMediaDirs {
	my @mediadirs = @{ getDirsPref('ignoreInAudioScan') };
	
	if (main::IMAGE && main::MEDIASUPPORT && scalar @mediadirs) {
		my $ignoreList = { map { $_, 1 } @{ getImageDirs() } };
		@mediadirs = grep { !$ignoreList->{$_} } @mediadirs; 
	}

	if (main::VIDEO && main::MEDIASUPPORT && scalar @mediadirs) {
		my $ignoreList = { map { $_, 1 } @{ getVideoDirs() } };
		@mediadirs = grep { !$ignoreList->{$_} } @mediadirs; 
	}
	
	return \@mediadirs;
}

sub getDirsPref {
	return [ map { Slim::Utils::Unicode::encode_locale($_) } @{ $prefs->get($_[0]) || [''] } ];
}

=head2 inMediaFolder( $)

	Check if argument is an item contained in one of the media folder trees

=cut

sub inMediaFolder {
	my $path = shift;
	my $mediadirs = getMediaDirs();
	
	foreach ( @$mediadirs ) {
		return 1 if _checkInFolder($path, $_); 
	}
	
	return 0;
}

=head2 inPlaylistFolder( $)

	Check if argument is an item contained in the playlist folder tree

=cut

sub inPlaylistFolder {
	return _checkInFolder(shift, getPlaylistDir());
}

sub _checkInFolder {
	my $path = shift || return;
	my $checkdir = shift;

	# Fully qualify the path - and strip out any url prefix.
	$path = fixPath($path) || return 0;
	$path = pathFromFileURL($path) || return 0;

	if ($checkdir && $path =~ /^\Q$checkdir\E/) {
		return 1;
	} else {
		return 0;
	}
}

# the hash's value is the parent path from which a file should be excluded
# 1 means "from all folders", "/" -> "subfolders in root only" etc.
my %_ignoredItems = Slim::Utils::OSDetect::getOS->ignoredItems();

# always ignore . and ..
$_ignoredItems{'.'}  = 1;
$_ignoredItems{'..'} = 1;

# Don't include old Shoutcast recently played items.
$_ignoredItems{'ShoutcastBrowser_Recently_Played'} = 1;

=head2 fileFilter( $dirname, $item )

	Verify whether we want to include a file or folder in our search.
	This helper function is used to guarantee identical filtering across 
	different browse/scan procedures

=cut

sub fileFilter {
	my $dirname = shift;
	my $item    = shift;
	my $validRE = shift || Slim::Music::Info::validTypeExtensions();
	my $hasStat = shift || 0;
	my $showHidden = shift;		# optionally allow Windows to use hidden artwork, as eg. WMP is storing it as system files

	if (my $filter = $_ignoredItems{$item}) {
		
		# '1' items are always to be ignored
		return 0 if $filter eq '1';

		my @parts = splitpath($dirname);
		if ($parts[1] && (!defined $parts[2] || length($parts[2]) == 0)) {
			# replace back slashes on Windows
			$parts[1] =~ s/\\/\//g;
			
			return 0 if $filter eq $parts[1];
		}

	}

	# Ignore special named files and directories
	# __ is a match against our old __history and __mac playlists.
	return 0 if $item =~ /^__\S+\.m3u$/o;
	return 0 if ($item =~ /^\.[^\.]+/o && !main::ISWINDOWS);

	if ((my $ignore = $prefs->get('ignoreDirRE') || '') ne '') {
		return 0 if $item =~ /$ignore/;
	}

	# BUG 7111: don't catdir if the $item is already a full path.
	my $fullpath = $dirname ? catdir($dirname, $item) : $item;

	# Don't display hidden/system folders on Windows
	if (main::ISWINDOWS && !$showHidden) {
		my $attributes;
		Win32::File::GetAttributes($fullpath, $attributes);
		return 0 if ($attributes & Win32::File::HIDDEN()) || ($attributes & Win32::File::SYSTEM());
	}

	# We only want files, directories and symlinks Bug #441
	# Otherwise we'll try and read them, and bad things will happen.
	# symlink must come first so an lstat() is done.
	if ( !$hasStat ) {
		lstat($fullpath);
	}
	
	return 0 unless (-l _ || -d _ || -f _);

	# Make sure we can read the file, honoring ACLs. This check is optional and provided by a plugin only.
	if ( !main::ISWINDOWS && (my $filetest = Slim::Utils::OSDetect::getOS->aclFiletest()) ) {
		return 0 unless $filetest->($fullpath);
	}
	else {
		return 0 if ! -r _;
	}

	my $target;
 
	# a file can be an Alias on Mac
	if (main::ISMAC && -f _ && (stat _)[7] == 0 && $validRE && ($target = pathFromMacAlias($fullpath))) {
		unless (-d $target) {
			return 0;
		}
	}
	# Don't bother with file types we don't understand.
	elsif ($validRE && -f _) {
		return 0 if $item !~ $validRE;
	}
	elsif ($validRE && -l _ && defined ($target = readlink($fullpath))) {
		# fix relative/absolute path
		$target = ($target =~ /^\// ? $target : catdir($dirname, $target));

		if (-f $target) {
			return 0 if $target !~ $validRE;
		}
	}
	
	return 1;
}

=head2 folderFilter( $dirname, $hasStat, $validRE )

	Verify whether we want to include a folder in our search.

=cut

sub folderFilter {
	my @path = splitdir(shift);
	my $folder = pop @path;
	
	my $hasStat = shift || 0;
	my $validRE = shift;
	my $file = catdir(@path);
	
	# Bug 15209, Hack for UNC bug where catdir turns \\foo into \foo
	if ( main::ISWINDOWS && $path[0] eq '' && $path[1] eq '' && $file !~ /^\\{2}/ ) {
		$file = '\\' . $file;
	}
	
	return fileFilter($file, $folder, $validRE, $hasStat);
}


=head2 cleanupFilename( $filename )

	Do some basic, simple sanity checks.
	Don't allow periods, colons, control characters, slashes, backslashes, just to be safe.

=cut

sub cleanupFilename {
	my $filename = shift; 

	$filename =~ tr|:\x00-\x1f\/\\| |s;
	$filename =~ s/^\.//;

	return $filename;
}


=head2 readDirectory( $dirname, [ $validRE, $recursive ])

	Return the contents of a directory $dirname as an array.  Optionally return only 
	those items that match a regular expression given by $validRE. Optionally do a
	recursive search.

=cut

sub readDirectory {
	my $dirname  = shift;
	my $validRE  = shift || Slim::Music::Info::validTypeExtensions();
	my $recursive = shift;
	
	my @diritems = ();

	my $native_dirname = Slim::Utils::Unicode::encode_locale($dirname);
	
	if (main::ISWINDOWS) {
		my ($volume) = splitpath($native_dirname);

		if ($volume && isWinDrive($volume) && !Slim::Utils::OS::Win32->isDriveReady($volume)) {
			
			main::DEBUGLOG && $osfileslog->is_debug && $osfileslog->debug("drive [$dirname] not ready");

			return @diritems;
		}
	}

	if ($recursive) {
		require Slim::Utils::Scanner;
		push @diritems, @{ Slim::Utils::Scanner->findFilesMatching($dirname, {
			types => $validRE,
		}) };
	}
	else {
		opendir(DIR, $native_dirname) || do {
	
			main::DEBUGLOG && $osfileslog->is_debug && $osfileslog->debug("opendir on [$dirname] failed: $!");
	
			return @diritems;
		};
	
		main::INFOLOG && $osfileslog->is_info && $osfileslog->info("Reading directory: $dirname");
	
		while (defined (my $item = readdir(DIR)) ) {
			# call idle streams to service timers - used for blocking animation.
			if (scalar @diritems % 3) {
				main::idleStreams();
			}
	
	        # readdir returns only bytes, so try and decode the
	        # filename to UTF-8 here or the later calls to -d/-f may fail,
	        # causing directories and files to be skipped.
			# utf8::decode($item);
			#
			# This was the wrong fix. The entries returned by this method
			# should be in native byte-strings. It is likely that the previous problem
			# was caused by the incoming $dirname having the uft8 flag set,
			# so that concatenating the dirname and an entry would result in a UTF-8
			# string that was incorrectly auto-decoded.
	
			next unless fileFilter($native_dirname, $item, $validRE);
	
			push @diritems, $item;
		}
	
		closedir(DIR);
		
		@diritems = Slim::Music::Info::sortFilename(@diritems);
	}

	if ( main::INFOLOG && $osfileslog->is_info ) {
		$osfileslog->info("Directory contains " . scalar(@diritems) . " items");
	}

	return @diritems;
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
		
		if (defined $url) {
			if (!Slim::Music::Info::isURL($url)) {
				$url = fileURLFromPath($url);
			}
	
			$topLevelObj = Slim::Schema->objectForUrl({
				'url'      => $url,
				'create'   => 1,
				'readTags' => 1,
				'commit'   => 1,
			});
		}
	}

	if (main::ISMAC && blessed($topLevelObj) && $topLevelObj->can('path')) {
		my $topPath = $topLevelObj->path;

		if ( my $alias = Slim::Utils::Misc::pathFromMacAlias($topPath) ) {
	
			$topLevelObj = Slim::Schema->objectForUrl({
				'url'      => $alias,
				'create'   => 1,
				'readTags' => 1,
				'commit'   => 1,
			});

		}
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
	
	main::DEBUGLOG && $scannerlog->is_debug && $scannerlog->debug( "findAndScanDirectoryTree( $path ): fsMTime: $fsMTime, dbMTime: $dbMTime" );

	if ($fsMTime != $dbMTime && !$topLevelObj->remote) {

		if ( main::INFOLOG && $scannerlog->is_info ) {
			$scannerlog->info("mtime db: $dbMTime : " . localtime($dbMTime));
			$scannerlog->info("mtime fs: $fsMTime : " . localtime($fsMTime));
		}

		# Update the mtime in the db.
		$topLevelObj->timestamp($fsMTime);
		$topLevelObj->update;

		# Do a quick directory scan.
		# XXX this should really be async but callers would need updated, lots of work
		Slim::Utils::Scanner::Local->rescan( $path, {
			no_async  => 1,
			recursive => 0,
		} );
	}

	# Now read the raw directory and return it. This should always be really fast.
	my $items = [ readDirectory($path, $params->{typeRegEx}, $params->{recursive}) ];
	my $count = scalar @$items;

	return ($topLevelObj, $items, $count);
}

=head2 deleteFiles( $dir, $typeRegEx )

Delete all files matching $typeRegEx in folder $dir

=cut

sub deleteFiles {
	my ($dir, $typeRegEx, $excludeFile) = @_;
	
	opendir my ($dirh), $dir;
	
	my @files = grep { /$typeRegEx/ } readdir $dirh;
	
	closedir $dirh;
	
	for my $file ( @files ) {
		next if $excludeFile && $file eq basename($excludeFile);
		unlink catdir( $dir, $file ) or logError("Unable to remove file: $file: $!");
	}
	
}


=head2 isWinDrive( )

Return true if a given string seems to be a Windows drive letter (eg. c:\)
No low-level check is done whether the drive actually exists.

=cut

sub isWinDrive { if (main::ISWINDOWS) {
	my $path = shift;

	return 0 if length($path) > 3;

	return $path =~ /^[a-z]{1}:[\\\/]?$/i;
} }

=head2 parseRevision( )

Read revision number and build time

=cut

sub parseRevision {

	# The revision file may not exist for svn copies.
	my $tempBuildInfo = eval { File::Slurp::read_file(
		catdir(Slim::Utils::OSDetect::dirsFor('revision'), 'revision.txt')
	) } || "TRUNK\nUNKNOWN";
	
	my ($revision, $builddate) = split (/\n/, $tempBuildInfo);
	
	# if we're running from a git clone, report the last commit ID and timestamp
	# "git -C ..." is only available in recent git version, more recent than what CentOS provides...
	if ( !main::ISWINDOWS && $revision eq 'TRUNK' && `cd $Bin && git show -s --format=%h\\|%ci 2> /dev/null` =~ /^([0-9a-f]+)\|(\d{4}-\d\d-\d\d.*)/i ) {
		$revision = 'git-' . $1;
		$builddate = $2;
	}

	# Once we've read the file, split it up so we have the Revision and Build Date
	return ($revision, $builddate);
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
	# Note: Using SqueezeNetwork/SqueezeCenter here until RadioTime relaxes their user-agent restrictions
	$userAgentString = sprintf("iTunes/4.7.1 (%s; N; %s; %s; %s; %s) %s/$::VERSION/$::REVISION",

		$osDetails->{'os'},
		$osDetails->{'osName'},
		($osDetails->{'osArch'} || 'Unknown'),
		$prefs->get('language'),
		Slim::Utils::Unicode::currentLocale(),
		'SqueezeCenter, Squeezebox Server, Logitech Media Server',
	);

	return $userAgentString;
}

=head2 assert ( $exp, $msg )

	If $exp is not defined and a true value, then dump the string $msg to the log and call bt()

=cut

sub assert {
	$_[0] && return;
	
	my $msg = $_[1];
	msg($msg) if $msg;
	
	bt();
}

=head2 bt( [ $return ] )

	Useful for tracking the source of a problem during the execution of the server.
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

	Outputs an entry to the server log file. 
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
	
	# No caching unless it's http
	return 0 unless $url =~ /^http/i;
	
	# No caching for local network hosts
	# This is determined by either:
	# 1. No dot in hostname
	# 2. host is a private IP address type
	my $host = URI->new($url)->host;
	
	return 0 if $host !~ /\./;
	
	# If the host doesn't start with a number, cache it
	return 1 if $host !~ /^\d/;
	
	if ( Slim::Utils::Network::ip_is_private($host) ) {
		return 0;
	}
	
	return 1;
}

=head2 runningAsService ( )

Returns true if running as a Windows service.

=cut

sub runningAsService { if (main::ISWINDOWS) {

	if (defined(&PerlSvc::RunningAsService) && PerlSvc::RunningAsService()) {
		return 1;
	}

	return 0;
} }

=head2 validMacAddress ( )

Returns true if string is in correct form of a mac address

=cut

sub validMacAddress {

	#return true if $string is a mac address, otherwise return false
	my $string = shift;

	my $d = "[0-9A-Fa-f]";
	my $dd = $d . $d;

	if ($string =~ /$dd:$dd:$dd:$dd:$dd:$dd/) {
		return 1;
	}

	return 0;
}

=head2 createUUID ( )

Generate a new UUID and return it.

=cut

sub createUUID {
	require Slim::Utils::Network;
	return substr( sha1_hex( Time::HiRes::time() . $$ . Slim::Utils::Network::hostName() ), 0, 8 );
}

=head2 round ( )

Round a number to an integer

=cut

sub round {
	my $number = shift;
	return int($number + .5 * ($number <=> 0));
}

=head2 min ( )

Return the minimum value from a list supplied as an array reference

=cut

# Smaller and faster than Math::VecStat::min

sub min {
  my $v = $_[0];
  my $m = $v->[0];
  foreach (@$v) { $m = $_ if $_ < $m; }
  return $m;
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
