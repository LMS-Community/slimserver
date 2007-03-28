package Slim::Plugin::iTunes::Common;

# SlimServer Copyright (C) 2001-2005 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This module supports the following configuration variables:
#
#	itunes	-- 1 to attempt to use iTunes library XML file,
#		0 to simply scan filesystem.
#
#	itunes_library_xml_path
#		-- full path to 'iTunes Music Library.xml' file.
#
#	itunes_library_music_path
#		-- full path to 'iTunes Music' directory (that is, the
#		directory that contains your actual song files).
#
#	ignoredisableditunestracks
#		-- if this is set (1), songs that are 'disabled' (unchecked)
#		in iTunes will still be available to Slimserver.  If this is
#		unset (0) or undefined, disabled songs will be skipped.
#
#	itunesscaninterval
#		-- how long to wait between checking
#		'iTunes Music Library.xml' for changes.

use strict;
use base qw(Class::Data::Inheritable);

use File::Spec::Functions qw(:ALL);
use File::Basename;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $log = logger('plugin.itunes');

{
	my $class = __PACKAGE__;

	$class->mk_classdata('iTunesLibraryBasePath');
	$class->mk_classdata('lastMusicLibraryFinishTime');
	$class->mk_classdata('lastITunesMusicLibraryDate');
	$class->mk_classdata('iTunesScanInterval');
	$class->mk_classdata('initialized');

	$class->lastITunesMusicLibraryDate(0);
	$class->iTunesScanInterval(3600);
}

sub useiTunesLibrary {
	my $class    = shift;
	my $newValue = shift;

	if (defined($newValue)) {
		Slim::Utils::Prefs::set('itunes', $newValue);
	}

	my $use = Slim::Utils::Prefs::get('itunes');
	my $can = $class->canUseiTunesLibrary();

	Slim::Music::Import->useImporter($class, $use && $can);

	$log->info("Using iTunes library: $use");

	return $use && $can;
}

sub canUseiTunesLibrary {
	my $class = shift;

	return 1 if $class->initialized;

	$class->checkDefaults;

	return defined $class->findMusicLibraryFile;
}

sub findLibraryFromPlist {
	my $class = shift;
	my $base  = shift;

	my $path  = undef;

	my @parts = qw(Library Preferences com.apple.iApps.plist);

	if ($base) {
		unshift @parts, $base;
	}

	open (PLIST, catfile(@parts)) || return $path;

	while (<PLIST>) {

		if (/<string>(.*iTunes%20Music%20Library.xml)<\/string>$/) {
			$path = Slim::Utils::Misc::pathFromFileURL($1);
			last;
		}
	}

	close PLIST;

	return $path;
}

sub findLibraryFromRegistry {
	my $class = shift;
	my $path  = undef;

	if (Slim::Utils::OSDetect::OS() ne 'win') {
		return;
	}

	Slim::bootstrap::tryModuleLoad('Win32::Registry');

	if (!$@) {

		my $folder;

		if ($::HKEY_CURRENT_USER && $::HKEY_CURRENT_USER->Open("Software\\Microsoft\\Windows"
				."\\CurrentVersion\\Explorer\\Shell Folders",
				$folder)) {
			my ($type, $value);

			if ($folder->QueryValueEx("My Music", $type, $value)) {
				$path = $value . '\\iTunes\\iTunes Music Library.xml';
				$log->info("Found 'My Music' here: $value for $path");
			}

			if ($path && -r $path) {

				return $path;

			} elsif ($folder->QueryValueEx("Personal", $type, $value)) {
				$path = $value . '\\My Music\\iTunes\\iTunes Music Library.xml';
				$log->info("Found 'Personal' here: $value for $path");
			}
		}
	}

	return $path;
}

sub findMusicLibraryFile {
	my $class = shift;

	my $explicit_xml_path = Slim::Utils::Prefs::get('itunes_library_xml_path');

	if ($explicit_xml_path) {

		if (-d $explicit_xml_path) {
			$explicit_xml_path =  catfile(($explicit_xml_path), 'iTunes Music Library.xml');
		}
			 
		if (-r $explicit_xml_path) {
			return $explicit_xml_path;
		}
	}

	$log->info("Attempting to locate iTunes Music Library.xml automatically");

	my $base = $ENV{'HOME'} || '';

	my $path = findLibraryFromPlist($base);

	if ($path && -r $path) {

		$log->info("Found path via iTunes preferences at: $path");

		Slim::Utils::Prefs::set( 'itunes_library_xml_path', $path );

		return $path;
	}

	$path = findLibraryFromRegistry();

	if ($path && -r $path) {

		$log->info("Found path via Windows registry at: $path");

		Slim::Utils::Prefs::set( 'itunes_library_xml_path', $path );

		return $path;
	}

	# This defines the list of directories we will search for
	# the 'iTunes Music Library.xml' file.
	my @searchdirs = (
		catdir($base, 'Music', 'iTunes'),
		catdir($base, 'Documents', 'iTunes'),
		$base,
	);

	my $audiodir = Slim::Utils::Prefs::get('audiodir');

	if (defined $audiodir) {
		push @searchdirs, (
			catdir($audiodir, 'My Music', 'iTunes'),
			catdir($audiodir, 'iTunes'),
			$audiodir
		);
	}

	for my $dir (@searchdirs) {
		$path = catfile(($dir), 'iTunes Music Library.xml');

		if ($path && -r $path) {

			$log->info("Found path via directory search at: $path");

			return $path;
		}
	}

	$log->info("Unable to find iTunes Music Library.xml");

	return undef;
}

