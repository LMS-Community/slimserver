package Slim::DataStores::DBI::DBIStore;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use DBI;
use MP3::Info;
use Tie::Cache::LRU::Expires;

use Slim::DataStores::DBI::DataModel;

use Slim::DataStores::DBI::Album;
use Slim::DataStores::DBI::Contributor;
use Slim::DataStores::DBI::ContributorTrack;
use Slim::DataStores::DBI::Genre;
use Slim::DataStores::DBI::GenreTrack;

use Slim::Formats::Movie;
use Slim::Formats::AIFF;
use Slim::Formats::FLAC;
use Slim::Formats::MP3;
use Slim::Formats::APE;
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
our %tagFunctions = (
	'mp3' => \&Slim::Formats::MP3::getTag,
	'mp2' => \&Slim::Formats::MP3::getTag,
	'ogg' => \&Slim::Formats::Ogg::getTag,
	'flc' => \&Slim::Formats::FLAC::getTag,
	'wav' => \&Slim::Formats::Wav::getTag,
	'aif' => \&Slim::Formats::AIFF::getTag,
	'wma' => \&Slim::Formats::WMA::getTag,
	'mov' => \&Slim::Formats::Movie::getTag,
	'shn' => \&Slim::Formats::Shorten::getTag,
	'mpc' => \&Slim::Formats::Musepack::getTag,
	'ape' => \&Slim::Formats::APE::getTag,
);

# Only look these up once.
our ($_unknownArtistID, $_unknownGenreID);

# Keep the last 5 find results set in memory and expire them after 60 seconds
tie our %lastFind, 'Tie::Cache::LRU::Expires', EXPIRES => 60, ENTRIES => 5;

#
# Readable DataStore interface methods:
#
sub new {
	my $class = shift;

	my $self = {
		# Handle to the DBI database we're going to use.
		dbh => Slim::DataStores::DBI::DataModel->db_Main(),
		# Values persisted in metainformation table
		trackCount => 0,
		totalTime => 0,
		# Non-persistent hash to maintain the VALID and TTL values for
		# track entries.
		validityCache => {},
		# Non-persistent cache to make sure we don't set album artwork
		# too many times.
		artworkCache => {},
		# Non-persistent caches to store cover and thumb properties
		coverCache => {},
		thumbCache => {},
		# Optimization to cache content type for track entries rather than
		# look them up everytime.
		contentTypeCache => {},
		# Optimization to cache last track accessed rather than retrieve it
		# again. 
		lastTrackURL => '',
		lastTrack => undef,
		# Selected list of external (for now iTunes and Moodlogic)
		# playlists.
		externalPlaylists => [],
		# Tracks that are out of date and should be deleted the next time
		# we get around to it.
		zombieList => {},
	};

	bless $self, $class;

	Slim::DataStores::DBI::Track->setLoader($self);
	
	($self->{'trackCount'}, $self->{'totalTime'}) = Slim::DataStores::DBI::DataModel->getMetaInformation();
	$self->generateExternalPlaylists();
	
	$self->_commitDBTimer();

	return $self;
}

sub contentType {
	my $self = shift;
	my $url = shift;
	my $create = shift;

	my $ct = $self->{'contentTypeCache'}->{$url};

	if (defined($ct)) {
		return wantarray ? ($ct, $self->_retrieveTrack($url)) : $ct;
	}

	my $track = $self->objectForUrl($url, $create);

	if (defined($track)) {
		$ct = $track->content_type();
	} else {
		$ct = Slim::Music::Info::typeFromPath($url);
	}

	$self->{'contentTypeCache'}->{$url} = $ct;

	return wantarray ? ($ct, $track) : $ct;
}

