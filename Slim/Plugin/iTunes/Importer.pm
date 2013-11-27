package Slim::Plugin::iTunes::Importer;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::iTunes::Common);

use Date::Parse qw(str2time);
use File::Spec::Functions qw(:ALL);
use File::Basename;
use File::Path qw(rmtree);
use XML::Parser;

INIT: {
	if ($] > 5.007) {
		require Encode;
	}
}

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $lastMusicLibraryFinishTime = undef;
my $lastITunesMusicLibraryDate = 0;
my $currentITunesMusicLibraryDate = 0;
my $iTunesScanStartTime = 0;

my $inPlaylists;
my $inTracks;
my %tracks = ();
my $progress;

my ($inKey, $inDict, $inValue, %item, $currentKey, $nextIsMusicFolder, $nextIsPlaylistName, $inPlaylistArray);

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.itunes',
	'defaultLevel' => 'ERROR',
});

my $prefs = preferences('plugin.itunes');

sub initPlugin {
	my $class = shift;

	return 1 if $class->initialized;

	if (!$class->canUseiTunesLibrary) {
		return;
	}

	Slim::Music::Import->addImporter($class, {
		'type'         => 'file',
		'weight'       => 20,
		'reset'        => \&resetState,
		'playlistOnly' => 1,
		'use'          => $prefs->get('itunes'),
	});
	
	if ( main::ISWINDOWS && $prefs->get('extract_artwork') ) {
		require Win32;
		require Slim::Plugin::iTunes::Importer::Artwork::Win32;
		Slim::Music::Import->addImporter( 'Slim::Plugin::iTunes::Importer::Artwork::Win32', {
			'type' => 'artwork',
			'use'  => $prefs->get('itunes'),
		} );
	}
	elsif ( main::ISMAC && $prefs->get('extract_artwork') ) {
		
		require Slim::Plugin::iTunes::Importer::Artwork::OSX;
		Slim::Music::Import->addImporter( 'Slim::Plugin::iTunes::Importer::Artwork::OSX', {
			'type' => 'artwork',
			'use'  => $prefs->get('itunes'),
		} );
	}

	Slim::Player::ProtocolHandlers->registerHandler('itunesplaylist', 0);

	$class->initialized(1);

	return 1;
}

# This will be called when wipeDB is run - we always want to rescan at that point.
sub resetState {

	main::INFOLOG && $log->info("wipedb called - resetting lastITunesMusicLibraryDate");

	$lastITunesMusicLibraryDate = -1;

	Slim::Music::Import->setLastScanTime('iTunesLastLibraryChange', -1);
	Slim::Music::Import->setLastScanTime('iTunesLastLibraryChecksum', '');
	
	# Delete the iTunes artwork cache
	my $cachedir = catdir( preferences('server')->get('librarycachedir'), 'iTunesArtwork' );
	if ( -d $cachedir ) {
		rmtree $cachedir;
	}
}

sub getTotalTrackCount {
	my $class = shift;

	return $class->_getTotalCount('Location', @_);
}

sub getTotalPlaylistCount {
	my $class = shift;

	return $class->_getTotalCount('Playlist ID', @_);
}

sub _getTotalCount {
	my $class = shift;
	my $type  = shift;
	my $file  = shift || $class->findMusicLibraryFile;

	# Get the total count of tracks for the progress bar.
	open(XML, $file) or do {

		logError("Couldn't open [$file]: [$@]");
		return 0;
	};

	my $count = 0;

	local $_;
	while(<XML>) {

		if (/<key>$type/) {
			$count++;
		}
	}

	close(XML);

	return $count;
}

sub startScan {
	my $class = shift;

	if (!$class->useiTunesLibrary) {
		return;
	}
		
	my $file = $class->findMusicLibraryFile;

	# Set the last change time for the next go-round.
	$currentITunesMusicLibraryDate = (stat($file))[9];

	main::INFOLOG && $log->info("Parsing file: $file");
	main::INFOLOG && $log->info("iTunes music_path: " . $prefs->get('music_path'));

	if (!defined $file) {

		logError("Trying to scan an iTunes XML file that doesn't exist.");
		return;
	}

	main::INFOLOG && $log->info("Get music folder from iTunes XML file");
	
	my $iTunesParser = XML::Parser->new(
		'ErrorContext'     => 2,
		'ProtocolEncoding' => 'UTF-8',
		'NoExpand'         => 1,
		'NoLWP'            => 1,
		'Handlers'         => {

			'Start' => \&handleStartElement,
			'Char'  => \&handleCharElement,
			'End'   => \&handleMusicFolderEndElement,
		},
	);

	$iTunesParser->parsefile($file);

	$progress = Slim::Utils::Progress->new({ 
		'type'  => 'importer', 
		'name'  => 'itunes', 
		'total' => $class->getTotalTrackCount($file), 
		'bar'   => 1
	});

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

	$iTunesParser->parsefile($file);

	main::INFOLOG && $log->info("Finished scanning iTunes XML");

	$class->doneScanning;
	
	# XXX return number of changes made
	return 1;
}

