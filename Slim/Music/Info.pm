package Slim::Music::Info;

# $Id: Info.pm,v 1.142 2004/08/21 00:54:11 kdf Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Fcntl;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

use MP3::Info;

use Slim::Formats::Movie;
use Slim::Formats::AIFF;
use Slim::Formats::FLAC;
use Slim::Formats::MP3;
use Slim::Formats::Ogg;
use Slim::Formats::Wav;
use Slim::Formats::WMA;
use Slim::Formats::Musepack;
use Slim::Formats::Shorten;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Text;

eval "use Storable";

# Constants:

# the items in the infocache that we actually use
# NOTE: THE ORDER MATTERS HERE FOR THE PERSISTANT DB
# IF YOU ADD SOMETHING, PUT IT AT THE END
# AND CHANGE $DBVERSION
my @infoCacheItems = (
	'CT',	 # content type
	'TITLE', # title
	'LIST',	 # list items (array)
	'AGE',   # list age
	'GENRE', # genre
	'TRACKNUM', # tracknumber as an int
	'FS',	 # file size
	'SIZE',	 # audio data size in bytes
	'OFFSET', # offset to start of song
	'ARTIST', # artist
	'ALBUM',  # album name
	'COMMENT',	# ID3 comment
	'YEAR',		# year
	'SECS', 	# total seconds
	'VBR_SCALE', # vbr/cbr
	'BITRATE', # bitrate
	'TAGVERSION', # ID3 tag version
	'COMPOSER', # composer
	'TAGSIZE', # tagsize
	'DISC', # album number in a set 
	'DISCC', # number of albums in a set
	'MOODLOGIC_SONG_ID', # MoodLogic fields
	'MOODLOGIC_ARTIST_ID', #
	'MOODLOGIC_GENRE_ID', #
	'MOODLOGIC_SONG_MIXABLE', #
	'MOODLOGIC_ARTIST_MIXABLE', #
	'MOODLOGIC_GENRE_MIXABLE', #
	'COVER', # cover art
	'COVERTYPE', # cover art content type
	'THUMB', # thumbnail cover art
	'THUMBTYPE', #thumnail content type
	'TAG', # have we read the tags yet?
	'ALBUMSORT',
	'ARTISTSORT',
	'TITLESORT',
	'RATE', # Sample rate
	'SAMPLESIZE', # Sample size
	'CHANNELS', # number of channels
	'BAND',
	'CONDUCTOR', # conductor
	'BLOCKALIGN', # block alignment
	'ENDIAN', # 0 - little endian, 1 - big endian
	'VALID', # 0 - entry not checked, 1 - entry checked and valid. Used to find stale entries in the cache
	'TTL', # Time to Live for Cache Entry
	'BPM', # Beats per minute
);

# Save the persistant DB cache every hour
my $dbSaveInterval = 3600;
# Entries in cache are assumed to be valid for 5 minutes before we check date/time stamps again
my $dbCacheLifeTime = 5 * 60;
my $dbCacheDirty = 0;		# Set to 0 if cache is clean, 1 if dirty

# three hashes containing the types we know about, populated by the loadTypesConfig routine below
# hash of default mime type index by three letter content type e.g. 'mp3' => audio/mpeg
%Slim::Music::Info::types = ();

# hash of three letter content type, indexed by mime type e.g. 'text/plain' => 'txt'
%Slim::Music::Info::mimeTypes = ();

# hash of three letter content types, indexed by file suffixes (past the dot)  'aiff' => 'aif'
%Slim::Music::Info::suffixes = ();

# hash of types that the slim server recoginzes internally e.g. aif => audio
%Slim::Music::Info::slimTypes = ();

# Global caches:

# a hierarchical cache of genre->artist->album->tracknum based on ID3 information
my %genreCache = ();

# a cache of the titles used for uniquely identifing and sorting items 
my %caseCache = ();

my %sortCache = ();

# the main cache of ID3 and other metadata
my %infoCache = ();

# moodlogic cache for genre and artist mix indicator; empty if moodlogic isn't used
my %genreMixCache = ();
my %artistMixCache = ();

my $songCount = 0;
my $total_time = 0;

my %songCountMemoize = ();
my %artistCountMemoize = ();
my %albumCountMemoize = ();
my %genreCountMemoize = ();

my %infoCacheItemsIndex;

my $dbname;
my $DBVERSION = 13;

my %artworkCache = ();
my $artworkDir;
my %lastFile;

my @playlists=();

# Hash for tag function per format
my %tagFunctions = (
			'mp3' => \&Slim::Formats::MP3::getTag
			,'mp2' => \&Slim::Formats::MP3::getTag
			,'ogg' => \&Slim::Formats::Ogg::getTag
			,'flc' => \&Slim::Formats::FLAC::getTag
			,'wav' => \&Slim::Formats::Wav::getTag
			,'aif' => \&Slim::Formats::AIFF::getTag
			,'wma' => \&Slim::Formats::WMA::getTag
			,'mov' => \&Slim::Formats::Movie::getTag
			,'shn' => \&Slim::Formats::Shorten::getTag
			,'mpc' => \&Slim::Formats::Musepack::getTag
		);

# if we don't have storable, then stub out the cache routines

if (defined @Storable::EXPORT) {

	eval q{
		sub saveDBCache {

			if (Slim::Utils::Prefs::get('usetagdatabase') && $dbCacheDirty) {
		
				my $cacheToStore = {
					'albumCountMemoize'   => \%albumCountMemoize,
					'artistCountMemoize'  => \%artistCountMemoize,
					'artistMixCache'      => \%artistMixCache,
					'artworkCache'        => \%artworkCache,
					'caseCache'           => \%caseCache,
					'genreCache'          => \%genreCache,
					'genreCountMemoize'   => \%genreCountMemoize,
					'genreMixCache'       => \%genreMixCache,
					'infoCache'           => \%infoCache,
					'songCount'           => \$songCount,
					'songCountMemoize'    => \%songCountMemoize,
					'sortCache'           => \%sortCache,
					'total_time'          => \$total_time,
					'playlists'           => \@playlists,
					'ver'                 => $DBVERSION,
				};
			
				# "store" "die"s on fatal errors, so catch that with an "eval"
				eval {
						$::d_info && Slim::Utils::Misc::msg("saving DB cache: $dbname\n");

						store($cacheToStore, $dbname);

						$::d_info && Slim::Utils::Misc::msg("DB cache saved\n");

						$dbCacheDirty = 0;
				};

				if ($@ ne "") {
						$::d_info && Slim::Utils::Misc::msg("could not save DB cache ($@)\n");
				}

				$dbCacheDirty = 0;
			}
		}
		
		sub loadDBCache {

			return unless Slim::Utils::Prefs::get('usetagdatabase');
			
			$::d_info && Slim::Utils::Misc::msg("ID3 tag database support is ON, saving into: $dbname\n");

			clearDBCache();

			if (! -f $dbname || -z $dbname) {

				$::d_info && Slim::Utils::Misc::msg("Tag database $dbname does not exist or has zero size\n");

				%infoCache = ();

				Slim::Music::Import::startScan();

				$dbCacheDirty = 1;

				return;
			}

			# Pull in the flushed data from Storable.
			my $cacheToRead = retrieve($dbname);
			my $version     = $cacheToRead->{'ver'};

			if (!defined($version) || $version ne $DBVERSION) {

				$::d_info && Slim::Utils::Misc::msg(
					"Deleting Tag database. DB is version ". $version ." and SlimServer is $DBVERSION\n"
				);

				%infoCache = ();

				Slim::Music::Import::startScan();

				$dbCacheDirty = 1;

			} else {

				%albumCountMemoize   = %{$cacheToRead->{'albumCountMemoize'}};
				%artistCountMemoize  = %{$cacheToRead->{'artistCountMemoize'}};
				%artistMixCache      = %{$cacheToRead->{'artistMixCache'}};
				%artworkCache        = %{$cacheToRead->{'artworkCache'}};
				%caseCache           = %{$cacheToRead->{'caseCache'}};
				%genreCache          = %{$cacheToRead->{'genreCache'}};
				%genreCountMemoize   = %{$cacheToRead->{'genreCountMemoize'}};
				%genreMixCache       = %{$cacheToRead->{'genreMixCache'}};
				%infoCache           = %{$cacheToRead->{'infoCache'}};
				%songCountMemoize    = %{$cacheToRead->{'songCountMemoize'}};
				%sortCache           = %{$cacheToRead->{'sortCache'}};
				$songCount           = ${$cacheToRead->{'songCount'}};
				@playlists           = @{$cacheToRead->{'playlists'}};
				$total_time          = ${$cacheToRead->{'total_time'}};
				$dbCacheDirty        = 0;
			}
		}
		
		sub scanDBCache {

			return unless Slim::Utils::Prefs::get('usetagdatabase');

			$::d_info && Slim::Utils::Misc::msg("starting cache scan\n");
		
			my $validindex = $infoCacheItemsIndex{"VALID"};
			my $thumbindex = $infoCacheItemsIndex{"THUMB"};
			my $coverindex = $infoCacheItemsIndex{"COVER"};
			
			foreach my $file (keys %infoCache) {
			
				my $cacheEntryArray = $infoCache{$file};

				# Mark all data as invalid for now
				$cacheEntryArray->[$validindex] = '0';

				# Remove any entry for uncached coverart - we scan for it again once upon a rescan
				if (defined $cacheEntryArray->[$thumbindex] && $cacheEntryArray->[$thumbindex] eq "0") { 

					$cacheEntryArray->[$thumbindex] = undef;
				}

				if (defined $cacheEntryArray->[$coverindex] && $cacheEntryArray->[$coverindex] eq "0") { 

					$cacheEntryArray->[$coverindex] = undef;
				}
			
			}

			$::d_info && Slim::Utils::Misc::msg("finished cache scan\n");
		}
	};

} else {
	eval q{
		sub saveDBCache { };
		sub loadDBCache { };
		sub scanDBCache { };
	}
}

##################################################################################
# these routines deal with the caches directly
##################################################################################
sub init {

	loadTypesConfig();
	
	my $i = 0;
	foreach my $tag (@infoCacheItems) {
		$infoCacheItemsIndex{$tag} = $i;
		$i++;
	}

	# Setup $dbname regardless of if we're caching as cache could be turned on later

	if (Slim::Utils::OSDetect::OS() eq 'unix') {
		$dbname = '.slimserver.db';
	} else {
		$dbname ='slimserver.db';
	}

	$dbname = catdir(Slim::Utils::Prefs::get('cachedir'), $dbname);
	
	if (Slim::Utils::Prefs::get('usetagdatabase')) {
		loadDBCache();
	}

	saveDBCacheTimer(); # Start the timer to save the DB every $dbSaveInterval
	
	# use all the genres we know about...
	MP3::Info::use_winamp_genres();
	
	# also get the album, performer and title sort information
	$MP3::Info::v2_to_v1_names{'TSOA'} = 'ALBUMSORT';
	$MP3::Info::v2_to_v1_names{'TSOP'} = 'ARTISTSORT';
	$MP3::Info::v2_to_v1_names{'XSOP'} = 'ARTISTSORT';
	$MP3::Info::v2_to_v1_names{'TSOT'} = 'TITLESORT';

	# get composers
	$MP3::Info::v2_to_v1_names{'TCM'} = 'COMPOSER';
	$MP3::Info::v2_to_v1_names{'TCOM'} = 'COMPOSER';

	# get band/orchestra
	$MP3::Info::v2_to_v1_names{'TP2'} = 'BAND';
	$MP3::Info::v2_to_v1_names{'TPE2'} = 'BAND';	

	# get artwork
	$MP3::Info::v2_to_v1_names{'PIC'} = 'PIC';
	$MP3::Info::v2_to_v1_names{'APIC'} = 'PIC';	

	# get conductors
	$MP3::Info::v2_to_v1_names{'TP3'} = 'CONDUCTOR';
	$MP3::Info::v2_to_v1_names{'TPE3'} = 'CONDUCTOR';
	
	$MP3::Info::v2_to_v1_names{'TBP'} = 'BPM';
	$MP3::Info::v2_to_v1_names{'TBPM'} = 'BPM';

	#turn on unicode support
#	if (!MP3::Info::use_mp3_utf8(1)) {	
#		$::d_info && Slim::Utils::Misc::msg("Couldn't turn on unicode support.\n");
#	};
}

