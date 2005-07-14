package Plugins::iTunes;

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# todo:
#   Enable saving current playlist in iTunes playlist format

# LKS 05-May-2004
#
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

use Date::Parse qw(str2time);
use Fcntl ':flock'; # import LOCK_* constants
use File::Spec::Functions qw(:ALL);
use File::Basename;

if ($] > 5.007) {
	require Encode;
}

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $lastMusicLibraryFinishTime = undef;
my $lastITunesMusicLibraryDate = 0;
my $iTunesScanStartTime = 0;

my $isScanning = 0;
my $opened = 0;
my $locked = 0;
my $iBase = '';

my $inPlaylists;
my $inTracks;
our %tracks;
my $applicationVersion;
my $majorVersion;
my $minorVersion;

my $ituneslibrary;
my $ituneslibraryfile;
my $ituneslibrarypath;
	
my $initialized = 0;

# mac file types
our %filetypes = (
	1095321158 => 'aif', # AIFF
	1295270176 => 'mov', # M4A 
	1295270432 => 'mov', # M4B 
#	1295274016 => 'mov', # M4P 
	1297101600 => 'mp3', # MP3 	
	1297101601 => 'mp3', # MP3! 
	1297106247 => 'mp3', # MPEG
	1297106738 => 'mp3', # MPG2 
	1297106739 => 'mp3', # MPG3 
	1299148630 => 'mov', # MooV
	1299198752 => 'mp3', # Mp3 
	1463899717 => 'wav', # WAVE
	1836069665 => 'mp3', # mp3! 
	1836082995 => 'mp3', # mpg3 
	1836082996 => 'mov', # mpg4
);

# this library imports the iTunes Music Library.xml file for use as the music
# database, instead of scanning the file system.

# should we use the itunes library?

# LKS 05-May-2004
# I have also removed the conditional code surrounding the handling
# of $newValue, since set or not we still called canUseiTunesLibrary().
# All the extra code wasn't really gaining us anything.
sub useiTunesLibrary {
	my $newValue = shift;
	
	if (defined($newValue)) {
		Slim::Utils::Prefs::set('itunes', $newValue);
	}
	
	my $use = Slim::Utils::Prefs::get('itunes');
	
	my $can = canUseiTunesLibrary();
	
	if (!defined($use) && $can) { 

		Slim::Utils::Prefs::set('itunes', 1);

	} elsif (!defined($use) && !$can) {

		Slim::Utils::Prefs::set('itunes', 0);
	}
	
	$use = Slim::Utils::Prefs::get('itunes');
	Slim::Music::Import::useImporter('ITUNES',$use && $can);
	
	$::d_itunes && msg("iTunes: using itunes library: $use\n");
	
	return $use && $can;
}

sub canUseiTunesLibrary {
	
	return 1 if $initialized;
	
	checkDefaults();

	my $oldMusicPath = Slim::Utils::Prefs::get('itunes_library_music_path');

	$ituneslibraryfile = defined $ituneslibraryfile ? $ituneslibraryfile : findMusicLibraryFile();
	$ituneslibrarypath = defined $ituneslibrarypath ? $ituneslibrarypath : findMusicLibrary();

	# The user may have moved their music folder location. We need to nuke the db.
	if ($ituneslibrarypath && $oldMusicPath && $oldMusicPath ne $ituneslibrarypath) {

		$::d_itunes && Slim::Utils::Misc::msg("iTunes: Music Folder has changed from previous - wiping db\n");

		Slim::Music::Info::wipeDBCache();

		$lastITunesMusicLibraryDate = -1;
	}

	return defined $ituneslibraryfile && defined $ituneslibrarypath;
}

sub getDisplayName {
	return 'SETUP_ITUNES';
}

sub enabled {
	return ($::VERSION !~ /^5/) && initPlugin();
}

sub getFunctions {
	return '';
}