sub objectForUrl {
	my $self   = shift;
	my $url    = shift;
	my $create = shift;

	if (!defined($url)) {
		Slim::Utils::Misc::msg("Null track request!\n"); 
		Slim::Utils::Misc::bt();
		return undef;
	}
	
	my $track = $self->_retrieveTrack($url);

	if (defined $track && !$create) {
		$track = $self->_checkValidity($track);
	}

	if (!defined $track && $create) {

		# get the type without updating the cache
		my $type = Slim::Music::Info::typeFromPath($url);

		if (Slim::Music::Info::isSong($url, $type) ||
		    Slim::Music::Info::isList($url, $type) ||
		    Slim::Music::Info::isPlaylist($url, $type)) {

			$track = $self->newTrack($url, { 'url' => $url });
		}
	}

	return $track;
}

sub objectForId {
	my $self  = shift;
	my $field = shift;
	my $id    = shift;

	if ($field eq 'track') {

		my $track = Slim::DataStores::DBI::Track->retrieve($id) || return;

		return $self->_checkValidity($track);

	} elsif ($field eq 'genre') {

		return Slim::DataStores::DBI::Genre->retrieve($id);

	} elsif ($field eq 'album') {

		return Slim::DataStores::DBI::Album->retrieve($id);

	} elsif ($field eq 'contributor') {

		return Slim::DataStores::DBI::Contributor->retrieve($id);
	}
}

sub find {
	my $self   = shift;
	my $field  = shift;
	my $findCriteria = shift;
	my $sortBy = shift;
	my $limit  = shift;
	my $offset = shift;
	my $count  = shift;

	# Try and keep the last result set in memory - so if the user is
	# paging through, we don't keep hitting the database.
	#
	# Can't easily use $limit/offset for the page bars, because they
	# require knowing the entire result set.
	my @values = ();

	for my $value (values %$findCriteria) {

		if (ref $value eq 'ARRAY') {

			push @values, join(':', map { (ref $_ eq 'ARRAY' ? @{$_} : $_) } @{$value});

		} elsif (ref $value eq 'HASH') {

			push @values, join(':', map { $_, (ref $value->{$_} eq 'ARRAY' ? @{$value->{$_}} : $value->{$_}) } keys %$value);

		} else {
			push @values, $value;
		}
	}

	my $findKey = join(':', 
		$field,
		(keys %$findCriteria),
		(join(':', @values)),
		($sortBy || ''),
		($limit  || ''),
		($offset || ''),
		($count  || ''),
	);

	$::d_sql && Slim::Utils::Misc::msg("Generated findKey: [$findKey]\n");

	if (!defined $lastFind{$findKey}) {

		$lastFind{$findKey} = Slim::DataStores::DBI::DataModel->find($field, $findCriteria, $sortBy, $limit, $offset, $count);

	} else {

		$::d_sql && Slim::Utils::Misc::msg("Used previous results for findKey: [$findKey]\n");
	}

	my $items = $lastFind{$findKey};

	if (!$count && defined($items) && $field eq 'track') {
		return [ grep $self->_includeInTrackCount($_), @$items ];
	}

	return $items;
}

sub count {
	my $self = shift;
	my $field = shift;
	my $findCriteria = shift || {};

	# Optimize the all case
	if (scalar(keys %$findCriteria) == 0) {

		if ($field eq 'track') {

			return $self->{'trackCount'};

		} elsif ($field eq 'genre') {

			return Slim::DataStores::DBI::Genre->count_all();

		} elsif ($field eq 'album') {

			return Slim::DataStores::DBI::Album->count_all();

		} elsif ($field eq 'contributor') {

			return Slim::DataStores::DBI::Contributor->count_all();
		}
	}

	# XXX Brute force implementation. For now, retrieve from the database.
	# Last option to find() is $count - don't instansiate objects
	return $self->find($field, $findCriteria, undef, undef, undef, 1);
}