sub isMusicLibraryFileChanged {
	my $class     = shift;

	my $file      = $class->findMusicLibraryFile() || return;
	my $fileMTime = (stat $file)[9];

	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, iTunesLastLibraryChange is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	my $lastScanTime     = Slim::Music::Import->lastScanTime;
	my $lastiTunesChange = Slim::Music::Import->lastScanTime('iTunesLastLibraryChange');

	# Set this so others can use it without going through the DB in a tight loop.
	$class->lastITunesMusicLibraryDate($lastiTunesChange);

	if ($fileMTime > $lastiTunesChange) {

		my $scanInterval = Slim::Utils::Prefs::get('itunesscaninterval');

		$log->debug("lastiTunesChange: " . scalar localtime($lastiTunesChange));
		$log->debug("lastScanTime    : $lastScanTime");
		$log->debug("scanInterval    : $scanInterval");

		if (!$scanInterval) {

			# only scan if itunesscaninterval is non-zero.
			$log->info("Scan Interval set to 0, rescanning disabled.");

			return 0;
		}

		if (!$lastScanTime) {

			$log->info("lastScanTime is 0: Will start scanning.");

			return 1;
		}

		if ((time - $lastScanTime) > $scanInterval) {

			$log->info("(time - lastScanTime) > scanInterval: Will start scanning.");

			return 1;

		} else {

			$log->info("Waiting for $scanInterval seconds to pass before rescanning");
		}
	}

	return 0;
}

sub normalize_location {
	my $class    = shift;
	my $location = shift;
	my $fallback = shift;   # if set, ignore itunes_library_music_path
	my $url;

	my $stripped = $class->strip_automounter($location);

	# on non-mac or windows, we need to substitute the itunes library path for the one in the iTunes xml file
	my $explicit_path = Slim::Utils::Prefs::get('itunes_library_music_path');

	if ( $explicit_path && !$fallback ) {

		# find the new base location.  make sure it ends with a slash.
		my $base = Slim::Utils::Misc::fileURLFromPath($explicit_path);

		$url = $stripped;
		
		my $itunesbase = $class->iTunesLibraryBasePath;
		
		$url =~ s/$itunesbase/$base/isg;
		
		$url =~ s/(\w)\/\/(\w)/$1\/$2/isg;

	} else {

		$url = Slim::Utils::Misc::fixPath($stripped);
	}

	$url =~ s/file:\/\/localhost\//file:\/\/\//;

	$log->debug("Normalized $location to $url");

	return $url;
}

sub strip_automounter {
	my $class = shift;
	my $path  = shift;

	if ($path && ($path =~ /automount/)) {

		# Strip out automounter 'private' paths.
		# OSX wants us to use file://Network/ or timeouts occur
		# There may be more combinations
		$path =~ s/private\/var\/automount\///;
		$path =~ s/private\/automount\///;
		$path =~ s/automount\/static\///;
	}

	#remove trailing slash
	$path && $path =~ s/\/$//;

	return $path;
}

sub checkDefaults {
	my $class = shift;

	if (!Slim::Utils::Prefs::isDefined('itunesscaninterval')) {

		Slim::Utils::Prefs::set('itunesscaninterval', $class->iTunesScanInterval);
	}

	if (!Slim::Utils::Prefs::isDefined('iTunesplaylistprefix')) {
		Slim::Utils::Prefs::set('iTunesplaylistprefix','iTunes: ');
	}

	if (!Slim::Utils::Prefs::isDefined('iTunesplaylistsuffix')) {
		Slim::Utils::Prefs::set('iTunesplaylistsuffix','');
	}

	if (!Slim::Utils::Prefs::isDefined('ignoredisableditunestracks')) {
		Slim::Utils::Prefs::set('ignoredisableditunestracks',0);
	}

	if (!Slim::Utils::Prefs::isDefined('lastITunesMusicLibraryDate')) {
		Slim::Utils::Prefs::set('lastITunesMusicLibraryDate',0);
	}

	if (!Slim::Utils::Prefs::isDefined('itunes') && defined findMusicLibraryFile()) {
		Slim::Utils::Prefs::set('itunes', 1);
	}
}

1;

__END__