sub loadTypesConfig {
	my @typesFiles;
	$::d_info && Slim::Utils::Misc::msg("loading types config file...\n");
	
	push @typesFiles, catdir($Bin, 'types.conf');
	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @typesFiles, $ENV{'HOME'} . "/Library/SlimDevices/types.conf";
		push @typesFiles, "/Library/SlimDevices/types.conf";
		push @typesFiles, $ENV{'HOME'} . "/Library/SlimDevices/custom-types.conf";
		push @typesFiles, "/Library/SlimDevices/custom-types.conf";
	}

	push @typesFiles, catdir($Bin, 'custom-types.conf');
	push @typesFiles, catdir($Bin, '.custom-types.conf');
	
	foreach my $typeFileName (@typesFiles) {
		if (open my $typesFile, $typeFileName) {
			for my $line (<$typesFile>) {
				# get rid of comments and leading and trailing white space
				$line =~ s/#.*$//;
				$line =~ s/^\s//;
				$line =~ s/\s$//;
	
				if ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/) {
					my $type = $1;
					my @suffixes = split ',', $2;
					my @mimeTypes = split ',', $3;
					my @slimTypes = split ',', $4;
					
					foreach my $suffix (@suffixes) {
						next if ($suffix eq '-');
						$Slim::Music::Info::suffixes{$suffix} = $type;
					}
					
					foreach my $mimeType (@mimeTypes) {
						next if ($mimeType eq '-');
						$Slim::Music::Info::mimeTypes{$mimeType} = $type;
					}

					foreach my $slimType (@slimTypes) {
						next if ($slimType eq '-');
						$Slim::Music::Info::slimTypes{$type} = $slimType;
					}
					
					# the first one is the default
					if ($mimeTypes[0] ne '-') {
						$Slim::Music::Info::types{$type} = $mimeTypes[0];
					}				
				}
			}
			close $typesFile;
		}
	}
}

sub hasChanged {
	my $file = shift;
	
	# We return 0 if the file hasn't changed
	#    return 1 if the file has (cached entry is deleted by us)
	# As this is an internal cache function we don't sanity check our arguments...	

	my $filepath = Slim::Utils::Misc::pathFromFileURL($file);
		
	# Return if it's a directory - they expire themselves 
	# Todo - move directory expire code here?
	return 0 if -d $filepath;
	
	# See if the file exists
	#
	# Reuse _, as we only need to stat() once.
	if (-e _) {

		# Check FS and AGE (TIMESTAMP) to decide if we use the cached data.		
		my $cacheEntryArray = $infoCache{$file};

		my $index   = $infoCacheItemsIndex{"FS"};
		my $fsdef   = (defined $cacheEntryArray->[$index]);
		my $fscheck = 0;

		if ($fsdef) {
			$fscheck = (-s _ == $cacheEntryArray->[$index]);
		}

		# Now the AGE
		$index       = $infoCacheItemsIndex{"AGE"};
		my $agedef   = (defined $cacheEntryArray->[$index]);
		my $agecheck = 0;

		if ($agedef) {
			$agecheck = ((stat(_))[9] == $cacheEntryArray->[$index]);
		}
			
		return 0 if  $fsdef && $fscheck && $agedef && $agecheck;
		return 0 if  $fsdef && $fscheck && !$agedef;
		return 0 if !$fsdef && $agedef  && $agecheck;
		
		$::d_info && Slim::Utils::Misc::msg("deleting $file from cache as it has changed\n");
	}
	else {
		$::d_info && Slim::Utils::Misc::msg("deleting $file from cache as it no longer exists\n");
	}
	$dbCacheDirty = 1;

	delete $infoCache{$file};

	return 1;
}


# This gets called to save the infoDBCache every $dbSaveInterval seconds
sub saveDBCacheTimer {
	saveDBCache();
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $dbSaveInterval, \&saveDBCacheTimer);
}

sub clearCache {
	my $item = shift;
	if ($item) {
		delete $infoCache{$item};
		$::d_info && Slim::Utils::Misc::msg("cleared $item from cache\n");
	} else {
		$::d_info && Slim::Utils::Misc::msg("clearing cache for rescan\n");
		if (Slim::Utils::Prefs::get('usetagdatabase')) {
			scanDBCache();
		} else {
			%infoCache = ();
			completeClearCache();
		}

		%genreMixCache = ();
		%artistMixCache = ();
	}
}

sub completeClearCache {
	$songCount = 0;
	$total_time = 0;
	@playlists = ();
			
	# a hierarchical cache of genre->artist->album->song based on ID3 information
	%genreCache = ();
	%caseCache = ();
	%sortCache = ();
	%artworkCache = ();
		
	%songCountMemoize=();
	%artistCountMemoize=();
	%albumCountMemoize=();
	%genreCountMemoize=();
}

sub fixCase {
	my @fixed = ();
	foreach my $item (@_) {
		push @fixed, $caseCache{$item};
	}
	return @fixed;
}


# Wipe the memory cache
sub clearDBCache {
	%infoCache = ();
	completeClearCache();
	$dbCacheDirty=1;
	$::d_info && Slim::Utils::Misc::msg("clearDBCache: Cleared infoCache\n");
}

# Wipe the disk cache as well as memory
sub wipeDBCache {
	clearDBCache();
	saveDBCache();
	$::d_info && Slim::Utils::Misc::msg("wipeDBCache: Wiped infoCache\n");
}

sub clearStaleCacheEntries {

	$::d_info && Slim::Utils::Misc::msg("starting cache scan for expired items\n");
		
	my $validindex = $infoCacheItemsIndex{"VALID"};
			
	foreach my $file (keys %infoCache) {
			
		my $cacheEntryArray = $infoCache{$file};

		# Remove any data marked as invalid
		if ($cacheEntryArray->[$validindex] eq '0') 
		{
			$::d_info && Slim::Utils::Misc::msg("Removing item $file from cache as it has expired\n");
			delete $infoCache{$file};
		}
	}
	
	$::d_info && Slim::Utils::Misc::msg("finished cache scan for expired items\n");
}

# Mark an item as having been rescanned
sub markAsScanned {
	my $item = shift;
	my $cacheEntryHash;
	$cacheEntryHash->{'VALID'}='1';
	updateCacheEntry($item,$cacheEntryHash);
}

sub total_time {
	return $total_time;
}

sub memoizedCount {
	my ($memoized,$function,$genre,$artist,$album,$track)=@_;

	if (!defined($genre))  { $genre  = [] }
	if (!defined($artist)) { $artist = [] }
	if (!defined($album))  { $album  = [] }
	if (!defined($track))  { $track  = [] }

	my $key=join("\1",@$genre) . "\0" .
		    join("\1",@$artist). "\0" .
			join("\1",@$album) . "\0" .
			join("\1",@$track);

	if (defined($memoized->{$key})) {
		return $memoized->{$key};
	}

	my $count = &$function($genre,$artist,$album,$track);

	if (!Slim::Utils::Misc::stillScanning()) {
		return ($memoized->{$key} = $count);
	}

	return $count;
}

sub playlists {
	return \@playlists;
}

sub addPlaylist {
	my $url=shift;
	foreach my $existing (@playlists) {
		return if ($existing eq $url);
	}
	push @playlists, $url;
}

sub clearPlaylists {
	@playlists = ();
}

sub sortPlaylists {
	@playlists = Slim::Utils::Text::sortIgnoringCase(@playlists);
}

sub generatePlaylists {

 	clearPlaylists();

 

	foreach my $url (keys %infoCache) {

 		if (isITunesPlaylistURL($url) || isMoodLogicPlaylistURL($url)) {

			push @playlists, $url;

		}

	}
	
	sortPlaylists();
}

# called:
#   undef,undef,undef,undef
sub songCount {
	my ($genre,$artist,$album,$track)=@_;
	if (!defined($genre)) { $genre = [] }
	if (!defined($artist)) { $artist = [] }
	if (!defined($album)) { $album = [] }
	if (!defined($track)) { $track = [] }
	
	if ((scalar @$genre == 0 || $$genre[0] eq '*') &&
		(scalar @$artist == 0 || $$artist[0] eq '*') &&
		(scalar @$album == 0 || $$album[0] eq '*') &&
		(scalar @$track == 0 || $$track[0] eq '*')
	) {
		return $songCount;	
	}
	
	return memoizedCount(\%songCountMemoize,\&songs,($genre,$artist,$album,$track,'count'));
}

# called:
#   undef,undef,undef,undef
#	[$item],[],[],[]
#	$genreref,$artistref,$albumref,$songref
sub artistCount {
	return memoizedCount(\%artistCountMemoize,\&artists,@_, 1);
}

# called:
#   undef,undef,undef,undef
#   [$item],[],[],[]
#	[$genre],['*'],[],[]
#   [$genre],[$item],[],[]
#	$genreref,$artistref,$albumref,$songref
sub albumCount { 
	return memoizedCount(\%albumCountMemoize,\&albums,@_, 1);
}

# called:
#   undef,undef,undef,undef
sub genreCount { 
	return memoizedCount(\%genreCountMemoize,\&genres,@_, 1);
}

sub isCached {
	my $url = shift;
	return (exists $infoCache{$url});
}

sub cacheItem {
	my $url = shift;
	my $item = shift;
	my $cacheEntryArray;
	
	if (!defined($url)) {
		Slim::Utils::Misc::msg("Null cache item!\n"); 
		Slim::Utils::Misc::bt();
		return undef;
	}
	
	$::d_info_v && Slim::Utils::Misc::msg("CacheItem called for item $item in $url\n");
	
	if (exists $infoCache{$url}) {
		$cacheEntryArray = $infoCache{$url};
		my $index = $infoCacheItemsIndex{$item};
		if (defined($index) && exists $cacheEntryArray->[$index]) {
		
			my $ttlindex = $infoCacheItemsIndex{'TTL'};
			if ( isFileURL($url) && (($cacheEntryArray->[$ttlindex]) < (time()))) {
				$::d_info && Slim::Utils::Misc::msg("CacheItem: Checking status of $url (TTL: ".$cacheEntryArray->[$ttlindex].")\n");
				if (hasChanged($url)) {
					return undef;
				} 
				else {
					updateCacheEntry($url); # Update TTL
					$cacheEntryArray = $infoCache{$url};
				}
			}

			return $cacheEntryArray->[$index];
		} else {
			return undef;
		}
	}
	return undef;
}

sub cacheEntry {
	my $url = shift;
	my $cacheEntryHash = {};
	my $cacheEntryArray;
	my $cacheupdate = 0;

	if ($::d_info && !defined($url)) {die;}

	$::d_info_v && Slim::Utils::Misc::msg("CacheEntry called for $url\n");

	if ( exists $infoCache{$url}) {
		$cacheEntryArray = $infoCache{$url};
		my $ttlindex = $infoCacheItemsIndex{'TTL'};
		
		if ( isFileURL($url) && (($cacheEntryArray->[$ttlindex]) < (time()))) {
			$::d_info && Slim::Utils::Misc::msg("CacheEntry: Checking status of $url (TTL: ".$cacheEntryArray->[$ttlindex].")\n");
			if (hasChanged($url)) {
				$cacheEntryArray =undef;
			} 
			else {
				updateCacheEntry($url); # Update TTL
				$cacheEntryArray = $infoCache{$url};
			}
		}
	}

	my $i = 0;
	foreach my $key (@infoCacheItems) {
		if (defined $cacheEntryArray->[$i]) {
			$cacheEntryHash->{$key} = $cacheEntryArray->[$i];
		}
		$i++;
	}

	return $cacheEntryHash;
}

