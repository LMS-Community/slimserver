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
#	itunes_library_autolocate
#		-- if this is set (1), attempt to automatically set both
#		itunes_library_xml_path or itunes_library_music_path.  If
#		this is unset (0) or undefined, you MUST explicitly set both
#		itunes_library_xml_path and itunes_library_music_path.
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

	$class->mk_classdata('iTunesLibraryPath');
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

	if (!defined($use) && $can) {

		Slim::Utils::Prefs::set('itunes', 1);

	} elsif (!defined($use) && !$can) {

		Slim::Utils::Prefs::set('itunes', 0);
	}

	$use = Slim::Utils::Prefs::get('itunes');

	Slim::Music::Import->useImporter($class, $use && $can);

	$::d_itunes && msg("iTunes: using itunes library: $use\n");

	return $use && $can;
}

sub canUseiTunesLibrary {
	my $class = shift;

	return 1 if $class->initialized;

	$class->checkDefaults;

	my $oldMusicPath = Slim::Utils::Prefs::get('itunes_library_music_path');

	if (!defined $class->iTunesLibraryPath) {

		 $class->iTunesLibraryPath( $class->findMusicLibrary );
	}

	# The user may have moved their music folder location. We need to nuke the db.
	if ($class->iTunesLibraryPath && $oldMusicPath && $oldMusicPath ne $class->iTunesLibraryPath) {

		$::d_itunes && msg("iTunes: Music Folder has changed from previous - wiping db\n");

		Slim::Music::Info::wipeDBCache();

		$class->lastITunesMusicLibraryDate(-1);
	}

	return defined $class->findMusicLibraryFile && defined $class->iTunesLibraryPath;
}

sub setPodcasts {
	my $class = shift;

	if (!$INC{'Slim::Web::Pages'}) {
		return;
	}

	my $ds = Slim::Music::Info::getCurrentDataStore();

	my @podcasts  = $ds->find({
		'field' => 'genre',
		'find'  => { 'genre.name' => 'Podcasts' },
	});

	if ($podcasts[0]) {
		my $id = $podcasts[0]->id;
		
		Slim::Web::Pages::addLinks("browse", {
			'ITUNES_PODCASTS' => "browsedb.html?hierarchy=genre,artist,album,track&level=2&&genre=".$id
		});

		Slim::Buttons::Home::addMenuOption('ITUNES_PODCASTS', {
			'useMode'      => 'browsedb',
			'hierarchy'    => 'genre,artist,album,track',
			'level'        => 2,
			'findCriteria' => {'genre' => $id},
		});

		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC','ITUNES_PODCASTS', {
			'useMode'      => 'browsedb',
			'hierarchy'    => 'genre,artist,album,track',
			'level'        => 2,
			'findCriteria' => {'genre' => $id},
		});
	}
}

