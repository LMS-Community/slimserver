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
use XML::Parser;

if ($] > 5.007) {
	require Encode;
}

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $lastMusicLibraryFinishTime = undef;
my $lastITunesMusicLibraryDate = 0;
my $currentITunesMusicLibraryDate = 0;
my $iTunesScanStartTime = 0;

my $isScanning = 0;
my $opened = 0;
my $locked = 0;
my $iBase = '';

my $inPlaylists;
my $inTracks;
our %tracks;

my $iTunesLibraryFile;
my $iTunesParser;
my $iTunesParserNB;
my $offset = 0;

my ($inKey, $inDict, $inValue, %item, $currentKey, $nextIsMusicFolder, $nextIsPlaylistName, $inPlaylistArray);

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

	Slim::Music::Import::useImporter('ITUNES',$use && $can);

	$::d_itunes && msg("iTunes: using itunes library: $use\n");

	return $use && $can;
}

sub canUseiTunesLibrary {

	return 1 if $initialized;

	checkDefaults();

	return defined findMusicLibraryFile();
}

sub getDisplayName {
	return 'SETUP_ITUNES';
}

sub enabled {
	return ($::VERSION ge '6.1');
}

sub getFunctions {
	return '';
}

sub initPlugin {
	return 1 if $initialized;

	addGroups();

	return unless canUseiTunesLibrary();

	Slim::Music::Import::addImporter('ITUNES', {
		'scan'  => \&startScan,
		'reset' => \&resetState,
		'setup' => \&addGroups,
	});

	Slim::Music::Import::useImporter('ITUNES',Slim::Utils::Prefs::get('itunes'));
	Slim::Player::ProtocolHandlers->registerHandler('itunesplaylist', 0);
	
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

	my @podcasts  = $ds->find({
		'field' => 'genre',
		'find' => { 'genre.name' => 'Podcasts' },
	});

	if ($podcasts[0]) {
		my $id = $podcasts[0]->id;
		
		Slim::Web::Pages->addPageLinks("browse", {
			'ITUNES_PODCASTS' => "browsedb.html?hierarchy=genre,artist,album,track&level=2&&genre=".$id
		});

		Slim::Buttons::Home::addMenuOption('ITUNES_PODCASTS', {
			'useMode'  => 'browsedb',
			'hierarchy' => 'genre,artist,album,track',
			'level' => 2,
			'findCriteria' => {'genre' => $id},
		});

		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC','ITUNES_PODCASTS', {
			'useMode'  => 'browsedb',
			'hierarchy' => 'genre,artist,album,track',
			'level' => 2,
			'findCriteria' => {'genre' => $id},
		});
	}
}

# This will be called when wipeDB is run - we always want to rescan at that point.
sub resetState {

	$::d_itunes && msg("iTunes: wipedb called - resetting lastITunesMusicLibraryDate\n");

	$lastITunesMusicLibraryDate = -1;

	# set to -1 to force all the tracks to be updated.
	Slim::Utils::Prefs::set('lastITunesMusicLibraryDate', $lastITunesMusicLibraryDate);
}

sub shutdownPlugin {
	# turn off checker
	Slim::Utils::Timers::killTimers(0, \&checker);

	# remove playlists

	# disable protocol handler
	#Slim::Player::ProtocolHandlers->registerHandler('itunesplaylist', 0);

	# reset last scan time
	$lastMusicLibraryFinishTime = undef;
	$initialized = 0;

	# delGroups, categories and prefs
	Slim::Web::Setup::delCategory('ITUNES');
	Slim::Web::Setup::delGroup('SERVER_SETTINGS','itunes',1);

	# set importer to not use
	#Slim::Utils::Prefs::set('itunes', 0);
	Slim::Music::Import::useImporter('ITUNES',0);
}