sub initPlugin {
	return 1 if $initialized;

	Slim::Web::Setup::addChildren('server','itunes',3);
	Slim::Web::Setup::addCategory('itunes',&setupCategory);

	return unless canUseiTunesLibrary();

	$::d_itunes && Slim::Utils::Misc::msg("iTunes: Can use iTunes Music Folder - adding importer.\n");

	# Auto-turn on iTunes importer if we can use it.
	# But check to see if they've explictly turned it off.
	my $useiTunes = Slim::Utils::Prefs::get('itunes');

	if (!defined $useiTunes) {

		Slim::Utils::Prefs::set('itunes', 1);
	}

	Slim::Music::Import::addImporter('ITUNES', {
		'scan'  => \&startScan, 
		'reset' => \&resetState,
	});

	Slim::Music::Import::useImporter('ITUNES', Slim::Utils::Prefs::get('itunes'));
	Slim::Player::Source::registerProtocolHandler("itunesplaylist", "0");

	my ($groupRef,$prefRef) = setupUse();
	Slim::Web::Setup::addGroup('server','itunes',$groupRef,3,$prefRef);

	$initialized = 1;

	# Pass checker a value, to let it know that we're just seeing if we're
	# available, not to actually start the scan. Slim::Music::Import will do that.
	# Otherwise, doneScanning() will be called when Slim::Music::Import
	# kicks off, and it will reset the lastiTunesCheck time, which isn't
	# what we want. That needs to be set when we're really done scanning.
	checker($initialized);

	setPodcasts();
	
	return 1;
}

sub setPodcasts {
	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $podcast = $ds->find('playlist', {
		'url' => [ qw(itunesplaylist:podcasts*) ],
	},);
	Slim::Web::Pages::addLinks("browse",{'ITUNES_PODCASTS' => "browsedb.html?hierarchy=playlist,playlistTrack&level=1&playlist=".@$podcast[0]->id()}) if @$podcast[0];
}

# This will be called when wipeDB is run - we always want to rescan at that point.
sub resetState {

	$::d_itunes && Slim::Utils::Misc::msg("iTunes: wipedb called - resetting lastITunesMusicLibraryDate\n");

	$lastITunesMusicLibraryDate = -1;

	# set to -1 to force all the tracks to be updated.
	Slim::Utils::Prefs::set('iTunesXMLModificationDate', $lastITunesMusicLibraryDate);
}

sub disablePlugin {
	# turn off checker
	Slim::Utils::Timers::killTimers(0, \&checker);

	# remove playlists

	# disable protocol handler
	#Slim::Player::Source::registerProtocolHandler("itunesplaylist", "0");

	# reset last scan time
	$lastMusicLibraryFinishTime = undef;
	$initialized = 0;

	# delGroups, categories and prefs
	Slim::Web::Setup::delCategory('itunes');
	Slim::Web::Setup::delGroup('server','itunes',1);

	# set importer to not use
	Slim::Utils::Prefs::set('itunes', 0);
	Slim::Music::Import::useImporter('ITUNES',0);
}

