package Slim::Music::LocalDataSource;

# $Id: LocalDataSource.pm,v 1.1 2004/08/13 07:42:31 vidur Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw{Slim::Music::DataSource};

use MP3::Info;
use DBI;

use Slim::Music::DBI;
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

# Save the persistant DB cache on an interval
use constant DB_SAVE_INTERVAL => 600;

# Entries in the database are assumed to be valid for approximately 5
# minutes before we check date/time stamps again
use constant DB_CACHE_LIFETIME => 5 * 60;

# Validity cache entries are arrays with:
use constant VALID_INDEX => 0;
use constant TTL_INDEX => 1;

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

#
# Generic DataSource interface methods:
#
sub new {
	my $class = shift;

	my $self = {
		# Handle to the DBI database we're going to use.
		dbh => Slim::Music::DBI::db_Main,
		# Values persisted in metainformation table
		songCount => 0,
		totalTime => 0,
		# Non-persistent hash to maintain the VALID and TTL values for
		# song entries.
		validityCache => {},
		# Non-persistent cache to make sure we don't set album artwork
		# too many times.
		artworkCache => {},
		# Non-persistent caches to store cover and thumb properties
		coverCache => {},
		thumbCache => {},
		# Optimization to cache content type for song entries rather than
		# look them up everytime.
		contentTypeCache => {},
		# Optimization to cache last song accessed rather than retrieve it
		# again. 
		lastSongURL => '',
		lastSong => undef,
		# Selected list of external (for now iTunes and Moodlogic)
		# playlists.
		externalPlaylists => [],
		# Songs that are out of date and should be deleted the next time
		# we get around to it.
		zombieList => {},
	};
	bless $self, $class;

	($self->{songCount}, $self->{totalTime}) = 
	  Slim::Music::DBI::getMetaInformation;
	$self->generateExternalPlaylists();
	
	$self->_commitDBTimer();

	return $self;
}

sub song {
	my $self = shift;
	my $url = shift;
	my $fleshTags = shift;
	my $dontCheckTTL = shift;

	if (!defined($url)) {
		Slim::Utils::Misc::msg("Null song request!\n"); 
		Slim::Utils::Misc::bt();
		return undef;
	}

	my $song = $self->_retrieveSong($url);

	# we'll update the cache if we don't have a valid title in the cache
	if ($fleshTags && (!defined($song) || !$song->tag)) {
		$song = $self->readTags($url)
	}

	if (defined($song)) {
		if (!$dontCheckTTL) {
			my $ttl = $self->{validityCache}->{$url}->[TTL_INDEX] || 0;
			if (Slim::Music::Info::isFileURL($url) && ($ttl < (time()))) {
				$::d_info && Slim::Utils::Misc::msg("CacheItem: Checking status of $url (TTL: $ttl).\n");
				if ($self->_hasChanged($song)) {
					return undef;
				} 
				else {
					$self->{validityCache}->{$url}->[TTL_INDEX] = (time()+ DB_CACHE_LIFETIME + int(rand(DB_CACHE_LIFETIME)));
				}
			}
		}
	}

	return $song;

}

sub songAttribute {
	my $self = shift;
	my $url = shift;
	my $attribute = shift;

	if (!defined($url) || $url eq "" || !defined($attribute)) { 
		$::d_info && Slim::Utils::Misc::msg("trying to get attribute on an empty url\n");
		$::d_info && Slim::Utils::Misc::bt();
		return; 
	};

	my $item;
	# Cache the value of the content type, since it's fetched
	# very often.
	if ($attribute eq 'CT') {
		$item = $self->{contentTypeCache}->{$url};
		return $item if defined($item);
	}

	my $song = $self->song($url, 0, 1);
	if (defined($song)) {
		$item = $song->get($attribute);
	}
	
	# update the cache if the tag is not defined in the cache
	if (!defined($item)) {
		# defer cover information until needed
		if ($attribute =~ /^(COVER|COVERTYPE)$/) {
			$self->_updateCoverArt($url, 'cover');
		# defer thumb information until needed
		} elsif ($attribute =~ /^(THUMB|THUMBTYPE)$/) {
			$self->_updateCoverArt($url, 'thumb');
		} elsif (!defined($song) || !$song->tag) {
			$::d_info && Slim::Utils::Misc::msg("cache miss for $url\n");
			$song = $self->readTags($url);
		}
		$item = $song->get($attribute);	
	}

	if ($item && $attribute eq 'CT') {
		$self->{contentTypeCache}->{$url} = $item;
	}

	return $item;
}