sub addGroups {
	Slim::Web::Setup::addChildren('SERVER_SETTINGS','ITUNES',3);
	Slim::Web::Setup::addCategory('ITUNES',&setupCategory);

	my ($groupRef,$prefRef) = &setupUse();

	Slim::Web::Setup::addGroup('SERVER_SETTINGS','itunes',$groupRef,2,$prefRef);
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
	my $path = undef;
	my $base = "";
	$base = $ENV{'HOME'} if $ENV{'HOME'};

	$path = findLibraryFromPlist($base);

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
			Slim::Utils::Prefs::set( 'itunes_library_xml_path', $path );
			return $path;
		}

	}

	$::d_itunes && msg("iTunes: unable to find iTunes Music Library.xml.\n");

	return undef;
}

sub isMusicLibraryFileChanged {

	my $file      = findMusicLibraryFile();
	my $fileMTime = (stat $file)[9];

	# Set this so others can use it without going through Prefs in a tight loop.
	$lastITunesMusicLibraryDate = Slim::Utils::Prefs::get('lastITunesMusicLibraryDate');
	
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
	
	my $interval = Slim::Utils::Prefs::get('itunesscaninterval') || 3600;
	
	# the very first time, we do want to scan right away
	if ( $firstTime ) {
		$interval = 10;
	}
	
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $interval, \&checker);
}

sub startScan {

	if (!useiTunesLibrary()) {
		return;
	}
		
	my $file = findMusicLibraryFile();

	$::d_itunes && msg("iTunes: startScan on file: $file\n");

	if (!defined($file)) {
		warn "Trying to scan an iTunes file that doesn't exist.";
		return;
	}

	stopScan();

	$isScanning = 1;
	$iTunesScanStartTime = time();

	$iTunesParser = XML::Parser->new(
		'ErrorContext'     => 2,
		'ProtocolEncoding' => 'UTF-8',
		'NoExpand'         => 1,
		'NoLWP'            => 1,
		'Handlers'         => {

			'Start' => \&handleStartElement,
			'Char'  => \&handleCharElement,
			'End'   => \&handleEndElement,
		},
	);

	Slim::Utils::Scheduler::add_task(\&scanFunction);
}

sub stopScan {

	if (stillScanning()) {

		$::d_itunes && msg("iTunes: Was stillScanning - stopping old scan.\n");

		Slim::Utils::Scheduler::remove_task(\&scanFunction);
		$isScanning = 0;
		$locked = 0;
		$opened = 0;
		
		close(ITUNESLIBRARY);
		$iTunesParser = undef;
		resetScanState();
	}

	$iTunesLibraryFile = undef;
}

sub stillScanning {
	return $isScanning;
}

sub doneScanning {
	$::d_itunes && msg("iTunes: done Scanning: unlocking and closing\n");

	if (defined $iTunesParserNB) {

		# This spews, but it's harmless.
		eval { $iTunesParserNB->parse_done };
	}

	$iTunesParserNB = undef;
	$iTunesParser   = undef;

	$locked = 0;
	$opened = 0;

	$iTunesLibraryFile = undef;
	$lastMusicLibraryFinishTime = time();
	$isScanning = 0;

	# Don't leak filehandles.
	close(ITUNESLIBRARY);

	setPodcasts();

	if ($::d_itunes) {
		msgf("iTunes: scan completed in %d seconds.\n", (time() - $iTunesScanStartTime));
	}

	Slim::Utils::Prefs::set('lastITunesMusicLibraryDate', $currentITunesMusicLibraryDate);

	# Take the scanner off the scheduler.
	Slim::Utils::Scheduler::remove_task(\&scanFunction);

	Slim::Music::Import::endImporter('ITUNES');
}