sub search {
	my $self    = shift;
	my $field   = shift;
	my $pattern = shift;
	my $sortby  = shift;

	my $contributorFields = Slim::DataStores::DBI::Contributor->contributorFields();

	if ($field eq 'track') {

		my $items = Slim::DataStores::DBI::Track->searchTitle($pattern);

		if (defined($items)) {
			return [ grep $self->_includeInTrackCount($_), @$items ];
		}

	} elsif ($field eq 'genre') {

		return Slim::DataStores::DBI::Genre->searchName($pattern);

	} elsif (grep { $_ eq $field } @$contributorFields) {

		return Slim::DataStores::DBI::Contributor->searchName($pattern, $field);

	} elsif ($field eq 'album') {

		return Slim::DataStores::DBI::Album->searchTitle($pattern);
	}

	return Slim::DataStores::DBI::Track->searchColumn($pattern, $field);
}

# XXX - dsully - this isn't quite used yet, and may not be the right thing to
# do. I think it's semi-redundant with some code in Buttons/BrowseID3 - which
# should probaably be moved to here anyways.
sub searchWithCriteria {
	my $class	 = shift;
	my $findCriteria = shift;

	# First turn Artist 'ACDC' => id 10, etc.
	while (my ($key, $value) = each %$findCriteria) {

		if (defined $value && scalar @$value && defined $value->[0] && $value->[0] ne '*') {

			# normalize the values
			for (my $i = 0; $i < scalar(@$value); $i++) {
				$value->[$i] = Slim::Utils::Text::ignoreCaseArticles($value->[$i]);
			}

			my $results = $class->search($key, $value);

			return () unless scalar @$results;

			$findCriteria->{$key} = $results;
		}
	}
}

sub albumsWithArtwork {
	my $self = shift;
	
	return [ Slim::DataStores::DBI::Album->hasArtwork() ];
}

sub totalTime {
	my $self = shift;

	return $self->{'totalTime'};
}

sub externalPlaylists {
	my $self = shift;

	return $self->{'externalPlaylists'};
}

#
# Writeable DataStore interface methods:
#

# Update the track object in the database. The assumption is that
# attribute setter methods may already have been invoked on the
# object.
sub updateTrack {
	my $self   = shift;
	my $track  = shift;
	my $commit = shift;

	$track->update();
	$self->_updateTrackValidity($track);

	$self->{'dbh'}->commit() if $commit;
}

# Create a new track with the given attributes
sub newTrack {
	my $self = shift;
	my $url = shift || return;
 	my $attributeHash = shift;
	my $commit = shift;
	my $deferredAttributes;
	
	$::d_info && Slim::Utils::Misc::msg("New track for $url\n");

	($attributeHash, $deferredAttributes) = _preCheckAttributes($attributeHash, 1);
	
	my $track = Slim::DataStores::DBI::Track->create($attributeHash) || return undef;

	_postCheckAttributes($track, $deferredAttributes, 1);

	$self->{'lastTrackURL'} = $url;
	$self->{'lastTrack'}    = $track;

	if ($self->_includeInTrackCount($track)) { 

		my $time = $track->getCached('secs');

		if ($time) {
			$self->{'totalTime'} += $time;
		}

		$self->{'trackCount'}++;
	}

	$self->_updateTrackValidity($track);

	$self->{'dbh'}->commit() if $commit;

	return $track;
}

