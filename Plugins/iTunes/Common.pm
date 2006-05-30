package Plugins::iTunes::Common;

# SlimServer Copyright (C) 2001-2005 Sean Adams, Slim Devices Inc.
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

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

INIT: {
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

	$::d_itunes && msg("iTunes: using itunes library: $use\n");

	return $use && $can;
}

sub canUseiTunesLibrary {
	my $class = shift;

	return 1 if $class->initialized;

	$class->checkDefaults;

	return defined $class->findMusicLibraryFile;
}

sub setPodcasts {
	my $class = shift;

	if (!$INC{'Slim/Web/Pages.pm'}) {
		return;
	}

	my $genre = Slim::Schema->single('Genre', { 'name' => 'Podcasts' });

	if ($genre) {
		my $id = $genre->id;
		
		Slim::Web::Pages->addPageLinks("browse", {
			'ITUNES_PODCASTS' => "browsedb.html?hierarchy=genre,contributor,album,track&level=2&&genre.id=".$id
		});

		Slim::Buttons::Home::addMenuOption('ITUNES_PODCASTS', {
			'useMode'      => 'browsedb',
			'hierarchy'    => 'genre,contributor,album,track',
			'level'        => 2,
			'findCriteria' => { 'genre.id' => $id },
		});

		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC','ITUNES_PODCASTS', {
			'useMode'      => 'browsedb',
			'hierarchy'    => 'genre,contributor,album,track',
			'level'        => 2,
			'findCriteria' => { 'genre.id' => $id },
		});
	}
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

	my $path = undef;

	return if Slim::Utils::OSDetect::OS() ne 'win';

	if (!eval "use Win32::Registry;") {
		my $folder;

		if ($::HKEY_CURRENT_USER && $::HKEY_CURRENT_USER->Open("Software\\Microsoft\\Windows"
				."\\CurrentVersion\\Explorer\\Shell Folders",
				$folder)) {
			my ($type, $value);

			if ($folder->QueryValueEx("My Music", $type, $value)) {
				$path = $value . '\\iTunes\\iTunes Music Library.xml';
				$::d_itunes && msg("iTunes: found My Music here: $value for $path\n");
			}

			if ($path && -r $path) {

				return $path;

			} elsif ($folder->QueryValueEx("Personal", $type, $value)) {
				$path = $value . '\\My Music\\iTunes\\iTunes Music Library.xml';
				$::d_itunes && msg("iTunes: found  Personal: $value for $path\n");
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

	$::d_itunes && msg("iTunes: attempting to locate iTunes Music Library.xml automatically\n");

	my $base = $ENV{'HOME'} || '';

	my $path = findLibraryFromPlist($base);

	if ($path && -r $path) {

		$::d_itunes && msg("iTunes: found path via iTunes preferences at: $path\n");
		Slim::Utils::Prefs::set( 'itunes_library_xml_path', $path );

		return $path;
	}

	$path = findLibraryFromRegistry();

	if ($path && -r $path) {

		$::d_itunes && msg("iTunes: found path via Windows registry at: $path\n");
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
			$::d_itunes && msg("iTunes: found path via directory search at: $path\n");
			return $path;
		}
	}

	$::d_itunes && msg("iTunes: unable to find iTunes Music Library.xml.\n");

	return undef;
}

sub isMusicLibraryFileChanged {
	my $class = shift;

	my $file      = $class->findMusicLibraryFile();
	my $fileMTime = (stat $file)[9];

	# Set this so others can use it without going through Prefs in a tight loop.
	$class->lastITunesMusicLibraryDate( Slim::Utils::Prefs::get('lastITunesMusicLibraryDate') );
	
	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, lastITunesMusicLibraryDate is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	if ($file && $fileMTime > $class->lastITunesMusicLibraryDate) {

		my $itunesScanInterval = Slim::Utils::Prefs::get('itunesscaninterval');

		$::d_itunes && msgf("iTunes: music library has changed: %s\n", 
			scalar localtime($class->lastITunesMusicLibraryDate)
		);
		
		if (!$itunesScanInterval) {
			
			# only scan if itunesscaninterval is non-zero.
			$::d_itunes && msg("iTunes: Scan Interval set to 0, rescanning disabled\n");

			return 0;
		}

		if (!$class->lastMusicLibraryFinishTime) {
			return 1;
		}

		if (time() - $class->lastMusicLibraryFinishTime > $itunesScanInterval) {

			return 1;

		} else {

			$::d_itunes && msg("iTunes: waiting for $itunesScanInterval seconds to pass before rescanning\n");
		}
	}

	return 0;
}

sub checker {
	my $class = shift;
	my $firstTime = shift || 0;

	if (!Slim::Utils::Prefs::get('itunes')) {

		return 0;
	}

	if (!$firstTime && !$class->stillScanning && $class->isMusicLibraryFileChanged) {
		#startScan();
	}

	# make sure we aren't doing this more than once...
	#Slim::Utils::Timers::killTimers(0, \&checker);

	#my $interval = Slim::Utils::Prefs::get('itunesscaninterval') || 3600;

	# the very first time, we do want to scan right away
	#if ( $firstTime ) {
	#	$interval = 10;
	#}

	#Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $interval, \&checker);
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
		$url =~ s/$class->iTunesLibraryBasePath/$base/isg;
		$url =~ s/(\w)\/\/(\w)/$1\/$2/isg;

	} else {

		$url = Slim::Utils::Misc::fixPath($stripped);
	}

	$url =~ s/file:\/\/localhost\//file:\/\/\//;

	$::d_itunes_verbose && msg("iTunes: normalized $location to $url\n");

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
	my $class = shift;;

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