sub findLibraryFromPlist {
	my $path = undef;
	my $base = shift @_;
	
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

	my $path = undef;

	my $base = "";
	$base = $ENV{'HOME'} if $ENV{'HOME'};

	my $audiodir = Slim::Utils::Prefs::get('audiodir');
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

		$path = findLibraryFromPlist($base);

		if ($path && -r $path) {
			$::d_itunes && msg("iTunes: found path via iTunes preferences at: $path\n");
			return $path;
		}

		$path = findLibraryFromRegistry();

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
	my $autolocate = Slim::Utils::Prefs::get('itunes_library_autolocate');
	my $path       = undef;
	my $file       = $ituneslibraryfile || findMusicLibraryFile();

	if (defined($file) && $autolocate) {

		$::d_itunes && msg("iTunes: attempting to locate iTunes library from $file.\n");

		# This is kind of lame - and needs to be refactored. If the
		# user moves the location of the iTunes Music Folder, we need
		# to grab that out of the XML file.
		open (ITUNESLIBRARY, $file) || do {
			$::d_itunes && msg("iTunes: Couldn't open XML file: [$file]\n");
			return;
		};

		my $len = read ITUNESLIBRARY, $ituneslibrary, -s $file;

		close ITUNESLIBRARY;

		$ituneslibrary =~ s/></>\n</g;

		while (my $curLine = getLine()) {

			next unless $curLine eq "<key>Music Folder</key>";
		
			$path = Slim::Utils::Misc::pathFromFileURL(strip_automounter(getValue()));
		
			$::d_itunes && msg("iTunes: found the music folder: $path\n");

			last;
		}

		# Reset this for later use.
		$ituneslibrary = undef;

		if ($path && -d $path) {

			$::d_itunes && msg("iTunes: set iTunes library to $file: $path\n");
			Slim::Utils::Prefs::set('itunes_library_music_path', $path);
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
	my $file = $ituneslibraryfile || findMusicLibraryFile();
	my $fileMTime = (stat $file)[9];

	# Set this so others can use it without going through Prefs in a tight loop.
	$lastITunesMusicLibraryDate = Slim::Utils::Prefs::get('iTunesXMLModificationDate');
	
	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, lastITunesMusicLibraryDate is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	if ($file && $fileMTime > $lastITunesMusicLibraryDate) {

		my $itunesscaninterval = Slim::Utils::Prefs::get('itunesscaninterval');

		$::d_itunes && msgf("iTunes: music library has changed: %s\n", scalar localtime($lastITunesMusicLibraryDate));
		
		unless ($itunesscaninterval) {
			
			# only scan if itunesscaninterval is non-zero.
			$::d_itunes && msg("iTunes: Scan Interval set to 0, rescanning disabled\n");

			return 0;
		}

		return 1 if (!$lastMusicLibraryFinishTime);
		
		if (time() - $lastMusicLibraryFinishTime > $itunesscaninterval) {

			return 1;

		} else {

			$::d_itunes && msg("iTunes: waiting for $itunesscaninterval seconds to pass before rescanning\n");
		}
	}
	
	return 0;
}

sub checker {
	my $firstTime = shift || 0;

	return unless (Slim::Utils::Prefs::get('itunes'));
	
	if (!$firstTime && !stillScanning() && isMusicLibraryFileChanged()) {
		startScan();
	}

	# make sure we aren't doing this more than once...
	Slim::Utils::Timers::killTimers(0, \&checker);

	# Call ourselves again after 10 seconds
	Slim::Utils::Timers::setTimer(0, (Time::HiRes::time() + 10.0), \&checker);
}

sub startScan {

	if (!useiTunesLibrary()) {
		return;
	}
		
	my $file = $ituneslibraryfile || findMusicLibraryFile();

	$::d_itunes && msg("iTunes: startScan on file: $file\n");

	if (!defined($file)) {
		warn "Trying to scan an iTunes file that doesn't exist.";
		return;
	}

	stopScan();

	$isScanning = 1;
	$iTunesScanStartTime = time();

	# start the checker
	checker();
	
	Slim::Utils::Scheduler::add_task(\&scanFunction);
} 

sub stopScan {
	if (stillScanning()) {

		Slim::Utils::Scheduler::remove_task(\&scanFunction);
		doneScanning();
	}
}

sub stillScanning {
	return $isScanning;
}

sub doneScanning {
	$::d_itunes && msg("iTunes: done Scanning: unlocking and closing\n");

	$locked = 0;

	$opened = 0;
	
	$ituneslibrary = undef;
	
	$lastMusicLibraryFinishTime = time();

	$isScanning = 0;

	# Set the last change time for the next go-round.
	my $file  = $ituneslibraryfile || findMusicLibraryFile();
	my $mtime = (stat($file))[9];

	$lastITunesMusicLibraryDate = $mtime;

	setPodcasts();

	if ($::d_itunes) {
		msgf("iTunes: scan completed in %d seconds.\n", (time() - $iTunesScanStartTime));
	}

	Slim::Utils::Prefs::set('iTunesXMLModificationDate', $lastITunesMusicLibraryDate);
	
	Slim::Music::Import::endImporter('ITUNES');
}

###########################################################################################
	# This incredibly ugly parser is highly dependent on the iTunes 3.0 file format.
	# A wise man with more time would use a true XML parser and integrate the appropriate
	# libraries into the distribution to work cross platform, until then...

    # Abandon all hope ye who enter here...
###########################################################################################
sub scanFunction {
	my $file = $ituneslibraryfile || findMusicLibraryFile();
	
	# this assumes that iTunes uses file locking when writing the xml file out.
	if (!$opened) {

		if (!open(ITUNESLIBRARY, "<$file")) {
			$::d_itunes && warn "Couldn't open iTunes Library: $file";
			return 0;	
		}

		$opened = 1;

		resetScanState();
	}
	
	if ($opened && !$locked) {
		$locked = 1;
		$locked = flock(ITUNESLIBRARY, LOCK_SH | LOCK_NB) unless ($^O eq 'MSWin32'); 

		if ($locked) {
			$::d_itunes && msg("iTunes: Got file lock on iTunes Library\n");
			$locked = 1;

			my $len = read ITUNESLIBRARY, $ituneslibrary, -s $file;

			die "couldn't read itunes library!" if (!defined($len));
			flock(ITUNESLIBRARY, LOCK_UN) unless ($^O eq 'MSWin32');
			close ITUNESLIBRARY;

			$ituneslibrary =~ s/></>\n</g;

		} else {
			$::d_itunes && warn "Waiting on lock for iTunes Library";
			return 1;
		}
	}
	
	my $curLine = getLine();

	if (!defined($curLine)) {

		$::d_itunes && msg("iTunes:  Finished scanning iTunes XML\n");

		doneScanning();

		return 0;
	}
	
	if ($inTracks) {

		if ($curLine eq '</dict>') {
			$inTracks = 0;
		} elsif ($curLine =~ /<key>([^<]*)<\/key>/) {

			my $id = $1;
			my %curTrack = getDict();
			my %cacheEntry = ();
			my $ds = Slim::Music::Info::getCurrentDataStore();

			# add this track to the library
			if ($id ne $curTrack{'Track ID'}) {
				warn "Danger, the Track ID (" . $curTrack{'Track ID'} . ") and the key ($id) don't match.\n";
			}
			
			my $kind = $curTrack{'Kind'};
			my $location = $curTrack{'Location'};
			my $filetype = $curTrack{'File Type'};
			my $type = undef;

			if ($filetype) {

				if (exists $Slim::Music::Info::types{$filetype}) {
					$type = $Slim::Music::Info::types{$filetype};
				} else {
					$type = $filetypes{$filetype};
				}
			}
			
			if ($location =~ /^((\d+\.\d+\.\d+\.\d+)|([-\w]+(\.[-\w]+)*)):\d+$/) {
				$location = "http://$location"; # fix missing prefix in old invalid entries
			}

			my $url = normalize_location($location);

			# Use this for playlist verification.
			$tracks{$id} = $url;

			# skip track if Disabled in iTunes
			if ($curTrack{'Disabled'} && !Slim::Utils::Prefs::get('ignoredisableditunestracks')) {

				$::d_itunes && msg("iTunes: deleting disabled track $url\n");

				$ds->markEntryAsInvalid($url);

				return 1;
			}

			if (Slim::Music::Info::isFileURL($url)) {

				# pathFromFileURL needs to convert from the
				# UTF-8 which iTunes stores it's data in to
				# the current locale - which on Windows is
				# cp1252 for most Western speakers.
				my $file  = Slim::Utils::Misc::pathFromFileURL($url);

				if ($] > 5.007 && $file && $Slim::Utils::Misc::locale ne 'utf8') {
					eval { Encode::from_to($file, 'utf8', $Slim::Utils::Misc::locale) };
				}

				# dsully - Sun Mar 20 22:50:41 PST 2005
				# iTunes has a last 'Date Modified' field, but
				# it isn't updated even if you edit the track
				# properties directly in iTunes (dumb) - the
				# actual mtime of the file is updated however.

				my $mtime = (stat($file))[9];
				my $ctime = str2time($curTrack{'Date Added'});
				
				# If the file hasn't changed since the last
				# time we checked, then don't bother going to
				# the database. A file could be new to iTunes
				# though, but it's mtime can be anything.
				#
				# A value of -1 for lastITunesMusicLibraryDate
				# means the user has pressed 'wipe db'.
				if ($lastITunesMusicLibraryDate &&
				    $lastITunesMusicLibraryDate != -1 &&
				    ($ctime && $ctime < $lastITunesMusicLibraryDate) &&
				    ($mtime && $mtime < $lastITunesMusicLibraryDate)) {

					$::d_itunes && msg("iTunes: not updated, skipping: $file\n");

					return 1;
				}

				# Reuse the stat from above.
				if (!$file || !-r _) { 
					$::d_itunes && msg("iTunes: file not found: $file\n");

					# Tell the database to cleanup.
					$ds->markEntryAsInvalid($url);

					return 1;
				}
			}

			$::d_itunes && msg("iTunes: got a track named " . $curTrack{'Name'} . " location: $location\n");

			if ($url && !defined($type)) {
				$type = Slim::Music::Info::typeFromPath($url);
			}

			if ($url && (Slim::Music::Info::isSong($url, $type) || Slim::Music::Info::isHTTPURL($url))) {

				$cacheEntry{'CT'} = $type;
				$cacheEntry{'TITLE'} = $curTrack{'Name'};
				$cacheEntry{'ARTIST'} = $curTrack{'Artist'};
				$cacheEntry{'COMPOSER'} = $curTrack{'Composer'};
				$cacheEntry{'TRACKNUM'} = $curTrack{'Track Number'};

				my $discNum = $curTrack{'Disc Number'};
				my $discCount = $curTrack{'Disc Count'};

				$cacheEntry{'DISC'} = $discNum if defined $discNum;
				$cacheEntry{'DISCC'} = $discCount if defined $discCount;
				$cacheEntry{'ALBUM'} = $curTrack{'Album'};			

				# Slim::Music::Info::addDiscNumberToAlbumTitle(\%cacheEntry);
				
				$cacheEntry{'GENRE'} = $curTrack{'Genre'};
				$cacheEntry{'FS'} = $curTrack{'Size'};

				if ($curTrack{'Total Time'}) { $cacheEntry{'SECS'} = $curTrack{'Total Time'} / 1000; };

				$cacheEntry{'BITRATE'} = $curTrack{'Bit Rate'} * 1000 if ($curTrack{'Bit Rate'});
				$cacheEntry{'YEAR'} = $curTrack{'Year'};
				$cacheEntry{'COMMENT'} = $curTrack{'Comments'};

				# cacheEntry{'???'} = $curTrack{'Track Count'};
				# cacheEntry{'???'} = $curTrack{'Sample Rate'};

				$cacheEntry{'VALID'} = '1';

				my $track = $ds->updateOrCreate({

					'url'        => $url,
					'attributes' => \%cacheEntry,
					'readTags'   => 1,

				}) || do {

					$::d_itunes && Slim::Utils::Misc::msg("Couldn't create track for: $url\n");

					return 0;
				};

				my $albumObj = $track->album();

				if (Slim::Utils::Prefs::get('lookForArtwork') && $albumObj) {

					if (!Slim::Music::Import::artwork($albumObj) && !defined $track->thumb()) {

						Slim::Music::Import::artwork($albumObj, $track);
					}
				}

				%curTrack = ();
				%cacheEntry = ();

			} else {

				$::d_itunes && Slim::Utils::Misc::msg(
					"iTunes: unknown file type %s " . ($url || ''), $curTrack{'Kind'}
				);
			} 

		}

	} elsif ($inPlaylists) {
		
		if ($curLine eq '</array>') {

			$inPlaylists = 0;

			%tracks = ();
		
		} else {
		
			my %curPlaylist = getDict();
			my %cacheEntry = ();
			my $name = $curPlaylist{'Name'};
			my $url = 'itunesplaylist:' . Slim::Web::HTTP::escape($name);
			$url = Slim::Utils::Misc::fixPath($url);

			$::d_itunes && msg("iTunes: got a playlist ($url) named $name\n");

			if ($name eq 'Library') {
				
				$::d_itunes && msg("iTunes: Skipping default 'Library' playlist.\n");
				return 1;
			}
		
			# add this playlist to our playlist library
			#	'LIST',	 # list items (array)
			#	'AGE',   # list age
		
			$cacheEntry{'TITLE'} = Slim::Utils::Prefs::get('iTunesplaylistprefix') . $name . Slim::Utils::Prefs::get('iTunesplaylistsuffix');
			$cacheEntry{'LIST'} = $curPlaylist{'Playlist Items'};
			$cacheEntry{'CT'} = 'itu';
			$cacheEntry{'TAG'} = 1;
			$cacheEntry{'VALID'} = '1';
		
			Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);

			%curPlaylist = ();
			%cacheEntry  = ();
	
			# This is inaccurate.	
			#$::d_itunes && msg("iTunes: playlists now has " . scalar Slim::Music::Info::playlists() . " items...\n");
		}

	} else {
		if ($curLine eq "<key>Major Version</key>") {
		
			$majorVersion = getValue();
		
			$::d_itunes && msg("iTunes Major Version: $majorVersion\n");
		
		} elsif ($curLine eq "<key>Minor Version</key>") {
		
			$minorVersion = getValue();
		
			$::d_itunes && msg("iTunes Minor Version: $minorVersion\n");
		
		} elsif ($curLine eq "<key>Application Version</key>") {
		
			$applicationVersion = getValue();
		
			$::d_itunes && msg("iTunes application version: $applicationVersion\n");
		
		} elsif ($curLine eq "<key>Music Folder</key>") {
		
			$iBase = getValue();
			#$iBase = Slim::Utils::Misc::pathFromFileURL($iBase);
			$iBase = strip_automounter($iBase);
		
			$::d_itunes && msg("iTunes: found the music folder: $iBase\n");
		
		} elsif ($curLine eq "<key>Tracks</key>") {
		
			$inTracks = 1;

			$inPlaylists = 0;
		
			$::d_itunes && msg("iTunes: starting track parsing\n");
		
		} elsif ($curLine eq "<key>Playlists</key>") {
		
			$inPlaylists = 1;

			$inTracks = 0;
			
			Slim::Music::Info::clearPlaylists('itunesplaylist:');
			
			$::d_itunes && msg("iTunes: starting playlist parsing, cleared old playlists\n");
		
		}
	}

	return 1;
}