sub getGenres {
	my $self = shift;
	my $genrePatterns = shift;

	return Slim::Music::Genre::genreSearch($genrePatterns);
}

sub getArtists {
	my $self = shift;
	my $genrePatterns = shift;
	my $artistPatterns = shift;
	my $albumPatterns = shift;

	return Slim::Music::Artist::artistSearch($genrePatterns, 
											 $artistPatterns, 
											 $albumPatterns,
											 0);
}

sub getAlbums {
	my $self = shift;
	my $genrePatterns = shift;
	my $artistPatterns = shift;
	my $albumPatterns = shift;

	return Slim::Music::Album::albumSearch($genrePatterns, 
										   $artistPatterns, 
										   $albumPatterns,
										   0);
}

sub getSongs {
	my $self = shift;
	my $genrePatterns = shift;
	my $artistPatterns = shift;
	my $albumPatterns = shift;
	my $songPatterns = shift;
	my $sortByTitle = shift;

	return Slim::Music::Song::songSearch($genrePatterns, 
										 $artistPatterns, 
										 $albumPatterns, 
										 $songPatterns, 
										 $sortByTitle, 0);
}

sub getAlbumsWithArtwork {
	my $self = shift;
	
	return Slim::Music::Album->hasArtwork();
}

sub totalTime {
	my $self = shift;

	return $self->{totalTime};
}

sub genreCount {
	my $self = shift;
	my $genrePatterns = shift;

	if (!$genrePatterns || scalar @$genrePatterns == 0 ||  
		$$genrePatterns[0] eq '*') {
		return Slim::Music::Genres->sql_count_all->select_val;
	} 

	return scalar($self->genres($genrePatterns));
}

sub artistCount {
	my $self = shift;
	my $genrePatterns = shift;
	my $artistPatterns = shift;
	my $albumPatterns = shift;

	return Slim::Music::Artist::artistSearch($genrePatterns, 
											 $artistPatterns, 
											 $albumPatterns,
											 1);
}

sub albumCount {
	my $self = shift;
	my $genrePatterns = shift;
	my $artistPatterns = shift;
	my $albumPatterns = shift;

	return Slim::Music::Album::albumSearch($genrePatterns, 
										   $artistPatterns, 
										   $albumPatterns,
										   1);
}

sub songCount {
	my $self = shift;
	my $genrePatterns = shift;
	my $artistPatterns = shift;
	my $albumPatterns = shift;
	my $songPatterns = shift;

	if ((scalar @$genrePatterns == 0 || $$genrePatterns[0] eq '*') &&
		(scalar @$artistPatterns == 0 || $$artistPatterns[0] eq '*') &&
		(scalar @$albumPatterns == 0 || $$albumPatterns[0] eq '*') &&
		(scalar @$songPatterns == 0 || $$songPatterns[0] eq '*')) {
		return $self->{songCount};	
	}

	return Slim::Music::Song::songSearch($genrePatterns, 
										 $artistPatterns, 
										 $albumPatterns, 
										 $songPatterns, 
										 0, 1);
}

sub getExternalPlaylists {
	my $self = shift;

	return $self->{externalPlaylists};
}

#
# LocalDataSource interface methods:
#

