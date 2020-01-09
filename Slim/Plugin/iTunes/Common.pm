package Slim::Plugin::iTunes::Common;

# Logitech Media Server Copyright 2001-2020 Logitech.
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
#		in iTunes will still be available to Logitech Media Server.  If this is
#		unset (0) or undefined, disabled songs will be skipped.
#
#	itunesscaninterval
#		-- how long to wait between checking
#		'iTunes Music Library.xml' for changes.

use strict;
use base qw(Class::Data::Inheritable);

use Digest::SHA1;
use File::Spec::Functions qw(:ALL);
use File::Basename;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $log = logger('plugin.itunes');

my $prefs = preferences('plugin.itunes');
my $prefsServer = preferences('server');

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
		$prefs->set('itunes', $newValue);
	}

	my $use = $prefs->get('itunes');
	my $can = $class->canUseiTunesLibrary();

	Slim::Music::Import->useImporter($class, $use && $can);

	main::INFOLOG && $log->info("Using iTunes library: $use");

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

	local $_;
	while (<PLIST>) {
		if (/<string>(.*iTunes%20Music%20Library.xml)<\/string>$/) {
			$path = Slim::Utils::Misc::pathFromFileURL($1);
			last;
		}
		elsif (/<string>(.*iTunes%20Library.xml)<\/string>$/) {
			$path = Slim::Utils::Misc::pathFromFileURL($1);
			last;
		}
		elsif (/(file:\/\/localhost.*iTunes%20Music%20Library.xml)/) {
			$path = Slim::Utils::Misc::pathFromFileURL($1);
			last;
		}
		elsif (/(file:\/\/localhost.*iTunes%20Library.xml)/) {
			$path = Slim::Utils::Misc::pathFromFileURL($1);
			last;
		}
	}

	close PLIST;

	return $path;
}

sub findLibraryFromRegistry {
	if (main::ISWINDOWS) {
		my $class = shift;
		my $path  = undef;

		Slim::bootstrap::tryModuleLoad('Win32::TieRegistry');

		if (!$@) {

			require Win32::TieRegistry;

			$Win32::TieRegistry::Registry->Delimiter('/');
			$Win32::TieRegistry::Registry->ArrayValues(0);
			
			if (my $folder = $Win32::TieRegistry::Registry->{"HKEY_CURRENT_USER/Software/Microsoft/Windows"
					."/CurrentVersion/Explorer/Shell Folders/My Music"}) {
				
				$path = $folder . '\\iTunes\\iTunes Music Library.xml';
					
				if (! -r $path) {
					$path = $folder . '\\My Music\\iTunes\\iTunes Library.xml';
				}
				
				main::INFOLOG && $log->info("Searching 'My Music' here: $folder for $path");

				if ($path && -r $path) {

					return $path;

				}
			}
			
			if (my $folder = $Win32::TieRegistry::Registry->{"HKEY_CURRENT_USER/Software/Microsoft/Windows"
					."/CurrentVersion/Explorer/Shell Folders/Personal"}) {

				$path = $folder . '\\My Music\\iTunes\\iTunes Music Library.xml';
				
				if (! -r $path) {
					$path = $folder . '\\My Music\\iTunes\\iTunes Library.xml';
				}
				
				main::INFOLOG && $log->info("Searching 'Personal' here: $folder for $path");
			}
		}

		return $path;
	}
}

sub findMusicLibraryFile {
	my $class = shift;

	my $explicit_xml_path = $prefs->get('xml_file');

	if ($explicit_xml_path) {

		if (-d $explicit_xml_path) {
			$explicit_xml_path =  catfile(($explicit_xml_path), 'iTunes Music Library.xml');
		}
			 
		if (!-r $explicit_xml_path) {
			$explicit_xml_path =  catfile(($explicit_xml_path), 'iTunes Library.xml');
		}
		
		if (-r $explicit_xml_path) {
			return $explicit_xml_path;
		}
	}

	main::INFOLOG && $log->info("Attempting to locate iTunes Music Library.xml automatically");

	my $base = $ENV{'HOME'} || '';

	my $path = $class->findLibraryFromPlist($base);

	if ($path && -r $path) {

		main::INFOLOG && $log->info("Found path via iTunes preferences at: $path");

		$prefs->set('xml_file', $path );

		return $path;
	}

	$path = $class->findLibraryFromRegistry();

	if ($path && -r $path) {

		main::INFOLOG && $log->info("Found path via Windows registry at: $path");

		$prefs->set('xml_file', $path );

		return $path;
	}

	# This defines the list of directories we will search for
	# the 'iTunes Music Library.xml' file.
	my @searchdirs = (
		catdir($base, 'Music', 'iTunes'),
		catdir($base, 'Documents', 'iTunes'),
		$base,
	);

	my $mediadirs = Slim::Utils::Misc::getAudioDirs();

	if (scalar @{ $mediadirs }) {
		foreach my $audiodir (@{ $mediadirs }) {
			push @searchdirs, (
				catdir($audiodir, 'My Music', 'iTunes'),
				catdir($audiodir, 'iTunes'),
				$audiodir
			);
		}
	}
	
	for my $dir (@searchdirs) {
		$path = catfile(($dir), 'iTunes Music Library.xml');

		if (!($path && -r $path)) {

			$path = catfile(($dir), 'iTunes Library.xml');
		}
		
		if ($path && -r $path) {

			main::INFOLOG && $log->info("Found path via directory search at: $path");

			return $path;
		}
	}

	main::INFOLOG && $log->info("Unable to find iTunes Music Library.xml");

	return undef;
}