sub normalize_location {
	my $location = shift;
	my $url;
	
	my $stripped = strip_automounter($location);

	# on non-mac or windows, we need to substitute the itunes library path for the one in the iTunes xml file
	if (Slim::Utils::OSDetect::OS() eq 'unix') {
		
		# find the new base location.  make sure it ends with a slash.
		my $path = $ituneslibrarypath || findMusicLibrary();
		my $base = Slim::Utils::Misc::fileURLFromPath($path);

		$url = $stripped;		
		$url =~ s,$iBase,$base,isg;
		$url =~ s,(\w)\/\/(\w),$1\/$2,isg;

	} else {
		$url = Slim::Utils::Misc::fixPath($stripped);
	}

	$url =~ s,file:\/\/localhost\/,file:\/\/\/,;
	
	$::d_itunes_verbose && msg("iTunes: normalized $location to $url\n");

	return $url;
}

sub getValue {
	my $curLine = getLine();
	my $data = '';
	
	if ($curLine =~ /^<(?=[ids])(?:integer|date|string)>([^<]*)<\/(?=[ids])(?:integer|date|string)>$/) {
		$data = $1;

	} elsif ($curLine eq '<true/>') {
	
		$data = 1;
	
	} elsif ($curLine eq '<data>') {
	
		$curLine = getLine();
	
		while (defined($curLine) && ($curLine ne '</data>')) {
			$data .= $curLine;
			$curLine = getLine();
		}
	
	} elsif ($curLine =~ /<string>([^<]*)/) {
			$data = $1;
			$curLine = getLine();
	
			while (defined($curLine) && ($curLine !~ /<\/string>/)) {
				$data .= $curLine;
				$curLine = getLine();
			}
	
			if ($curLine =~ /([^<]*)<\/string>/) {
				$data .= $1;
			}
	
	}

	$data =~ s/&#(\d*);/chr($1)/ge;

	return $data;
}

