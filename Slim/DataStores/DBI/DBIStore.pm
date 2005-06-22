package Slim::DataStores::DBI::DBIStore;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use DBI;
use File::Basename qw(dirname);
use MP3::Info;
use Tie::Cache::LRU::Expires;

use Slim::DataStores::DBI::DataModel;

use Slim::DataStores::DBI::Album;
use Slim::DataStores::DBI::Contributor;
use Slim::DataStores::DBI::ContributorTrack;
use Slim::DataStores::DBI::Genre;
use Slim::DataStores::DBI::GenreTrack;
use Slim::DataStores::DBI::LightWeightTrack;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Text;

# Save the persistant DB cache on an interval
use constant DB_SAVE_INTERVAL => 30;

# Entries in the database are assumed to be valid for approximately 5
# minutes before we check date/time stamps again
use constant DB_CACHE_LIFETIME => 5 * 60;

# cached value of commonAlbumTitles pref
our $common_albums;

# hold the current cleanup state
our $cleanupIds;
our $cleanupStage;

# Singleton objects for Unknowns
our ($_unknownArtist, $_unknownGenre, $_unknownAlbum);

# Keep the last 5 find results set in memory and expire them after 60 seconds
tie our %lastFind, 'Tie::Cache::LRU::Expires', EXPIRES => 60, ENTRIES => 5;

# Optimization to cache content type for track entries rather than look them up everytime.
tie our %contentTypeCache, 'Tie::Cache::LRU::Expires', EXPIRES => 300, ENTRIES => 128;

# Non-persistent hash to maintain the VALID and TTL values for track entries.
tie our %validityCache, 'Tie::Cache::LRU::Expires', EXPIRES => 300, ENTRIES => 128;

# Don't spike the CPU on cleanup.
our $staleCounter = 0;

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
		# Non-persistent cache to make sure we don't set album artwork
		# too many times.
		artworkCache => {},
		# Non-persistent caches to store cover and thumb properties
		coverCache => {},
		thumbCache => {},
		# Optimization to cache last track accessed rather than retrieve it again. 
		lastTrackURL => '',
		lastTrack => {},
		# Tracks that are out of date and should be deleted the next time
		# we get around to it.
		zombieList => {},
	};

	bless $self, $class;

	Slim::DataStores::DBI::Track->setLoader($self);
	
	($self->{'trackCount'}, $self->{'totalTime'}) = Slim::DataStores::DBI::DataModel->getMetaInformation();
	
	$self->_commitDBTimer();

	$common_albums = Slim::Utils::Prefs::get('commonAlbumTitles');

	Slim::Utils::Prefs::addPrefChangeHandler('commonAlbumTitles', \&commonAlbumTitlesChanged);

	return $self;
}

sub contentType {
	my $self = shift;
	my $url  = shift;

	my $ct = 'unk';

	# Can't get a content type on a undef url
	unless (defined $url) {

		return wantarray ? ($ct) : $ct;
	}

	$ct = $contentTypeCache{$url};

	if (defined($ct)) {
		return wantarray ? ($ct, $self->_retrieveTrack($url)) : $ct;
	}

	my $track = $self->objectForUrl($url);

	if (defined($track)) {
		$ct = $track->content_type();
	} else {
		$ct = Slim::Music::Info::typeFromPath($url);
	}

	$contentTypeCache{$url} = $ct;

	return wantarray ? ($ct, $track) : $ct;
}

sub objectForUrl {
	my $self   = shift;
	my $url    = shift;
	my $create = shift;
	my $readTag = shift;
	my $lightweight = shift;

	if (!defined($url)) {
		Slim::Utils::Misc::msg("Null track request!\n"); 
		Slim::Utils::Misc::bt();
		return undef;
	}

	my $track = $self->_retrieveTrack($url, $lightweight);

	if (defined $track && !$create && !$lightweight) {
		$track = $self->_checkValidity($track);
	}

	if (!defined $track && $create) {

		$track = $self->updateOrCreate({
			'url'      => $url,
			'readTags' => $readTag,
		});
	}

	return $track;
}

sub objectForId {
	my $self  = shift;
	my $field = shift;
	my $id    = shift;

	if ($field eq 'track' || $field eq 'playlist') {

		my $track = Slim::DataStores::DBI::Track->retrieve($id) || return;

	} elsif ($field eq 'lightweighttrack') {

		my $track = Slim::DataStores::DBI::LightWeightTrack->retrieve($id) || return;

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

		# refcnt-- if we can, to prevent leaks.
		if ($Class::DBI::Weaken_Is_Available && !$count) {

			Scalar::Util::weaken($lastFind{$findKey} = Slim::DataStores::DBI::DataModel->find(
				$field, $findCriteria, $sortBy, $limit, $offset, $count
			));

		} else {

			$lastFind{$findKey} = Slim::DataStores::DBI::DataModel->find($field, $findCriteria, $sortBy, $limit, $offset, $count);
		}

	} else {

		$::d_sql && Slim::Utils::Misc::msg("Used previous results for findKey: [$findKey]\n");
	}

	my $items = $lastFind{$findKey};

	if (!$count && defined($items) && 
		($field eq 'track' || $field eq 'lightweighttrack')) {

		$items = [ grep $self->_includeInTrackCount($_), @$items ];

		# Does the track still exist?
		if ($field ne 'lightweighttrack') {
			$items = [ grep $self->_checkValidity($_), @$items ];
		}
	}
	
	return $items if $count;
	return wantarray() ? @$items : $items;
}