sub updateCacheEntry {
	my $url = shift;
	my $cacheEntryHash = shift;
	my $newsong = shift;
	my $cacheEntryArray;
	
	if (!defined $newsong) { $newsong=0; }
	
	if (!defined($url)) {
		Slim::Utils::Misc::msg("No URL specified for updateCacheEntry\n");
		Slim::Utils::Misc::msg(%{$cacheEntryHash});
		Slim::Utils::Misc::bt();
		return;
	}
	
	if (!isURL($url)) { 
		Slim::Utils::Misc::msg("Non-URL passed to updateCacheEntry::info ($url)\n");
		Slim::Utils::Misc::bt();
		$url=Slim::Utils::Misc::fileURLFromPath($url); 
	}
	
	if ( isFileURL($url)) {
		$cacheEntryHash->{'TTL'}=(time()+$dbCacheLifeTime + int(rand($dbCacheLifeTime)));
	} else {
		$cacheEntryHash->{'TTL'}='0';
	}

	if (!exists($infoCache{$url})) {
		$newsong = 1;
		$::d_info && Slim::Utils::Misc::msg("Newsong: $newsong for $url\n");
	} else {
		$::d_info && Slim::Utils::Misc::msg("merging $url\n");
	}
	
	$cacheEntryArray=$infoCache{$url};
	
	my $i = 0;
	foreach my $key (@infoCacheItems) {
		my $val = $cacheEntryHash->{$key};
		if (defined $val) {
			$cacheEntryArray->[$i] = $val;
			$::d_info && Slim::Utils::Misc::msg("updating $url with " . $val . " for $key\n");
		}
		$i++;
	}

	$infoCache{$url} = $cacheEntryArray;
	
	$dbCacheDirty=1;
			
	if ($newsong) {
		updateCaches($url);
	}
}

sub updateCaches {
	my $url=shift;

	if (isSong($url) && !isHTTPURL($url) && (-e (Slim::Utils::Misc::pathFromFileURL($url)) )) { 
		my $cacheEntryHash=cacheEntry($url);
		updateGenreCache($url, $cacheEntryHash);
		updateArtworkCache($url, $cacheEntryHash);
		updateSortCache($url, $cacheEntryHash);
		$::d_info && Slim::Utils::Misc::msg("Inc SongCount $url\n");
		my $time = $cacheEntryHash->{SECS};
		if ($time) {
			$total_time += $time;
		}
		$songCount++;
	}
}

sub reBuildCaches {
	completeClearCache();
	foreach my $url (keys %infoCache) {
		updateCaches($url);

	}
	generatePlaylists();
}

sub updateGenreMixCache {
        my $cacheEntry = shift;

        if (defined $cacheEntry->{MOODLOGIC_GENRE_MIXABLE} &&
                $cacheEntry->{MOODLOGIC_GENRE_MIXABLE} == 1) {
                $genreMixCache{$cacheEntry->{'GENRE'}} = $cacheEntry->{'MOODLOGIC_GENRE_ID'};
        }
}

sub updateArtistMixCache {
        my $cacheEntry = shift;

        if (defined $cacheEntry->{MOODLOGIC_ARTIST_MIXABLE} &&
            $cacheEntry->{MOODLOGIC_ARTIST_MIXABLE} == 1) {
            $artistMixCache{$cacheEntry->{'ARTIST'}} = $cacheEntry->{'MOODLOGIC_ARTIST_ID'};
        }
}

##################################################################################
# this routine accepts both our three letter content types as well as mime types.
# if neither match, we guess from the URL.
sub setContentType {
	my $url = shift;
	my $type = shift;
	
	my $cacheEntry;

	$type = lc($type);
	
	if ($Slim::Music::Info::types{$type}) {
		# we got it
	} elsif ($Slim::Music::Info::mimeTypes{$type}) {
		$type = $Slim::Music::Info::mimeTypes{$type};
	} else {
		my $guessedtype = typeFromPath($url);
		if ($guessedtype ne 'unk') {
			$type = $guessedtype;
		}
	}
	
	$cacheEntry->{'CT'} = $type;
	$cacheEntry->{'VALID'} = '1';

	updateCacheEntry($url, $cacheEntry);
	$::d_info && Slim::Utils::Misc::msg("Content type for $url is cached as $type\n");
}

sub setTitle {
	my $url = shift;
	my $title = shift;

	$::d_info && Slim::Utils::Misc::msg("Adding title $title for $url\n");
		
	my $cacheEntry;
	$cacheEntry->{'TITLE'} = $title;
	$cacheEntry->{'VALID'} = '1';

	updateCacheEntry($url, $cacheEntry);
}

sub setBitrate {
	my $url = shift;
	my $bitrate = shift;

	my $cacheEntry;
	$cacheEntry->{'BITRATE'} = $bitrate;
	$cacheEntry->{'VALID'} = '1';
					
	updateCacheEntry($url, $cacheEntry);
}

my $ncElemstring = "VOLUME|PATH|FILE|EXT|DURATION|LONGDATE|SHORTDATE|CURRTIME|FROM|BY"; #non-cached elements
my $ncElems = qr/$ncElemstring/;

my $elemstring = (join '|',@infoCacheItems,$ncElemstring);
#		. "|VOLUME|PATH|FILE|EXT" #file data (not in infoCache)
#		. "|DURATION" # SECS expressed as mm:ss (not in infoCache)
#		. "|LONGDATE|SHORTDATE|CURRTIME" #current date/time (not in infoCache)
my $elems = qr/$elemstring/;


#TODO Add elements for size dependent items (volume bar, progress bar)
#my $sdElemstring = "VOLBAR|PROGBAR"; #size dependent elements (also not cached)
#my $sdElems = qr/$sdElemstring/;

sub elemLookup {
	my $element = shift;
	#my $file = shift;
	my $infoHashref = shift;
	my $value;

	# don't return disc number if known to be single disc set
	if ($element eq "DISC") {
		my $discCount = $infoHashref->{"DISCC"};
		return undef if defined $discCount and $discCount == 1;
	}
	$value = $infoHashref->{$element};

	return $value;
}

# used by infoFormat to add items not in infoCache to hash of info
sub addToinfoHash {
	my $infoHashref = shift;
	my $file = shift;
	my $str = shift;
	
	if ($str =~ /VOLUME|PATH|FILE|EXT/) {
		if (isFileURL($file)) { $file=Slim::Utils::Misc::pathFromFileURL($file); }
		my ($volume, $path, $filename) = splitpath($file);
		$filename =~ s/\.([^\.]*?)$//;
		my $ext = $1;
		$infoHashref->{'VOLUME'} = $volume;
		$infoHashref->{'PATH'} = $path;
		$infoHashref->{'FILE'} = $filename;
		$infoHashref->{'EXT'} = $ext;
	}
	
	if ($str =~ /LONGDATE|SHORTDATE|CURRTIME/) {
		$infoHashref->{'LONGDATE'} = Slim::Utils::Misc::longDateF();
		$infoHashref->{'SHORTDATE'} = Slim::Utils::Misc::shortDateF();
		$infoHashref->{'CURRTIME'} = Slim::Utils::Misc::timeF();
	}
	
	if ($str =~ /DURATION/ && defined($infoHashref->{'SECS'})) {
		$infoHashref->{'DURATION'} = int($infoHashref->{'SECS'}/60) . ":" 
			. ((($infoHashref->{'SECS'}%60) < 10) ? ("0" . $infoHashref->{'SECS'}%60) : $infoHashref->{'SECS'}%60)
	}
	
	$infoHashref->{'FROM'} = string('FROM');
	$infoHashref->{'BY'} = string('BY'); 
}