sub getPlaylistTrackArray {
	my @playlist = ();
	my $curLine = getLine();
	
	if ($curLine ne '<array>') {
		warn "Unexpected $curLine in playlist track array while looking for <array>";
		return;
	}
		
	while (($curLine = getLine()) && ($curLine ne '</array>')) {

		if ($curLine ne '<dict>') {
			warn "Unexpected $curLine in playlist track array while looking for <dict>";
			return;
		}
		
		$curLine = getLine();
		
		if ($curLine ne '<key>Track ID</key>') {
			warn "Unexpected $curLine in playlist track array while looking for track id";
			return \@playlist;
		}
		
		my $value = getValue();
		
		if (defined($tracks{$value})) {
			push @playlist, $tracks{$value};
			$::d_itunes_verbose && msg("  pushing $value on to list: " . $tracks{$value} . "\n");
		
		} else {
			$::d_itunes_verbose && msg("  NOT pusing $value on to list, it's missing\n");
		}

		$curLine = getLine();
		
		if ($curLine ne '</dict>') {
			warn "Unexpected $curLine in playlist track array while looking for </dict>";
			return \@playlist;
		}
	}	
	
	$::d_itunes && msg("got a playlist array of " . scalar(@playlist) . " items\n");
	
	return \@playlist;
}

