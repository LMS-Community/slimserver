package Slim::Music::Info;

# $Id: Info.pm,v 1.173 2005/01/08 03:42:53 kdf Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Fcntl;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

use MP3::Info;

use Slim::DataStores::DBI::DBIStore;

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

# moodlogic cache for genre and artist mix indicator; empty if moodlogic isn't used
my %genreMixCache = ();
my %artistMixCache = ();

# musicmagic cache for genre and artist mix indicator; empty if musicmagic isn't used
my %genreMMMixCache = ();
my %artistMMMixCache = ();
my %albumMMMixCache = ();

my %artworkCache = ();
my $artworkDir='';

my %lastFile;

my ($currentDB, $localDB);

my %display_cache;

sub init {

	loadTypesConfig();

	$currentDB = $localDB = Slim::DataStores::DBI::DBIStore->new();

	if (!$::noScan && $currentDB->count('track', {}) == 0) {
		Slim::Music::Import::startScan();
	}
	
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

sub getCurrentDataStore {
	return $currentDB;
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


sub clearCache {
	my $item = shift;

	if ($item) {
		$currentDB->delete($item);
	} else {
		$currentDB->markAllEntriesStale();
		$::d_info && Slim::Utils::Misc::msg("clearing validity for rescan\n");
	}

	# moodlogic caches
	%genreMixCache = ();
	%artistMixCache = ();
	
	# musicmagic caches
	%genreMMMixCache = ();
	%artistMMMixCache = ();
	%albumMMMixCache = ();
}


sub saveDBCache {
	$currentDB->forceCommit();
}

sub wipeDBCache {
	$currentDB->wipeAllData();
}

sub clearStaleCacheEntries {
	$currentDB->clearStaleEntries();
}

# Mark an item as having been rescanned
sub markAsScanned {
	my $item = shift;

	$currentDB->markEntryAsValid($item);
}

sub total_time {
	return $currentDB->totalTime();
}

sub clearPlaylists {
	return $currentDB->clearExternalPlaylists() if defined($currentDB);
}

sub playlists {
	return $currentDB->getExternalPlaylists();
}

sub addPlaylist {
	my $url = shift;

	$currentDB->addExternalPlaylist($url);
}

sub generatePlaylists {
	$currentDB->generateExternalPlaylists();
}

# called:
#   undef,undef,undef,undef
sub songCount {
	my ($genre, $artist, $album) = @_;

	my $findCriteria = {};

	if (defined($genre) && scalar(@$genre) && $genre->[0] ne '*') { 
		my $genres = $currentDB->search('genre', $genre);
		return 0 if !scalar(@$genres);
		$findCriteria->{genre} = $genres;
	}

	if (defined($artist) && scalar(@$artist) && $artist->[0] ne '*') { 
		my $artists = $currentDB->search('artist', $artist);
		return 0 if !scalar(@$artists);
		$findCriteria->{contributor} = $artists;
	}

	if (defined($album) && scalar(@$album) && $album->[0] ne '*') { 
		my $albums = $currentDB->search('album', $album);
		return 0 if !scalar(@$albums);
		$findCriteria->{album} = $albums;
	}

	return $currentDB->count('track', $findCriteria);
}

# called:
#   undef,undef,undef,undef
#	[$item],[],[],[]
#	$genreref,$artistref,$albumref,$songref
sub artistCount {
	my ($genre, $artist, $album) = @_;

	my $findCriteria = {};

	if (defined($genre) && scalar(@$genre) && $genre->[0] ne '*') { 
		my $genres = $currentDB->search('genre', $genre);
		return 0 if !scalar(@$genres);
		$findCriteria->{genre} = $genres;
	}

	if (defined($artist) && scalar(@$artist) && $artist->[0] ne '*') { 
		my $artists = $currentDB->search('artist', $artist);
		return 0 if !scalar(@$artists);
		$findCriteria->{contributor} = $artists;
	}

	if (defined($album) && scalar(@$album) && $album->[0] ne '*') { 
		my $albums = $currentDB->search('album', $album);
		return 0 if !scalar(@$albums);
		$findCriteria->{album} = $albums;
	}

	return $currentDB->count('contributor', $findCriteria);
}


# called:
#   undef,undef,undef,undef
#   [$item],[],[],[]
#	[$genre],['*'],[],[]
#   [$genre],[$item],[],[]
#	$genreref,$artistref,$albumref,$songref
sub albumCount { 
	my ($genre, $artist, $album) = @_;

	my $findCriteria = {};

	if (defined($genre) && scalar(@$genre) && $genre->[0] ne '*') { 
		my $genres = $currentDB->search('genre', $genre);
		return 0 if !scalar(@$genres);
		$findCriteria->{genre} = $genres;
	}
	if (defined($artist) && scalar(@$artist) && $artist->[0] ne '*') { 
		my $artists = $currentDB->search('artist', $artist);
		return 0 if !scalar(@$artists);
		$findCriteria->{contributor} = $artists;
	}
	if (defined($album) && scalar(@$album) && $album->[0] ne '*') { 
		my $albums = $currentDB->search('album', $album);
		return 0 if !scalar(@$albums);
		$findCriteria->{album} = $albums;
	}

	return $currentDB->count('album', $findCriteria);
}

# called:
#   undef,undef,undef,undef
sub genreCount { 
	my ($genre, $artist, $album) = @_;

	my $findCriteria = {};

	if (defined($genre) && scalar(@$genre) && $genre->[0] ne '*') { 
		my $genres = $currentDB->search('genre', $genre);
		return 0 if !scalar(@$genres);
		$findCriteria->{genre} = $genres;
	}
	if (defined($artist) && scalar(@$artist) && $artist->[0] ne '*') { 
		my $artists = $currentDB->search('artist', $artist);
		return 0 if !scalar(@$artists);
		$findCriteria->{contributor} = $artists;
	}
	if (defined($album) && scalar(@$album) && $album->[0] ne '*') { 
		my $albums = $currentDB->search('album', $album);
		return 0 if !scalar(@$albums);
		$findCriteria->{album} = $albums;
	}

	return $currentDB->count('genre', $findCriteria);
}

sub isCached {
	my $url = shift;
	return defined($currentDB->objectForUrl($url, 0));
}

sub cacheItem {
	my $url = shift;
	my $item = shift;

	$::d_info_v && Slim::Utils::Misc::msg("CacheItem called for item $item in $url\n");

	my $track = $currentDB->objectForUrl($url, 0) || return undef;

	if ($item eq 'ALBUM') {
		return $track->album()->title();
	}

        return $track->get(lc $item) || undef;
}

sub updateCacheEntry {
	my $url = shift;
	my $cacheEntryHash = shift;

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

	my $list;
	if ($cacheEntryHash->{'LIST'}) {
		$list = $cacheEntryHash->{'LIST'};
	}

	my $song = $currentDB->updateOrCreate($url, $cacheEntryHash);
	if ($list) {
		my @tracks = map { $currentDB->objectForUrl($_, 1); } @$list;
		$song->setTracks(@tracks);
	}
}

sub reBuildCaches {
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

sub updateGenreMMMixCache {
	my $genre = shift;
	$genreMMMixCache{$genre} = $genre;
}

sub updateArtistMMMixCache {
	my $artist = shift;
	$artistMMMixCache{$artist} = $artist;
}

sub updateAlbumMMMixCache {
	my $cacheEntry = shift;

	if (defined $cacheEntry->{MUSICMAGIC_ALBUM_MIXABLE} &&
		$cacheEntry->{MUSICMAGIC_ALBUM_MIXABLE} == 1) {
		my $artist = $cacheEntry->{'ARTIST'};
		my $album = $cacheEntry->{'ALBUM'};
		my $key = "$artist\@\@$album";
		$albumMMMixCache{$key} = 1;
	}
}

##################################################################################
# this routine accepts both our three letter content types as well as mime types.
# if neither match, we guess from the URL.
sub setContentType {
	my $url = shift;
	my $type = shift;
	
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

	$currentDB->updateOrCreate($url, { 'CT' => $type });
	$::d_info && Slim::Utils::Misc::msg("Content type for $url is cached as $type\n");
}

sub setTitle {
	my $url = shift;
	my $title = shift;

	$::d_info && Slim::Utils::Misc::msg("Adding title $title for $url\n");

	$currentDB->updateOrCreate($url, { 'TITLE' => $title });
}

sub setBitrate {
	my $url = shift;
	my $bitrate = shift;

	$currentDB->updateOrCreate($url, { 'BITRATE' => $bitrate });
}

my $ncElemstring = "VOLUME|PATH|FILE|EXT|DURATION|LONGDATE|SHORTDATE|CURRTIME|FROM|BY"; #non-cached elements
my $ncElems = qr/$ncElemstring/;

my $elemstring = (join '|', map { uc $_ } keys %{Slim::DataStores::DBI::Track->attributes()}, $ncElemstring, "ARTIST|ALBUM|GENRE|ALBUMSORT|ARTISTSORT|DISC|DISCC");
#		. "|VOLUME|PATH|FILE|EXT" #file data (not in infoCache)
#		. "|DURATION" # SECS expressed as mm:ss (not in infoCache)
#		. "|LONGDATE|SHORTDATE|CURRTIME" #current date/time (not in infoCache)
my $elems = qr/$elemstring/;


#TODO Add elements for size dependent items (volume bar, progress bar)
#my $sdElemstring = "VOLBAR|PROGBAR"; #size dependent elements (also not cached)
#my $sdElems = qr/$sdElemstring/;

sub elemLookup {
	my $element     = shift;
	my $infoHashref = shift;

	# don't return disc number if known to be single disc set
	if ($element eq "DISC") {
		my $discCount = $infoHashref->{"DISCC"};
		return undef if defined $discCount and $discCount == 1;
	}

	return $infoHashref->{$element};
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

# formats information about a file using a provided format string
sub infoFormat {
	no warnings; # this is to allow using null values with string concatenation, it only effects this procedure
	my $fileOrObj = shift; # item whose information will be formatted
	my $str = shift; # format string to use
	my $safestr = shift; # format string to use in the event that after filling the first string, there is nothing left
	my $pos = 0; # keeps track of position within the format string
	
	my $track = ref $fileOrObj ? $fileOrObj  : $currentDB->objectForUrl($fileOrObj, 1);
	my $file  = ref $fileOrObj ? $track->url : $fileOrObj;

	return '' unless defined $file && $track;
	
	my $infoRef = infoHash($track, $file) || return '';
	
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

	# same regex as above, but the last element is the end of the string
	$str =~ s{\G(.*?)?(?:=>(.*?)=>)?(?:=>(.*?)=>)?($elems)(?:<=(.*?)<=)?(.*?)?(?:<#(.*?)#>)?$}
				{
					my $out = '';
					my $value = elemLookup($4, \%infoHash);
					if (defined($value)) {
						#fill with all the separators
						#no need to do the <##> conversion since this is the end of the string
						$out = $1 . $2 . $3 . $value . $5 . $6 . $7;

					} else {
						# value not defined
						# only use the bare separators if there were framed ones as well
						$out  = (defined($2) || defined($3)) ? $1 : "";
						$out .= (defined($5) || defined($7)) ? $6 : "";
					}
					$out;
				}e;

	if ($str eq "" && defined($safestr)) {

		# if there isn't anything left of the format string after the replacements, use the safe string, if supplied
		return infoFormat($track,$safestr);

	} else {
		$str =~ s/%([0-9a-fA-F][0-9a-fA-F])%/chr(hex($1))/eg;
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

	if (isRemoteURL($file)) {
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
	my $client    = shift;
	my $pathOrObj = shift; # item whose information will be formatted
	my $track     = ref $pathOrObj ? $pathOrObj : $currentDB->objectForUrl($pathOrObj, 1);
	my $fullpath  = ref $pathOrObj ? $track->url : $pathOrObj;
	my $format;

	if (isPlaylistURL($fullpath) || isList($fullpath)) {

		$format = 'TITLE';

	} elsif (defined($client)) {

		# in array syntax this would be
		# $titleFormat[$clientTitleFormat[$clientTitleFormatCurr]] get
		# the title format

		$format = Slim::Utils::Prefs::getInd("titleFormat",
			# at the array index of the client titleformat array
			Slim::Utils::Prefs::clientGet($client, "titleFormat",
				# which is currently selected
				Slim::Utils::Prefs::clientGet($client,'titleFormatCurr')
			)
		);

	} else {

		# in array syntax this would be $titleFormat[$titleFormatWeb]
		$format = Slim::Utils::Prefs::getInd("titleFormat", Slim::Utils::Prefs::get("titleFormatWeb"));
	}
	
	# Client may not be defined, but we still want to use the cache.
	$client ||= 'NOCLIENT';

	my $ref = $display_cache{$client} ||= {
		'fullpath' => '',
		'format'   => '',
	};

	if (!isFile($fullpath) || $fullpath ne $ref->{'fullpath'} || $format ne $ref->{'format'}) {

		$ref = $display_cache{$client} = {
			'fullpath' => $fullpath,
			'format'   => $format,
			'display'  => infoFormat($fullpath, $format, 'TITLE'),
		};
	}

	return $ref->{'display'};
}

#
# Guess the important tags from the filename; use the strings in preference
# 'guessFileFormats' to generate candidate regexps for matching. First
# match is accepted and applied to the argument tag hash.
#
sub guessTags {
	my $filename = shift;
	my $type = shift;
	my $taghash = shift;
	
	my $file = $filename;
	$::d_info && Slim::Utils::Misc::msg("Guessing tags for: $file\n");

	# Rip off from plainTitle()
	if (isRemoteURL($file)) {
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
				$match =~ tr/_/ / if (defined $match);
				$match = int($match) if $tags[$i] =~ /TRACKNUM|DISC{1,2}/;
				$taghash->{$tags[$i++]} = $match;
			}
			return;
		}
	}
	
	# Nothing found; revert to plain title
	$taghash->{'TITLE'} = plainTitle($filename, $type);	
}


#
# Return a structure containing the ID3 tag attributes of the given MP3 file.
#
sub infoHash {
	my $track = shift;
	my $file  = shift;

	if (!defined($file) || $file eq "") { 
		$::d_info && Slim::Utils::Misc::msg("trying to get infoHash on an empty file name\n");
		$::d_info && Slim::Utils::Misc::bt();
		return; 
	};

	if (!defined($track)) { 
		$::d_info && Slim::Utils::Misc::msg("trying to get infoHash on an empty track\n");
		$::d_info && Slim::Utils::Misc::bt();
		return; 
	};
	
	if (!isURL($file)) { 
		Slim::Utils::Misc::msg("Non-URL passed to InfoHash::info ($file)\n");
		Slim::Utils::Misc::bt();
		$file = Slim::Utils::Misc::fileURLFromPath($file); 
	}
	
	my $cacheEntryHash = {};

	foreach my $attribute (keys %{Slim::DataStores::DBI::Track->attributes}) {

		if ($attribute eq "album") {

			my $album = $track->album() || next;

			$cacheEntryHash->{"ALBUM"}     = $album->title;
			$cacheEntryHash->{"ALBUMSORT"} = $album->titlesort;
			$cacheEntryHash->{"DISC"}      = $album->disc;
			$cacheEntryHash->{"DISCC"}     = $album->discc;

			next;
		}

		if (my $item = $track->get($attribute)) {
			$cacheEntryHash->{uc $attribute} = $item;
		}
	}

	$cacheEntryHash->{"ARTIST"}     = $track->artist;
	$cacheEntryHash->{"ARTISTSORT"} = $track->artistsort;
	$cacheEntryHash->{"GENRE"}      = $track->genre;

	return $cacheEntryHash;
}

sub info {
	my $file    = shift;
	my $tagname = shift;

	if (!defined $file || $file eq '' || !defined $tagname || $tagname eq '') { 
		$::d_info && Slim::Utils::Misc::msg("trying to get info on an empty file name\n");
		$::d_info && Slim::Utils::Misc::bt();
		return; 
	};
	
	$::d_info && Slim::Utils::Misc::msg("Request for $tagname on file $file\n");
	
	if (!isURL($file)) { 
		$::d_info && Slim::Utils::Misc::msg("Non-URL passed to Info::info ($file)\n");
		$::d_info && Slim::Utils::Misc::bt();

		$file = Slim::Utils::Misc::fileURLFromPath($file); 
	}
	
	my $track = $currentDB->objectForUrl($file, 0) || return;

	if ($tagname =~ /^(?:ALBUM|ALBUMSORT|DISC|DISCC)$/o) {

		my $album = $track->album() || return;

		return $album->title()     if $tagname eq 'ALBUM';
		return $album->titlesort() if $tagname eq 'ALBUMSORT';
		return $album->disc()      if $tagname eq 'DISC';
		return $album->disccc()    if $tagname eq 'DISCCC';
	}

	#FIXME
	if ($tagname =~ /^(?:COMPOSER|BAND|CONDUCTOR|COMMENT)$/o) {
		return undef;
	}
	
	# Fall through
	my $lcTag = lc($tagname);

	# These need to go through their overridden methods.
	if ($tagname =~ /^(?:GENRE|ARTIST|ARTISTSORT)$/o) {
		return $track->$lcTag();
	}

	return $track->get($lcTag);
}

sub trackNumber { return info(shift,'TRACKNUM'); }

sub cleanTrackNumber {
	my $tracknumber = shift;

	if (defined($tracknumber)) {
		# extracts the first digits only sequence then converts it to int
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

	return info($file,'ARTISTSORT') || Slim::Utils::Text::ignoreCaseArticles(artist($file));
}

sub albumSort {
	my $file = shift;

	return info($file,'ALBUMSORT') || Slim::Utils::Text::ignoreCaseArticles(album($file));
}

sub titleSort {
	my $file = shift;

	return info($file,'TITLESORT') || Slim::Utils::Text::ignoreCaseArticles(title($file));
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

	return sprintf('%s:%02s',int($secs / 60),$secs % 60) if defined $secs;
}

sub durationSeconds { return info(shift,'SECS'); }

sub offset { return info(shift,'OFFSET'); }

sub size { return info(shift,'SIZE'); }

sub bitrate {
	my $file = shift;
	my $mode = (defined info($file,'VBR_SCALE')) ? 'VBR' : 'CBR';

	my $bitrate = info($file,'BITRATE');

	if ($bitrate) {
		return int ($bitrate/1000).Slim::Utils::Strings::string('KBPS').' '.$mode;
	}
}

sub digitalrights { return info(shift,'DRM'); }

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
	my $artwork = $art eq 'cover' ? haveCoverArt($file) : haveThumbArt($file);
	
	if ($artwork && ($artwork ne '1')) {
		$body = getImageContent($artwork);
		if ($body) {
			$::d_artwork && Slim::Utils::Misc::msg("Found cached $art file: $artwork\n");
			$contenttype = mimeType(Slim::Utils::Misc::fileURLFromPath($artwork));
			$path = $artwork;
		} else {
			($body, $contenttype, $path) = readCoverArt($file, $art);
		}
	} 
	else {
		($body, $contenttype,$path) = readCoverArt($file,$art);
	}

	# kick this back up to the webserver so we can set last-modified
	if ($path && -r $path) {
		$mtime = (stat(_))[9];
	}

	return ($body, $contenttype, $mtime);
}

sub age { return info(shift, 'AGE') || 0; }
sub tagVersion { return info(shift,'TAGVERSION'); }

sub cachedPlaylist {
	my $url = shift;

	my $song = $currentDB->objectForUrl($url, 0) || return undef;

	my @urls = map { $_->url } $song->tracks();

	if (!scalar @urls) {
		@urls = $song->diritems();
	}

	return \@urls if scalar(@urls);

	return undef;
}

sub cachePlaylist {
	my $url = shift;
	my $list = shift;
	my $age = shift;

	my $song = $currentDB->objectForUrl($url, 1);

	if (scalar(@$list) && isURL($list->[0])) {
		my @tracks = map { $currentDB->objectForUrl($_, 1); } @$list;
		$song->setTracks(@tracks);
	} else {
		$song->setDirItems(@$list);
	}

	$age = Time::HiRes::time() unless defined $age;

	$song->timestamp($age);
	$currentDB->updateTrack($song);
	
	$::d_info && Slim::Utils::Misc::msg("cached an " . (scalar @$list) . " item playlist for $url\n");
}

# genres|artists|albums|songs(genre,artist,album,song)
#===========================================================================
# Return list of matching keys at the given level in the genre tree.  Each
# of the arguments is an array reference of file glob type patterns to match.
# In order to match, all the elements of the list must match at the given
# level of the genre tree.

sub genres {
	my $genre  = shift;
	
	$::d_info && Slim::Utils::Misc::msg("genres: $genre\n");

	Slim::Utils::Misc::bt();
	warn "Slim::Music::Info::genres() is deprecated - use the DataSource API instead.\n";

	my $findCriteria = {};

	if (defined($genre) && scalar(@$genre) && $genre->[0] && $genre->[0] ne '*') { 
		my $genres = $currentDB->search('genre', $genre);
		return () if !scalar(@$genres);
		$findCriteria->{genre} = $genres;
	}

	my $genres = $currentDB->find('genre', $findCriteria, 'genre');
	return map { $_->name } @$genres;
}

sub artists {
	my $genre  = shift;
	my $artist = shift;
	my $album  = shift;
	my $song   = shift;
	my $limit  = shift || '';
	my $offset = shift || '';

	Slim::Utils::Misc::bt();
	warn "Slim::Music::Info::artists() is deprecated - use the DataSource API instead.\n";

	$::d_info && Slim::Utils::Misc::msg("artists: $genre - $artist - $album - $limit - $offset\n");

	my $findCriteria = {};

	if (defined($genre) && scalar(@$genre) && $genre->[0] && $genre->[0] ne '*') { 
		my $genres = $currentDB->search('genre', $genre);
		return () if !scalar(@$genres);
		$findCriteria->{genre} = $genres;
	}

	if (defined($artist) && scalar(@$artist) && $artist->[0] && $artist->[0] ne '*') { 
		my $artists = $currentDB->search('artist', $artist);
		return () if !scalar(@$artists);
		$findCriteria->{contributor} = $artists;
	}

	if (defined($album) && scalar(@$album) && $album->[0] && $album->[0] ne '*') { 
		my $albums = $currentDB->search('album', $album);
		return () if !scalar(@$albums);
		$findCriteria->{album} = $albums;
	}

	#my $artists = $currentDB->find('artist', $findCriteria, 'artist', $limit, $offset);
	my $artists = $currentDB->find('artist', $findCriteria, 'artist');

	return map { $_->name } @$artists;
}

sub artwork {
	my $albums = $currentDB->albumsWithArtwork();

	return Slim::Utils::Text::sortuniq_ignore_articles(map {$_->title} @$albums);
}

sub albums {
	my $genre  = shift;
	my $artist = shift;
	my $album  = shift;

	$::d_info && Slim::Utils::Misc::msg("albums: $genre - $artist - $album\n");

	Slim::Utils::Misc::bt();
	warn "Slim::Music::Info::albums() is deprecated - use the DataSource API instead.\n";

	my $findCriteria = {};

	if (defined($genre) && scalar(@$genre) && $genre->[0] && $genre->[0] ne '*') { 
		my $genres = $currentDB->search('genre', $genre);
		return () if !scalar(@$genres);
		$findCriteria->{genre} = $genres;
	}

	if (defined($artist) && scalar(@$artist) && $artist->[0] && $artist->[0] ne '*') { 
		my $artists = $currentDB->search('artist', $artist);
		return () if !scalar(@$artists);
		$findCriteria->{contributor} = $artists;
	}

	if (defined($album) && scalar(@$album) && $album->[0] && $album->[0] ne '*') { 
		my $albums = $currentDB->search('album', $album);
		return () if !scalar(@$albums);
		$findCriteria->{album} = $albums;
	}

	my $albums = $currentDB->find('album', $findCriteria, 'album');
	return map { $_->title } @$albums;
}

# Return cached path for a given album name
sub pathFromAlbum {
	my $album = shift;

	my ($albums) = $currentDB->search('album', [$album]);

	my ($obj) = $currentDB->find('album', { album => $albums }, 'album') || return undef;

	return $obj->artwork_path();
}

# return all songs for a given genre, artist, and album
sub songs {
	my $genre	= shift;
	my $artist	= shift;
	my $album	= shift;
	my $track	= shift;
	my $sortbytitle = shift;

	$::d_info && Slim::Utils::Misc::msg("songs: $genre - $artist - $album - $track\n");

	Slim::Utils::Misc::bt();
	warn "Slim::Music::Info::songs() is deprecated - use the DataSource API instead.\n";

	my $findCriteria = {};

	if (defined($genre) && scalar(@$genre) && $genre->[0] && $genre->[0] ne '*') { 
		my $genres = $currentDB->search('genre', $genre);
		return () if !scalar(@$genres);
		$findCriteria->{genre} = $genres;
	}

	if (defined($artist) && scalar(@$artist) && $artist->[0] && $artist->[0] ne '*') { 

		my $artists = $currentDB->search('artist', $artist);
		return () if !scalar(@$artists);
		$findCriteria->{contributor} = $artists;
	}

	if (defined($album) && scalar(@$album) && $album->[0] && $album->[0] ne '*') { 
		my $albums = $currentDB->search('album', $album);
		return () if !scalar(@$albums);
		$findCriteria->{album} = $albums;
	}

	if (defined($track) && scalar(@$track) && $track->[0] && $track->[0] ne '*') { 
		my $tracks = $currentDB->search('track', $track);
		return () if !scalar(@$tracks);
		$findCriteria->{track} = $tracks;
	}

	my $multalbums  = ((scalar(@$album) > 1) || (scalar(@$album) == 1 && $album->[0] =~ /\*/));
	
	my $sortBy;
	if ($sortbytitle) {
		$sortBy = "title";
	} elsif ($multalbums) {
		$sortBy = "track";
	} else {
		$sortBy = "tracknum";
	}

	my $songs = $currentDB->find('track', $findCriteria, $sortBy);

	return map { $_->url } @$songs;
}

# XXX - sigh, globals
my $articles = undef;

sub sortByTrack {

	$articles = undef;

	#get info for items and ignoreCaseArticles it
	my @sortinfo =  map { getInfoForSort($_) } @_;

	#return the first element of each entry in the sorted array
	return map {$_->[0]} sort sortByTrackAlg @sortinfo;
}

sub sortByAlbum {

	$articles = undef;

	#get info for items and ignoreCaseArticles it
	my @sortinfo =  map { getInfoForSort($_) } @_;

	#return an array of first elements of the entries in the sorted array
	return map {$_->[0]} sort sortByAlbumAlg @sortinfo;
}

sub sortByTitles {

	$articles = undef;

	#get info for items and ignoreCaseArticles it
	my @sortinfo =  map { getInfoForSort($_) } @_;

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
	my $list = isList($item);
	return [
		$item,
		$list,
		$list ? undef : artistSort($item),
		$list ? undef : albumSort($item),
		$list ? undef : trackNumber($item),
		titleSort($item),
		$list ? undef : disc($item)
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
	} elsif (isRemoteURL($j)) {
		$j = Slim::Web::HTTP::unescape($j);
	} else {
		$j = (splitdir($j))[-1];
	}
	return $j;
}


sub sortFilename {
	#build the sort index
	my @nocase = map { Slim::Utils::Text::ignoreCaseArticles(fileName($_)) } @_;
	#return the input array sliced by the sorted array
	return @_[sort {$nocase[$a] cmp $nocase[$b]} 0..$#_];
}


sub isFragment {
	my $fullpath = shift;
	
	return unless isURL($fullpath);

	my $anchor = Slim::Utils::Misc::anchorFromURL($fullpath);

	if ($anchor && $anchor =~ /([\d\.]+)-([\d\.]+)/) {
		return ($1, $2);
	}
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
		$entry->{'ALBUM'} .= sprintf(" (%s %${discCountLen}d %s %d)", $discWord, $discNum, string('OF'), $discCount);
	} else {
		$entry->{'ALBUM'} .= " ($discWord $discNum)";
	}
}

sub getImageContent {
	my $path = shift;

	use bytes;
	my $contentref;

	if (open (TEMPLATE, $path)) { 
		local $/ = undef;
		binmode(TEMPLATE);
		$$contentref = <TEMPLATE>;
		close TEMPLATE;
	}
	
	defined($$contentref) && length($$contentref) || $::d_artwork && Slim::Utils::Misc::msg("Image File empty or couldn't read: $path\n");
	return $$contentref;
}

sub readCoverArt {
	my $fullpath = shift;
	my $image    = shift || 'cover';

	my ($body,$contenttype,$path) = readCoverArtTags($fullpath);

	if (!defined $body) {
		($body,$contenttype,$path) = readCoverArtFiles($fullpath,$image);
	}

	return ($body,$contenttype,$path);
}
	
sub readCoverArtTags {
	use bytes;
	my $fullpath = shift;
	my $tags = shift;

	return undef unless Slim::Utils::Prefs::get('lookForArtwork');

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
	
			$tags = MP3::Info::get_mp3tag($file, 2, 1);
			if (defined $tags) {
				$::d_artwork && Slim::Utils::Misc::msg("Looking for image in ID3 2.2 tag in file $file\n");
				# look for ID3 v2.2 picture
				my $pic = $tags->{'PIC'};
				if (defined($pic)) {
					if (ref($pic) eq 'ARRAY') {
						$pic = (@$pic)[0];
					}					
					my ($encoding, $format, $picturetype, $description) = unpack 'Ca3CZ*', $pic;
					my $len = length($description) + 1 + 5;
					if ($encoding) { $len++; } # skip extra terminating null if unicode
					
					if ($len < (length($pic))) {		
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


sub updateArtworkCache {
	my $file = shift;
	my $cacheEntry = shift;

	if (! Slim::Utils::Prefs::get('lookForArtwork')) { return undef};

	my $artworksmall = $cacheEntry->{'THUMB'};
	my $album = $cacheEntry->{'ALBUM'};

	$currentDB->setAlbumArtwork($album, $artworksmall);
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

sub isHTTPURL {
	my $url = shift;

	return (defined($url) && ($url =~ /^(http|icy):\/\//i));
}

sub isRemoteURL {
	my $url = shift;
	return (defined($url) && ($url =~ /^([a-zA-Z0-9\-]+):/) && $Slim::Player::Source::protocolHandlers{$1});
}

sub isPlaylistURL {
	my $url = shift;
	return (defined($url) && ($url =~ /^([a-zA-Z0-9\-]+):/) && exists($Slim::Player::Source::protocolHandlers{$1}) && !isFileURL($url));
}

sub isURL {
	my $url = shift;
	return (defined($url) && ($url =~ /^([a-zA-Z0-9\-]+):/) && exists($Slim::Player::Source::protocolHandlers{$1}));
}

sub isType {
	my $pathOrObj = shift;
	my $testtype  = shift;
if (!defined $currentDB) {Slim::Utils::Misc::bt();}
	my $type = ref $pathOrObj ? $pathOrObj->content_type : $currentDB->contentType($pathOrObj, 1);

	if ($type && ($type eq $testtype)) {
		return 1;
	} else {
		return 0;
	}
}

sub isWinShortcut {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'lnk');
}

sub isMP3 {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'mp[23]');
}

sub isOgg {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'ogg');
}

sub isWav {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'wav');
}

sub isMOV {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'mov');
}

sub isAIFF {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'aif');
}

sub isSong {
	my $pathOrObj = shift;
	my $type = shift;

	$type = ref $pathOrObj ? $pathOrObj->content_type : $currentDB->contentType($pathOrObj, 1) unless defined $type;

	if ($type && $Slim::Music::Info::slimTypes{$type} && $Slim::Music::Info::slimTypes{$type} eq 'audio') {
		return $type;
	}
}

sub isDir {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'dir');
}

sub isM3U {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'm3u');
}

sub isPLS {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'pls');
}

sub isCUE {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'cue');
}

sub isKnownType {
	my $pathOrObj = shift;

	return !isType($pathOrObj, 'unk');
}

sub isList {
	my $pathOrObj = shift;
	my $type = shift;

	$type = ref $pathOrObj ? $pathOrObj->content_type : $currentDB->contentType($pathOrObj, 1) unless defined $type;

	if ($type && $Slim::Music::Info::slimTypes{$type} && $Slim::Music::Info::slimTypes{$type} =~ /list/) {
		return $type;
	}
}

sub isPlaylist {
	my $pathOrObj = shift;
	my $type = shift;

	$type = ref $pathOrObj ? $pathOrObj->content_type : $currentDB->contentType($pathOrObj, 1) unless defined $type;

	if ($type && $Slim::Music::Info::slimTypes{$type} && $Slim::Music::Info::slimTypes{$type} eq 'playlist') {
		return $type;
	}
}

sub isSongMixable {
	my $song = shift;

	return info($song,'MOODLOGIC_SONG_MIXABLE'); 
}

sub isSongMMMixable {
	my $song = shift;

	return defined info($song,'MUSICMAGIC_SONG_MIXABLE') ? 1 : 0; 
}

sub isAlbumMMMixable {
	my $artist = shift;
	my $album = shift;
	my $key = "$artist\@\@$album";
	return defined $albumMMMixCache{$key} ? 1 : 0;
}

sub isArtistMixable {
	my $artist = shift;
	return defined $artistMixCache{$artist} ? 1 : 0;
}

sub isArtistMMMixable {
	my $artist = shift;
	return defined $artistMMMixCache{$artist} ? 1 : 0;
}

sub isGenreMixable {
	my $genre = shift;
	return defined $genreMixCache{$genre} ? 1 : 0;
}

sub isGenreMMMixable {
	my $genre = shift;
	return defined $genreMMMixCache{$genre} ? 1 : 0;
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

sub contentType { 
	return $currentDB->contentType(shift, 1); 
}

sub typeFromSuffix {
	my $path = shift;
	my $defaultType = shift || 'unk';
	
	if (defined $path && $path =~ /\.([^.]+)$/) {
		return $Slim::Music::Info::suffixes{lc($1)};
	}

	return $defaultType;
}

sub typeFromPath {
	my $fullpath = shift;
	my $defaultType = shift || 'unk';
	my $type;

	if (defined($fullpath) && $fullpath ne "" && $fullpath !~ /\x00/) {
		if (isRemoteURL($fullpath)) {
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