sub getLibraryChecksum {
	my ( $class, $file ) = @_;
	
	$file ||= $class->findMusicLibraryFile();
	
	open my $fh, '<', $file;
	binmode $fh;
	
	my $sha1 = Digest::SHA1->new;
	$sha1->addfile($fh);
	my $checksum = $sha1->hexdigest;
	
	close $fh;
	
	return $checksum;
}

sub isMusicLibraryFileChanged {
	my $class = shift;

	my $file = $class->findMusicLibraryFile() || return;

	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, iTunesLastLibraryChange is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	my $lastScanTime       = Slim::Music::Import->lastScanTime;
	my $lastiTunesChange   = Slim::Music::Import->lastScanTime('iTunesLastLibraryChange');
	my $lastiTunesChecksum = Slim::Music::Import->lastScanTime('iTunesLastLibraryChecksum');

	# Set this so others can use it without going through the DB in a tight loop.
	$class->lastITunesMusicLibraryDate($lastiTunesChange);

	if ($class->getLibraryChecksum($file) ne $lastiTunesChecksum) {

		my $scanInterval = $prefs->get('scan_interval');

		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug("lastiTunesChange: " . scalar localtime($lastiTunesChange));
			$log->debug("lastScanTime    : $lastScanTime");
			$log->debug("scanInterval    : $scanInterval");
		}

		if (!$scanInterval) {

			# only scan if itunesscaninterval is non-zero.
			main::INFOLOG && $log->info("Scan Interval set to 0, rescanning disabled.");

			return 0;
		}

		if (!$lastScanTime) {

			main::INFOLOG && $log->info("lastScanTime is 0: Will start scanning.");

			return 1;
		}

		if ((time - $lastScanTime) > $scanInterval) {

			main::INFOLOG && $log->info("(time - lastScanTime) > scanInterval: Will start scanning.");

			return 1;

		} else {

			main::INFOLOG && $log->info("Waiting for $scanInterval seconds to pass before rescanning");
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
	my $explicit_path = $prefs->get('music_path');

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

	main::DEBUGLOG && $log->debug("Normalized $location to $url");

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

	if (!defined $prefs->get('scan_interval')) {
		$prefs->set('scan_interval', $class->iTunesScanInterval);
	}

	if (!defined $prefs->get('playlist_prefix')) {
		$prefs->set('playlist_prefix','');
	}

	if (!defined $prefs->get('playlist_suffix')) {
		$prefs->set('playlist_suffix','');
	}

	if (!defined $prefs->get('ignore_disabled')) {
		$prefs->set('ignore_disabled',0);
	}

	if (!defined $prefs->get('lastITunesMusicLibraryDate')) {
		$prefs->set('lastITunesMusicLibraryDate',0);
	}

	if (!defined $prefs->get('itunes')) {
		require Slim::Utils::OSDetect;

		# disable iTunes unless
		# - an iTunes XML file is found
		# - or we're on a Mac
		# - or we're running Windows (but not Windows Home Server)
		if (defined $class->findMusicLibraryFile() || main::ISMAC 
				|| (main::ISWINDOWS && !Slim::Utils::OSDetect->getOS()->get('isWHS'))) {
			$prefs->set('itunes', 1);
		}
		else {
			$prefs->set('itunes', 0);
		}
	}
	
	if (!defined $prefs->get('ignore_playlists')) {
		$prefs->set('ignore_playlists', string('ITUNES_IGNORED_PLAYLISTS_DEFAULTS'))
	}
}

1;

__END__