sub getLine {
	my $curLine;
	
	$ituneslibrary =~ /([^\n]*)\n/g;	
	
	$curLine = $1;
	
	if (!defined($curLine)) {
		return undef;
	}
	
	$curLine =~ s/^\s+//;
	$curLine =~ s/\s$//;
	
	$::d_itunes_verbose && msg("Got line: $curLine\n");
	return $curLine;
}

sub getDict {
	my $curLine;
	my $nextLine;
	my %dict;
	
	while ($curLine = getLine()) {
		my $key = undef;
		my $value = undef;
		
		if ($curLine =~ /<key>([^<]*)<\/key>/) {
			$key = $1;
			
			if ($key eq "Playlist Items") {
				$value = getPlaylistTrackArray();
			} else {
				$value = getValue();
			}			
			
			if (defined($key) && defined($value)) { 
				$dict{$key} = $value;
				$::d_itunes_verbose && msg("got dictionary entry: $key = $value\n");
			} else {
				warn "iTunes: Couldn't get key and value in dictionary, got $key and $value";
			}
		
		} elsif ($curLine eq '<dict>') {
			$::d_itunes_verbose && msg("found beginning of dictionary\n");
		
		} elsif ($curLine eq '</dict>') {
			$::d_itunes_verbose && msg("found end of dictionary\n");
			last;
		
		} else {
			warn "iTunes: Confused looking for key in dictionary";
		}
	}
	return %dict;
}