# Update the song object in the database. The assumption is that
# attribute setter methods may already have been invoked on the
# object.
sub updateSong {
	my $self = shift;
	my $song = shift;
	my $commit = shift;

	$song->update;
	if ($commit) {
		$self->{dbh}->commit;
	}

	my $url = $song->url;
	$self->_updateSongValidity($url);
}

# Create a new song with the given attributes
sub newSong {
	my $self = shift;
	my $url = shift;
 	my $attributeHash = shift;
	my $commit = shift;

	return if !$url;

	$::d_info && Slim::Utils::Misc::msg("New song for $url\n");
	$attributeHash = _checkAttributes($attributeHash);
	
	my $song = Slim::Music::Song->create($attributeHash);
	return undef if !defined($song);

	$self->{lastSongURL} = $url;
	$self->{lastSong} = $song;

	if ($self->_includeInSongCount($song)) { 
		my $time = $song->secs;
		if ($time) {
			$self->{totalTime} += $time;
		}
		$self->{songCount}++;
	}
	$self->_updateSongValidity($url);

	if ($commit) {
		$self->{dbh}->commit;
	}

	return $song;
}

# Update the attributes of a song or create one if one doesn't 
# already exist.
sub updateSongAttributes {
	my $self = shift;
	my $url = shift;
	my $attributeHash = shift;
	my $commit = shift;

	if (!defined($url)) {
		Slim::Utils::Misc::msg("No URL specified for updateSongAttributes\n");
		Slim::Utils::Misc::msg(%{$attributeHash});
		Slim::Utils::Misc::bt();
		return;
	}

	delete $self->{zombieList}->{$url};

	my $song = $self->_retrieveSong($url);
	my $songColumns = Slim::Music::Song::columnNames();
	if ($song) {
		$::d_info && Slim::Utils::Misc::msg("Merging entry for $url\n");
		$attributeHash = _checkAttributes($attributeHash);
		while (my ($key, $val) = each %$attributeHash) {
			if (defined $val && exists $songColumns->{$key}) {
				$song->set(lc $key => $val);
			}
		}
		$self->updateSong($song, $commit);
	}
	else {
		my $columnValueHash = { url => $url };
		while (my ($key, $val) = each %$attributeHash) {
			if (defined $val && exists $songColumns->{$key}) {
				$columnValueHash->{$key} = $val;
			}
		}
		$song = $self->newSong($url, $columnValueHash);
	}

	if ($attributeHash->{CT}) {
		$self->{contentTypeCache}->{$url} = $attributeHash->{CT};
	}

	return $song;
}

# Delete a song from the database.
sub deleteSong {
	my $self = shift;
	my $url = shift;
	my $commit = shift;

	if ($url) {
		delete $self->{validityCache}->{$url};
		my $song = Slim::Music::Song->retrieve($url);
		if ($self->_includeInSongCount($song)) {
			$self->{songCount}--;
			my $time = $song->secs;
			if ($time) {
				$self->{totalTime} -= $time;
			}
		}
		$song->delete if $song;
		if ($commit) {
			$self->{dbh}->commit;
		}
		$::d_info && Slim::Utils::Misc::msg("cleared $url from database\n");
	}
}

sub setPlaylistSongs {
	my $self = shift;
	my $song = shift;
	my $list = shift;
	my $url = $song->url;

	my @tracks = Slim::Music::Track->tracksof($url);
	for my $track (@tracks) {
		$track->delete;
	}

	my $i = 0;
	for my $track (@$list) {
		Slim::Music::Track->create({
			playlist => $url,
			track => $track,
			position => $i});
		$i++;
	}
}

# Mark all song entries as being stale in preparation for scanning
# for validity.
sub markAllEntriesStale {
	my $self = shift;

	$self->{validityCache} = {};
}

# Mark a song entry as valid.
sub markEntryAsValid {
	my $self = shift;
	my $url = shift;

	$self->{validityCache}->{$url}->[VALID_INDEX] = 1;
}