sub findLibraryFromPlist {
	my $class = shift;
	my $base  = shift;

	my $path  = undef;

	my $plist = catfile(($base, 'Library', 'Preferences'), 'com.apple.iApps.plist');

	open (PLIST, $plist) || return $path;

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

	my $path = undef;
	my $base = $ENV{'HOME'} || '';

	my $audiodir   = Slim::Utils::Prefs::get('audiodir');
	my $autolocate = Slim::Utils::Prefs::get('itunes_library_autolocate');

	if ($autolocate) {
		$::d_itunes && msg("iTunes: attempting to locate iTunes Music Library.xml\n");

		# This defines the list of directories we will search for
		# the 'iTunes Music Library.xml' file.
		my @searchdirs = (
			catdir($base, 'Music', 'iTunes'),
			catdir($base, 'Documents', 'iTunes'),
			$base,
		);

		if (defined $audiodir) {
			push @searchdirs, (
				catdir($audiodir, 'My Music', 'iTunes'),
				catdir($audiodir, 'iTunes'),
				$audiodir
			);
		}

		$path = $class->findLibraryFromPlist($base);

		if ($path && -r $path) {
			$::d_itunes && msg("iTunes: found path via iTunes preferences at: $path\n");
			return $path;
		}

		$path = $class->findLibraryFromRegistry();

		if ($path && -r $path) {
			$::d_itunes && msg("iTunes: found path via Windows registry at: $path\n");
			return $path;
		}

		for my $dir (@searchdirs) {
			$path = catfile(($dir), 'iTunes Music Library.xml');

			if ($path && -r $path) {
				$::d_itunes && msg("iTunes: found path via directory search at: $path\n");
				Slim::Utils::Prefs::set('itunes_library_xml_path',$path);
				return $path;
			}

		}
	}

	if (!$path) {
		$path = Slim::Utils::Prefs::get('itunes_library_xml_path');

		if ($path && -d $path) {
			$path = catfile(($path), 'iTunes Music Library.xml');
		}

		if ($path && -r $path) {
			Slim::Utils::Prefs::set('itunes_library_xml_path',$path);
			$::d_itunes && msg("iTunes: found path via config file at: $path\n");
			return $path;
		}
	}		

	$::d_itunes && msg("iTunes: unable to find iTunes Music Library.xml.\n");

	return undef;
}

sub findMusicLibrary {
	my $class = shift;

	my $autolocate = Slim::Utils::Prefs::get('itunes_library_autolocate');
	my $path = undef;

	my $file = $class->findMusicLibraryFile();

	if (defined($file) && $autolocate) {
		$::d_itunes && msg("iTunes: attempting to locate iTunes library relative to $file.\n");

		my $itunesdir = dirname($file);
		$path = catdir($itunesdir, 'iTunes Music');

		if ($path && -d $path) {
			$::d_itunes && msg("iTunes: set iTunes library relative to $file: $path\n");
			Slim::Utils::Prefs::set('itunes_library_music_path',$path);
			return $path;
		}
	}

	$path = Slim::Utils::Prefs::get('itunes_library_music_path');

	if ($path && -d $path) {
		$::d_itunes && msg("iTunes: set iTunes library to itunes_library_music_path value of: $path\n");
		return $path;
	}

	$path = Slim::Utils::Prefs::get('audiodir') || return undef;

	$::d_itunes && msg("iTunes: set iTunes library to audiodir value of: $path\n");

	Slim::Utils::Prefs::set('itunes_library_music_path', $path);

	return $path;
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

	# Call ourselves again after 10 seconds
	#Slim::Utils::Timers::setTimer(0, (Time::HiRes::time() + 10.0), \&checker);
}

sub normalize_location {
	my $class    = shift;
	my $location = shift;
	my $url;

	my $stripped = $class->strip_automounter($location);

	# on non-mac or windows, we need to substitute the itunes library path for the one in the iTunes xml file
	if (Slim::Utils::OSDetect::OS() eq 'unix') {

		# find the new base location.  make sure it ends with a slash.
		my $path = $class->iTunesLibraryPath || $class->findMusicLibrary;
		my $base = Slim::Utils::Misc::fileURLFromPath($path);

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

	if (!Slim::Utils::Prefs::isDefined('ignoredisableditunestracks')) {
		Slim::Utils::Prefs::set('ignoredisableditunestracks',0);
	}

	if (!Slim::Utils::Prefs::isDefined('itunes_library_music_path')) {
		Slim::Utils::Prefs::set('itunes_library_music_path',Slim::Utils::Prefs::defaultAudioDir());
	}

	if (!Slim::Utils::Prefs::isDefined('itunes_library_autolocate')) {
		Slim::Utils::Prefs::set('itunes_library_autolocate',1);
	}

	if (!Slim::Utils::Prefs::isDefined('lastITunesMusicLibraryDate')) {
		Slim::Utils::Prefs::set('lastITunesMusicLibraryDate',0);
	}
}

1;

__END__