# Update the attributes of a track or create one if one doesn't already exist.
sub updateOrCreate {
	my $self = shift;
	my $urlOrObj = shift;
	my $attributeHash = shift;
	my $commit = shift;

	my $track = ref $urlOrObj ? $urlOrObj : undef;
	my $url   = ref $urlOrObj ? $track->url : $urlOrObj;

	if (!defined($url)) {
		Slim::Utils::Misc::msg("No URL specified for updateOrCreate\n");
		Slim::Utils::Misc::msg(%{$attributeHash});
		Slim::Utils::Misc::bt();
		return;
	}
	
	if (defined($track)) {
		delete $self->{'zombieList'}->{$track->id};
	} else {
		$track = $self->_retrieveTrack($url);
	}

	my $trackAttrs = Slim::DataStores::DBI::Track::attributes();

	if (defined($track)) {

		$::d_info && Slim::Utils::Misc::msg("Merging entry for $url\n");

		my $deferredAttributes;
		($attributeHash, $deferredAttributes) = _preCheckAttributes($attributeHash, 0);

		while (my ($key, $val) = each %$attributeHash) {
			if (defined $val && exists $trackAttrs->{lc $key}) {
				$track->set(lc $key => $val);
			}
		}

		_postCheckAttributes($track, $deferredAttributes, 0);
		$self->updateTrack($track, $commit);

	} else {

		my $columnValueHash = { url => $url };

		while (my ($key, $val) = each %$attributeHash) {

			if (defined $val && exists $trackAttrs->{lc $key}) {
				$columnValueHash->{lc $key} = $val;
			}
		}

		$track = $self->newTrack($url, $columnValueHash);
	}

	if ($attributeHash->{'CT'}) {
		$self->{'contentTypeCache'}->{$url} = $attributeHash->{'CT'};
	}

	return $track;
}

# Delete a track from the database.
sub delete {
	my $self = shift;
	my $urlOrObj = shift;
	my $commit = shift;

	my $track = ref $urlOrObj ? $urlOrObj : undef;
	my $url   = ref $urlOrObj ? $track->url : $urlOrObj;

	if (!defined($track)) {
		$track = $self->_retrieveTrack($url);		
	}

	if (defined($track)) {

		delete $self->{'validityCache'}->{$url};

		if ($self->_includeInTrackCount($track)) {

			$self->{'trackCount'}--;

			my $time = $track->getCached('secs');

			if ($time) {
				$self->{'totalTime'} -= $time;
			}
		}

		$track->delete();
		$self->{'dbh'}->commit() if $commit;

		$::d_info && Slim::Utils::Misc::msg("cleared $url from database\n");
	}
}

# Mark all track entries as being stale in preparation for scanning for validity.
sub markAllEntriesStale {
	my $self = shift;

	$self->{'validityCache'} = {};

	%lastFind = ();
}

# Mark a track entry as valid.
sub markEntryAsValid {
	my $self = shift;
	my $url = shift;

	$self->{'validityCache'}->{$url}->[VALID_INDEX] = 1;
}

# Clear all stale track entries.
sub clearStaleEntries {
	my $self = shift;

	$::d_info && Slim::Utils::Misc::msg("starting scan for expired items\n");

	my $validityCache = $self->{'validityCache'};

	for my $url (keys %$validityCache) {

		if (!$validityCache->{$url}->[VALID_INDEX]) {
			$self->delete($url, 0);
		}
	}

	# Cleanup any stale entries in the database.
	# 
	# First walk the list of tracks, checking to see if the
	# file/directory/shortcut still exists on disk. If it doesn't, delete
	# it. This will cascade ::Track's has_many relationships, including
	# contributor_track, etc.
	#
	# After that, walk the Album, Contributor & Genre tables, to see if
	# each item has valid tracks still. If it doesn't, remove the object.
	$::d_info && Slim::Utils::Misc::msg("Starting db garbage collection..\n");

	my $tracks = Slim::DataStores::DBI::Track->retrieve_all();

	while (my $track = $tracks->next()) {
	
		unless (Slim::Music::Info::isFileURL($track->url())) {
			undef $track;
			next;
		}
		
		my $filepath = Slim::Utils::Misc::pathFromFileURL($track->url());

		# Don't use _hasChanged - because that does more than we want.
		if (!-e $filepath) {
			$self->delete($track, 0);
		}

		undef $track;
	}

	Slim::DataStores::DBI::Contributor->removeStaleDBEntries('contributorTracks');
	Slim::DataStores::DBI::Album->removeStaleDBEntries('tracks');
	Slim::DataStores::DBI::Genre->removeStaleDBEntries('genreTracks');

	$::d_info && Slim::Utils::Misc::msg("Ending db garbage collection.\n");

	$self->forceCommit();
}