sub doneScanning {
	my $class = shift;

	$progress->final($class->getTotalPlaylistCount);

	main::INFOLOG && $log->info("Finished Scanning");

	$lastMusicLibraryFinishTime = time();

	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("Scan completed in %d seconds.", (time() - $iTunesScanStartTime)));
	}
	
	Slim::Music::Import->setLastScanTime( 'iTunesLastLibraryChange', $currentITunesMusicLibraryDate );
	Slim::Music::Import->setLastScanTime( 'iTunesLastLibraryChecksum', $class->getLibraryChecksum() );

	Slim::Music::Import->endImporter($class);
}

my $i;
sub handleTrack {
	my $class    = shift;
	my $curTrack = shift;

	my %cacheEntry = ();

	my $pid      = $curTrack->{'Persistent ID'};
	my $id       = $curTrack->{'Track ID'};
	my $location = $curTrack->{'Location'};

	# Always update the progress, even if we return.
	$progress->update;
	time() > $i && ($i = time + 5) && Slim::Schema->forceCommit;

	# We got nothin
	if (scalar keys %{$curTrack} == 0) {
		return 1;
	}

	if (defined $location) {
		$location = Slim::Utils::Unicode::utf8off($location);
	} else {
		return 1;
	}

	if ($location =~ /^((\d+\.\d+\.\d+\.\d+)|([-\w]+(\.[-\w]+)*)):\d+$/) {
		$location = "http://$location"; # fix missing prefix in old invalid entries
	}

	my $url = $class->normalize_location($location);
	my $file;

	if (Slim::Music::Info::isFileURL($url)) {

		$file  = Slim::Utils::Misc::pathFromFileURL($url);

		if ($] > 5.007 && $file && Slim::Utils::Unicode::currentLocale() ne 'utf8') {

			my $file2 = $file;

			eval { Encode::from_to($file, 'utf8', Slim::Utils::Unicode::currentLocale()) };

			if ($@) {
				logError("[$@]");
			}

			if (main::ISWINDOWS && !-e $file) {

				# bug 7966: try the short (8.3) file name for unreadable unicode file names
				$file2 = Slim::Utils::Unicode::utf8decode( Slim::Utils::Unicode::recomposeUnicode($file2) );
				
				if ( ($file2 = Win32::GetANSIPathName($file2)) && -e $file2 ) {
					main::DEBUGLOG && $log->debug("Falling back to DOS style 8.3 filename: $file2");
					$file = $file2;
				}
			}
		}

		# Bug 5339
		# iTunes uses decomposed utf-8 (on a MAC), which corresponds to the decomposed UTF-8 file path on an HFS+ volume.
		# if the file is moved to a different path on an NFS or SMB file system, the path is automagically
		# converted into composed utf-8.
		if (!-e $file && -e Slim::Utils::Unicode::recomposeUnicode( $file )) {
			$file = Slim::Utils::Unicode::recomposeUnicode( $file );
		}

		# Bug 3402 
		# If the file can't be found using itunes_library_music_path,
		# we want to fall back to the real file path from the XML file
		#
		# Bug 3717 - check this after we've checked the locale above.
		elsif (!-e $file && $prefs->get('music_path')) {
			$url  = $class->normalize_location($location, 'fallback');
			$file = Slim::Utils::Misc::pathFromFileURL($url);
		}

		# If the user is using both iTunes & a music folder,
		# iTunes stores the url as encoded utf8 - but we want
		# it in the locale of the machine, so we won't get duplicates.
		#
		# Likewise - iTunes uses stricter URI escaping than we care
		# for. Re-escape it.
		$url = Slim::Utils::Misc::fileURLFromPath($file);
	}

	# Use this for playlist verification.
	$tracks{$id} = $url;

	# skip track if Disabled in iTunes
	if ($curTrack->{'Disabled'} && !$prefs->get('ignore_disabled')) {

		main::INFOLOG && $log->info("Deleting disabled track $url");

		Slim::Schema->search('Track', { 'url' => $url })->delete;

		# Don't show these tracks in the playlists either.
		delete $tracks{$id};

		return 1;
	}

	if (Slim::Music::Info::isFileURL($url)) {
		
		if ( !$file || !-r $file ) {

			# Use Data::Dump to log exactly what the wrong file path is, avoiding UTF-8 output issues
			require Data::Dump;
			$log->warn("File not found: " . Data::Dump::dump($file));

			# Tell the database to cleanup.
			Slim::Schema->search('Track', { 'url' => $url })->delete;

			delete $tracks{$id};
			
			return 1;
		}

		# dsully - Sun Mar 20 22:50:41 PST 2005
		# iTunes has a last 'Date Modified' field, but
		# it isn't updated even if you edit the track
		# properties directly in iTunes (dumb) - the
		# actual mtime of the file is updated however.

		my $mtime = (stat _)[9];
		my $ctime = str2time($curTrack->{'Date Added'});

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
		    ($mtime && $mtime < $lastITunesMusicLibraryDate) &&
		    Slim::Schema->count('Track', { 'url' => $url })) {

			main::DEBUGLOG && $log->debug("Not updated, skipping: $file");

			return 1;
		}
	}

	# We don't need to do all the track processing if we just want to map
	# the ID to url, and then proceed to the playlist parsing.
	if (Slim::Music::Import->scanPlaylistsOnly) {
		return 1;
	}

	main::DEBUGLOG && $log->debug("Got a track id $id named '$curTrack->{'Name'}' location: $url");

	if ($url && (Slim::Music::Info::isSong($url) || Slim::Music::Info::isHTTPURL($url))) {

		for my $key (keys %{$curTrack}) {

			next if $key eq 'Location';

			$curTrack->{$key} = Slim::Utils::Misc::unescape($curTrack->{$key});
		}

		$cacheEntry{'EXTID'}    = $pid;
		$cacheEntry{'TITLE'}    = $curTrack->{'Name'};
		$cacheEntry{'ARTIST'}   = $curTrack->{'Artist'};
		$cacheEntry{'COMPOSER'} = $curTrack->{'Composer'};
		$cacheEntry{'TRACKNUM'} = $curTrack->{'Track Number'};

		# iTunes 7.x adds support for Album Artist.
		if ($curTrack->{'Album Artist'}) {

			$cacheEntry{'ALBUMARTIST'} = $curTrack->{'Album Artist'};
		}

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

		$cacheEntry{'AUDIO'} = 1;

		# Only read tags if we don't have a music folder defined.
		my $track = Slim::Schema->updateOrCreate({

			'url'        => $url,
			'attributes' => \%cacheEntry,
			'readTags'   => 1,
			'checkMTime' => 1,

		}) || do {

			$log->error("Couldn't create track for: $url");

			return 1;
		};
		
		# If a music folder is defined, the above updateOrCreate won't update attributes
		# We need to make sure the persistent ID is set
		if ( !$track->extid ) {
			$track->extid( $pid );
			$track->update;
		}

	} else {

		delete $tracks{$id};

		if ( $log->is_warn ) {
			$log->warn("Unknown file type " . ($curTrack->{'Kind'} || '') . " " . ($url || 'Unknown URL'));
		}
	}
}

