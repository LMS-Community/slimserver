package Slim::Utils::Misc;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
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
 functions useful throughout SqueezeCenter and third party plugins.

=cut

use strict;
use Exporter::Lite;

our @EXPORT = qw(assert bt msg msgf watchDog errorMsg specified validMacAddress);

use Config;
use Cwd ();
use File::Spec::Functions qw(:ALL);
use File::Which ();
use File::Slurp;
use FindBin qw($Bin);
use Log::Log4perl;
use Net::IP;
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
use Slim::Utils::Network ();

my $prefs = preferences('server');

my $scannerlog = logger('scan.scanner');

my $canFollowAlias = 0;

if ( !main::SLIM_SERVICE ) {
	if ($^O =~ /Win32/) {
		require Win32::File;
		require Slim::Utils::OS::Win32;
	}
	
	elsif ($^O =~/darwin/i) {
		# OSX 10.3 doesn't have the modules needed to follow aliases
		$canFollowAlias = Slim::Utils::OS::OSX->canFollowAlias();
	}
}

# Cache our user agent string.
my $userAgentString;

my %pathToFileCache = ();
my %fileToPathCache = ();
my @findBinPaths    = ();

=head1 METHODS

=head2 findbin( $executable)

	Little bit of magic to find the executable program given by the string $executable.

=cut

sub findbin {
	my $executable = shift;

	my $log = logger('os.paths');

	$log->debug("Looking for executable: [$executable]");

	my $isWin = Slim::Utils::OSDetect::isWindows();

	if ($isWin && $executable !~ /\.\w{3}$/) {

		$executable .= '.exe';
	}

	for my $search (@findBinPaths) {

		my $path = catdir($search, $executable);

		$log->debug("Checking for $executable in $path");

		if (-x $path) {

			$log->info("Found binary $path for $executable");

			return $path;
		}
	}

	# For Windows we don't include the path in @findBinPaths so now search this
	if ($isWin && (my $path = File::Which::which($executable))) {

		$log->info("Found binary $path for $executable");

		return $path;

	} else {

		$log->info("Didn't find binary for $executable");

		return undef;
	}
}

=head2 addFindBinPaths( $path1, $path2, ... )

Add $path1, $path2 etc to paths searched by findbin

=cut
sub addFindBinPaths {

	my $log = logger('os.paths');

	while (my $path = shift) {

		if (-d $path) {

			$log->info("adding $path");

			push @findBinPaths, $path;

		} else {

			$log->info("not adding $path - does not exist");
		}
	}
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

sub pathFromMacAlias {
	my $fullpath = shift;
	my $path = '';

	return $path unless $fullpath && $canFollowAlias;
	
	return Slim::Utils::OS::OSX->pathFromMacAlias($fullpath);
}

=head2 isMacAlias( $path )

Return the filepath for a given Mac Alias

=cut

sub isMacAlias {
	my $fullpath = shift;
	my $isAlias  = 0;

	return unless $fullpath && $canFollowAlias;

	return Slim::Utils::OS::OSX->isMacAlias($fullpath);
}

=head2 pathFromFileURL( $url, [ $noCache ])

	Given a file:// style url, return the filepath to the caller

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
		# Bug 10199 - need to ensure that the perl-internal UTF8 flag is set if necessary
		# (this should really be done by URI::file)
		$file = fixPathCase(Slim::Utils::Unicode::utf8on($uri->file));
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

	$string =~ m|[$urlstring]://(?:([^\@:]+):?([^\@]*)\@)?([^:/]+):*(\d*)(\S*)|i;
	
	my ($user, $pass, $host, $port, $path) = ($1, $2, $3, $4, $5);

	$path ||= '/';
	$port ||= 80;

	my $log = logger('os.paths');

	if ( $log->is_debug ) {
		$log->debug("Cracked: $string with [$host],[$port],[$path]");
		$log->debug("   user: [$user]") if $user;
		$log->debug("   pass: [$pass]") if $pass;
	}

	return ($host, $port, $path, $user, $pass);
}

=head2 fixPathCase( $path )

	fixPathCase makes sure that we are using the actual casing of paths in
	a case-insensitive but case preserving filesystem.

=cut