sub scanFunction {
	$iTunesLibraryFile ||= findMusicLibraryFile();

	# this assumes that iTunes uses file locking when writing the xml file out.
	if (!$opened) {

		$::d_itunes && msg("iTunes: opening iTunes Library XML file.\n");

		open(ITUNESLIBRARY, $iTunesLibraryFile) || do {
			$::d_itunes && warn "iTunes: Couldn't open iTunes Library: $iTunesLibraryFile";
			return 0;
		};

		$opened = 1;

		resetScanState();

		# Set the last change time for the next go-round.
		my $mtime = (stat($iTunesLibraryFile))[9];
	
		$currentITunesMusicLibraryDate = $mtime;
	}

	if ($opened && !$locked) {

		$::d_itunes && msg("iTunes: Attempting to get lock on iTunes Library XML file.\n");

		$locked = 1;
		$locked = flock(ITUNESLIBRARY, LOCK_SH | LOCK_NB) unless ($^O eq 'MSWin32'); 

		if ($locked) {

			$::d_itunes && msg("iTunes: Got file lock on iTunes Library\n");

			$locked = 1;

			if (defined $iTunesParser) {

				$::d_itunes && msg("iTunes: Created a new Non-blocking XML parser.\n");

				$iTunesParserNB = $iTunesParser->parse_start();

			} else {

				$::d_itunes && msg("iTunes: No iTunesParser was defined!\n");
			}

		} else {

			$::d_itunes && warn "iTunes: Waiting on lock for iTunes Library";
			return 1;
		}
	}

	# parse a little more from the stream.
	if (defined $iTunesParserNB) {

		#$::d_itunes && msg("iTunes: Parsing next bit of XML..\n");

		local $/ = '</dict>';
		my $line = <ITUNESLIBRARY>;

		$iTunesParserNB->parse_more($line);

		return 1;
	}

	$::d_itunes && msg("iTunes: No iTunesParserNB defined!\n");

	return 0;
}