sub resetScanState {
	
	$inPlaylists = 0;
	
	$inTracks = 0;
	
	$applicationVersion = undef;
	
	$majorVersion = undef;
	
	$minorVersion = undef;
	
	%tracks = ();
}

sub strip_automounter {
	my $path = shift;
	
	if ($path && ($path =~ /automount/)) {
	
		#Strip out automounter 'private' paths.
		#OSX wants us to use file://Network/ or timeouts occur
		#There may be more combinations
		$path =~ s/private\/var\/automount\///;
		$path =~ s/private\/automount\///;
		$path =~ s/automount\/static\///;
	}
	
	#remove trailing slash
	$path && $path =~ s/\/$//;

	return $path;
}

sub setupUse {
	my $client = shift;

	my %setupGroup = (
		'PrefOrder' => ['itunes']
		,'PrefsInTable' => 1
		,'Suppress_PrefHead' => 1
		,'Suppress_PrefDesc' => 1
		,'Suppress_PrefLine' => 1
		,'Suppress_PrefSub' => 1
		,'GroupHead' => string('SETUP_ITUNES')
		,'GroupDesc' => string('SETUP_ITUNES_DESC')
		,'GroupLine' => 1
				,'GroupSub' => 1
	);
	my %setupPrefs = (
		'itunes'	=> {
			'validate' => \&Slim::Web::Setup::validateTrueFalse
			,'changeIntro' => ""
			,'options' => {
				'1' => string('USE_ITUNES'),
				'0' => string('DONT_USE_ITUNES')
			}
			,'onChange' => 	sub {
				my ($client,$changeref,$paramref,$pageref) = @_;

				foreach my $client (Slim::Player::Client::clients()) {
					Slim::Buttons::Home::updateMenu($client);
				}
				Slim::Music::Import::useImporter('ITUNES',$changeref->{'itunes'}{'new'});
				Slim::Music::Import::startScan('ITUNES');
			}
			,'optionSort' => 'KR'
			,'inputTemplate' => 'setup_input_radio.html'
		}
	);
	return (\%setupGroup,\%setupPrefs);
}