# Clear all stale song entries.
sub clearStaleEntries {
	my $self = shift;

	$::d_info && Slim::Utils::Misc::msg("starting scan for expired items\n");
	my $validityCache = $self->{validityCache};
	foreach my $file (keys %$validityCache) {
		if (!$validityCache->{$file}->[VALID_INDEX]) {
			$self->deleteSong($file, 0);
		}
	}
	$self->forceSave;
}

# Wipe all data in the database
sub wipeAllData {
	my $self = shift;

	Slim::Music::DBI::wipeDB();
	$self->{validityCache} = {};
	$self->{totalTime} = 0;
	$self->{songCount} = 0;
	$self->{artworkCache} = {};
	$self->{coverCache} = {};
	$self->{thumbCache} = {};	
	$self->{contentTypeCache} = {};
	$self->{lastSongURL} = '';
	$self->{lastSong} = undef;
	$self->clearExternalPlaylists();
	$self->{zombieList} = {};
	$::d_info && Slim::Utils::Misc::msg("wipeAllData: Wiped info database\n");

	$self->{dbh} = Slim::Music::DBI::db_Main;
}

# Force a commit of the database
sub forceSave {
	my $self = shift;
	Slim::Music::DBI::setMetaInformation($self->{songCount}, 
										 $self->{totalTime});
	for my $url (keys %{$self->{zombieList}}) {
		if ($self->{zombieList}->{$url}) {
			$self->deleteSong($url);
		}
	}
	$self->{zombieList} = {};

	$self->{dbh}->commit;
}

sub addExternalPlaylist {
	my $self = shift;
	my $url = shift;
	my $playlists = $self->{externalPlaylists};

	return if grep $_ eq $url, @$playlists;
	push @$playlists, $url;
}

sub clearExternalPlaylists {
	my $self = shift;
	$self->{externalPlaylists} = [];
}

sub generateExternalPlaylists {
	my $self = shift;

	$self->clearExternalPlaylists();

	my @playlists = Slim::Utils::Text::sortIgnoringCase(map {$_->url} Slim::Music::Song->externalPlaylists);
	$self->{externalPlaylists} = \@playlists;
}