sub handleTrack {
	my $curTrack = shift;

	my $ds = Slim::Music::Info::getCurrentDataStore();
	my %cacheEntry = ();

	my $id       = $curTrack->{'Track ID'};
	my $location = $curTrack->{'Location'};
	my $filetype = $curTrack->{'File Type'};
	my $type     = undef;

	# We got nothin
	if (scalar keys %{$curTrack} == 0) {
		return 1;
	}

	if (defined $location) {
		$location = Slim::Utils::Unicode::utf8off($location);
	}

	if ($location =~ /^((\d+\.\d+\.\d+\.\d+)|([-\w]+(\.[-\w]+)*)):\d+$/) {
		$location = "http://$location"; # fix missing prefix in old invalid entries
	}

	my $url = normalize_location($location);
	my $file;

	if (Slim::Music::Info::isFileURL($url)) {

		$file  = Slim::Utils::Misc::pathFromFileURL($url);
		
		# Bug 3402
		# If the file can't be found using itunes_library_music_path,
		# we want to fall back to the real file path from the XML file
		if ( !-e $file ) {
			
			if ( Slim::Utils::Prefs::get('itunes_library_music_path') ) {
				$url  = normalize_location( $location, 'fallback' ); 
				$file = Slim::Utils::Misc::pathFromFileURL($url);
			}
		}

		if ($] > 5.007 && $file && Slim::Utils::Unicode::currentLocale() ne 'utf8') {

			eval { Encode::from_to($file, 'utf8', Slim::Utils::Unicode::currentLocale()) };

			if ($@) {
				errorMsg("iTunes: handleTrack: [$@]\n");
			}

			# If the user is using both iTunes & a music folder,
			# iTunes stores the url as encoded utf8 - but we want
			# it in the locale of the machine, so we won't get
			# duplicates.
			$url = Slim::Utils::Misc::fileURLFromPath($file);
		}
	}

	# Use this for playlist verification.
	$tracks{$id} = $url;

	# skip track if Disabled in iTunes
	if ($curTrack->{'Disabled'} && !Slim::Utils::Prefs::get('ignoredisableditunestracks')) {

		$::d_itunes && msg("iTunes: deleting disabled track $url\n");

		$ds->markEntryAsInvalid($url);

		# Don't show these tracks in the playlists either.
		delete $tracks{$id};

		return 1;
	}

	if (Slim::Music::Info::isFileURL($url)) {

		# dsully - Sun Mar 20 22:50:41 PST 2005
		# iTunes has a last 'Date Modified' field, but
		# it isn't updated even if you edit the track
		# properties directly in iTunes (dumb) - the
		# actual mtime of the file is updated however.

		my $mtime = (stat($file))[9];
		my $ctime = str2time($curTrack->{'Date Added'});

		# If the file hasn't changed since the last
		# time we checked, then don't bother going to
		# the database. A file could be new to iTunes
		# though, but it's mtime can be anything.
		#
		# A value of -1 for lastITunesMusicLibraryDate
		# means the user has pressed 'wipe db'.
		# also check to see if that track is in the library by looking for 
		# a lightweighttrack via objectForUrl()
		if ($lastITunesMusicLibraryDate &&
		    $lastITunesMusicLibraryDate != -1 &&
		    ($ctime && $ctime < $lastITunesMusicLibraryDate) &&
		    ($mtime && $mtime < $lastITunesMusicLibraryDate) &&
		    ref($ds->objectForUrl($url,0,0,1))) {

			$::d_itunes && msg("iTunes: not updated, skipping: $file\n");

			return 1;
		}

		# Reuse the stat from above.
		if (!$file || !-r _) { 
			$::d_itunes && msg("iTunes: file not found: $file\n");

			# Tell the database to cleanup.
			$ds->markEntryAsInvalid($url);

			delete $tracks{$id};

			return 1;
		}
	}

	# We don't need to do all the track processing if we just want to map
	# the ID to url, and then proceed to the playlist parsing.
	if (Slim::Music::Import::scanPlaylistsOnly()) {
		return 1;
	}

	$::d_itunes && msg("iTunes: got a track named " . $curTrack->{'Name'} . " location: $url\n");

	if ($filetype) {

		if (exists $Slim::Music::Info::types{$filetype}) {
			$type = $Slim::Music::Info::types{$filetype};
		} else {
			$type = $filetypes{$filetype};
		}
	}

	if ($url && !defined($type)) {
		$type = Slim::Music::Info::typeFromPath($url);
	}

	if ($url && (Slim::Music::Info::isSong($url, $type) || Slim::Music::Info::isHTTPURL($url))) {

		for my $key (keys %{$curTrack}) {

			next if $key eq 'Location';

			$curTrack->{$key} = Slim::Utils::Misc::unescape($curTrack->{$key});
		}

		$cacheEntry{'CT'}       = $type;
		$cacheEntry{'TITLE'}    = $curTrack->{'Name'};
		$cacheEntry{'ARTIST'}   = $curTrack->{'Artist'};
		$cacheEntry{'COMPOSER'} = $curTrack->{'Composer'};
		$cacheEntry{'TRACKNUM'} = $curTrack->{'Track Number'};

		my $discNum   = $curTrack->{'Disc Number'};
		my $discCount = $curTrack->{'Disc Count'};

		$cacheEntry{'DISC'}  = $discNum   if defined $discNum;
		$cacheEntry{'DISCC'} = $discCount if defined $discCount;
		$cacheEntry{'ALBUM'} = $curTrack->{'Album'};

		$cacheEntry{'GENRE'} = $curTrack->{'Genre'};
		$cacheEntry{'FS'}    = $curTrack->{'Size'};

		if ($curTrack->{'Total Time'}) {
			$cacheEntry{'SECS'} = $curTrack->{'Total Time'} / 1000;
		}

		$cacheEntry{'BITRATE'}   = $curTrack->{'Bit Rate'} * 1000 if $curTrack->{'Bit Rate'};
		$cacheEntry{'YEAR'}      = $curTrack->{'Year'};
		$cacheEntry{'COMMENT'}   = $curTrack->{'Comments'};
		$cacheEntry{'RATE'}      = $curTrack->{'Sample Rate'};
		$cacheEntry{'RATING'}    = $curTrack->{'Rating'};
		$cacheEntry{'PLAYCOUNT'} = $curTrack->{'Play Count'};
		
		my $gain = $curTrack->{'Volume Adjustment'};
		
		# looking for a defined or non-zero volume adjustment
		if ($gain) {
			# itunes uses a range of -255 to 255 to be -100% (silent) to 100% (+6dB)
			if ($gain == -255) {
				$gain = -96.0;
			} else {
				$gain = 20.0 * log(($gain+255)/255)/log(10);
			}
			$cacheEntry{'REPLAYGAIN_TRACK_GAIN'} = $gain;
		}

		$cacheEntry{'VALID'} = 1;

		my $track = $ds->updateOrCreate({

			'url'        => $url,
			'attributes' => \%cacheEntry,
			'readTags'   => 1,
			'checkMTime' => 1,

		}) || do {

			$::d_itunes && msg("iTunes: Couldn't create track for: $url\n");

			return 1;
		};

		my $albumObj = $track->album;

		if (Slim::Utils::Prefs::get('lookForArtwork') && $albumObj) {

			if (!Slim::Music::Import::artwork($albumObj) && !defined $track->thumb) {

				Slim::Music::Import::artwork($albumObj, $track);
			}
		}

	} else {

		$::d_itunes && msg("iTunes: unknown file type " . ($curTrack->{'Kind'} || '') . " " . ($url || 'Unknown URL') . "\n");

	}
}