sub handlePlaylist {
	my $class      = shift;
	my $cacheEntry = shift;

	return unless scalar @{$cacheEntry->{'LIST'}};

	my $name = Slim::Utils::Misc::unescape($cacheEntry->{'TITLE'});
	my $url  = join('', 'itunesplaylist:', Slim::Utils::Misc::escape($name));

	# Always update the progress.
	$progress->update($name);
	time() > $i && ($i = time + 5) && Slim::Schema->forceCommit;

	# this is the "all tracks" playlist - skip it
	return if $name eq '####!####';

	main::INFOLOG && $log->info("Got a playlist ($url) named $name");

	# add this playlist to our playlist library
	# 'LIST',  # list items (array)
	# 'AGE',   # list age

	$cacheEntry->{'CT'}    = 'itu';
	$cacheEntry->{'TITLE'} = join($name, 
		$prefs->get('playlist_prefix'),
		$prefs->get('playlist_suffix')
	);

	Slim::Music::Info::updateCacheEntry($url, $cacheEntry);

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("Playlist now has " . scalar @{$cacheEntry->{'LIST'}} . " items.");
	}
}

sub handleStartElement {
	my ($p, $element) = @_;

	# Don't care about the outer <dict> right after <plist>
	if ($inTracks && $element eq 'dict') {
		$inDict = 1;
	}

	if ($element eq 'key') {
		$inKey = 1;
		undef $currentKey;
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

	my $class = __PACKAGE__;

	# Just need the one value here.
	if ($nextIsMusicFolder && $inValue) {

		$nextIsMusicFolder = 0;

		$class->iTunesLibraryBasePath( $class->strip_automounter($value) );

		if ( main::INFOLOG && $log->is_info ) {
			$log->info("Found the music folder: ", $class->iTunesLibraryBasePath);
		}

		return;
	}

	# Playlists have their own array structure.
	if ($nextIsPlaylistName && $inValue) {

		$item{'TITLE'} .= $value;

		return;
	}

	if ($inKey) {
		$currentKey .= $value;
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

			main::DEBUGLOG && $log->debug("Pushing $value on to list: $tracks{$value}");

			push @{$item{'LIST'}}, $tracks{$value};

		} else {

			main::DEBUGLOG && $log->debug("NOT pushing $value on to list, it's missing (or disabled).");
		}
	}
}