sub readTags {
	my $self = shift;
	my $file = shift;
	my ($track, $artistName, $albumName);
	my $filepath;
	my $type;
	my $attributesHash;

	if (!defined($file) || $file eq "") { return; };

	my $song = $self->_retrieveSong($file);

	# get the type without updating the cache
	$type = Slim::Music::Info::typeFromPath($file);
	if ($type eq 'unk' && $song && $song->content_type) {
		$type = $song->content_type;
	}

	$::d_info && Slim::Utils::Misc::msg("Updating cache for: " . $file . "\n");

	if (Slim::Music::Info::isSong($file, $type) ) {
		if (Slim::Music::Info::isHTTPURL($file)) {
			# if it's an HTTP URL, guess the title from the the last
			# part of the URL, and don't bother with the other parts
			if (!$song || !defined($song->title)) {
				$::d_info && Slim::Utils::Misc::msg("Info: no title found, calculating title from url for $file\n");
				$attributesHash->{'TITLE'} = 
				  Slim::Music::Info::plainTitle($file, $type);
			}
		} else {
			my $anchor;
			if (Slim::Music::Info::isFileURL($file)) {
				$filepath = Slim::Utils::Misc::pathFromFileURL($file);
				$anchor = Slim::Utils::Misc::anchorFromURL($file);
			} else {
				$filepath = $file;
			}

			# Extract tag and audio info per format
			if (exists $tagFunctions{$type}) {
				$attributesHash = &{$tagFunctions{$type}}($filepath, $anchor);
			}
			$::d_info && !defined($attributesHash) && Slim::Utils::Misc::msg("Info: no tags found for $filepath\n");

			if (defined($attributesHash->{'TRACKNUM'})) {
				$attributesHash->{'TRACKNUM'} = Slim::Music::Info::cleanTrackNumber($attributesHash->{'TRACKNUM'});
			}
			
			# Turn the tag SET into DISC and DISCC if it looks like # or #/#
			if ($attributesHash->{'SET'} and $attributesHash->{'SET'} =~ /(\d+)(?:\/(\d+))?/) {
				$attributesHash->{'DISC'} = $1;
				$attributesHash->{'DISCC'} = $2 if defined $2;
 			}

			Slim::Music::Info::addDiscNumberToAlbumTitle($attributesHash);
			
			if (!$attributesHash->{'TITLE'} && 
				(!$song || !defined($song->title))) {
				$::d_info && Slim::Utils::Misc::msg("Info: no title found, using plain title for $file\n");
				#$attributesHash->{'TITLE'} = Slim::Music::Info::plainTitle($file, $type);
				Slim::Music::Info::guessTags($file, $type, $attributesHash);
			}

			# fix the genre
			if (defined($attributesHash->{'GENRE'}) && $attributesHash->{'GENRE'} =~ /^\((\d+)\)$/) {
				# some programs (SoundJam) put their genres in as text digits surrounded by parens.
				# in this case, look it up in the table and use the real value...
				if (defined($MP3::Info::mp3_genres[$1])) {
					$attributesHash->{'GENRE'} = $MP3::Info::mp3_genres[$1];
				}
			}

			# cache the file size & date
			$attributesHash->{'FS'} = -s $filepath;					
			$attributesHash->{'AGE'} = (stat($filepath))[9];
			
			# rewrite the size, offset and duration if it's just a fragment
			if ($anchor && $anchor =~ /([\d\.]+)-([\d\.]+)/ && $attributesHash->{'SECS'}) {
				my $start = $1;
				my $end = $2;
				
				my $duration = $end - $start;
				my $byterate = $attributesHash->{'SIZE'} / $attributesHash->{'SECS'};
				my $header = $attributesHash->{'OFFSET'};
				my $startbytes = int($byterate * $start);
				my $endbytes = int($byterate * $end);
				
				$startbytes -= $startbytes % $attributesHash->{'BLOCKALIGN'} if $attributesHash->{'BLOCKALIGN'};
				$endbytes -= $endbytes % $attributesHash->{'BLOCKALIGN'} if $attributesHash->{'BLOCKALIGN'};
				
				$attributesHash->{'OFFSET'} = $header + $startbytes;
				$attributesHash->{'SIZE'} = $endbytes - $startbytes;
				$attributesHash->{'SECS'} = $duration;
				
				$::d_info && Slim::Utils::Misc::msg("readTags: calculating duration for anchor: $duration\n");
				$::d_info && Slim::Utils::Misc::msg("readTags: calculating header $header, startbytes $startbytes and endbytes $endbytes\n");
			}
			
			# cache the content type
			$attributesHash->{'CT'} = $type;
			
			if (!Slim::Music::iTunes::useiTunesLibrary()) {
				# Check for Cover Artwork, only if not already present.
				if (exists $attributesHash->{'COVER'} || exists $attributesHash->{'THUMB'}) {
					$::d_artwork && Slim::Utils::Misc::msg("already checked artwork for $file\n");
				} elsif (Slim::Utils::Prefs::get('lookForArtwork')) {
					my $album = $attributesHash->{'ALBUM'};
					$attributesHash->{'TAG'} = 1;

					# cache the content type
					$attributesHash->{'CT'} = $type;
					# update the cache so we can use readCoverArt without recursion.
					$self->updateSongAttributes($file, $attributesHash);

					$attributesHash = {};

					# Look for Cover Art and cache location
					my ($body,$contenttype,$path);
					if (defined $attributesHash->{'PIC'}) {
						($body,$contenttype,$path) = Slim::Music::Info::readCoverArtTags($file, 'cover');
					}
					if (defined $body) {
						$attributesHash->{'COVER'} = 1;
						$attributesHash->{'THUMB'} = 1;
						if ($album && !exists $self->{artworkCache}->{$album}) {
							$::d_artwork && Slim::Utils::Misc::msg("ID3 Artwork cache entry for $album: $filepath\n");
							$self->setAlbumArtwork($album, $filepath);
						}
					} else {
						($body,$contenttype,$path) = Slim::Music::Info::readCoverArtFiles($file, 'cover');
						if (defined $body) {
							$attributesHash->{'COVER'} = $path;
						}
						# look for Thumbnail Art and cache location
						($body,$contenttype,$path) = Slim::Music::Info::readCoverArtFiles($file, 'thumb');
						if (defined $body) {
							$attributesHash->{'THUMB'} = $path;
							if ($album && !exists $self->{artworkCache}->{$album}) {
								$::d_artwork && Slim::Utils::Misc::msg("Artwork cache entry for $album: $filepath\n");
								$self->setAlbumArtwork($album, $filepath);
							}
						}
					}
				}
			}
		} 
	} else {
		if (!defined($song) || !defined($song->title)) {
			my $title = Slim::Music::Info::plainTitle($file, $type);
			$attributesHash->{'TITLE'} = $title;
		}
	}
	
	if (!defined($attributesHash->{'CT'})) {
		$attributesHash->{'CT'} = $type;
	}
	
			
	# note that we've read in the tags.
	$attributesHash->{'TAG'} = 1;
	
	return $self->updateSongAttributes($file, $attributesHash);
}