# Wipe all data in the database
sub wipeAllData {
	my $self = shift;

	$self->forceCommit();

	Slim::DataStores::DBI::DataModel->wipeDB();

	$self->{'validityCache'}    = {};
	$self->{'totalTime'}        = 0;
	$self->{'trackCount'}       = 0;
	$self->{'artworkCache'}     = {};
	$self->{'coverCache'}       = {};
	$self->{'thumbCache'}       = {};	
	$self->{'contentTypeCache'} = {};
	$self->{'lastTrackURL'}     = '';
	$self->{'lastTrack'}        = undef;

	$self->clearExternalPlaylists();
	$self->{'zombieList'}       = {};

	$::d_info && Slim::Utils::Misc::msg("wipeAllData: Wiped info database\n");

	$self->{'dbh'} = Slim::DataStores::DBI::DataModel->db_Main();
}

# Force a commit of the database
sub forceCommit {
	my $self = shift;

	# Update the track count
	Slim::DataStores::DBI::DataModel->setMetaInformation($self->{'trackCount'}, $self->{'totalTime'});

	for my $id (keys %{$self->{'zombieList'}}) {

		next unless $self->{'zombieList'}->{$id};

		my $track = Slim::DataStores::DBI::Track->retrieve($id);

		delete $self->{'zombieList'}->{$id};

		$self->delete($track, 0) if $track;
	}

	$self->{'zombieList'} = {};

	$self->{'dbh'}->commit();

	# clear our find cache
	%lastFind = ();
}

sub addExternalPlaylist {
	my $self = shift;
	my $url  = shift;

	my $playlists = $self->{'externalPlaylists'};

	return if grep $_ eq $url, @$playlists;

	push @$playlists, $url;
}

sub clearExternalPlaylists {
	my $self = shift;

	$self->{'externalPlaylists'} = [];
}

sub generateExternalPlaylists {
	my $self = shift;

	$self->clearExternalPlaylists();

	$self->{'externalPlaylists'} = [ Slim::Utils::Text::sortIgnoringCase(
		map { $_->url() } Slim::DataStores::DBI::Track->externalPlaylists
	) ];
}

sub getExternalPlaylists {
	my $self = shift;

	return $self->{'externalPlaylists'};
}