sub count {
	my $self  = shift;
	my $field = shift;
	my $find  = shift || {};

	# make a copy, because we might modify it below.
	my %findCriteria = %$find;

	# The user may not want to include all the composers / conductors
	if ($field eq 'contributor' && !Slim::Utils::Prefs::get('composerInArtists')) {

		$findCriteria{'contributor.role'} = $Slim::DataStores::DBI::ContributorTrack::contributorToRoleMap{'ARTIST'};
	}

	# Optimize the all case
	if (scalar(keys %findCriteria) == 0) {

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
	return $self->find($field, \%findCriteria, undef, undef, undef, 1);
}

sub albumsWithArtwork {
	my $self = shift;
	
	return [ Slim::DataStores::DBI::Album->hasArtwork() ];
}

sub totalTime {
	my $self = shift;

	return $self->{'totalTime'};
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
	my $args = shift;

	#
	my $url           = $args->{'url'} || return;
 	my $attributeHash = $args->{'attributes'} || {};

	my $deferredAttributes;

	$::d_info && Slim::Utils::Misc::msg("New track for $url\n");

	# Default the tag reading behaviour if not explicitly set
	if (!defined $args->{readTags}) {
		$args->{readTags} = "default";
	}

	# Read the tag, and start populating the database.
	if ($args->{'readTags'}) {

		$::d_info && Slim::Utils::Misc::msg("readTag was ". $args->{'readTags'}  ." for $url\n");

		$attributeHash = { %{$self->readTags($url)}, %$attributeHash  };
	}

	($attributeHash, $deferredAttributes) = $self->_preCheckAttributes($url, $attributeHash, 1);

	# Creating the track only wants lower case values from valid columns.
	my $columnValueHash = {};

	my $trackAttrs = Slim::DataStores::DBI::Track::attributes();

	# Walk our list of valid attributes, and turn them into something ->create() can use.
	while (my ($key, $val) = each %$attributeHash) {

		if (defined $val && exists $trackAttrs->{lc $key}) {

			$::d_info && Slim::Utils::Misc::msg("Adding $url : $key to $val\n");

			$columnValueHash->{lc $key} = $val;
		}
	}

	# Tag and rename set URL to the Amazon image path. Smack that. We
	# don't use it anyways.
	$columnValueHash->{'url'} = $url;

	# Create the track - or bail. We should probably spew an error.
	my $track = eval { Slim::DataStores::DBI::Track->create($columnValueHash) };

	if ($@) {
		Slim::Utils::Misc::bt();
		Slim::Utils::Misc::msg("Couldn't create track for $url : $@\n");

		#require Data::Dumper;
		#print Data::Dumper::Dumper($columnValueHash);
		return;
	}

	# Now that we've created the track, and possibly an album object -
	# update genres, etc - that we need the track ID for.
	$self->_postCheckAttributes($track, $deferredAttributes, 1);

	$self->{'lastTrackURL'} = $url;
	$self->{'lastTrack'}->{dirname($url)} = $track;

	if ($self->_includeInTrackCount($track)) { 

		my $time = $columnValueHash->{'secs'};

		if ($time) {
			$self->{'totalTime'} += $time;
		}

		$self->{'trackCount'}++;
	}

	$self->_updateTrackValidity($track);

	$self->{'dbh'}->commit() if $args->{'commit'};

	return $track;
}

# Update the attributes of a track or create one if one doesn't already exist.
sub updateOrCreate {
	my $self = shift;
	my $args = shift;

	#
	my $urlOrObj      = $args->{'url'};
	my $attributeHash = $args->{'attributes'} || {};
	my $commit        = $args->{'commit'};
	my $readTags      = $args->{'readTags'};

	my $track = ref $urlOrObj ? $urlOrObj : undef;
	my $url   = ref $urlOrObj ? $track->url : $urlOrObj;

	if (!defined($url)) {
		Slim::Utils::Misc::msg("No URL specified for updateOrCreate\n");
		Slim::Utils::Misc::msg(%{$attributeHash});
		Slim::Utils::Misc::bt();
		return;
	}

	# Always remove from the zombie list, since we're about to update or
	# create this item.
	delete $self->{'zombieList'}->{$url};

	if (!defined($track)) {
		$track = $self->_retrieveTrack($url);
	}

	my $trackAttrs = Slim::DataStores::DBI::Track::attributes();

	if (defined($track)) {

		$::d_info && Slim::Utils::Misc::msg("Merging entry for $url\n");

		my $deferredAttributes;
		($attributeHash, $deferredAttributes) = $self->_preCheckAttributes($url, $attributeHash, 0);

		my %set = ();

		while (my ($key, $val) = each %$attributeHash) {

			if (defined $val && exists $trackAttrs->{lc $key}) {

				$::d_info && Slim::Utils::Misc::msg("Updating $url : $key to $val\n");

				$set{$key} = $val;
			}
		}

		# Just make one call.
		$track->set(%set);

		$self->_postCheckAttributes($track, $deferredAttributes, 0);

		$self->updateTrack($track, $commit);

	} else {

		$track = $self->newTrack({
			'url'        => $url,
			'attributes' => $attributeHash,
			'readTags'   => $readTags,
			'commit'     => $commit,
		});
	}

	if ($attributeHash->{'CT'}) {
		$contentTypeCache{$url} = $attributeHash->{'CT'};
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

		# XXX - make sure that playlisttracks are deleted on cascade 
		# otherwise call $track->setTracks() with an empty list

		delete $validityCache{$url};

		if ($self->_includeInTrackCount($track)) {

			$self->{'trackCount'}--;

			my $time = $track->get('secs');

			if ($time) {
				$self->{'totalTime'} -= $time;
			}
		}

		# Be sure to clear the track out of the cache as well.
		if ($url eq $self->{'lastTrackURL'}) {
			$self->{'lastTrackURL'} = '';
		}

		my $dirname = dirname($url);

		if (defined $self->{'lastTrack'}->{$dirname} && $self->{'lastTrack'}->{$dirname}->url() eq $url) {
			delete $self->{'lastTrack'}->{$dirname};
		}

		$track->delete();
		$self->{'dbh'}->commit() if $commit;

		$::d_info && Slim::Utils::Misc::msg("cleared $url from database\n");
	}
}

# Mark all track entries as being stale in preparation for scanning for validity.
sub markAllEntriesStale {
	my $self = shift;

	%validityCache    = ();
	%lastFind         = ();
	%contentTypeCache = ();

	$self->{'artworkCache'} = {};
}

# Mark a track entry as valid.
sub markEntryAsValid {
	my $self = shift;
	my $url = shift;

	$validityCache{$url} = time();
	delete $self->{'zombieList'}->{$url};
}

# Mark a track entry as invalid.
# Does the reverse of above.
sub markEntryAsInvalid {
	my $self = shift;
	my $url  = shift || return undef;

	if (exists $validityCache{$url}) {
		delete $validityCache{$url};
	}

	$self->{'zombieList'}->{$url} = 1;
}

sub cleanupStaleEntries {
	my $self = shift;

	# Setup a little state machine so that the db cleanup can be
	# scheduled appropriately - ie: one record per run.
	Slim::Utils::Scheduler::add_task(\&cleanupStaleTrackEntries, $self);
}

# Clear all stale track entries.
sub cleanupStaleTrackEntries {
	my $self = shift;

	# Sun Mar 20 22:29:03 PST 2005
	# XXX - dsully - a lot of this is commented out, as myself
	# and Vidur decided that lazy track cleanup was best for now. This
	# means that if a user selects (via browsedb) a list of tracks which
	# is now longer there, it will be run through _checkValidity, and
	# marked as invalid. We still want to do Artist/Album/Genre cleanup
	# however.
	#
	# At Some Point in the Future(tm), Class::DBI should be modified, so
	# that retrieve_all() is lazy, and only fetches a $sth->row when
	# $obj->next is called.

	unless ($cleanupIds) {

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

		$cleanupIds = Slim::DataStores::DBI::Track->retrieveAllOnlyIds();
	}

	# Only cleanup every 20th time through the scheduler.
	$staleCounter++;
	return 1 if $staleCounter % 20;

	# fetch one at a time to keep memory usage in check.
	my $item  = shift(@{$cleanupIds});
	my $track = Slim::DataStores::DBI::Track->retrieve($item->[0]) if defined $item;

	if (!defined $track && !defined $item && scalar @{$cleanupIds} == 0) {

		$::d_info && Slim::Utils::Misc::msg(
			"Finished with stale track cleanup. Adding tasks for Contributors, Albums & Genres.\n"
		);

		$cleanupIds = undef;

		# Proceed with Albums, Genres & Contributors
		$cleanupStage = 'contributors';
		$staleCounter = 0;

		# Setup a little state machine so that the db cleanup can be
		# scheduled appropriately - ie: one record per run.
		Slim::Utils::Scheduler::add_task(\&cleanupStaleTableEntries, $self);

		return 0;
	};

	my $url = $track->url;

	# return 1 to move onto the next track
	unless (Slim::Music::Info::isFileURL($url)) {
		return 1;
	}
	
	my $filepath = Slim::Utils::Misc::pathFromFileURL($url);

	# Don't use _hasChanged - because that does more than we want.
	if (!-r $filepath) {

		$::d_info && Slim::Utils::Misc::msg("Track: $filepath no longer exists. Removing.\n");

		$self->delete($track, 0);
	}

	$track = undef;

	return 1;
}

# Walk the Album, Contributor and Genre tables to see if we have any dangling
# entries, pointing to non-existant tracks.
sub cleanupStaleTableEntries {
	my $self = shift;

	$staleCounter++;
	return 1 if $staleCounter % 20;

	if ($cleanupStage eq 'contributors') {

		unless (Slim::DataStores::DBI::Contributor->removeStaleDBEntries('contributorTracks')) {
			$cleanupStage = 'albums';
		}

		return 1;
	}

	if ($cleanupStage eq 'albums') {

		unless (Slim::DataStores::DBI::Album->removeStaleDBEntries('tracks')) {
			$cleanupStage = 'genres';
		}

		return 1;
	}

	if ($cleanupStage eq 'genres') {

		Slim::DataStores::DBI::Genre->removeStaleDBEntries('genreTracks');
	}

	# We're done.
	$self->{'dbh'}->commit();

	$::d_info && Slim::Utils::Misc::msg("Finished with cleanupStaleTableEntries()\n");

	%lastFind = ();

	$staleCounter = 0;
	return 0;
}

# Wipe all data in the database
sub wipeAllData {
	my $self = shift;

	$self->forceCommit();

	# clear the references to these singletons
	$_unknownArtist = undef;
	$_unknownGenre  = undef;
	$_unknownAlbum  = undef;

	# nuke any caches we may have.
	%contentTypeCache = ();
	%validityCache    = ();
	%lastFind         = ();

	$self->{'totalTime'}    = 0;
	$self->{'trackCount'}   = 0;
	$self->{'artworkCache'} = {};
	$self->{'coverCache'}   = {};
	$self->{'thumbCache'}   = {};	
	$self->{'lastTrackURL'} = '';
	$self->{'lastTrack'}    = {};
	$self->{'zombieList'}   = {};

	Slim::DataStores::DBI::ContributorTrack->clearCache();
	Slim::DataStores::DBI::GenreTrack->clearCache();
	Slim::DataStores::DBI::DataModel->wipeDB();

	$::d_info && Slim::Utils::Misc::msg("wipeAllData: Wiped info database\n");

	$self->{'dbh'} = Slim::DataStores::DBI::DataModel->db_Main();
}

# Force a commit of the database
sub forceCommit {
	my $self = shift;

	# Update the track count
	Slim::DataStores::DBI::DataModel->setMetaInformation($self->{'trackCount'}, $self->{'totalTime'});

	for my $zombie (keys %{$self->{'zombieList'}}) {

		my ($track) = Slim::DataStores::DBI::Track->search('url' => $zombie);

		if ($track) {

			delete $self->{'zombieList'}->{$zombie};

			$self->delete($track, 0) if $track;
		}
	}

	$self->{'zombieList'} = {};
	$self->{'lastTrackURL'} = '';
	$self->{'lastTrack'} = {};

	$::d_info && Slim::Utils::Misc::msg("forceCommit: syncing to the database.\n");

	$self->{'dbh'}->commit();

	$Slim::DataStores::DBI::DataModel::dirtyCount = 0;

	# clear our find cache
	%lastFind = ();
}

sub clearExternalPlaylists {
	my $self = shift;
	my $url = shift;

	my $playLists = getExternalPlaylists();

	# We can specify a url prefix to only delete certain types of external
	# playlists - ie: only iTunes, or only MusicMagic.
	while (my $track = $playLists->next()) {

		$track->delete() if (defined $url ? $track->url() =~ /^$url/ : 1);
	}

	$self->forceCommit();
}

sub getExternalPlaylists {
	my $self = shift;

	return Slim::DataStores::DBI::Track->externalPlaylists();
}

sub getInternalPlaylists {
	my $self = shift;

	return Slim::DataStores::DBI::Track->internalPlaylists();
}

sub getPlaylistForClient {
	my $self   = shift;
	my $client = shift;

	return (Slim::DataStores::DBI::Track->search({
		'url' => sprintf('playlist://%s', $client->id())
	}))[0];
}

sub readTags {
	my $self  = shift;
	my $file  = shift;

	my ($filepath, $attributesHash, $anchor);

	if (!defined($file) || $file eq '') {
		return {};
	}

	# get the type without updating the cache
	my $type = Slim::Music::Info::typeFromPath($file);

	$::d_info && Slim::Utils::Misc::msg("reading tags for: $file\n");

	if (Slim::Music::Info::isFileURL($file)) {
		$filepath = Slim::Utils::Misc::pathFromFileURL($file);
		$anchor   = Slim::Utils::Misc::anchorFromURL($file);
	} else {
		$filepath = $file;
	}

	if (Slim::Music::Info::isSong($file, $type) && !Slim::Music::Info::isRemoteURL($file)) {

		# Extract tag and audio info per format
		if (exists $Slim::Music::Info::tagFunctions{$type}) {

			# Dynamically load the module in.
			if (!$Slim::Music::Info::tagFunctions{$type}->{'loaded'}) {
			
				Slim::Music::Info::loadTagFormatForType($type);
			}

			$attributesHash = eval { &{$Slim::Music::Info::tagFunctions{$type}->{'getTag'}}($filepath, $anchor) };
		}

		if ($@) {
			Slim::Utils::Misc::msg("The following error occurred: $@\n");
			Slim::Utils::Misc::bt();
		}

		$::d_info && !defined($attributesHash) && Slim::Utils::Misc::msg("Info: no tags found for $filepath\n");

		if (defined $attributesHash->{'TRACKNUM'}) {
			$attributesHash->{'TRACKNUM'} = Slim::Music::Info::cleanTrackNumber($attributesHash->{'TRACKNUM'});
		}
		
		# Turn the tag SET into DISC and DISCC if it looks like # or #/#
		if ($attributesHash->{'SET'} and $attributesHash->{'SET'} =~ /(\d+)(?:\/(\d+))?/) {
			$attributesHash->{'DISC'} = $1;
			$attributesHash->{'DISCC'} = $2 if defined $2;
		}

		if (!$attributesHash->{'TITLE'}) {

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
	}

	# Last resort
	if (!defined $attributesHash->{'TITLE'} || $attributesHash->{'TITLE'} =~ /^\s*$/) {

		$::d_info && Slim::Utils::Misc::msg("Info: no title found, calculating title from url for $file\n");

		$attributesHash->{'TITLE'} = Slim::Music::Info::plainTitle($file, $type);
	}

	if (-e $filepath) {
		# cache the file size & date
		($attributesHash->{'FS'}, $attributesHash->{'AGE'}) = (stat($filepath))[7,9];
	}

	# Only set if we couldn't read it from the file.
	$attributesHash->{'CT'} ||= $type;

	# note that we've read in the tags.
	$attributesHash->{'TAG'} = 1;

	return $attributesHash;
}

sub setAlbumArtwork {
	my $self  = shift;
	my $track = shift;
	
	if (!Slim::Utils::Prefs::get('lookForArtwork')) {
		return undef
	}

	my $album    = $track->album();
	my $albumId  = $album->id() if $album;
	my $filepath = $track->url();

	# only cache albums once each
	if ($album && !exists $self->{'artworkCache'}->{$albumId}) {

		if (Slim::Music::Info::isFileURL($filepath)) {
			$filepath = Slim::Utils::Misc::pathFromFileURL($filepath);
		}

		$::d_artwork && Slim::Utils::Misc::msg("Updating $album artwork cache: $filepath\n");

		$self->{'artworkCache'}->{$albumId} = 1;

		$album->artwork_path($track->id);
		$album->update();
	}
}

#
# Private methods:
#

sub _retrieveTrack {
	my $self = shift;
	my $url  = shift;
	my $lightweight = shift;

	return undef if $self->{'zombieList'}->{$url};

	my $track;

	# Keep the last track per dirname.
	my $dirname = dirname($url);

	if ($url eq $self->{'lastTrackURL'}) {

		$track = $self->{'lastTrack'}->{$dirname};

	} elsif ($lightweight) {

		($track) = Slim::DataStores::DBI::LightWeightTrack->search('url' => $url);

	} else {

		# XXX - keep a url => id cache. so we can use the
		# live_object_index and not hit the db.
		($track) = Slim::DataStores::DBI::Track->search('url' => $url);
	}
	
	if (defined($track) && !$lightweight) {
		$self->{'lastTrackURL'} = $url;
		$self->{'lastTrack'}->{$dirname} = $track;
	}

	return $track;
}

sub _commitDBTimer {
	my $self = shift;
	my $items = $Slim::DataStores::DBI::DataModel::dirtyCount;

	if ($items > 0) {
		$::d_info && Slim::Utils::Misc::msg("DBI: Periodic commit - $items dirty items\n");
		$self->forceCommit();
	} else {
		$::d_info && Slim::Utils::Misc::msg("DBI: Supressing periodic commit - no dirty items\n");
	}

	Slim::Utils::Timers::setTimer($self, Time::HiRes::time() + DB_SAVE_INTERVAL, \&_commitDBTimer);
}

sub _checkValidity {
	my $self  = shift;
	my $track = shift;

	my $id  = $track->get('id');
	my $url = $track->get('url');

	return undef if $self->{'zombieList'}->{$url};

	my $ttl = $validityCache{$url} || 0;

	if (Slim::Music::Info::isFileURL($url) && ($ttl < (time()))) {

		$::d_info && Slim::Utils::Misc::msg("CacheItem: Checking status of $url (TTL: $ttl).\n");

		if ($self->_hasChanged($track, $url, $id)) {

			$track = undef;

		} else {	

			$validityCache{$url} = (time()+ DB_CACHE_LIFETIME + int(rand(DB_CACHE_LIFETIME)));
		}
	}

	# If the track was deleted out from under us - say by the db garbage collection, don't return it.
	# This is mostly defensive, I've seen it, but I'm not sure how to
	# reproduce it. It's happened when testing with a customer's db, which
	# I don't have the tracks to, so _checkValidity may be bogus.
	if (defined $track && ref($track) && $track->isa('Class::DBI::Object::Has::Been::Deleted')) {

		Slim::Utils::Misc::msg("Track: [$id] - [$track] was deleted out from under us!\n");
		Slim::Utils::Misc::bt();

		$track = undef;
	}

	return $track;
}

sub _hasChanged {
	my $self  = shift;
	my $track = shift;
	my $url   = shift || $track->get('url');
	my $id    = shift || $track->get('id');

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

		$::d_info && Slim::Utils::Misc::msg("re-reading tags from $url as it has changed\n");
		my $attributeHash = $self->readTags($url);
		$self->updateOrCreate({
			 'url' => $track,
			 'attributes' => $attributeHash
		});
		
		return 0;

	} else {
		$::d_info && Slim::Utils::Misc::msg("deleting $url from cache as it no longer exists\n");
	}

	# Tell the DB to sync - if we're deleting something.
	$Slim::DataStores::DBI::DataModel::dirtyCount++;

	return $self->{'zombieList'}->{$url} = 1;
}

sub _includeInTrackCount {
	my $self  = shift;
	my $track = shift;
	my $url   = $track->get('url');

	return 0 if Slim::Music::Info::isRemoteURL($url);
	return 1 if Slim::Music::Info::isSong($track, $track->get('ct'));

	return 0;
}

sub _preCheckAttributes {
	my $self = shift;
	my $url = shift;
 	my $attributeHash = shift;
 	my $create = shift;
	my $deferredAttributes = {};

	# Copy the incoming hash, so we don't modify it
	my $attributes = { %$attributeHash };

	# We also need these in _postCheckAttributes, but they should be set during create()
	$deferredAttributes->{'COVER'}   = $attributes->{'COVER'};
	$deferredAttributes->{'THUMB'}   = $attributes->{'THUMB'};

	# Only pass this along if we're creating > 1 albums
	unless (Slim::Utils::Prefs::get('groupdiscs')) {
		$deferredAttributes->{'DISC'} = $attributes->{'DISC'};
	}

	if ($attributes->{'TITLE'} && !$attributes->{'TITLESORT'}) {
		$attributes->{'TITLESORT'} = $attributes->{'TITLE'};
	}

	if ($attributes->{'TITLE'} && $attributes->{'TITLESORT'}) {
		# Always normalize the sort, as TITLESORT could come from a TSOT tag.
		$attributes->{'TITLESORT'} = Slim::Utils::Text::ignoreCaseArticles($attributes->{'TITLESORT'});
	}

	# Normalize ARTISTSORT in ContributorTrack->add() the tag may need to be split. See bug #295
	#
	# Push these back until we have a Track object.
	for my $tag (qw(COMMENT BAND COMPOSER CONDUCTOR GENRE ARTIST ARTISTSORT PIC APIC ALBUM ALBUMSORT DISCC)) {

		next unless defined $attributes->{$tag};

		$deferredAttributes->{$tag} = delete $attributes->{$tag};
	}
	
	return ($attributes, $deferredAttributes);
}

sub _postCheckAttributes {
	my $self = shift;
	my $track = shift;
	my $attributes = shift;
	my $create = shift;

	# Don't bother with directories / lnks. This makes sure "No Artist",
	# etc don't show up if you don't have any.
	if (Slim::Music::Info::isDir($track) || Slim::Music::Info::isWinShortcut($track)) {
		return;
	}

	my ($trackId, $trackUrl) = $track->get(qw(id url));

	# We don't want to add "No ..." entries for remote URLs, or meta
	# tracks like iTunes playlists.
	my $isLocal = Slim::Music::Info::isSong($track) && !Slim::Music::Info::isRemoteURL($track);

	# Genre addition. If there's no genre for this track, and no 'No Genre' object, create one.
	my $genre = $attributes->{'GENRE'};

	if ($create && $isLocal && !$genre && !$_unknownGenre) {

		$_unknownGenre = Slim::DataStores::DBI::Genre->find_or_create({
			'name'     => string('NO_GENRE'),
			'namesort' => Slim::Utils::Text::ignoreCaseArticles(string('NO_GENRE')),
		});

		Slim::DataStores::DBI::GenreTrack->add($_unknownGenre, $track);

	} elsif ($create && $isLocal && !$genre) {

		Slim::DataStores::DBI::GenreTrack->add($_unknownGenre, $track);

	} elsif ($create && $isLocal && $genre) {

		Slim::DataStores::DBI::GenreTrack->add($genre, $track);
	}

	# Walk through the valid contributor roles, adding them to the
	# database for each track.
	my $foundContributor = 0;
	my @contributors     = ();

	for my $tag (qw(ARTIST BAND COMPOSER CONDUCTOR)) {

		my $contributor = $attributes->{$tag} || next;

		# Is ARTISTSORT/TSOP always right for non-artist
		# contributors? I think so. ID3 doesn't have
		# "BANDSORT" or similar at any rate.
		push @contributors, Slim::DataStores::DBI::ContributorTrack->add(
			$contributor, 
			$Slim::DataStores::DBI::ContributorTrack::contributorToRoleMap{$tag},
			$track,
			$tag eq 'ARTIST' ? $attributes->{'ARTISTSORT'} : undef,
		);

		$foundContributor = 1;
	}

	# Create a singleton for "No Artist"
	if ($create && $isLocal && !$foundContributor && !$_unknownArtist) {

		$_unknownArtist = Slim::DataStores::DBI::Contributor->find_or_create({
			'name'     => string('NO_ARTIST'),
			'namesort' => Slim::Utils::Text::ignoreCaseArticles(string('NO_ARTIST')),
		});

		Slim::DataStores::DBI::ContributorTrack->add(
			$_unknownArtist,
			$Slim::DataStores::DBI::ContributorTrack::contributorToRoleMap{'ARTIST'},
			$track
		);

		push @contributors, $_unknownArtist;

	} elsif ($create && $isLocal && !$foundContributor) {

		# Otherwise - reuse the singleton object, since this is the
		# second time through.
		Slim::DataStores::DBI::ContributorTrack->add(
			$_unknownArtist,
			$Slim::DataStores::DBI::ContributorTrack::contributorToRoleMap{'ARTIST'},
			$track
		);

		push @contributors, $_unknownArtist;
	}

	# Now handle Album creation
	my $album = $attributes->{'ALBUM'};
	my $disc  = $attributes->{'DISC'};
	my $discc = $attributes->{'DISCC'};
	my $albumObj;

	# Create a singleton for "No Album"
	# Album should probably have an add() method
	if ($create && $isLocal && !$album && !$_unknownAlbum) {

		$_unknownAlbum = Slim::DataStores::DBI::Album->find_or_create({
			'title'     => string('NO_ALBUM'),
			'titlesort' => Slim::Utils::Text::ignoreCaseArticles(string('NO_ALBUM')),
		});

		$track->album($_unknownAlbum);
		$albumObj = $_unknownAlbum;

	} elsif ($create && $isLocal && !$album) {

		$track->album($_unknownAlbum);
		$albumObj = $_unknownAlbum;

	} elsif ($create && $isLocal && $album) {

		my $sortable_title = Slim::Utils::Text::ignoreCaseArticles($attributes->{'ALBUMSORT'} || $album);


		# Used for keeping track of the album name.
		my $basename = dirname($trackUrl);

		# Go through some contortions to see if the album we're in
		# already exists. Because we keep contributors now, but an
		# album can have many contributors, check the last path and
		# album name, to see if we're actually the same.
		if (!$disc && $self->{'lastTrack'}->{$basename} && 
			$self->{'lastTrack'}->{$basename}->album() && 
			$self->{'lastTrack'}->{$basename}->album() eq $album
			) {

			$albumObj = $self->{'lastTrack'}->{$basename}->album();

		} else {

			my $search = {
				'titlesort' => $sortable_title,
			};

			# Add disc to the search criteria, so we get
			# the right object for multi-disc sets with
			# the same album name.
			$search->{'disc'} = $disc if $disc;

			# Check if the album name is one of the "common album names"
			# we've identified in prefs. If so, we require a match on
			# both album name and primary artist name.
			if ((grep $album =~ m/^$_$/i, @$common_albums) && 
				$contributors[0]) {

				$search->{'contributors'} = $contributors[0]->namesort;

				($albumObj) = Slim::DataStores::DBI::Album->search($search);

			} else {

				($albumObj) = Slim::DataStores::DBI::Album->search($search);
			}

			# Didn't match anything? It's a new album - create it.
			unless ($albumObj) {

				$albumObj = Slim::DataStores::DBI::Album->create({ 
					title => $album,
				});
			}
		}

		# Associate cover art with this album, and keep it cached.
		unless ($self->{'artworkCache'}->{$albumObj->id}) {

			my $artworkPath = $self->_findCoverArt($trackUrl, $albumObj, $attributes);

			if ($artworkPath) {

				$self->{'artworkCache'}->{$albumObj->id} = 1;

				$albumObj->artwork_path($trackId);
			}
		}

		if ($contributors[0]) {
			$albumObj->contributors($contributors[0]->namesort);
		}

		# Always normalize the sort, as ALBUMSORT could come from a TSOA tag.
		$albumObj->titlesort($sortable_title) if $sortable_title;

		$albumObj->disc($disc) if $disc;
		$albumObj->discc($discc) if $discc;
		$albumObj->update();

		$track->album($albumObj);
	}

	# Compute a compound sort key we'll use for queries that involve
	# multiple albums. Rather than requiring a multi-way join to get
	# all the individual sort keys from different tables, this is an
	# optimization that only requires the tracks table.
	$albumObj ||= $track->album();

	my $albumName = defined($albumObj) ? $albumObj->titlesort : '';
	my $primary_contributor = defined($contributors[0]) ? $contributors[0]->namesort :  defined($albumObj) ? $albumObj->contributors : '';

	# Save 2 get calls
	my ($titlesort, $tracknum) = $track->get(qw(titlesort tracknum));

	my @keys = ();

	push @keys, $primary_contributor || '';
	push @keys, $albumName || '';
	push @keys, $disc if defined($disc);
	push @keys, sprintf("%03d", $tracknum) if defined $tracknum;
	push @keys, $titlesort || '';

	$track->multialbumsortkey(join ' ', @keys);
	$track->update();

	# Add comments if we have them:
	if ($attributes->{'COMMENT'}) {

		Slim::DataStores::DBI::Comment->find_or_create({
			'track' => $trackId,
			'value' => $attributes->{'COMMENT'},
		});
	}

	# refcount--
	@contributors = ();
}

sub _findCoverArt {
	my ($self, $file, $album, $attributesHash) = @_;

	# Check for Cover Artwork, only if not already present.
	if ($attributesHash->{'COVER'} || $attributesHash->{'THUMB'}) {

		$::d_artwork && Slim::Utils::Misc::msg("already checked artwork for $file\n");

		return;
	}

	# Don't bother if the user doesn't care.
	return unless Slim::Utils::Prefs::get('lookForArtwork');

	my $filepath = $file;

	if (Slim::Music::Info::isFileURL($file)) {
		$filepath = Slim::Utils::Misc::pathFromFileURL($file);
	}

	# Look for Cover Art and cache location
	my ($body, $contentType, $path);

	if (defined $attributesHash->{'PIC'} || defined $attributesHash->{'APIC'}) {

		($body, $contentType, $path) = Slim::Music::Info::readCoverArtTags($file, $attributesHash);
	}

	if (defined $body) {

		$attributesHash->{'COVER'} = 1;
		$attributesHash->{'THUMB'} = 1;

		if ($album && !exists $self->{'artworkCache'}->{$album->id}) {

			$::d_artwork && Slim::Utils::Misc::msg("ID3 Artwork cache entry for $album: $filepath\n");

			return $filepath;
		}
	
	} else {

		($body, $contentType, $path) = Slim::Music::Info::readCoverArtFiles($file, 'cover');

		if (defined $body) {
			$attributesHash->{'COVER'} = $path;
		}

		# look for Thumbnail Art and cache location
		($body, $contentType, $path) = Slim::Music::Info::readCoverArtFiles($file, 'thumb');

		if (defined $body) {

			$attributesHash->{'THUMB'} = $path;

			if ($album && !exists $self->{'artworkCache'}->{$album->id}) {

				$::d_artwork && Slim::Utils::Misc::msg("Artwork cache entry for $album: $filepath\n");

				return $filepath;
			}
		}
	}
}

sub _updateTrackValidity {
	my $self  = shift;
	my $track = shift;

	my $url   = $track->get('url');

	if (Slim::Music::Info::isFileURL($url)) {

		$validityCache{$url} = (time() + DB_CACHE_LIFETIME + int(rand(DB_CACHE_LIFETIME)));

	} else {

		$validityCache{$url} = 0;
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

		$self->updateOrCreate({
			'url'        => $fullpath,
			'attributes' => $info
		});

 	} else {

		if ($type eq 'cover') {
			$self->{'coverCache'}->{$fullpath} = 0;
 		} elsif ($type eq 'thumb') {
			$self->{'thumbCache'}->{$fullpath} = 0;
 		}
 	}
}

# This is a callback that is run when the user changes the common album titles
# preference in settings.
sub commonAlbumTitlesChanged {
	my ($value, $key, $index) = @_;

	# Add the new value, or splice it out.
	if ($value) {

		$common_albums->[$index] = $value;

	} else {

		splice @$common_albums, $index, 1;
	}
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