sub setAlbumArtwork {
	my $self = shift;
	my $album = shift;
	my $filepath = shift;
	
	if (! Slim::Utils::Prefs::get('lookForArtwork')) { return undef};

	if (!exists $self->{artworkCache}->{$album}) { # only cache albums once each
		if (Slim::Music::Info::isFileURL($filepath)) {
			$filepath = Slim::Utils::Misc::pathFromFileURL($filepath);
		}
		$::d_artwork && Slim::Utils::Misc::msg("Updating $album artwork cache: $filepath\n");
		$self->{artworkCache}->{$album} = $filepath;
		my @objs = Slim::Music::Album->search(title => $album);
		if (scalar(@objs)) {
			$objs[0]->artwork_path($filepath);
			$objs[0]->update;
		}
	}
}

#
# LocalDataSource private methods:
#

sub _retrieveSong {
	my $self = shift;
	my $url = shift;

	return undef if $self->{zombieList}->{$url};

	my $song;
	if ($url eq $self->{lastSongURL}) {
		$song = $self->{lastSong};
	}
	else {
		$song = Slim::Music::Song->retrieve($url);
	}
	
	if (defined($song)) {
		$self->{lastSongURL} = $url;
		$self->{lastSong} = $song;
	}

	return $song;
}

sub _commitDBTimer {
	my $self = shift;
	$self->forceSave();
	Slim::Utils::Timers::setTimer($self, Time::HiRes::time() + DB_SAVE_INTERVAL, \&_commitDBTimer);
}

sub _hasChanged {
	my $self = shift;
	my $song = shift;
	my $file = $song->url;

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

		# Check filesize and timestamp to decide if we use the cached data.
		my $fsdef   = (defined $song->filesize);
		my $fscheck = 0;

		if ($fsdef) {
			$fscheck = (-s _ == $song->filesize);
		}

		# Now the AGE
		my $agedef   = (defined $song->timestamp);
		my $agecheck = 0;

		if ($agedef) {
			$agecheck = ((stat(_))[9] == $song->timestamp);
		}
			
		return 0 if  $fsdef && $fscheck && $agedef && $agecheck;
		return 0 if  $fsdef && $fscheck && !$agedef;
		return 0 if !$fsdef && $agedef  && $agecheck;
		
		$::d_info && Slim::Utils::Misc::msg("deleting $file from cache as it has changed\n");
	}
	else {
		$::d_info && Slim::Utils::Misc::msg("deleting $file from cache as it no longer exists\n");
	}

	$self->{zombieList}->{$file} = 1;

	return 1;
}