#formats information about a file using a provided format string
sub infoFormat {
	no warnings; # this is to allow using null values with string concatenation, it only effects this procedure
	my $file = shift; # item whose information will be formatted
	my $str = shift; # format string to use
	my $safestr = shift; # format string to use in the event that after filling the first string, there is nothing left
	my $pos = 0; # keeps track of position within the format string
	
	return '' unless defined $file;
	
	my $infoRef = infoHash($file);
	
	return '' unless defined $infoRef;

	my %infoHash = %{$infoRef}; # hash of data elements not cached in the main repository

	$str = 'TITLE' unless defined $str; #use a safe format string if none specified

	if ($str =~ $ncElems) {
		addToinfoHash(\%infoHash,$file,$str);
	}

	#here is a breakdown of the following regex:
	#\G -> start at the current pos() for the string
	#(.*?)? -> match 0 or 1 instances of any string 0 or more characters in length (non-greedy),capture as $1
	#(?:=>(.*?)=>)? -> 0 or 1 instances of any string in a =>=> frame, capture as $2 (excluding =>=>)
	#(?:=>(.*?)=>)? -> same, captured as $3
	#($elems) -> match one of the precompiled list of allowed data elements, capture as $4
	#(?:<=(.*?)<=)? -> 0 or 1 instances of any string in a <=<= frame, capture as $5 (excluding <=<=)
	#(.*?)? -> 0 or 1 instances of any string, capture as $6
	#(?:<#(.*?)#>)? -> 0 or 1 instances of any string in a <##> frame, capture as $7 (excluding <##>)
	#($elems|(?:=>.*?=>)) -> either another data element or a =>=> frame in front of another data element, as $8 (includes =>=>)
	while ($str =~ s{\G(.*?)?(?:=>(.*?)=>)?(?:=>(.*?)=>)?($elems)(?:<=(.*?)<=)?(.*?)?(?:<#(.*?)#>)?($elems|(?:=>.*?=>))}
				{
					my $out = ''; #replacement string for this substitution
					#look up the value corresponding to the first data element
					my $value = elemLookup($4,\%infoHash);
					#if another data element comes next replace <##> frames with =>=> frames
					#otherwise leave off the frames
					my $frame = defined($8) ? "=>" : "";
					if (defined($value)) { #the data element had a value, so include all the separators
						#pos() is set to the first character of the match by the s/// function
						#so adjust it to be where we want the next s/// to start
						#$pos is used to hold the value of pos() that we want, because pos()
						#gets reset to 0 since we aren't using /g.  We aren't using /g because we need
						#do do some backtracking and that is not allowed all in one go.
						#we want the next replace to start at the beginning of either
						#the next data element or the =>=> frame preceding it
						$pos = pos($str) + length($1) + length($2) + length($3) + length($value);
						if (!(defined($5) || defined($7))) {
							#neither a <=<= or a <##> frame is present so treat a bare
							#separator like one framed with <##>
							$out = $1 . $2 . $3 . $value . $frame . $6 . $frame . $8;
						} else {
							#either <=<= or <##> was present, so always write out a bare separator
							#if no <##> was present, don't add a =>=> frame
							$out = $1 . $2 . $3 . $value . $5 . $6 . (defined($7) ? ($frame . $7 . $frame) : "") . $8;
							#we want the next replace to start at the beginning of either
							#the next data element or the =>=> frame preceding it
							$pos += length($5) + length($6);
						}
					} else { #the data element did not have a value, so collapse the string
						#initialize $pos
						$pos = pos($str);
						if (defined($2) || defined($3)) {
							#a =>=> frame exists so always write a preceding bare separator
							#which should only happen in the first iteration if ever
							$out = $1;
							$pos += length($1);
							if (defined($6)) {
								#the bare separator is always used if a <=<= or a <##> frame was present
								#otherwise since there was a =>=> frame preceding the missing element convert
								#a bare separator to a =>=>
								$out .= (defined($5) || defined($7)) ? $6 : $frame . $6 . $frame;
								$pos += (defined($5) || defined($7)) ? length($6) : 0;
							}
							if (defined($7)) {
								#since there was a =>=> frame preceding the missing element convert
								#the <##> separator to a =>=>
								$out .= $frame . $7 . $frame;
							}
						} else {
							#treat a non-zero length bare separator as a data element for the purpose of determining
							#whether to convert a bare separator or a <##> to a =>=>
							$out = "";
							if (defined($6)) {
								$out .= (defined($5) || defined($7)) ? $6 : (length($1) ? ($frame . $6 . $frame) : "");
								$pos += (defined($5) || defined($7)) ? length($6) : 0;
							}
							if (defined($7)) {
								$out .= (length($1) || length($6)) ? ($frame . $7 . $frame) : "";
							}
						}
						$out .= $8;
					}
					$out;
				}e) {
		# since we aren't using s///g we need to reset the string position after each pass
		pos($str) = $pos;
	}
	# reset the string position which the failed match set to 0
	pos($str) = $pos;
	#same regex as above, but the last element is the end of the string
	$str =~ s{\G(.*?)?(?:=>(.*?)=>)?(?:=>(.*?)=>)?($elems)(?:<=(.*?)<=)?(.*?)?(?:<#(.*?)#>)?$}
				{
					my $out = '';
					my $value = elemLookup($4,\%infoHash);
					if (defined($value)) {
						#fill with all the separators
						#no need to do the <##> conversion since this is the end of the string
						$out = $1 . $2 . $3 . $value . $5 . $6 . $7;
					} else {#value not defined
						#only use the bare separators if there were framed ones as well
						$out  = (defined($2) || defined($3)) ? $1 : "";
						$out .= (defined($5) || defined($7)) ? $6 : "";
					}
					$out;
				}e;
	if ($str eq "" && defined($safestr)) {
		# if there isn't anything left of the format string after the replacements, use the safe string, if supplied
		return infoFormat($file,$safestr);
	} else {
		$str=~ s/%([0-9a-fA-F][0-9a-fA-F])%/chr(hex($1))/eg;
	}

	return $str;
}

#
# if no ID3 information is available,
# use this to get a title, which is derived from the file path or URL.
# Also used to get human readable titles for playlist files and directories.
#
# for files, file URLs and directories:
#             Any ending .mp3 is stripped off and only last part of the path
#             is returned
# for HTTP URLs:
#             URL unescaping is undone.
#

sub plainTitle {
	my $file = shift;
	my $type = shift;

	my $title = "";

	$::d_info && Slim::Utils::Misc::msg("Plain title for: " . $file . "\n");

	if (isHTTPURL($file)) {
		$title = Slim::Web::HTTP::unescape($file);
	} else {
		if (isFileURL($file)) {
			$file = Slim::Utils::Misc::pathFromFileURL($file);
		}
		if ($file) {
			$title = (splitdir($file))[-1];
		}
		# directories don't get the suffixes
		if ($title && !($type && $type eq 'dir')) {
				$title =~ s/\.[^.]+$//;
		}
	}

	if ($title) {
		$title =~ s/_/ /g;
	}
	
	$::d_info && Slim::Utils::Misc::msg(" is " . $title . "\n");

	return $title;
}

# get a potentially client specifically formatted title.
sub standardTitle {
	my $client = shift;
	my $fullpath = shift;
	my $title;
	my $format;

	if (isITunesPlaylistURL($fullpath) || isMoodLogicPlaylistURL($fullpath)) {
		$format = 'TITLE';
	} elsif (defined($client)) {
		#in array syntax this would be $titleFormat[$clientTitleFormat[$clientTitleFormatCurr]]
		#get the title format
		$format = Slim::Utils::Prefs::getInd("titleFormat"
				#at the array index of the client titleformat array
				,Slim::Utils::Prefs::clientGet($client, "titleFormat"
					#which is currently selected
					,Slim::Utils::Prefs::clientGet($client,'titleFormatCurr')));
	} else {
		#in array syntax this would be $titleFormat[$titleFormatWeb]
		$format = Slim::Utils::Prefs::getInd("titleFormat",Slim::Utils::Prefs::get("titleFormatWeb"));
	}
	
	$title = infoFormat($fullpath, $format, "TITLE");

	return $title;
}

#
# Guess the important tags from the filename; use the strings in preference
# 'guessFileFormats' to generate candidate regexps for matching. First
# match is accepted and applied to the argument tag hash.
#
sub guessTags {
	my $file = shift;
	my $type = shift;
	my $taghash = shift;

	$::d_info && Slim::Utils::Misc::msg("Guessing tags for: $file\n");

	# Rip off from plainTitle()
	if (isHTTPURL($file)) {
		$file = Slim::Web::HTTP::unescape($file);
	} else {
		if (isFileURL($file)) {
			$file = Slim::Utils::Misc::pathFromFileURL($file);
		}
		# directories don't get the suffixes
		if ($file && !($type && $type eq 'dir')) {
				$file =~ s/\.[^.]+$//;
		}
	}

	# Replace all backslashes in the filename
	$file =~ s/\\/\//g;
	
	# Get the candidate file name formats
	my @guessformats = Slim::Utils::Prefs::getArray("guessFileFormats");

	# Check each format
	foreach my $guess ( @guessformats ) {
		# Create pattern from string format
		my $pat = $guess;
		
		# Escape _all_ regex special chars
		$pat =~ s/([{}[\]()^\$.|*+?\\])/\\$1/g;

		# Replace the TAG string in the candidate format string
		# with regex (\d+) for TRACKNUM, DISC, and DISCC and
		# ([^\/+) for all other tags
		
		$pat =~ s/(TRACKNUM|DISC{1,2})/\(\\d+\)/g;
		$pat =~ s/($elems)/\(\[^\\\/\]\+\)/g;
		$::d_info && Slim::Utils::Misc::msg("Using format \"$guess\" = /$pat/...\n" );
		$pat = qr/$pat/;

		# Check if this format matches		
		my @matches;
		if (@matches = $file =~ $pat) {
			$::d_info && Slim::Utils::Misc::msg("Format string $guess matched $file\n" );
			my @tags = $guess =~ /($elems)/g;
			my $i = 0;
			foreach my $match (@matches) {
				$::d_info && Slim::Utils::Misc::msg("$tags[$i] => $match\n");
				$match = int($match) if $tags[$i] =~ /TRACKNUM|DISC{1,2}/;
				$taghash->{$tags[$i++]} = $match;
			}
			return;
		}
	}
	
	# Nothing found; revert to plain title
	$taghash->{'TITLE'} = plainTitle($file, $type);	
}


#
# Return a structure containing the ID3 tag attributes of the given MP3 file.
#
sub infoHash {
	my $file = shift;

	if (!defined($file) || $file eq "") { 
		$::d_info && Slim::Utils::Misc::msg("trying to get infoHash on an empty file name\n");
		$::d_info && Slim::Utils::Misc::bt();
		return; 
	};
	
	if (!isURL($file)) { 
		Slim::Utils::Misc::msg("Non-URL passed to InfoHash::info ($file)\n");
		Slim::Utils::Misc::bt();
		$file=Slim::Utils::Misc::fileURLFromPath($file); 
	}
	
	my $item = cacheEntry($file);
	
	# we'll update the cache if we don't have a valid title in the cache
	if (!defined($item) || !exists($item->{'TAG'})) {
		#$::d_info && Slim::Utils::Misc::msg("cache miss for $file\n");
		#$::d_info && Slim::Utils::Misc::bt();
		$item = readTags($file)
	}
	
	return $item;
}

sub info {
	my $file = shift;
	my $tagname = shift;
	my $update = shift;

	if (!defined($file) || $file eq "" || !defined($tagname)) { 
		$::d_info && Slim::Utils::Misc::msg("trying to get info on an empty file name\n");
		$::d_info && Slim::Utils::Misc::bt();
		return; 
	};
	
	$::d_info && Slim::Utils::Misc::msg("Request for $tagname on file $file\n");
	
	if (!isURL($file)) { 
		$::d_info && Slim::Utils::Misc::msg("Non-URL passed to Info::info ($file)\n");
		$::d_info && Slim::Utils::Misc::bt();
		$file=Slim::Utils::Misc::fileURLFromPath($file); 
	}
	
	my $item = cacheItem($file, $tagname);

	# update the cache if the tag is not defined in the cache
	if (!defined($item)) {
		# defer cover information until needed
		if ($tagname =~ /^(COVER|COVERTYPE)$/) {
			updateCoverArt($file, 'cover');
			$item = cacheItem($file, $tagname);
		# defer thumb information until needed
		} elsif ($tagname =~ /^(THUMB|THUMBTYPE)$/) {
			updateCoverArt($file,'thumb');
			$item = cacheItem($file, $tagname);
		# load up item information if we've never seen it or we haven't loaded the tags
		} elsif (!isCached($file) || !cacheItem($file, 'TAG')) {
			#$::d_info && Slim::Utils::Misc::bt();
			$::d_info && Slim::Utils::Misc::msg("cache miss for $file\n");
			$item = readTags($file)->{$tagname};
		}	
	}
	return $item;
}


sub trackNumber { return info(shift,'TRACKNUM'); }

sub cleanTrackNumber {
	my $tracknumber = shift;

	if (defined($tracknumber)) {
		#extracts the first digits only sequence then converts it to int
		$tracknumber =~ /(\d*)/;
		$tracknumber = $1 ? int($1) : undef;
	}
	
	return $tracknumber;
}

sub genre { return info(shift,'GENRE'); }

sub title { return info(shift,'TITLE'); }

sub artist { return info(shift,'ARTIST'); }

sub artistSort {
	my $file = shift;
	my $artistSort = info($file,'ARTISTSORT');
	if (!defined($artistSort)) {
		$artistSort = Slim::Utils::Text::ignoreCaseArticles(artist($file));
	}
	return $artistSort;
}

sub albumSort {
	my $file = shift;
	my $albumSort = info($file,'ALBUMSORT');
	if (!defined($albumSort)) {
		$albumSort = Slim::Utils::Text::ignoreCaseArticles(album($file));
	}
	return $albumSort;
}

sub titleSort {
	my $file = shift;
	my $titleSort = info($file,'TITLESORT');
	if (!defined($titleSort)) {
		$titleSort = Slim::Utils::Text::ignoreCaseArticles(title($file));
	}
	return $titleSort;
}

sub composer { return info(shift,'COMPOSER'); }

sub band { return info(shift,'BAND'); }

sub conductor {	return info(shift,'CONDUCTOR'); }

sub album { return info(shift,'ALBUM'); }

sub year { return info(shift,'YEAR'); }

sub disc { return info(shift,'DISC'); }

sub discCount { return info(shift,'DISCC'); }

sub bpm { return info(shift,'BPM'); }

sub comment {
	my $file = shift;
	my $comment;
	my @comments;

	if (ref(info($file,'COMMENT')) eq 'ARRAY') {
		@comments = @{info($file,'COMMENT')};
	} else {
		@comments = (info($file,'COMMENT'));
	}

	# extract multiple comments and concatenate them
	if (@comments) {
		foreach my $c (@comments) {

			next unless $c;

			# ignore SoundJam and iTunes CDDB comments
			if ($c =~ /SoundJam_CDDB_/ ||
			    $c =~ /iTunes_CDDB_/ ||
			    $c =~ /^\s*[0-9A-Fa-f]{8}(\+|\s)/ ||
			    $c =~ /^\s*[0-9A-Fa-f]{2}\+[0-9A-Fa-f]{32}/) {
				next;
			} 
			# put a slash between multiple comments.
			$comment .= ' / ' if $comment;
			$c =~ s/^eng(.*)/$1/;
			$comment .= $c;
		}
	}

	return $comment;
}

sub duration {
	my $file = shift;
	my $secs = info($file,'SECS');

	if (defined $secs) {
		return sprintf('%s:%02s',int($secs / 60),$secs % 60);
	} else {
		return;
	}
}

sub durationSeconds { return info(shift,'SECS'); }

sub offset { return info(shift,'OFFSET'); }

sub size { return info(shift,'SIZE'); }

sub bitrate {
	my $file = shift;
	my $mode = (defined info($file,'VBR_SCALE')) ? 'VBR' : 'CBR';
	if (info($file,'BITRATE')) {
		return int (info($file,'BITRATE')/1000).Slim::Utils::Strings::string('KBPS').' '.$mode;
	} else {
		return;
	}
}

sub bitratenum { return info(shift,'BITRATE'); }

sub samplerate { return info(shift,'RATE'); }

sub channels { return info(shift, 'CHANNELS'); }

sub blockalign { return info(shift, 'BLOCKALIGN'); }

sub endian { return info(shift, 'ENDIAN'); }

# we cache whether we had success reading the cover art.
sub haveCoverArt { return info(shift, 'COVER'); }

sub haveThumbArt { return info(shift, 'THUMB'); }

sub coverArt {
	my $file = shift;
	my $art = shift || 'cover';
	my $image;

	# return with nothing if this isn't a file.  We dont need to search on streams, for example.
	if (! Slim::Utils::Prefs::get('lookForArtwork') || ! Slim::Music::Info::isSong($file)) { return undef};
	
	$::d_artwork && Slim::Utils::Misc::msg("Retrieving artwork ($art) for: $file\n");
	
	my ($body, $contenttype, $mtime, $path);
	my $artwork = haveCoverArt($file);
	my $artworksmall = haveThumbArt($file);
	
	if (($art eq 'cover') && $artwork && ($artwork ne '1')) {
		$body = getImageContent($artwork);
		if ($body) {
			$::d_artwork && Slim::Utils::Misc::msg("Found cached artwork file: $artwork\n");
			$contenttype = mimeType(Slim::Utils::Misc::fileURLFromPath($artwork));
			$path = $artwork;
		} else {
			($body, $contenttype, $path) = readCoverArt($file, $art);
		}
	} 
	elsif (($art eq 'thumb') && $artworksmall && ($artworksmall ne '1')) {
		$body = getImageContent($artworksmall);
		if ($body) {
			$::d_artwork && Slim::Utils::Misc::msg("Found cached artwork-small file: $artworksmall\n");
			$contenttype = mimeType(Slim::Utils::Misc::fileURLFromPath($artworksmall));
			$path = $artworksmall;
		} else {
			($body, $contenttype, $path) = readCoverArt($file, $art);
		}
	}
	elsif ( (($art eq 'cover') && $artwork) || 
			(($art eq 'thumb') && $artworksmall) ) {
		($body, $contenttype,$path) = readCoverArt($file,$art);
	}

	# kick this back up to the webserver so we can set last-modified
	if ($path && -r $path) {
		$mtime = (stat(_))[9];
	}

	return ($body, $contenttype, $mtime);
}

sub age { return info(shift, 'AGE'); }
sub tagVersion { return info(shift,'TAGVERSION'); }
sub cachedPlaylist { return info(shift, 'LIST'); }

sub cachePlaylist {
	my $path = shift;
	my $inforef;
	$inforef->{'LIST'} = shift;
	my $age = shift;

	if (!defined($age)) { $age = Time::HiRes::time(); };
	$inforef->{'AGE'} = $age;

	updateCacheEntry($path, $inforef);
	
	$::d_info && Slim::Utils::Misc::msg("cached an " . (scalar @{$inforef->{'LIST'}}) . " item playlist for $path\n");
}


sub filterPrep {
	my $pattern = shift;
	#the following transformations assume that the pattern provided uses * to indicate
	#matching any character 0 or more times, and that . ^ and $ are not escaped
	$pattern =~ s/\\([^\*]|$)/($1 eq "\\")? "\\\\" : $1/eg; #remove single backslashes except those before a *
	$pattern =~ s/([\.\^\$\(\)\[\]\{\}\|\+\?])/\\$1/g; #escape metachars (other than * or \) in $pattern {}[]()^$.|+?
	$pattern =~ s/^(.*)$/\^$1\$/; #add beginning and end of string requirements
	$pattern =~ s/(?<=[^\\])\*/\.\*/g; #replace * (unescaped) with .*
	return qr/$pattern/i;
}

sub filterPats {
	my ($inpats) = @_;
	my @outpats = ();
	foreach my $pat (@$inpats) {
		push @outpats, filterPrep(Slim::Utils::Text::ignoreCaseArticles($pat));
	}
	return \@outpats;
}

sub filter {
	my ($patterns, $const, @items) = @_;
	if (!defined($patterns) || ! @{$patterns}) {
		return @items;
	}

	my @filtereditems;
	# Gross, but this seems to be a relevant optimization.
	if ($const eq '') {
		ITEM: foreach my $item (@items) {
			foreach my $regexpattern (@{$patterns}) {
				if ($item !~ $regexpattern) {
					next ITEM;
				}
			}
			push @filtereditems, $item;
		}
	  } else {
		ITEM: foreach my $item (@items) {
			my $item_const = $item . ' ' . $const;
			foreach my $regexpattern (@{$patterns}) {
				if ($item_const !~ $regexpattern) {
					next ITEM;
				}
			}
			push @filtereditems, $item;
		}
	}

	return @filtereditems;
}

sub filterHashByValue {
	my ($patterns, $hashref) = @_;

	if (!defined($hashref)) {
		return;
	}

	if (!defined($patterns) || ! @{$patterns}) {
		return keys %{$hashref};
	}

	my @filtereditems;
	my ($k,$v);
	ENTRY: while (($k,$v) = each %{$hashref}) {
		foreach my $pat (@{$patterns}) {
			if ($v !~ $pat) {
				next ENTRY;
			}
		}
		push @filtereditems, $k;
	}

	return @filtereditems;
}

# genres|artists|albums|songs(genre,artist,album,song)
#===========================================================================
# Return list of matching keys at the given level in the genre tree.  Each
# of the arguments is an array reference of file glob type patterns to match.
# In order to match, all the elements of the list must match at the given
# level of the genre tree.

sub genres {
	my $genre  = shift;
	my $artist = shift;
	my $album  = shift;
	my $song   = shift;
	my $count  = shift;

	$::d_info && Slim::Utils::Misc::msg("genres: $genre - $artist - $album - $song\n");

	my $genre_pats = filterPats($genre);
	my @genres     = filter($genre_pats, "", keys %genreCache);
	
	if ($count) {
		return scalar @genres;
	} else {
		return fixCase(Slim::Utils::Text::sortuniq(@genres));
	}
}

# XXX - seems all these foreach loops could be eliminated with a
# better?/different data structure.
sub artists {
	my $genre  = shift;
	my $artist = shift;
	my $album  = shift;
	my $song   = shift;
	my $count  = shift;

	my @artists = ();

	$::d_info && Slim::Utils::Misc::msg("artists: $genre - $artist - $album - $song\n");

	my $genre_pats  = filterPats($genre);
	my $artist_pats = filterPats($artist);

	if (defined($album) && scalar(@$album) && $$album[0]) {

		my $album_pats = filterPats($album);

		foreach my $g (filter($genre_pats, "", keys %genreCache)) {

			foreach my $art (filter($artist_pats, "", keys %{$genreCache{$g}})) {

				foreach my $alb (filter($album_pats, "", keys %{$genreCache{$g}{$art}})) {
					push @artists, $art;
				}
			}
		}

	} else {

		foreach my $g (filter($genre_pats,"",keys %genreCache)) {
			push @artists, filter($artist_pats,"",keys %{$genreCache{$g}});
		}
	}

	if ($count) {
		return scalar @artists;
	} else {
		return fixCase(Slim::Utils::Text::sortuniq_ignore_articles(@artists));
	}
}

sub artwork {
	my @covers;

	foreach my $key (keys %artworkCache) {
		if (exists $artworkCache{$key}) { # if its been lost since scan..
			push @covers, Slim::Utils::Text::ignoreCaseArticles(uc($key));
		}
	}
	return fixCase(Slim::Utils::Text::sortuniq_ignore_articles(@covers));
}

sub albums {
	my $genre  = shift;
	my $artist = shift;
	my $album  = shift;
	my $song   = shift;
	my $count  = shift;

	my @albums = ();

	$::d_info && Slim::Utils::Misc::msg("albums: $genre - $artist - $album - $song\n");

	my $genre_pats  = filterPats($genre);
	my $artist_pats = filterPats($artist);
	my $album_pats  = filterPats($album);

	foreach my $g (filter($genre_pats, "", keys %genreCache)) {

		foreach my $art (filter($artist_pats, "", keys %{$genreCache{$g}})) {

			if (Slim::Utils::Prefs::get("artistinalbumsearch")) {
				push @albums, filter($album_pats, $art, keys %{$genreCache{$g}{$art}});
			} else {
				push @albums, filter($album_pats, "",   keys %{$genreCache{$g}{$art}});
			}

			# XXX?
			::idleStreams();
		}
	}

	if ($count) {
		return scalar(@albums);
	} else {
 		return fixCase(Slim::Utils::Text::sortuniq_ignore_articles(@albums));
 	}
}

# Return cached path for a given album name
sub pathFromAlbum {

	my $album = shift;
	if (exists $artworkCache{$album}) {
		return $artworkCache{$album};
	}
	return undef;
}

# return all songs for a given genre, artist, and album
sub songs {
	my $genre	= shift;
	my $artist	= shift;
	my $album	= shift;
	my $track	= shift;
	my $sortbytitle = shift;
	
	my $multalbums  = (scalar(@$album) == 1 && $album->[0] !~ /\*/  && (!defined($artist->[0]) || $artist->[0] eq '*'));
	my $tracksort   = !$multalbums && !$sortbytitle;
	
	my $genre_pats  = filterPats($genre);
	my $artist_pats = filterPats($artist);
	my $album_pats  = filterPats($album);
	my $track_pats  = filterPats($track);

	my @alltracks	= ();

	$::d_info && Slim::Utils::Misc::msg("songs: $genre - $artist - $album - $track\n");

	foreach my $g (Slim::Utils::Text::sortIgnoringCase(filter($genre_pats, '', keys %genreCache))) {

		foreach my $art (Slim::Utils::Text::sortIgnoringCase(filter($artist_pats, '', keys %{$genreCache{$g}}))) {

			foreach my $alb (Slim::Utils::Text::sortIgnoringCase(filter($album_pats, '', keys %{$genreCache{$g}{$art}}))) {

				my %songs = ();

				foreach my $trk (values %{$genreCache{$g}{$art}{$alb}}) {

					$songs{$trk} = Slim::Utils::Text::ignoreCaseArticles(title($trk));
				}

				if ($tracksort) {
					push @alltracks, sortByTrack(filterHashByValue($track_pats,\%songs));
				} else {
					push @alltracks, filterHashByValue($track_pats,\%songs);
				}
			}

			::idleStreams();
		}
	}

	# remove duplicate tracks
	my %seen = ();
	my @uniq = ();
	
	foreach my $item (@alltracks) {

		unless (!defined($item) || ($item eq '') || $seen{Slim::Utils::Text::ignoreCaseArticles($item)}++) {
			push(@uniq, $item);
		}
	}
		
	if ($sortbytitle && $sortbytitle ne 'count') {

		@uniq = sortByTitles(@uniq);

	# if we are getting a specific album with an unspecific artist, re-sort the tracks
	} elsif ($multalbums) {

		# if there are duplicate track numbers, then sort as multiple albums
		my $duptracknum = 0;
		my @seen = ();

		foreach my $item (@uniq) {

			my $trnum = trackNumber($item) || next;

			if ($seen[$trnum]) {
				$duptracknum = 1;
				last;
			}

			$seen[$trnum]++;
		}

		if ($duptracknum) {
			@uniq =  sortByTrack(@uniq);
		} else {
			@uniq =  sortByAlbum(@uniq);
		}
	}

	if ($sortbytitle && $sortbytitle eq 'count') {
		return scalar @uniq;
	} else {
	 	return @uniq;
	}
}

# XXX - sigh, globals
my $articles = undef;

sub sortByTrack {

	$articles = undef;

	#get info for items and ignoreCaseArticles it
	my @sortinfo =  map {getInfoForSort($_)} @_;

	#return the first element of each entry in the sorted array
	return map {$_->[0]} sort sortByTrackAlg @sortinfo;
}

sub sortByAlbum {

	$articles = undef;

	#get info for items and ignoreCaseArticles it
	my @sortinfo =  map {getInfoForSort($_)} @_;

	#return an array of first elements of the entries in the sorted array
	return map {$_->[0]} sort sortByAlbumAlg @sortinfo;
}

sub sortByTitles {

	$articles = undef;

	#get info for items and ignoreCaseArticles it
	my @sortinfo =  map {getInfoForSort($_)} @_;

	#return an array of first elements of the entries in the sorted array
	return map {$_->[0]} sort sortByTitlesAlg @sortinfo;
}

#algorithm for sorting by just titles
sub sortByTitlesAlg ($$) {
	my $j = $_[0];
	my $k = $_[1];

	#compare titles
	return ($j->[5] || 0) cmp ($k->[5] || 0);
}

#Sets up an array entry for performing complex sorts
sub getInfoForSort {
	my $item = shift;

	return [
		$item,
		isList($item),
		artistSort($item),
		albumSort($item),
		trackNumber($item),
		titleSort($item),
		disc($item)
	];
}	

#algorithm for sorting by Artist, Album, Track
sub sortByTrackAlg ($$) {
	my $j = $_[0];
	my $k = $_[1];

	my $result;
	#If both lists compare titles
	if ($j->[1] && $k->[1]) {
		#compare titles
		if (defined($j->[5]) && defined($k->[5])) {
			return $j->[5] cmp $k->[5];
		} elsif (defined($j->[5])) {
			return -1;
		} elsif (defined($k->[5])) {
			return 1;
		} else {
			return 0;
		}
	}
	
	#compare artists
	if (defined($j->[2]) && defined($k->[2])) {
		$result = $j->[2] cmp $k->[2];
		if ($result) { return $result; }
	} elsif (defined($j->[2])) {
		return -1;
	} elsif (defined($k->[2])) {
		return 1;
	}
	
	#compare albums
	if (defined($j->[3]) && defined($k->[3])) {
		$result = $j->[3] cmp $k->[3];
		if ($result) { return $result; }
	} elsif (defined($j->[3])) {
		return -1;
	} elsif (defined($k->[3])) {
		return 1;
	}
	
	# compare discs
	if (defined $j->[6] && defined $k->[6]) {
	   $result = $j->[6] <=> $k->[6];
	   return $result if $result;
	}

	#compare track numbers
	if ($j->[4] && $k->[4]) {
		$result = $j->[4] <=> $k->[4];
		if ($result) { return $result; }
	} elsif ($j->[4]) {
		return -1;
	} elsif ($k->[4]) {
		return 1;
	}

	#compare titles
	return $j->[5] cmp $k->[5];
}

#algorithm for sorting by Album, Track
sub sortByAlbumAlg ($$) {
	my $j = $_[0];
	my $k = $_[1];

	my $result;
	#If both are lists compare titles
	if ($j->[1] && $k->[1]) { 
		#compare titles
		if (defined($j->[5]) && defined($k->[5])) {
			return $j->[5] cmp $k->[5];
		} elsif (defined($j->[5])) {
			return -1;
		} elsif (defined($k->[5])) {
			return 1;
		} else {
			return 0;
		}
	}
	
	#compare albums
	if (defined($j->[3]) && defined($k->[3])) {
		$result = $j->[3] cmp $k->[3];
		if ($result) { return $result; }
	} elsif (defined($j->[3])) {
		return -1;
	} elsif (defined($k->[3])) {
		return 1;
	}
	
	# compare discs
	if (defined $j->[6] && defined $k->[6]) {
	   $result = $j->[6] <=> $k->[6];
	   return $result if $result;
	}

	#compare track numbers
	if ($j->[4] && $k->[4]) {
		$result = $j->[4] <=> $k->[4];
		if ($result) { return $result; }
	} elsif ($j->[4]) {
		return -1;
	} elsif ($k->[4]) {
		return 1;
	}

	#compare titles
	return $j->[5] cmp $k->[5];
}

sub fileName {
	my $j = shift;

	if (isFileURL($j)) {
		$j = Slim::Utils::Misc::pathFromFileURL($j);
		if ($j) {
			$j = (splitdir($j))[-1];
		}
	} elsif (isHTTPURL($j)) {
		$j = Slim::Web::HTTP::unescape($j);
	} else {
		$j = (splitdir($j))[-1];
	}
	return $j;
}


sub sortFilename {
	#build the sort index
	my @nocase = map {Slim::Utils::Text::ignoreCaseArticles(fileName($_))} @_;
	#return the input array sliced by the sorted array
	return @_[sort {$nocase[$a] cmp $nocase[$b]} 0..$#_];
}


sub songPath {
	my $genre = shift;
	my $artist = shift;
	my $album = shift;
	my $track = shift;

	return $genreCache{Slim::Utils::Text::ignoreCaseArticles($genre)}{Slim::Utils::Text::ignoreCaseArticles($artist)}{Slim::Utils::Text::ignoreCaseArticles($album)}{Slim::Utils::Text::ignoreCaseArticles($track)};
}

sub isFragment {
	my $fullpath = shift;
	
	my $is = 0;
	if (isURL($fullpath)) {
		my $anchor = Slim::Utils::Misc::anchorFromURL($fullpath);
		if ($anchor && $anchor =~ /([\d\.]+)-([\d\.]+)/) {
			return ($1, $2);
		}
	}
}

sub readTags {
	my $file = shift;
	my ($track, $song, $artistName,$albumName);
	my $filepath;
	my $type;
	my $tempCacheEntry;

	if (!defined($file) || $file eq "") { return; };

	# get the type without updating the cache
	$type = typeFromPath($file);
	if (	$type eq 'unk' && 
			exists($infoCache{$file}) && 
			exists(cacheEntry($file)->{'CT'})
		) {
		$type = cacheEntry($file)->{'CT'};
	}


	$::d_info && Slim::Utils::Misc::msg("Updating cache for: " . $file . "\n");

	if (isSong($file, $type) ) {
		if (isHTTPURL($file)) {
			# if it's an HTTP URL, guess the title from the the last part of the URL,
			# and don't bother with the other parts
			if (!defined(cacheItem($file, 'TITLE'))) {
				$::d_info && Slim::Utils::Misc::msg("Info: no title found, calculating title from url for $file\n");
				$tempCacheEntry->{'TITLE'} = plainTitle($file, $type);
			}
		} else {
			my $anchor;
			if (isFileURL($file)) {
				$filepath = Slim::Utils::Misc::pathFromFileURL($file);
				$anchor = Slim::Utils::Misc::anchorFromURL($file);
			} else {
				$filepath = $file;
			}

			# Extract tag and audio info per format
			if (exists $tagFunctions{$type}) {
				$tempCacheEntry = &{$tagFunctions{$type}}($filepath, $anchor);
			}
			$::d_info && !defined($tempCacheEntry) && Slim::Utils::Misc::msg("Info: no tags found for $filepath\n");

			if (defined($tempCacheEntry->{'TRACKNUM'})) {
				$tempCacheEntry->{'TRACKNUM'} = cleanTrackNumber($tempCacheEntry->{'TRACKNUM'});
			}
			
			# Turn the tag SET into DISC and DISCC if it looks like # or #/#
			if ($tempCacheEntry->{'SET'} and $tempCacheEntry->{'SET'} =~ /(\d+)(?:\/(\d+))?/) {
				$tempCacheEntry->{'DISC'} = $1;
				$tempCacheEntry->{'DISCC'} = $2 if defined $2;
 			}

			addDiscNumberToAlbumTitle($tempCacheEntry);
			
			if (!$tempCacheEntry->{'TITLE'} && !defined(cacheItem($file, 'TITLE'))) {
				$::d_info && Slim::Utils::Misc::msg("Info: no title found, using plain title for $file\n");
				#$tempCacheEntry->{'TITLE'} = plainTitle($file, $type);					
				guessTags( $file, $type, $tempCacheEntry );
			}

			# fix the genre
			if (defined($tempCacheEntry->{'GENRE'}) && $tempCacheEntry->{'GENRE'} =~ /^\((\d+)\)$/) {
				# some programs (SoundJam) put their genres in as text digits surrounded by parens.
				# in this case, look it up in the table and use the real value...
				if (defined($MP3::Info::mp3_genres[$1])) {
					$tempCacheEntry->{'GENRE'} = $MP3::Info::mp3_genres[$1];
				}
			}

			# cache the file size & date
			$tempCacheEntry->{'FS'} = -s $filepath;					
			$tempCacheEntry->{'AGE'} = (stat($filepath))[9];
			
			# rewrite the size, offset and duration if it's just a fragment
			if ($anchor && $anchor =~ /([\d\.]+)-([\d\.]+)/ && $tempCacheEntry->{'SECS'}) {
				my $start = $1;
				my $end = $2;
				
				my $duration = $end - $start;
				my $byterate = $tempCacheEntry->{'SIZE'} / $tempCacheEntry->{'SECS'};
				my $header = $tempCacheEntry->{'OFFSET'};
				my $startbytes = int($byterate * $start);
				my $endbytes = int($byterate * $end);
				
				$startbytes -= $startbytes % $tempCacheEntry->{'BLOCKALIGN'} if $tempCacheEntry->{'BLOCKALIGN'};
				$endbytes -= $endbytes % $tempCacheEntry->{'BLOCKALIGN'} if $tempCacheEntry->{'BLOCKALIGN'};
				
				$tempCacheEntry->{'OFFSET'} = $header + $startbytes;
				$tempCacheEntry->{'SIZE'} = $endbytes - $startbytes;
				$tempCacheEntry->{'SECS'} = $duration;
				
				$::d_info && Slim::Utils::Misc::msg("readTags: calculating duration for anchor: $duration\n");
				$::d_info && Slim::Utils::Misc::msg("readTags: calculating header $header, startbytes $startbytes and endbytes $endbytes\n");
			}

			if (! Slim::Music::iTunes::useiTunesLibrary()) {
				# Check for Cover Artwork, only if not already present.
				if (exists $tempCacheEntry->{'COVER'} || exists $tempCacheEntry->{'THUMB'}) {
					$::d_artwork && Slim::Utils::Misc::msg("already checked artwork for $file\n");
				} elsif (Slim::Utils::Prefs::get('lookForArtwork')) {
					my $album = $tempCacheEntry->{'ALBUM'};
					$tempCacheEntry->{'TAG'} = 1;
					$tempCacheEntry->{'VALID'} = 1;
					# cache the content type
					$tempCacheEntry->{'CT'} = $type unless defined $tempCacheEntry->{'CT'};
					#update the cache so we can use readCoverArt without recursion.
					updateCacheEntry($file, $tempCacheEntry);
					# Look for Cover Art and cache location
					my ($body,$contenttype,$path);
					if (defined $tempCacheEntry->{'PIC'}) {
						($body,$contenttype,$path) = readCoverArtTags($file,'cover');
					}
					if (defined $body) {
						$tempCacheEntry->{'COVER'} = 1;
						$tempCacheEntry->{'THUMB'} = 1;
						if ($album && !exists $artworkCache{$album}) {
							$::d_artwork && Slim::Utils::Misc::msg("ID3 Artwork cache entry for $album: $filepath\n");
							$artworkCache{$album} = $filepath;
						}
					} else {
						($body,$contenttype,$path) = readCoverArtFiles($file,'cover');
						if (defined $body) {
							$tempCacheEntry->{'COVER'} = $path;
						}
						# look for Thumbnail Art and cache location
						($body,$contenttype,$path) = readCoverArtFiles($file,'thumb');
						if (defined $body) {
							$tempCacheEntry->{'THUMB'} = $path;
							# add song entry to %artworkcache if we have valid artwork
							if ($album && !exists $artworkCache{$album}) {
								$::d_artwork && Slim::Utils::Misc::msg("Artwork cache entry for $album: $filepath\n");
								$artworkCache{$album} = $filepath;
							}
						}
					}
				}
			}
		} 
	} else {
		if (!defined(cacheItem($file, 'TITLE'))) {
			my $title = plainTitle($file, $type);
			$tempCacheEntry->{'TITLE'} = $title;
		}
	}
	
	$tempCacheEntry->{'CT'} = $type unless defined $tempCacheEntry->{'CT'};
	
			
	# note that we've read in the tags.
	$tempCacheEntry->{'TAG'} = 1;
	$tempCacheEntry->{'VALID'} = 1;
	
	updateCacheEntry($file, $tempCacheEntry);

	return $tempCacheEntry;
}


sub updateSortCache {
	my $file = shift;
	my $tempCacheEntry = shift;
	
	if (exists($tempCacheEntry->{'ARTISTSORT'})) {
		$tempCacheEntry->{'ARTISTSORT'} = Slim::Utils::Text::ignoreCaseArticles($tempCacheEntry->{'ARTISTSORT'});
		
		if (exists($tempCacheEntry->{'ARTIST'})) { 
			$sortCache{Slim::Utils::Text::ignoreCaseArticles($tempCacheEntry->{'ARTIST'})} = $tempCacheEntry->{'ARTISTSORT'};
		};
	};
			
	if (exists($tempCacheEntry->{'ALBUMSORT'})) {
		$tempCacheEntry->{'ALBUMSORT'} = Slim::Utils::Text::ignoreCaseArticles($tempCacheEntry->{'ALBUMSORT'});
				
		if (exists($tempCacheEntry->{'ALBUM'})) { 
			$sortCache{Slim::Utils::Text::ignoreCaseArticles($tempCacheEntry->{'ALBUM'})} = $tempCacheEntry->{'ALBUMSORT'};
		};
	};
			
	if (exists($tempCacheEntry->{'TITLESORT'})) {
		$tempCacheEntry->{'TITLESORT'} = Slim::Utils::Text::ignoreCaseArticles($tempCacheEntry->{'TITLESORT'});

		if (exists($tempCacheEntry->{'TITLE'})) { 
			$sortCache{Slim::Utils::Text::ignoreCaseArticles($tempCacheEntry->{'TITLE'})} = $tempCacheEntry->{'TITLESORT'};
		};
	};
}

sub addDiscNumberToAlbumTitle
{
	my $entry = shift;
	# Unless the groupdiscs preference is selected:
	# Handle multi-disc sets with the same title
	# by appending a disc count to the track's album name.
	# If "disc <num>" (localized or English) is present in 
	# the title, we assume it's already unique and don't
	# add the suffix.
	# If it seems like there is only one disc in the set, 
	# avoid adding "disc 1 of 1"
	return if Slim::Utils::Prefs::get('groupdiscs');
	my $discNum = $entry->{'DISC'};
	return unless defined $discNum and $discNum > 0;
	my $discCount = $entry->{'DISCC'};
	if (defined $discCount) {
		return if $discCount == 1;
		undef $discCount if $discCount < 1; # errornous count
	}
	my $discWord = string('DISC');
	return if $entry->{'ALBUM'} =~ /\b(${discWord})|(Disc)\s+\d+/i;
	if (defined $discCount) {
		# add spaces to discNum to help plain text sorting
		my $discCountLen = length($discCount);
		$entry->{'ALBUM'} .= sprintf(" (%s %${discCountLen}d %s %d)",
				$discWord, $discNum, string('OF'), $discCount);
	} else {
		$entry->{'ALBUM'} .= " ($discWord $discNum)";
	}
}

sub getImageContent {
	my $path = shift;
	my $contentref;

	if (open (TEMPLATE, $path)) { 
		binmode(TEMPLATE);
		$$contentref=join('',<TEMPLATE>);
		close TEMPLATE;
	}
	
	defined($$contentref) && length($$contentref) || $::d_artwork && Slim::Utils::Misc::msg("Image File empty or couldn't read: $path\n");
	return $$contentref;
}

sub readCoverArt {
	my $fullpath = shift;
	my $image    = shift || 'cover';

	my ($body,$contenttype,$path) = readCoverArtTags($fullpath,$image);

	if (!defined $body) {
		($body,$contenttype,$path) = readCoverArtFiles($fullpath,$image);
	}

	return ($body,$contenttype,$path);
}
	
sub readCoverArtTags {
	use bytes;
	my $fullpath = shift;
	
#   this parameter isn't used...
#	my $image = shift || 'cover';

	if (! Slim::Utils::Prefs::get('lookForArtwork')) { return undef};

	my $body;	
	my $contenttype;
	
	$::d_artwork && Slim::Utils::Misc::msg("Updating image for $fullpath\n");
	
	if (isSong($fullpath) && isFile($fullpath)) {
	
		my $file = Slim::Utils::Misc::virtualToAbsolute($fullpath);
	
		if (isFileURL($file)) {
			$file = Slim::Utils::Misc::pathFromFileURL($file);
		} else {
			$file = $fullpath;
		}
			
		if (isMP3($fullpath) || isWav($fullpath) || isAIFF($fullpath)) {
	
			$::d_artwork && Slim::Utils::Misc::msg("Looking for image in ID3 tag in file $file\n");

			my $tags = MP3::Info::get_mp3tag($file, 2, 1);
			if ($tags) {
				# look for ID3 v2.2 picture
				my $pic = $tags->{'PIC'};
				if (defined($pic)) {
					if (ref($pic) eq 'ARRAY') {
						$pic = (@$pic)[0];
					}					
					my ($encoding, $format, $picturetype, $description) = unpack 'Ca3CZ*', $pic;
					my $len = length($description) + 1 + 5;
					if ($encoding) { $len++; } # skip extra terminating null if unicode
					
					if ($len < length($pic)) {		
						my ($data) = unpack "x$len A*", $pic;
						
						$::d_artwork && Slim::Utils::Misc::msg( "PIC format: $format length: " . length($pic) . "\n");

						if (length($pic)) {
							if ($format eq 'PNG') {
									$contenttype = 'image/png';
									$body = $data;
							} elsif ($format eq 'JPG') {
									$contenttype = 'image/jpeg';
									$body = $data;
							}
						}
					}
				} else {
					# look for ID3 v2.3 picture
					$pic = $tags->{'APIC'};
					if (defined($pic)) {
						# if there are more than one pictures, just grab the first one.
						if (ref($pic) eq 'ARRAY') {
							$pic = (@$pic)[0];
						}					
						my ($encoding, $format) = unpack 'C Z*', $pic;
						my $len = length($format) + 2;
						if ($len < length($pic)) {
							my ($picturetype, $description) = unpack "x$len C Z*", $pic;
							$len += 1 + length($description) + 1;
							if ($encoding) { $len++; } # skip extra terminating null if unicode
							
							my ($data) = unpack"x$len A*", $pic;
							
							$::d_artwork && Slim::Utils::Misc::msg( "APIC format: $format length: " . length($data) . "\n");
	
							if (length($data)) {
								$contenttype = $format;
								$body = $data;
							}
						}
					}
				}
			}
		} elsif (isMOV($fullpath)) {
			$::d_artwork && Slim::Utils::Misc::msg("Looking for image in Movie metadata in file $file\n");
			$body = Slim::Formats::Movie::getCoverArt($file);
			$::d_artwork && $body && Slim::Utils::Misc::msg("found image in $file of length " . length($body) . " bytes \n");
		}
		
		if ($body) {
			# iTunes sometimes puts PNG images in and says they are jpeg
			if ($body =~ /^\x89PNG\x0d\x0a\x1a\x0a/) {
				$::d_info && Slim::Utils::Misc::msg( "found PNG image\n");
				$contenttype = 'image/png';
			} elsif ($body =~ /^\xff\xd8\xff\xe0..JFIF/) {
				$::d_info && Slim::Utils::Misc::msg( "found JPEG image\n");
				$contenttype = 'image/jpeg';
			}
			
			# jpeg images must start with ff d8 ff e0 or they ain't jpeg, sometimes there is junk before.
			if ($contenttype && $contenttype eq 'image/jpeg')	{
				$body =~ s/^.*?\xff\xd8\xff\xe0/\xff\xd8\xff\xe0/;
			}
		}
 	} else {
 		$::d_info && Slim::Utils::Misc::msg("Not a song, skipping: $fullpath\n");
 	}
 	
	return ($body, $contenttype,1);
}

sub readCoverArtFiles {
	use bytes;
	my $fullpath = shift;
	my $image = shift || 'cover';
	my $artwork;

	my $body;	
	my $contenttype;

	my $file = isFileURL($fullpath) ? Slim::Utils::Misc::pathFromFileURL($fullpath) : $fullpath;

	my @components = splitdir($file);
	pop @components;
	$::d_artwork && Slim::Utils::Misc::msg("Looking for image files in ".catdir(@components)."\n");
	
	my @filestotry = ();
	my @names = qw(cover thumb album albumartsmall folder);
	my @ext = qw(jpg gif);
	my %nameslist = map { $_ => [do { my $t=$_; map { "$t.$_" } @ext }] } @names ;
	
	if ($image eq 'thumb') {
		@filestotry = map { @{$nameslist{$_}} } qw(thumb albumartsmall cover folder album);
		if (Slim::Utils::Prefs::get('coverThumb')) {
			$artwork = Slim::Utils::Prefs::get('coverThumb');
		}
	} else {
		@filestotry = map { @{$nameslist{$_}} } qw(cover folder album thumb albumartsmall);
		if (Slim::Utils::Prefs::get('coverArt')) {
			$artwork = Slim::Utils::Prefs::get('coverArt');
		}
	}
	if (defined($artwork) && $artwork =~ /^%(.*?)(\..*?){0,1}$/) {
		my $suffix = $2 ? $2 : ".jpg";
		$artwork = infoFormat(Slim::Utils::Misc::fileURLFromPath($fullpath), $1)."$suffix";
		my $artworktype = $image eq 'thumb' ? "Thumbnail" : "Cover";
		$::d_artwork && Slim::Utils::Misc::msg("Variable $artworktype: $artwork from $1\n");
		my $artpath = catdir(@components, $artwork);
		$body = getImageContent($artpath);
		my $artfolder = Slim::Utils::Prefs::get('artfolder');
		if (!$body && defined $artfolder) {
			$artpath = catdir(Slim::Utils::Prefs::get('artfolder'),$artwork);
			$body = getImageContent($artpath);
		}
		if ($body) {
			$::d_artwork && Slim::Utils::Misc::msg("Found $image file: $artpath\n\n");
			$contenttype = mimeType(Slim::Utils::Misc::fileURLFromPath($artpath));
			$lastFile{$image} = $artpath;
			return ($body, $contenttype, $artpath);
		}
	} elsif (defined($artwork)) {
		unshift @filestotry,$artwork;
	}

	if (defined $artworkDir && $artworkDir eq catdir(@components)) {
		if (exists $lastFile{$image}  && $lastFile{$image} ne '1') {
			$::d_artwork && Slim::Utils::Misc::msg("Using existing $image: $lastFile{$image}\n");
			$body = getImageContent($lastFile{$image});
			$contenttype = mimeType(Slim::Utils::Misc::fileURLFromPath($lastFile{$image}));
			$artwork = $lastFile{$image};
			return ($body, $contenttype, $artwork);
		} elsif (exists $lastFile{$image}) {
			$::d_artwork && Slim::Utils::Misc::msg("No $image in $artworkDir\n");
			return undef;
		}
	} else {
		$artworkDir = catdir(@components);
		%lastFile = ();
	}

	foreach my $file (@filestotry) {
		$file = catdir(@components, $file);
		$body = getImageContent($file);
		if ($body) {
			$::d_artwork && Slim::Utils::Misc::msg("Found $image file: $file\n\n");
			$contenttype = mimeType(Slim::Utils::Misc::fileURLFromPath($file));
			$artwork = $file;
			$lastFile{$image} = $file;
			last;
		} else {$lastFile{$image} = '1'};
	}
	return ($body, $contenttype, $artwork);
}

sub updateCoverArt {
	my $fullpath = shift;
	my $type = shift || 'cover';
	my $body;	
	my $contenttype;
	my $path;
	
	($body, $contenttype, $path) = readCoverArt($fullpath, $type);

 	my $info;
 	
 	if (defined($body)) {
 		if ($type eq 'cover') {
 			$info->{'COVER'} = $path;
 		} elsif ($type eq 'thumb') {
 			$info->{'THUMB'} = $path;
 		}
 		$::d_artwork && Slim::Utils::Misc::msg("$type caching $path for $fullpath\n");
 	} else {
		if ($type eq 'cover') {
 			$info->{'COVER'} = '0';
 		} elsif ($type eq 'thumb') {
 			$info->{'THUMB'} = '0';
 		}
 	}
 	
 	#if we're caching, might as well cache the actual type
 	if (defined($contenttype)) {
 		if ($type eq 'cover') {
 			$info->{'COVERTYPE'} = $contenttype;
 		} elsif ($type eq 'thumb') {
 			$info->{'THUMBTYPE'} = $contenttype;
 		}
 	} else {
		if ($type eq 'cover') {
 			$info->{'COVERTYPE'} = '0';
 		} elsif ($type eq 'thumb') {
 			$info->{'THUMBTYPE'} = '0';
 		}
 	}
 	updateCacheEntry($fullpath, $info);
}

sub updateArtworkCache {
	my $file = shift;
	my $cacheEntry = shift;
	
	if (! Slim::Utils::Prefs::get('lookForArtwork')) { return undef};
	
	# Check for Artwork and update %artworkCache
	my $artworksmall = $cacheEntry->{'THUMB'};
	my $album = $cacheEntry->{'ALBUM'};
	if (defined $artworksmall && defined $album && $artworksmall) {
		if (!exists $artworkCache{$album}) { # only cache albums once each
			my $filepath = $file;
			if (isFileURL($file)) {
				$filepath = Slim::Utils::Misc::pathFromFileURL($file);
			}
			$::d_artwork && Slim::Utils::Misc::msg("Updating $album artwork cache: $filepath\n");
			$artworkCache{$album} = $filepath;
		}
	}
}

sub updateGenreCache {
	my $file = shift;
	my $cacheEntry = shift;

	# cache songs  uniquely
	my $genre = $cacheEntry->{'GENRE'};
	if (!defined ($genre) || !$genre) {
		$genre = string('NO_GENRE');
	}

	my $artist = $cacheEntry->{'ARTIST'};
	if (!defined ($artist) || !$artist) {
		$artist = string('NO_ARTIST');
	}

	my $album = $cacheEntry->{'ALBUM'};
	if (!defined ($album) || !$album) {
		$album = string('NO_ALBUM');
	}
	
	my $track = cleanTrackNumber($cacheEntry->{'TRACKNUM'});

	if (!$track) {
		# we always have a title
		$track = $cacheEntry->{'TITLE'};
		if (!defined ($track) || !$track) {
			$track = string('NO_TITLE');
		}
	}

	foreach my $genre (splitTag($genre)) {
		$genre=~s/^\s*//;$genre=~s/\s*$//;
		my $genreCase = Slim::Utils::Text::ignoreCaseArticles($genre);
		foreach my $artist (splitTag($artist)) {
			$artist=~s/^\s*//;$artist=~s/\s*$//;
			my $artistCase = Slim::Utils::Text::ignoreCaseArticles($artist);
			my $albumCase = Slim::Utils::Text::ignoreCaseArticles($album);
			my $trackCase = Slim::Utils::Text::ignoreCaseArticles($track);
	
			my $discNum = $cacheEntry->{'DISC'};
			my $discCount = $cacheEntry->{'DISCC'};
			if (defined($discNum) && (!defined($discCount) || $discCount > 1)) {
				my $discCountLen = defined($discCount) ? length($discCount) : 1;
				$trackCase = sprintf("%0${discCountLen}d-%s", $discNum, $trackCase);
			}

			$genreCache{$genreCase}{$artistCase}{$albumCase}{$trackCase} = $file;

			$caseCache{$genreCase} = $genre;
			$caseCache{$artistCase} = $artist;
			$caseCache{$albumCase} = $album;
			$caseCache{$trackCase} = $track;
			
			if (Slim::Utils::Prefs::get('composerInArtists')) {
				includeSplitTag($genreCase,$albumCase,$trackCase,$file,$cacheEntry->{'COMPOSER'});
				includeSplitTag($genreCase,$albumCase,$trackCase,$file,$cacheEntry->{'BAND'});
			}
			$::d_info && Slim::Utils::Misc::msg("updating genre cache with: $genre - $artist - $album - $track\n--- for:$file\n");
		}
	}
}

sub includeSplitTag {
	my ($genreCase,$albumCase,$trackCase,$file,$tag) = @_;

	if (defined $tag) {
		foreach my $tag (splitTag($tag)) {
			$tag=~s/^\s*//;$tag=~s/\s*$//;
			my $tagCase = Slim::Utils::Text::ignoreCaseArticles($tag);
			$genreCache{$genreCase}{$tagCase}{$albumCase}{$trackCase} = $file;
			$caseCache{$tagCase} = $tag; 
		}
	}
}

sub splitTag {
	my $tag = shift;
	my @splittags=();
	
	my $splitpref = Slim::Utils::Prefs::get('splitchars');
	#only bother if there are some characters in the pref
	if ($splitpref) {
		# get rid of white space
		$splitpref =~ s/\s//g;

		
		foreach my $char (split('',$splitpref),'\x00') {
			my @temp=();
			foreach my $item (split(/\Q$char\E/,$tag)) {
				push (@temp,$item);
				$::d_info && Slim::Utils::Misc::msg("Splitting $tag by $char = @temp\n") unless scalar @temp <= 1;
			}
			#store this for return only if there has been a successfil split
			if (scalar @temp > 1) { push @splittags,@temp}
		}
	}
	#return the split array, or just return the whole tag is we know there hasn't been any splitting.
	if (scalar @splittags > 1) {
		return @splittags;
	} else {
		return $tag;
	}
}

sub fileLength { return info(shift,'FS'); }

sub isFile {
	my $fullpath = shift;

	$fullpath = isFileURL($fullpath) ? Slim::Utils::Misc::pathFromFileURL($fullpath) : $fullpath;
	
	return 0 if (isURL($fullpath));
	
	# check against types.conf
	return 0 unless $Slim::Music::Info::suffixes{ (split /\./, $fullpath)[-1] };

	my $stat = (-f $fullpath && -r $fullpath ? 1 : 0);

	$::d_info && Slim::Utils::Misc::msgf("isFile(%s) == %d\n", $fullpath, (1 * $stat));

	return $stat;
}

sub isFileURL {
	my $url = shift;

	return (defined($url) && ($url =~ /^file:\/\//i));
}

sub isITunesPlaylistURL { 
	my $url = shift;

	return (defined($url) && ($url =~ /^itunesplaylist:/i));
}

sub isMoodLogicPlaylistURL { 
	my $url = shift;

	return (defined($url) && ($url =~ /^moodlogicplaylist:/i));
}

sub isHTTPURL {
	my $url = shift;

	return (defined($url) && ($url =~ /^(http|icy):\/\//i));
}

sub isURL {
	my $url = shift;
	return (defined($url) && ($url =~ /^(http|icy|itunesplaylist|moodlogicplaylist|file):/i));
}

sub isType {
	my $fullpath = shift;
	my $testtype = shift;
	my $type = contentType($fullpath);
	if ($type && ($type eq $testtype)) {
		return 1;
	} else {
		return 0;
	}
}

sub isWinShortcut {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && ($type eq 'lnk'));
}

sub isMP3 {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && (($type eq 'mp3') || ($type eq 'mp2')));
}

sub isOgg {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && ($type eq 'ogg'));
}

sub isWav {
	my $fullpath = shift;
	my $type = contentType( $fullpath);
	return( $type && ( $type eq 'wav'));
}

sub isMOV {
	my $fullpath = shift;
	my $type = contentType( $fullpath);
	return( $type && ( $type eq 'mov'));
}

sub isAIFF {
	my $fullpath = shift;
	my $type = contentType( $fullpath);
	return( $type && ( $type eq 'aif'));
}

sub isSong {
	my $fullpath = shift;
	my $type = shift;

	$type = contentType($fullpath) unless defined $type;

	if ($type && $Slim::Music::Info::slimTypes{$type} && $Slim::Music::Info::slimTypes{$type} eq 'audio') {
		return $type;
	}
}

sub isDir {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && ($type eq 'dir'));
}

sub isM3U {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && ($type eq 'm3u'));
}

sub isPLS {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && ($type eq 'pls'));
}

sub isCUE {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && ($type eq 'cue'));
}

sub isKnownType {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return !(!$type || ($type eq 'unk'));
}

sub isList {
	my $fullpath = shift;

	my $type = contentType($fullpath);

	if ($type && $Slim::Music::Info::slimTypes{$type} && $Slim::Music::Info::slimTypes{$type} =~ /list/) {
		return $type;
	}
}

sub isPlaylist {
	my $fullpath = shift;

	my $type = contentType($fullpath);

	if ($type && $Slim::Music::Info::slimTypes{$type} && $Slim::Music::Info::slimTypes{$type} eq 'playlist') {
		return $type;
	}
}

sub isSongMixable { return info(shift,'MOODLOGIC_SONG_MIXABLE'); }

sub isArtistMixable {
	my $artist = shift;
	return defined $artistMixCache{$artist} ? 1 : 0;
}

sub isGenreMixable {
	my $genre = shift;
	return defined $genreMixCache{$genre} ? 1 : 0;
}

sub moodLogicSongId { return info(shift,'MOODLOGIC_SONG_ID'); }

sub moodLogicArtistId {
	my $artist = shift;
	return $artistMixCache{$artist};
}

sub moodLogicGenreId {
	my $genre = shift;
	return $genreMixCache{$genre};
}

sub mimeType {
	my $file = shift;
	my $contentType = contentType($file);
	foreach my $mt (keys %Slim::Music::Info::mimeTypes) {
		if ($contentType eq $Slim::Music::Info::mimeTypes{ $mt }) {
			return $mt;
		}
	}
	return undef;
};

sub contentType { return info(shift,'CT'); }

sub typeFromSuffix {
	my $path = shift;
	my $defaultType = shift || 'unk';
	
	my $type;
	
	if (defined($path)) {
		if ($path =~ /\.([^.]+)$/) {
			my $suffix = lc($1);
			$type = $Slim::Music::Info::suffixes{$suffix};
		}
	}
	if (!defined($type)) { $type = $defaultType; }
	return $type;
}

sub typeFromPath {
	my $fullpath = shift;
	my $defaultType = shift || 'unk';
	my $type;

	if (defined($fullpath) && $fullpath ne "" && $fullpath !~ /\x00/) {
		if (isHTTPURL($fullpath)) {
			$type = typeFromSuffix($fullpath, $defaultType);
		} elsif ( $fullpath =~ /^([a-z]+:)/ && defined($Slim::Music::Info::suffixes{$1})) {
			$type = $Slim::Music::Info::suffixes{$1};
		} else {
			my $filepath;

			if (isFileURL($fullpath)) {
				$filepath = Slim::Utils::Misc::pathFromFileURL($fullpath);
				$::d_info && Slim::Utils::Misc::msg("Converting $fullpath to $filepath\n");
			} else {
				$filepath = $fullpath;
			}

#			$filepath = Slim::Utils::Misc::fixPath($filepath);
			if (defined($filepath) && $filepath ne "") {
				if (-f $filepath) {
					if ($filepath =~ /\.lnk$/i && Slim::Utils::OSDetect::OS() eq 'win') {
						require Win32::Shortcut;
						if ((Win32::Shortcut->new($filepath)) ? 1 : 0) {
							$type = 'lnk';
						}
					} else {
						$type = typeFromSuffix($filepath, $defaultType);
					}
				} elsif (-d $filepath) {
					$type = 'dir';
				} else {
					#file doesn't exist, go ahead and do typeFromSuffix
					$type = typeFromSuffix($filepath, $defaultType);
				}
			}
		}
	}
	
	if (!defined($type)) {
		$type = $defaultType;
	}

	$::d_info && Slim::Utils::Misc::msg("$type file type for $fullpath\n");
	return $type;
}


1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