#sub setupGroup {
#	my $client = shift;
#	
#	my %setupGroup = (
#		'PrefOrder' => ['debug']
#		,'PrefsInTable' => 1
#		,'Suppress_PrefHead' => 1
#		,'Suppress_PrefDesc' => 1
#		,'Suppress_PrefLine' => 1
#		,'Suppress_PrefSub' => 1
#		,'GroupHead' => string('SETUP_ITUNES')
#		,'GroupDesc' => string('SETUP_ITUNES_DESC')
#		,'GroupLine' => 1
#				,'GroupSub' => 1
#	);
#	
#	my %setupPrefs = (
#		'debug'	=> {
#			'validate' => \&Slim::Web::Setup::validateTrueFalse
#			,'changeIntro' => "iTunes Debug"
#			,'options' => {
#					'1' => string('ON')
#					,'0' => string('OFF')
#				}
#			,'onChange' => 	sub {
#					my ($client,$changeref,$paramref,$pageref) = @_;
#
#					if ($changeref->{'debug'}{'new'}) {
#						$::d_import .= ($::d_itunes) ? "" : "itunes";
#					} else {
#						$::d_import =~ s/itunes//ig;
#					}
#					print $::d_import;
#				}
#			,'optionSort' => 'KR'
#			,'inputTemplate' => 'setup_input_radio.html'
#		}
#	);
#	
#	return (\%setupGroup,\%setupPrefs);
#}

sub checkDefaults {
	if (!Slim::Utils::Prefs::isDefined('itunesscaninterval')) {
		Slim::Utils::Prefs::set('itunesscaninterval',60)
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
	
	if (!Slim::Utils::Prefs::isDefined('itunes_library_music_path')) {
		Slim::Utils::Prefs::set('itunes_library_music_path',Slim::Utils::Prefs::defaultAudioDir());
	}
	
	if (!Slim::Utils::Prefs::isDefined('itunes_library_autolocate')) {
		Slim::Utils::Prefs::set('itunes_library_autolocate',1);
	}

	if (!Slim::Utils::Prefs::isDefined('iTunesXMLModificationDate')) {
		Slim::Utils::Prefs::set('iTunesXMLModificationDate',0);
	}
}

sub setupCategory {
	my %setupCategory =(
		'title' => string('SETUP_ITUNES')
		,'parent' => 'server'
		,'GroupOrder' => ['Default','iTunesPlaylistFormat']
		,'Groups' => {
			'Default' => {
					'PrefOrder' => ['itunesscaninterval','ignoredisableditunestracks','itunes_library_autolocate','itunes_library_xml_path','itunes_library_music_path']
				}
			,'iTunesPlaylistFormat' => {
					'PrefOrder' => ['iTunesplaylistprefix','iTunesplaylistsuffix']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => string('SETUP_ITUNESPLAYLISTFORMAT')
					,'GroupDesc' => string('SETUP_ITUNESPLAYLISTFORMAT_DESC')
					,'GroupLine' => 1
					,'GroupSub' => 1
				}
			}
		,'Prefs' => {
			'itunesscaninterval' => {
					'validate' => \&Slim::Web::Setup::validateNumber
					,'validateArgs' => [0,undef,1000]
				}
			,'iTunesplaylistprefix' => {
					'validate' => \&Slim::Web::Setup::validateAcceptAll
					,'PrefSize' => 'large'
				}
			,'iTunesplaylistsuffix' => {
					'validate' => \&Slim::Web::Setup::validateAcceptAll
					,'PrefSize' => 'large'
				}
			,'ignoredisableditunestracks' => {
					'validate' => \&Slim::Web::Setup::validateTrueFalse
					,'options' => {
							'1' => string('SETUP_IGNOREDISABLEDITUNESTRACKS_1')
							,'0' => string('SETUP_IGNOREDISABLEDITUNESTRACKS_0')
						}
				}
			,'itunes_library_xml_path' => {
					'validate' => \&Slim::Web::Setup::validateIsFile
					,'changeIntro' => string('SETUP_OK_USING')
					,'rejectMsg' => string('SETUP_BAD_FILE')
					,'PrefSize' => 'large'
				}
			,'itunes_library_music_path' => {
					'validate' => \&Slim::Web::Setup::validateIsDir
					,'changeIntro' => string('SETUP_OK_USING')
					,'rejectMsg' => string('SETUP_BAD_DIRECTORY')
					,'PrefSize' => 'large'
				}
			,'itunes_library_autolocate' => {
					'validate' => \&Slim::Web::Setup::validateTrueFalse
					,'options' => {
							'1' => string('SETUP_ITUNES_LIBRARY_AUTOLOCATE_1')
							,'0' => string('SETUP_ITUNES_LIBRARY_AUTOLOCATE_0')
						}
				}
		}
	);

	return (\%setupCategory);
}

sub strings {
	return '';
}

1;

__END__