sub fixPathCase {
	my $path = shift;
	my $orig = $path;

	# abs_path() will resolve any case sensetive filesystem issues (HFS+)
	# But don't for the bogus path we use with embedded cue sheets.
	if ($^O eq 'darwin' && $path !~ m|^/BOGUS/PATH|) {
		$path = Cwd::abs_path($path);
	}

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
	
	if ( main::SLIM_SERVICE ) {
		# Abort early if on SN
		return $file;
	}

	if (Slim::Music::Info::isFileURL($base)) {
		$base = pathFromFileURL($base);
	} 

	# People sometimes use playlists generated on Windows elsewhere.
	# See Bug 236
	unless (Slim::Utils::OSDetect::isWindows()) {

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

			if (Slim::Utils::OSDetect::isWindows()) {

				my ($volume) = splitpath($file);

				if (!$volume) {
					($volume) = splitpath($base);
					$file = $volume . $file;
				}
			}

			$fixed = fixPath($file);

		} else {

			if (Slim::Utils::OSDetect::isWindows()) {

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
	my $dirname = Slim::Utils::Unicode::utf8off(shift);
	my $item    = shift;
	my $validRE = shift || Slim::Music::Info::validTypeExtensions();

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
	return 0 if ($item =~ /^\./o && !Slim::Utils::OSDetect::isWindows());

	if ((my $ignore = $prefs->get('ignoreDirRE') || '') ne '') {
		return 0 if $item =~ /$ignore/;
	}

	# BUG 7111: don't catdir if the $item is already a full path.
	my $fullpath = $dirname ? catdir(Slim::Utils::Unicode::utf8off($dirname), $item) : $item;

	# Don't display hidden/system files on Windows
	if (Slim::Utils::OSDetect::isWindows()) {
		my $attributes;
		Win32::File::GetAttributes($fullpath, $attributes);
		return 0 if ($attributes & Win32::File::HIDDEN()) || ($attributes & Win32::File::SYSTEM());
	}


	# We only want files, directories and symlinks Bug #441
	# Otherwise we'll try and read them, and bad things will happen.
	# symlink must come first so an lstat() is done.
	return 0 unless (-l $fullpath || -d _ || -f _);


	# Make sure we can read the file.
	return 0 if !-r _;

	my $target;
 
	# a file can be an Alias on Mac
	if (Slim::Utils::OSDetect::OS() eq "mac" && -f _ && $validRE && ($target = pathFromMacAlias($fullpath))) {
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
	
	return 1
}

=head2 folderFilter( $dirname )

	Verify whether we want to include a folder in our search.

=cut

sub folderFilter {
	my @path = splitdir(shift);
	my $folder = pop @path; 

	return fileFilter(catdir(@path), $folder);
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


=head2 readDirectory( $dirname, [ $validRE ])

	Return the contents of a directory $dirname as an array.  Optionally return only 
	those items that match a regular expression given by $validRE

=cut

sub readDirectory {
	my $dirname  = shift;
	my $validRE  = shift || Slim::Music::Info::validTypeExtensions();
	my @diritems = ();
	my $log      = logger('os.files');

	if (Slim::Utils::OSDetect::isWindows()) {
		my ($volume) = splitpath($dirname);

		if ($volume && isWinDrive($volume) && !Slim::Utils::OS::Win32->isDriveReady($volume)) {
			
			$log->debug("drive [$dirname] not ready");

			return @diritems;
		}
	}

	opendir(DIR, $dirname) || do {

		$log->debug("opendir on [$dirname] failed: $!");

		return @diritems;
	};

	$log->info("Reading directory: $dirname");

	for my $item (readdir(DIR)) {

		# call idle streams to service timers - used for blocking animation.
		if (scalar @diritems % 3) {
			main::idleStreams();
		}

		next unless fileFilter($dirname, $item, $validRE);

		push @diritems, $item;
	}

	closedir(DIR);

	if ( $log->is_info ) {
		$log->info("Directory contains " . scalar(@diritems) . " items");
	}

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

	if (Slim::Utils::OSDetect::OS() eq 'mac' && blessed($topLevelObj) && $topLevelObj->can('path')) {
		my $topPath = $topLevelObj->path;

		if (Slim::Utils::Misc::isMacAlias($topPath)) {
	
			$topLevelObj = Slim::Schema->rs('Track')->objectForUrl({
				'url'      => Slim::Utils::Misc::pathFromMacAlias($topPath),
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
	
	$scannerlog->is_debug && $scannerlog->debug( "findAndScanDirectoryTree( $path ): fsMTime: $fsMTime, dbMTime: $dbMTime" );

	if ($fsMTime != $dbMTime) {

		if ( $scannerlog->is_info ) {
			$scannerlog->info("mtime db: $dbMTime : " . localtime($dbMTime));
			$scannerlog->info("mtime fs: $fsMTime : " . localtime($fsMTime));
		}

		# Update the mtime in the db.
		$topLevelObj->timestamp($fsMTime);
		$topLevelObj->update;

		# Do a quick directory scan.
		Slim::Utils::Scanner->scanDirectory({
			'url'       => $path,
			'recursive' => 0,
		});

		# Bug: 4812 - notify those interested that the database has changed.
		Slim::Control::Request::notifyFromArray(undef, [qw(rescan done)]);

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


=head2 isWinDrive( )

Return true if a given string seems to be a Windows drive letter (eg. c:\)
No low-level check is done whether the drive actually exists.

=cut

sub isWinDrive {
	my $path = shift;

	return 0 if (!Slim::Utils::OSDetect::isWindows() || length($path) > 3);

	return $path =~ /^[a-z]{1}:[\\]?$/i;
}

=head2 parseRevision( )

Read revision number and build time

=cut

sub parseRevision {

	# The revision file may not exist for svn copies.
	my $tempBuildInfo = eval { File::Slurp::read_file(
		catdir(Slim::Utils::OSDetect::dirsFor('revision'), 'revision.txt')
	) } || "TRUNK\nUNKNOWN";

	# Once we've read the file, split it up so we have the Revision and Build Date
	return split (/\n/, $tempBuildInfo);
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
	$userAgentString = sprintf("iTunes/4.7.1 (%s; N; %s; %s; %s; %s) %s/$::VERSION/$::REVISION",

		$osDetails->{'os'},
		$osDetails->{'osName'},
		($osDetails->{'osArch'} || 'Unknown'),
		$prefs->get('language'),
		Slim::Utils::Unicode::currentLocale(),
		main::SLIM_SERVICE ? 'SqueezeNetwork' : 'SqueezeCenter',
	);

	return $userAgentString;
}

=head2 settingsDiagString( )

	

=cut

# XXXX - this sub is no longer used by SC core code, since system information is available in Slim::Menu::SystemInfo
sub settingsDiagString {

	my $osDetails = Slim::Utils::OSDetect::details();
	
	my @diagString;

	# We masquerade as iTunes for radio stations that really want it.
	push @diagString, sprintf("%s%s %s - %s @ %s - %s - %s - %s",

		Slim::Utils::Strings::string('SERVER_VERSION'),
		Slim::Utils::Strings::string('COLON'),
		$::VERSION,
		$::REVISION,
		$::BUILDDATE,
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
	$_[0] && return;
	
	my $msg = $_[1];
	msg($msg) if $msg;
	
	bt();
}

=head2 bt( [ $return ] )

	Useful for tracking the source of a problem during the execution of SqueezeCenter.
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

	Outputs an entry to the SqueezeCenter log file. 
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

=head2 detectBrowser ( )

Attempts to figure out what the browser is by user-agent string identification

=cut

sub detectBrowser {

	my $request = shift;
	my $return = 'unknown';
	return $return unless $request->header('user-agent');

	if ($request->header('user-agent') =~ /Firefox/) {
		$return = 'Firefox';
	} elsif ($request->header('user-agent') =~ /Opera/) {
		$return = 'Opera';
	} elsif ($request->header('user-agent') =~ /Safari/) {
		$return = 'Safari';
	} elsif ($request->header('user-agent') =~ /MSIE 7/) {
		$return = 'IE7';
	} elsif (
	$request->header('user-agent') =~ /MSIE/   && # does it think it's IE
        $request->header('user-agent') !~ /Opera/  && # make sure it's not Opera
        $request->header('user-agent') !~ /Linux/  && # make sure it's not Linux
        $request->header('user-agent') !~ /arm/)      # make sure it's not a Nokia tablet
	{
		$return = 'IE';
	}
	return $return;
}

=head2 createUUID ( )

Generate a new UUID and return it.

=cut

sub createUUID {
	return substr( sha1_hex( Time::HiRes::time() . $$ . Slim::Utils::Network::hostName() ), 0, 8 );
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