sub handlePlaylist {
	my $cacheEntry = shift;

	my $name = Slim::Utils::Misc::unescape($cacheEntry->{'TITLE'});
	my $url  = 'itunesplaylist:' . $cacheEntry->{'TITLE'};

	$::d_itunes && msg("iTunes: got a playlist ($url) named $name\n");

	# add this playlist to our playlist library
	# 'LIST',  # list items (array)
	# 'AGE',   # list age

	$cacheEntry->{'TITLE'} = Slim::Utils::Prefs::get('iTunesplaylistprefix') . $name . Slim::Utils::Prefs::get('iTunesplaylistsuffix');
	$cacheEntry->{'CT'}    = 'itu';
	$cacheEntry->{'TAG'}   = 1;
	$cacheEntry->{'VALID'} = '1';

	Slim::Music::Info::updateCacheEntry($url, $cacheEntry);

	# Check for podcasts and add to custom Genre
	if ($name =~ /podcasts/i) {			
		my $ds = Slim::Music::Info::getCurrentDataStore();
		
		foreach my $url (@{$cacheEntry->{'LIST'}}) {
			# update with Podcast genre
			my $track = $ds->updateOrCreate({
				'url'        => $url,
				'attributes' => {'GENRE' => 'Podcasts'},
			});
		}
	}

	$::d_itunes && msg("iTunes: playlists now has " . scalar @{$cacheEntry->{'LIST'}} . " items...\n");
}

sub handleStartElement {
	my ($p, $element) = @_;

	# Don't care about the outer <dict> right after <plist>
	if ($inTracks && $element eq 'dict') {
		$inDict = 1;
	}

	if ($element eq 'key') {
		$inKey = 1;
	}

	# If we're inside the playlist element, and the array is starting,
	# clear out the previous array (defensive), and mark ourselves as inside.
	if ($inPlaylists && defined $item{'TITLE'} && $element eq 'array') {

		@{$item{'LIST'}} = ();
		$inPlaylistArray = 1;
	}

	# Disabled tracks are marked as such:
	# <key>Disabled</key><true/>
	if ($element eq 'true') {

		$item{$currentKey} = 1;
	}

	# Store this value somewhere.
	if ($element eq 'string' || $element eq 'integer' || $element eq 'date') {
		$inValue = 1;
	}
}

sub handleCharElement {
	my ($p, $value) = @_;

	# Just need the one value here.
	if ($nextIsMusicFolder && $inValue) {

		$nextIsMusicFolder = 0;

		#$iBase = Slim::Utils::Misc::pathFromFileURL($iBase);
		$iBase = strip_automounter($value);
		
		$::d_itunes && msg("iTunes: found the music folder: $iBase\n");

		return;
	}

	# Playlists have their own array structure.
	if ($nextIsPlaylistName && $inValue) {

		$item{'TITLE'} = $value;
		$nextIsPlaylistName = 0;

		return;
	}

	if ($inKey) {
		$currentKey = $value;
		return;
	}

	if ($inTracks && $inValue) {

		if ($] > 5.007) {
			$item{$currentKey} .= $value;
		} else {
			$item{$currentKey} .= Slim::Utils::Unicode::utf8toLatin1($value);
		}

		return;
	}

	if ($inPlaylistArray && $inValue) {

		if (defined($tracks{$value})) {

			$::d_itunes_verbose && msg("iTunes: pushing $value on to list: " . $tracks{$value} . "\n");

			push @{$item{'LIST'}}, $tracks{$value};

		} else {

			$::d_itunes_verbose && msg("iTunes: NOT pushing $value on to list, it's missing (or disabled).\n");
		}
	}
}