sub readTags {
	my $self  = shift;
	my $track = shift;

	my $file  = $track->getCached('url');

	my ($filepath, $attributesHash);

	if (!defined($file) || $file eq '') {
		return;
	}

	# get the type without updating the cache
	my $type = Slim::Music::Info::typeFromPath($file);

	if ($type eq 'unk' && (my $ct = $track->getCached('ct'))) {
		$type = $ct;
	}

	$::d_info && Slim::Utils::Misc::msg("Updating cache for: " . $file . "\n");

	if (Slim::Music::Info::isSong($file, $type) ) {

		if (Slim::Music::Info::isRemoteURL($file)) {

			# if it's an HTTP URL, guess the title from the the last
			# part of the URL, and don't bother with the other parts
			if (!defined($track->getCached('title'))) {

				$::d_info && Slim::Utils::Misc::msg("Info: no title found, calculating title from url for $file\n");
				$attributesHash->{'TITLE'} = Slim::Music::Info::plainTitle($file, $type);
			}

		} else {

			my $anchor;
			if (Slim::Music::Info::isFileURL($file)) {
				$filepath = Slim::Utils::Misc::pathFromFileURL($file);
				$anchor   = Slim::Utils::Misc::anchorFromURL($file);
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
				!defined($track->getCached('title'))) {
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
			$attributesHash->{'FS'}  = -s $filepath;
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
			
			if (!Slim::Utils::Prefs::get('itunes')) {

				# Check for Cover Artwork, only if not already present.
				if (exists $attributesHash->{'COVER'} || exists $attributesHash->{'THUMB'}) {

					$::d_artwork && Slim::Utils::Misc::msg("already checked artwork for $file\n");

				} elsif (Slim::Utils::Prefs::get('lookForArtwork')) {
					my $album = $attributesHash->{'ALBUM'};
					$attributesHash->{'TAG'} = 1;

					# cache the content type
					$attributesHash->{'CT'} = $type unless defined $track->getCached('ct');
					# update the cache so we can use readCoverArt without recursion.
					$self->updateOrCreate($track, $attributesHash);

					# Look for Cover Art and cache location
					my ($body, $contenttype, $path);

					if (defined $attributesHash->{'PIC'} || defined $attributesHash->{'APIC'}) {
						($body,$contenttype,$path) = Slim::Music::Info::readCoverArtTags($file, $attributesHash);
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

		if (!defined($track->getCached('title'))) {
			$attributesHash->{'TITLE'} = Slim::Music::Info::plainTitle($file, $type);
		}
	}
	
	$attributesHash->{'CT'} = $type unless defined $track->getCached('ct');;
			
	# note that we've read in the tags.
	$attributesHash->{'TAG'} = 1;
	
	return $self->updateOrCreate($track, $attributesHash);
}

sub setAlbumArtwork {
	my $self = shift;
	my $album = shift;
	my $filepath = shift;
	
	if (!Slim::Utils::Prefs::get('lookForArtwork')) {
		return undef
	}

	# only cache albums once each
	if (!exists $self->{'artworkCache'}->{$album}) {

		if (Slim::Music::Info::isFileURL($filepath)) {
			$filepath = Slim::Utils::Misc::pathFromFileURL($filepath);
		}

		$::d_artwork && Slim::Utils::Misc::msg("Updating $album artwork cache: $filepath\n");

		$self->{'artworkCache'}->{$album} = $filepath;

		my ($album) = Slim::DataStores::DBI::Album->search(title => $album);

		if ($album) {
			$album->artwork_path($filepath);
			$album->update();
		}
	}
}

#
# Private methods:
#

sub _retrieveTrack {
	my $self = shift;
	my $url  = shift;

	return undef if $self->{'zombieList'}->{$url};

	my $track;

	if ($url eq $self->{'lastTrackURL'}) {

		$track = $self->{'lastTrack'};

	} else {

		# XXX - keep a url => id cache. so we can use the
		# live_object_index and not hit the db.
		($track) = Slim::DataStores::DBI::Track->search('url' => $url);
	}
	
	if (defined($track)) {
		$self->{'lastTrackURL'} = $url;
		$self->{'lastTrack'} = $track;
	}

	return $track;
}

sub _commitDBTimer {
	my $self = shift;

	$self->forceCommit();

	Slim::Utils::Timers::setTimer($self, Time::HiRes::time() + DB_SAVE_INTERVAL, \&_commitDBTimer);
}

sub _checkValidity {
	my $self  = shift;
	my $track = shift;

	my $id  = $track->getCached('id');
	my $url = $track->getCached('url');

	return undef if $self->{'zombieList'}->{$id};

	my $ttl = $self->{'validityCache'}->{$url}->[TTL_INDEX] || 0;

	if (Slim::Music::Info::isFileURL($url) && ($ttl < (time()))) {

		$::d_info && Slim::Utils::Misc::msg("CacheItem: Checking status of $url (TTL: $ttl).\n");

		if ($self->_hasChanged($track, $url, $id)) {

			$track = undef;

		} else {	

			$self->{'validityCache'}->{$url}->[TTL_INDEX] = (time()+ DB_CACHE_LIFETIME + int(rand(DB_CACHE_LIFETIME)));
		}
	}

	return $track;
}

sub _hasChanged {
	my $self  = shift;
	my $track = shift;
	my $url   = shift || $track->getCached('url');
	my $id    = shift || $track->getCached('id');

	# We return 0 if the file hasn't changed
	#    return 1 if the file has (cached entry is deleted by us)
	# As this is an internal cache function we don't sanity check our arguments...	

	my $filepath = Slim::Utils::Misc::pathFromFileURL($url);
		
	# Return if it's a directory - they expire themselves 
	# Todo - move directory expire code here?
	#return 0 if -d $filepath;
	return 0 if Slim::Music::Info::isDir($track);
	return 0 if Slim::Music::Info::isWinShortcut($track);

	# See if the file exists
	#
	# Reuse _, as we only need to stat() once.
	if (-e $filepath) {

		my $filesize  = $track->filesize();
		my $timestamp = $track->timestamp();

		# Check filesize and timestamp to decide if we use the cached data.
		my $fsdef   = (defined $filesize);
		my $fscheck = 0;

		if ($fsdef) {
			$fscheck = (-s _ == $filesize);
		}

		# Now the AGE
		my $agedef   = (defined $timestamp);
		my $agecheck = 0;

		if ($agedef) {
			$agecheck = ((stat(_))[9] == $timestamp);
		}
			
		return 0 if  $fsdef && $fscheck && $agedef && $agecheck;
		return 0 if  $fsdef && $fscheck && !$agedef;
		return 0 if !$fsdef && $agedef  && $agecheck;
		
		$::d_info && Slim::Utils::Misc::msg("deleting $url from cache as it has changed\n");

	} else {
		$::d_info && Slim::Utils::Misc::msg("deleting $url from cache as it no longer exists\n");
	}

	return $self->{'zombieList'}->{$id} = 1;
}

sub _includeInTrackCount {
	my $self  = shift;
	my $track = shift;
	my $url   = $track->getCached('url');

	return 1 if (Slim::Music::Info::isSong($url, $track->getCached('ct')) && 
				 !Slim::Music::Info::isRemoteURL($url) && 
				 (-e (Slim::Utils::Misc::pathFromFileURL($url))));

	return 0;
}

sub _preCheckAttributes {
 	my $attributeHash = shift;
 	my $create = shift;
	my $deferredAttributes = {};

	# Copy the incoming hash, so we don't modify it
	my $attributes = { %$attributeHash };

	if (my $genre = $attributes->{'GENRE'}) {
		$deferredAttributes->{'GENRE'} = $genre;
		delete $attributes->{'GENRE'};
	}
	
	if (my $artist = $attributes->{'ARTIST'}) {

		$deferredAttributes->{'ARTIST'} = $artist;

		# Normalize in ContributorTrack->add() the tag may need to be split. See bug #295
		$deferredAttributes->{'ARTISTSORT'} = $attributes->{'ARTISTSORT'};
		delete $attributes->{'ARTIST'};
	}

	delete $attributes->{'ARTISTSORT'};

	my $album = $attributes->{'ALBUM'};

	$album = string('NO_ALBUM') if (!$album && $create);

	if ($album) {

		my $sortable_title = $attributes->{'ALBUMSORT'} || $album;

		my $disc  = $attributes->{'DISC'};
		my $discc = $attributes->{'DISCC'};

		my $albumObj = Slim::DataStores::DBI::Album->find_or_create({ 
			title => $album,
		});

		# Always normalize the sort, as ALBUMSORT could come from a TSOA tag.
		$albumObj->titlesort(Slim::Utils::Text::ignoreCaseArticles($sortable_title)) if $sortable_title;
		$albumObj->disc($disc) if $disc;
		$albumObj->discc($discc) if $discc;
		$albumObj->update();

		$attributes->{'ALBUM'} = $albumObj;

	} else {
		delete $attributes->{'ALBUM'};
	}

	delete $attributes->{'ALBUMSORT'};
	delete $attributes->{'DISC'};
	delete $attributes->{'DISCC'};

	if ($attributes->{'TITLE'} && !$attributes->{'TITLESORT'}) {
		$attributes->{'TITLESORT'} = $attributes->{'TITLE'};
	}

	if ($attributes->{'TITLE'} && $attributes->{'TITLESORT'}) {
		# Always normalize the sort, as TITLESORT could come from a TSOT tag.
		$attributes->{'TITLESORT'} = Slim::Utils::Text::ignoreCaseArticles($attributes->{'TITLESORT'});
	}
	
	return ($attributes, $deferredAttributes);
}

sub _postCheckAttributes {
	my $track = shift;
	my $attributes = shift;
	my $create = shift;
	
	if (my $genre = $attributes->{'GENRE'}) {

		my @genres = Slim::DataStores::DBI::GenreTrack->add($genre, $track);

		if (!$create && defined $_unknownGenreID) {

			foreach my $gen (@genres) {
				$gen->delete() if ($gen->id() eq $_unknownGenreID);
			}
		}

	} elsif ($create && !defined $_unknownGenreID) {

		($_unknownGenreID) = Slim::DataStores::DBI::GenreTrack->add(string('NO_GENRE'), $track);
	}

	if (my $artist = $attributes->{'ARTIST'}) {

		my @contributors = Slim::DataStores::DBI::ContributorTrack->add(
			$artist, 
			Slim::DataStores::DBI::ContributorTrack::ROLE_ARTIST, 
			$track,
			$attributes->{'ARTISTSORT'}
		);

		if (!$create && defined $_unknownArtistID) {
			
			foreach my $contrib (@contributors) {
				$contrib->delete() if ($contrib->id() eq $_unknownArtistID);
			} 
		}

	} elsif ($create && !defined $_unknownArtistID) {

		($_unknownArtistID) = Slim::DataStores::DBI::ContributorTrack->add(
			string('NO_ARTIST'),
			Slim::DataStores::DBI::ContributorTrack::ROLE_ARTIST, 
			$track
		);
	}
}

sub _updateTrackValidity {
	my $self  = shift;
	my $track = shift;

	my $url   = $track->getCached('url');

	$self->{'validityCache'}->{$url}->[0] = 1;

	if (Slim::Music::Info::isFileURL($url)) {

		$self->{'validityCache'}->{$url}->[TTL_INDEX] = (time() + DB_CACHE_LIFETIME + int(rand(DB_CACHE_LIFETIME)));

	} else {

		$self->{'validityCache'}->{$url}->[TTL_INDEX] = 0;
	}
}


sub updateCoverArt {
	my $self     = shift;
	my $fullpath = shift;
	my $type     = shift || 'cover';

	# Check if we've already attempted to get artwork this session
	if (($type eq 'cover') && defined($self->{'coverCache'}->{$fullpath})) {

		return;

	} elsif (($type eq 'thumb') && defined($self->{'thumbCache'}->{$fullpath})) {

		return;
	}
			
	my ($body, $contenttype, $path) = Slim::Music::Info::readCoverArt($fullpath, $type);

 	if (defined($body)) {

		my $info = {};

 		if ($type eq 'cover') {

 			$info->{'COVER'} = $path;
 			$info->{'COVERTYPE'} = $contenttype;
			$self->{'coverCache'}->{$fullpath} = $path;

 		} elsif ($type eq 'thumb') {

 			$info->{'THUMB'} = $path;
 			$info->{'THUMBTYPE'} = $contenttype;
			$self->{'thumbCache'}->{$fullpath} = $path;
 		}

 		$::d_artwork && Slim::Utils::Misc::msg("$type caching $path for $fullpath\n");

		$self->updateOrCreate($fullpath, $info);

 	} else {

		if ($type eq 'cover') {
			$self->{'coverCache'}->{$fullpath} = 0;
 		} elsif ($type eq 'thumb') {
			$self->{'thumbCache'}->{$fullpath} = 0;
 		}
 	}
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