sub _includeInSongCount {
	my $self = shift;
	my $song = shift;
	my $url = $song->url;

	return 1 if (Slim::Music::Info::isSong($url, $song->content_type) && 
				 !Slim::Music::Info::isHTTPURL($url) && 
				 (-e (Slim::Utils::Misc::pathFromFileURL($url))));

	return 0;
}

sub _checkAttributes {
 	my $attributeHash = shift;

	if (my $genre = $attributeHash->{GENRE}) {
		my $genreObj = Slim::Music::Genre->find_or_create({ 
			NAME => $genre,
		});
		$attributeHash->{GENRE_ID} = $genreObj;
	}
	
	if (my $artist = $attributeHash->{ARTIST}) {
		my $sortable_name = $attributeHash->{ARTISTSORT} || 
		  Slim::Utils::Text::ignoreCaseArticles($artist);
		my $artistObj = Slim::Music::Artist->find_or_create({ 
			NAME => $artist,
			SORTABLE_NAME => $sortable_name,
		});
		$attributeHash->{ARTISTSORT} = $sortable_name;
		$attributeHash->{ARTIST_ID} = $artistObj;
	}
	
	if (my $album = $attributeHash->{ALBUM}) {
		my $sortable_title = $attributeHash->{ALBUMSORT} || 
		  Slim::Utils::Text::ignoreCaseArticles($album);
		my $albumObj = Slim::Music::Album->find_or_create({ 
			TITLE => $album,
			SORTABLE_TITLE => $sortable_title,
		});
		$attributeHash->{ALBUMSORT} = $sortable_title;
		$attributeHash->{ALBUM_ID} = $albumObj;
	}
	
	return $attributeHash;
}

sub _updateSongValidity {
	my $self = shift;
	my $url = shift;

	$self->{validityCache}->{$url}->[0] = 1;
	if (Slim::Music::Info::isFileURL($url)) {
		$self->{validityCache}->{$url}->[TTL_INDEX] = 
			(time() + DB_CACHE_LIFETIME + int(rand(DB_CACHE_LIFETIME)));
	} else {
		$self->{validityCache}->{$url}->[TTL_INDEX] = 0;
	}
}


sub _updateCoverArt {
	my $self = shift;
	my $fullpath = shift;
	my $type = shift || 'cover';
	my $body;	
	my $contenttype;
	my $path;

	# Check if we've already attempted to get artwork this session
	if (($type eq 'cover') && defined($self->{coverCache}->{$fullpath})) {
		return;
	}
	elsif (($type eq 'thumb') && defined($self->{thumbCache}->{$fullpath})) {
		return;
	}
			
	($body, $contenttype, $path) = Slim::Music::Info::readCoverArt($fullpath, $type);

 	my $info;
 	
 	if (defined($body)) {
 		if ($type eq 'cover') {
 			$info->{'COVER'} = $path;
 			$info->{'COVERTYPE'} = $contenttype;
			$self->{coverCache}->{$fullpath} = $path;
 		} elsif ($type eq 'thumb') {
 			$info->{'THUMB'} = $path;
 			$info->{'THUMBTYPE'} = $contenttype;
			$self->{thumbCache}->{$fullpath} = $path;
 		}
 		$::d_artwork && Slim::Utils::Misc::msg("$type caching $path for $fullpath\n");
		$self->updateSongAttributes($fullpath, $info);
 	} else {
		if ($type eq 'cover') {
			$self->{coverCache}->{$fullpath} = 0;
 		} elsif ($type eq 'thumb') {
			$self->{thumbCache}->{$fullpath} = 0;
 		}
 	}
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