sub handleEndElement {
	my ($p, $element) = @_;

	# Start our state machine controller - tell the next char handler what to do next.
	if ($element eq 'key') {

		$inKey = 0;

		# This is the only top level value we care about.
		if ($currentKey eq 'Music Folder') {
			$nextIsMusicFolder = 1;
		}

		if ($currentKey eq 'Tracks') {

			$::d_itunes && msg("iTunes: starting track parsing\n");

			$inTracks = 1;
		}

		if ($inTracks && $currentKey eq 'Playlists') {

			Slim::Music::Info::clearPlaylists('itunesplaylist:');

			$::d_itunes && msg("iTunes: starting playlist parsing, cleared old playlists\n");

			$inTracks = 0;
			$inPlaylists = 1;
		}

		if ($inPlaylists && $currentKey eq 'Name') {
			$nextIsPlaylistName = 1;
		}

		return;
	}

	if ($element eq 'string' || $element eq 'integer' || $element eq 'date') {
		$inValue = 0;
	}

	# Done reading this entry - add it to the database.
	if ($inTracks && $element eq 'dict') {

		$inDict = 0;

		handleTrack(\%item);

		%item = ();
	}

	# Playlist is done.
	if ($inPlaylists && $inPlaylistArray && $element eq 'array') {

		$inPlaylistArray = 0;

		# Don't bother with 'Library' - it's not a real playlist
		if (defined $item{'TITLE'} && $item{'TITLE'} ne 'Library') {

			$::d_itunes && msg("iTunes: got a playlist array of " . scalar(@{$item{'LIST'}}) . " items\n");

			handlePlaylist(\%item);
		}

		%item = ();
	}

	# Finish up
	if ($element eq 'plist') {
		$::d_itunes && msg("iTunes: Finished scanning iTunes XML\n");

		doneScanning();

		return 0;
	}
}

sub resetScanState {

	$::d_itunes && msg("iTunes: Resetting scan state.\n");

	$inPlaylists = 0;
	$inTracks = 0;

	$inKey = 0;
	$inDict = 0;
	$inValue = 0;
	%item = ();
	$currentKey = undef;
	$nextIsMusicFolder = 0;
	$nextIsPlaylistName = 0;
	$inPlaylistArray = 0;
	
	%tracks = ();
}

sub normalize_location {
	my $location = shift;
	my $fallback = shift;   # if set, ignore itunes_library_music_path
	my $url;

	my $stripped = strip_automounter($location);

	# on non-mac or windows, we need to substitute the itunes library path for the one in the iTunes xml file
	my $explicit_path = Slim::Utils::Prefs::get('itunes_library_music_path');
	
	if ( $explicit_path && !$fallback ) {

		# find the new base location.  make sure it ends with a slash.
		my $base = Slim::Utils::Misc::fileURLFromPath($explicit_path);

		$url = $stripped;
		$url =~ s/$iBase/$base/isg;
		$url =~ s/(\w)\/\/(\w)/$1\/$2/isg;

	} else {

		$url = Slim::Utils::Misc::fixPath($stripped);
	}

	$url =~ s/file:\/\/localhost\//file:\/\/\//;

	$::d_itunes_verbose && msg("iTunes: normalized $location to $url\n");

	return $url;
}