sub handleEndElement {
	my ($p, $element) = @_;

	my $class = __PACKAGE__;

	# Start our state machine controller - tell the next char handler what to do next.
	if ($element eq 'key') {

		$inKey = 0;

		# This is the only top level value we care about.
		if ($currentKey eq 'Music Folder') {
			$nextIsMusicFolder = 1;
		}

		if ($currentKey eq 'Tracks') {

			main::DEBUGLOG && $log->debug("Starting track parsing.");

			$inTracks = 1;
		}

		if ($inTracks && $currentKey eq 'Playlists') {

			Slim::Schema->rs('Playlist')->clearExternalPlaylists('itunesplaylist:');

			main::DEBUGLOG && $log->debug("Starting playlist parsing, cleared old playlists");

			$inTracks = 0;
			$inPlaylists = 1;

			# Set the progress to final when we're done with tracks and have moved on to playlists.
			$progress->final;
			
			$progress = Slim::Utils::Progress->new({ 
				'type'  => 'importer', 
				'name'  => 'itunes_playlists', 
				'total' => $class->getTotalPlaylistCount, 
				'bar'   => 1
			});

		}

		if ($inPlaylists && $currentKey eq 'Name') {
			$nextIsPlaylistName = 1;
			%item = ();
		}

		return;
	}

	if ($element eq 'string' || $element eq 'integer' || $element eq 'date') {
		$inValue = 0;

		$nextIsPlaylistName = 0;
	}

	# Done reading this entry - add it to the database.
	if ($inTracks && $element eq 'dict') {

		$inDict = 0;

		$class->handleTrack(\%item);

		%item = ();
	}

	# Playlist is done.
	if ($inPlaylists && $inPlaylistArray && $element eq 'array') {

		$inPlaylistArray = 0;

		# Don't bother with 'Library' et al. - they're no real playlists or list
		# media we don't care about
		my $ignoreList = join('|', split( /,\s*/, $prefs->get('ignore_playlists') ) );

		if (defined $item{'TITLE'} && $item{'TITLE'} !~ /^(?:$ignoreList)$/i) {

			if ( main::DEBUGLOG && $log->is_debug ) {
				$log->debug("Got a playlist array of " . scalar(@{$item{'LIST'}}) . " items.");
			}

			$class->handlePlaylist(\%item);
		}

		%item = ();
	}
}

# End element handler which doesn't deal with tracks etc. Only used to find the music folder key.
sub handleMusicFolderEndElement {
	my ($p, $element) = @_;

	# Start our state machine controller - tell the next char handler what to do next.
	if ($element eq 'key') {

		$inKey = 0;

		# This is the only top level value we care about.
		if ($currentKey eq 'Music Folder') {
			$nextIsMusicFolder = 1;
		}

		return;
	}

	if ($element eq 'string' || $element eq 'integer' || $element eq 'date') {
		$inValue = 0;
	}
}

1;

__END__