sub strip_automounter {
	my $path = shift;

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

sub setupUse {
	my $client = shift;

	my %setupGroup = (
		'PrefOrder' => ['itunes'],
		'PrefsInTable' => 1,
		'Suppress_PrefHead' => 1,
		'Suppress_PrefDesc' => 1,
		'Suppress_PrefLine' => 1,
		'Suppress_PrefSub' => 1,
		'GroupHead' => 'SETUP_ITUNES',
		'GroupDesc' => 'SETUP_ITUNES_DESC',
		'GroupLine' => 1,
		'GroupSub' => 1,
	);

	my %setupPrefs = (

		'itunes' => {

			'validate' => \&Slim::Utils::Validate::trueFalse,
			'changeIntro' => "",
			'options' => {
				'1' => string('USE_ITUNES'),
				'0' => string('DONT_USE_ITUNES'),
			},

			'onChange' => sub {
				my ($client, $changeref, $paramref, $pageref) = @_;

				foreach my $tempClient (Slim::Player::Client::clients()) {
					Slim::Buttons::Home::updateMenu($tempClient);
				}

				Slim::Music::Import::useImporter('ITUNES',$changeref->{'itunes'}{'new'});
				Slim::Music::Import::startScan('ITUNES');
			},

			'optionSort' => 'KR',
			'inputTemplate' => 'setup_input_radio.html',
		}
	);

	return (\%setupGroup, \%setupPrefs);
}

sub checkDefaults {
	my $iTunesScanInterval = 3600;

	if (!Slim::Utils::Prefs::isDefined('itunesscaninterval')) {

		Slim::Utils::Prefs::set('itunesscaninterval', $iTunesScanInterval);
	}

	if (!Slim::Utils::Prefs::isDefined('iTunesplaylistprefix')) {
		Slim::Utils::Prefs::set('iTunesplaylistprefix','iTunes: ');
	}

	if (!Slim::Utils::Prefs::isDefined('ignoredisableditunestracks')) {
		Slim::Utils::Prefs::set('ignoredisableditunestracks',0);
	}

	if (!Slim::Utils::Prefs::isDefined('lastITunesMusicLibraryDate')) {
		Slim::Utils::Prefs::set('lastITunesMusicLibraryDate',0);
	}

	if (!Slim::Utils::Prefs::isDefined('itunes')) {
		if (defined(findMusicLibraryFile())) {
			Slim::Utils::Prefs::set('itunes', 1);
		}
	}
}

sub setupCategory {

	my %setupCategory = (

		'title' => string('SETUP_ITUNES'),

		'parent' => 'SERVER_SETTINGS',

		'GroupOrder' => [qw(Default iTunesPlaylistFormat)],

		'Groups' => {

			'Default' => {
				'PrefOrder' => ['itunesscaninterval',
								'ignoredisableditunestracks',
								'itunes_library_xml_path',
								'itunes_library_music_path']
			},

			'iTunesPlaylistFormat' => {
				'PrefOrder' => ['iTunesplaylistprefix','iTunesplaylistsuffix'],
				'PrefsInTable' => 1,
				'Suppress_PrefHead' => 1,
				'Suppress_PrefDesc' => 1,
				'Suppress_PrefLine' => 1,
				'Suppress_PrefSub' => 1,
				'GroupHead' => string('SETUP_ITUNESPLAYLISTFORMAT'),
				'GroupDesc' => string('SETUP_ITUNESPLAYLISTFORMAT_DESC'),
				'GroupLine' => 1,
				'GroupSub' => 1,
			}
		},

		'Prefs' => {

			'itunesscaninterval' => {
				'validate' => \&Slim::Utils::Validate::number,
				'validateArgs' => [0,undef,1000],
			},

			'iTunesplaylistprefix' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'PrefSize' => 'large'
			},

			'iTunesplaylistsuffix' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'PrefSize' => 'large'
			},

			'ignoredisableditunestracks' => {

				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options' => {
					'1' => string('SETUP_IGNOREDISABLEDITUNESTRACKS_1'),
					'0' => string('SETUP_IGNOREDISABLEDITUNESTRACKS_0'),
				},
			},

			'itunes_library_xml_path' => {
				'validate' => \&Slim::Utils::Validate::isFile,
				'validateArgs' => [1],
				'changeIntro' => string('SETUP_OK_USING'),
				'rejectMsg' => string('SETUP_BAD_FILE'),
				'PrefSize' => 'large',
			},

			'itunes_library_music_path' => {
				'validate' => \&Slim::Utils::Validate::isDir,
				'validateArgs' => [1],
				'changeIntro' => string('SETUP_OK_USING'),
				'rejectMsg' => string('SETUP_BAD_DIRECTORY'),
				'PrefSize' => 'large',
			},
		}
	);

	return \%setupCategory;
}

sub strings {
	return '';
}

1;

__END__
