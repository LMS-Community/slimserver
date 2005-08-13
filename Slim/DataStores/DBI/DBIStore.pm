package Slim::DataStores::DBI::DBIStore;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::DataStores::Base);

use DBI;
use File::Basename qw(dirname);
use MP3::Info;
use Tie::Cache::LRU::Expires;
use Storable;

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

# For the VA album merging & scheduler globals.
my ($variousAlbumIds, $vaObj);

# Abstract to the caller
my %typeToClass = (
	'artist' => 'Slim::DataStores::DBI::Contributor',
	'album'  => 'Slim::DataStores::DBI::Album',
	'track'  => 'Slim::DataStores::DBI::Track',
	'genre'  => 'Slim::DataStores::DBI::Genre',
);

#
# Readable DataStore interface methods:
#
sub new {
	my $class = shift;

	my $self = {
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
	Slim::DataStores::DBI::DataModel->db_Main(1);
	
	($self->{'trackCount'}, $self->{'totalTime'}) = Slim::DataStores::DBI::DataModel->getMetaInformation();
	
	$self->_commitDBTimer();

	$common_albums = Slim::Utils::Prefs::get('commonAlbumTitles');

	Slim::Utils::Prefs::addPrefChangeHandler('commonAlbumTitles', \&commonAlbumTitlesChanged);

	return $self;
}

sub dbh {
	my $self = shift;

	return Slim::DataStores::DBI::DataModel->dbh;
}

sub classForType {
	my $self = shift;
	my $type = shift;

	return $typeToClass{$type};
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

	# Confirm that the URL itself isn't an object (see bug 1811)
	if (ref($url) && ref($url) =~ /Track/) {
		return $url;
	}

	if (!defined($url)) {
		msg("Null track request!\n"); 
		bt();
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

	} elsif ($field eq 'contributor' || $field eq 'artist') {

		return Slim::DataStores::DBI::Contributor->retrieve($id);
	}
}

sub find {
	my $self = shift;

	my $args = {};

	# Backwards compatibility with the previous calling method.
	if (scalar @_ > 1) {

		for my $key (qw(field find sortBy limit offset count)) {

			my $value = shift @_;

			$args->{$key} = $value if defined $value;
		}

	} else {

		$args = shift;
	}

	# If we're undefined for some reason - ie: We want all the results,
	# make sure that the ref type is correct.
	if (!defined $args->{'find'}) {
		$args->{'find'} = {};
	}

	# Try and keep the last result set in memory - so if the user is
	# paging through, we don't keep hitting the database.
	#
	# Can't easily use $limit/offset for the page bars, because they
	# require knowing the entire result set.
	my $findKey = Storable::freeze($args);

	$::d_sql && msg("Generated findKey: [$findKey]\n");

	if (!defined $lastFind{$findKey}) {

		# refcnt-- if we can, to prevent leaks.
		if ($Class::DBI::Weaken_Is_Available && !$args->{'count'}) {

			Scalar::Util::weaken($lastFind{$findKey} = Slim::DataStores::DBI::DataModel->find($args));

		} else {

			$lastFind{$findKey} = Slim::DataStores::DBI::DataModel->find($args);
		}

	} else {

		$::d_sql && msg("Used previous results for findKey: [$findKey]\n");
	}

	my $items = $lastFind{$findKey};

	if (!$args->{'count'} && !$args->{'idOnly'} && defined($items) && 
		($args->{'field'} eq 'track' || $args->{'field'} eq 'lightweighttrack')) {

		$items = [ grep $self->_includeInTrackCount($_), @$items ];

		# Does the track still exist?
		if ($args->{'field'} ne 'lightweighttrack') {
			$items = [ grep $self->_checkValidity($_), @$items ];
		}
	}

	return $items if $args->{'count'};
	return wantarray() ? @$items : $items;
}

sub count {
	my $self  = shift;
	my $field = shift;
	my $find  = shift || {};

	# make a copy, because we might modify it below.
	my %findCriteria = %$find;

	# The user may not want to include all the composers / conductors
	#
	# But don't restrict if we have an album (this may be wrong) - 
	# for VA albums, we want the correct count.
	if ($field eq 'contributor' && !$findCriteria{'album'} && !Slim::Utils::Prefs::get('composerInArtists')) {

		$findCriteria{'contributor.role'} = $self->artistOnlyRoles;
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

	return $self->find({
		'field' => $field,
		'find'  => \%findCriteria,
		'count' => 1,
	});
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

	$self->dbh->commit if $commit;
}

# Create a new track with the given attributes
sub newTrack {
	my $self = shift;
	my $args = shift;

	#
	my $url           = $args->{'url'} || return;
 	my $attributeHash = $args->{'attributes'} || {};

	my $deferredAttributes;

	$::d_info && msg("New track for $url\n");

	# Default the tag reading behaviour if not explicitly set
	if (!defined $args->{readTags}) {
		$args->{readTags} = "default";
	}

	# Read the tag, and start populating the database.
	if ($args->{'readTags'}) {

		$::d_info && msg("readTag was ". $args->{'readTags'}  ." for $url\n");

		$attributeHash = { %{$self->readTags($url)}, %$attributeHash  };
	}

	($attributeHash, $deferredAttributes) = $self->_preCheckAttributes($url, $attributeHash, 1);

	# Creating the track only wants lower case values from valid columns.
	my $columnValueHash = {};

	my $trackAttrs = Slim::DataStores::DBI::Track::attributes();

	# Walk our list of valid attributes, and turn them into something ->create() can use.
	while (my ($key, $val) = each %$attributeHash) {

		if (defined $val && exists $trackAttrs->{lc $key}) {

			$::d_info && msg("Adding $url : $key to $val\n");

			$columnValueHash->{lc $key} = $val;
		}
	}

	# Tag and rename set URL to the Amazon image path. Smack that. We
	# don't use it anyways.
	$columnValueHash->{'url'} = $url;

	# Create the track - or bail. We should probably spew an error.
	my $track = eval { Slim::DataStores::DBI::Track->create($columnValueHash) };

	if ($@) {
		bt();
		msg("Couldn't create track for $url : $@\n");

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

	$self->dbh->commit if $args->{'commit'};

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
		msg("No URL specified for updateOrCreate\n");
		msg(%{$attributeHash});
		bt();
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

		$::d_info && msg("Merging entry for $url\n");

		my $deferredAttributes;
		($attributeHash, $deferredAttributes) = $self->_preCheckAttributes($url, $attributeHash, 0);

		my %set = ();

		while (my ($key, $val) = each %$attributeHash) {

			if (defined $val && $val ne '' && exists $trackAttrs->{lc $key}) {

				$::d_info && msg("Updating $url : $key to $val\n");

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
		$self->dbh->commit if $commit;

		$::d_info && msg("cleared $url from database\n");
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
	$::d_import && msg("Import: Adding task for cleanupStaleTrackEntries()..\n");

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

		$::d_import && msg("Import: Starting db garbage collection..\n");

		$cleanupIds = Slim::DataStores::DBI::Track->retrieveAllOnlyIds;
	}

	# Only cleanup every 20th time through the scheduler.
	$staleCounter++;
	return 1 if $staleCounter % 20;

	# fetch one at a time to keep memory usage in check.
	my $item  = shift(@{$cleanupIds});
	my $track = Slim::DataStores::DBI::Track->retrieve($item) if defined $item;

	if (!defined $track && !defined $item && scalar @{$cleanupIds} == 0) {

		$::d_import && msg(
			"Import: Finished with stale track cleanup. Adding tasks for Contributors, Albums & Genres.\n"
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

	# Not sure how we get here, but we can. See bug 1756
	if (!defined $track) {
		return 1;
	}

	my $url = $track->url;

	# return 1 to move onto the next track
	unless (Slim::Music::Info::isFileURL($url)) {
		return 1;
	}
	
	my $filepath = Slim::Utils::Misc::pathFromFileURL($url);

	# Don't use _hasChanged - because that does more than we want.
	if (!-r $filepath) {

		$::d_import && msg("Import: Track $filepath no longer exists. Removing.\n");

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
	$self->dbh->commit;

	$::d_import && msg("Import: Finished with cleanupStaleTableEntries()\n");

	%lastFind = ();

	$staleCounter = 0;
	return 0;
}

# This is a post-process on the albums and contributor_tracks tables, in order
# to identify albums which are compilations / various artist albums - by
# virtue of having more than one artist.
sub mergeVariousArtistsAlbums {
        my $self = shift;

	unless ($variousAlbumIds) {

		$variousAlbumIds = Slim::DataStores::DBI::Album->retrieveAllOnlyIds;
	}

	unless ($vaObj) {

		$vaObj  = Slim::DataStores::DBI::Contributor->search({
			'name' => Slim::Utils::Prefs::get('variousArtistsString') || string('VARIOUSARTISTS')
		})->next;
	}

	# fetch one at a time to keep memory usage in check.
	my $item = shift(@{$variousAlbumIds});
	my $obj  = Slim::DataStores::DBI::Album->retrieve($item) if defined $item;

	if (!defined $obj && !defined $item && scalar @{$variousAlbumIds} == 0) {

		$::d_import && msg("Import: Finished with mergeVariousArtistsAlbums()\n");

		$vaObj = undef;
		$variousAlbumIds = ();

		return 0;
	}

	if (!defined $obj) {
		$::d_import && msg("Import: mergeVariousArtistsAlbums: Couldn't fetch album for item: [$item]\n");
		return 0;
	}

	# Don't need to process something we've already marked as a
	# compilation.
	return 1 if $obj->compilation;

	my %artists = ();

	for my $track ($obj->tracks) {

		my $artist = $track->artist;

		if ($artist && ref($artist) && $artist->can('id')) {

			$artists{ $artist->id }++;
		}
	}

	# Not a VA album.
	my $count = scalar keys %artists;

	if ($count == 0 || $count == 1) {
		return 1;
	}

	$::d_import && msgf("Import: Marking album: [%s] as Various Artists.\n", $obj->title);

	$obj->compilation(1);
	$obj->contributor($vaObj);
	$obj->update;

	# Now update the contributor_tracks table.
	for my $track ($obj->tracks) {

		$self->_mergeAndCreateContributors($track, {
			'COMPILATION' => 1,
			'ARTIST'      => $track->artist,
		});
	}

	return 1;
}

sub wipeCaches {
	my $self = shift;

	$self->forceCommit();

	%contentTypeCache = ();
	%validityCache    = ();
	%lastFind         = ();

	$self->{'artworkCache'} = {};
	$self->{'coverCache'}   = {};
	$self->{'thumbCache'}   = {};	
	$self->{'lastTrackURL'} = '';
	$self->{'lastTrack'}    = {};
	$self->{'zombieList'}   = {};

	Slim::DataStores::DBI::DataModel->clearObjectCaches();

	$::d_import && msg("Import: Wiped all in-memory caches.\n");
}

# Wipe all data in the database
sub wipeAllData {
	my $self = shift;

	$self->forceCommit();

	# clear the references to these singletons
	$_unknownArtist = undef;
	$_unknownGenre  = undef;
	$_unknownAlbum  = undef;

	$self->{'totalTime'}    = 0;
	$self->{'trackCount'}   = 0;

	$self->wipeCaches;

	Slim::DataStores::DBI::DataModel->wipeDB();

	$::d_import && msg("Import: Wiped info database\n");
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

	$::d_info && msg("forceCommit: syncing to the database.\n");

	$self->dbh->commit;

	$Slim::DataStores::DBI::DataModel::dirtyCount = 0;

	# clear our find cache
	%lastFind = ();
}

sub clearExternalPlaylists {
	my $self = shift;
	my $url = shift;

	# We can specify a url prefix to only delete certain types of external
	# playlists - ie: only iTunes, or only MusicMagic.
	for my $track ($self->getExternalPlaylists) {

		$track->delete() if (defined $url ? $track->url() =~ /^$url/ : 1);
	}

	$self->forceCommit();
}

sub clearInternalPlaylists {
	my $self = shift;

	for my $track ($self->getInternalPlaylists) {
		$track->delete;
	}

	$self->forceCommit();
}

sub getExternalPlaylists {
	my $self = shift;

	my @playlists = ();

	# Don't search for playlists if the plugin isn't enabled.
	for my $importer (qw(itunes moodlogic musicmagic)) {

		if (Slim::Utils::Prefs::get($importer)) {

			push @playlists, $Slim::Music::Info::suffixes{sprintf('%splaylist:', $importer)};
		}
	}

	if (scalar @playlists) {

		# Use find()'s caching mechanism.
		return $self->find({
			'field'  => 'playlist',
			'find'   => { 'ct' => \@playlists },
			'sortBy' => 'title',
		});
	}

	return ();
}

sub getInternalPlaylists {
	my $self = shift;

	# Use find()'s caching mechanism.
	return $self->find({
		'field'  => 'playlist',
		'find'   => { 'ct' => $Slim::Music::Info::suffixes{'playlist:'} },
		'sortBy' => 'title',
	});
}

# Get all the playlists in one shot with optional name search parameter.
# Used by the CLI but could potentially apply to all uses of [getInt, getExt]...

sub getPlaylists {
	my $self = shift;
	my $search = shift;

	my @playlists = ('playlist:*');
	my $find = {};
	
	# Don't search for playlists if the plugin isn't enabled.
	for my $importer (qw(itunes moodlogic musicmagic)) {

		if (Slim::Utils::Prefs::get($importer)) {

			push @playlists, $Slim::Music::Info::suffixes{sprintf('%splaylist:', $importer)};
		}
	}

	# Add search criteria for playlists
	$find->{'ct'} = \@playlists;
		
	# Add title search if any
	$find->{'track.titlesort'} = $search if (defined $search && $search ne '*');
	
	return $self->find({
		'field'  => 'playlist',
		'find'   => $find,
		'sortBy' => 'title',
	});
}

sub getPlaylistForClient {
	my $self   = shift;
	my $client = shift;

	return (Slim::DataStores::DBI::Track->search({
		'url' => sprintf('clientplaylist://%s', $client->id())
	}))[0];
}

sub readTags {
	my $self  = shift;
	my $file  = shift;

	my ($filepath, $attributesHash, $anchor);

	if (!defined($file) || $file eq '') {
		return {};
	}

	$::d_info && msg("reading tags for: $file\n");

	if (Slim::Music::Info::isFileURL($file)) {
		$filepath = Slim::Utils::Misc::pathFromFileURL($file);
		$anchor   = Slim::Utils::Misc::anchorFromURL($file);
	} else {
		$filepath = $file;
	}

	# get the type without updating the cache
	my $type = Slim::Music::Info::typeFromPath($filepath);

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
			msg("The following error occurred: $@\n");
			bt();
		}

		$::d_info && !defined($attributesHash) && msg("Info: no tags found for $filepath\n");

		if (defined $attributesHash->{'TRACKNUM'}) {
			$attributesHash->{'TRACKNUM'} = Slim::Music::Info::cleanTrackNumber($attributesHash->{'TRACKNUM'});
		}
		
		# Turn the tag SET into DISC and DISCC if it looks like # or #/#
		if ($attributesHash->{'SET'} and $attributesHash->{'SET'} =~ /(\d+)(?:\/(\d+))?/) {
			$attributesHash->{'DISC'} = $1;
			$attributesHash->{'DISCC'} = $2 if defined $2;
		}

		if (!$attributesHash->{'TITLE'}) {

			$::d_info && msg("Info: no title found, using plain title for $file\n");
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

		$::d_info && msg("Info: no title found, calculating title from url for $file\n");

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

		$::d_artwork && msg("Updating $album artwork cache: $filepath\n");

		$self->{'artworkCache'}->{$albumId} = 1;

		$album->artwork_path($track->id);
		$album->update();
	}
}

sub artistOnlyRoles {
	my $self = shift;

	return [
		$Slim::DataStores::DBI::ContributorTrack::contributorToRoleMap{'ARTIST'},
		$Slim::DataStores::DBI::ContributorTrack::contributorToRoleMap{'ALBUMARTIST'}
	];
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
		$::d_info && msg("DBI: Periodic commit - $items dirty items\n");
		$self->forceCommit();
	} else {
		$::d_info && msg("DBI: Supressing periodic commit - no dirty items\n");
	}

	Slim::Utils::Timers::setTimer($self, Time::HiRes::time() + DB_SAVE_INTERVAL, \&_commitDBTimer);
}

sub _checkValidity {
	my $self  = shift;
	my $track = shift;

	my ($id, $url) = $track->get(qw(id url));

	# Don't bother checking the validity over and over for a cue sheet
	# referenced URL. Just get the base name.
	# XXX - this doesn't really do what I want. It should definitely check
	# the first time around.
	# $url = Slim::Utils::Misc::stripAnchorFromURL($url);

	return undef if $self->{'zombieList'}->{$url};

	my $ttl = $validityCache{$url} || 0;

	if (Slim::Music::Info::isFileURL($url) && ($ttl < (time()))) {

		$::d_info && msg("CacheItem: Checking status of $url (TTL: $ttl).\n");

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

		msg("Track: [$id] - [$track] was deleted out from under us!\n");
		bt();

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

		$::d_info && msg("re-reading tags from $url as it has changed\n");
		my $attributeHash = $self->readTags($url);
		$self->updateOrCreate({
			 'url' => $track,
			 'attributes' => $attributeHash
		});
		
		return 0;

	} else {
		$::d_info && msg("deleting $url from cache as it no longer exists\n");
	}

	# Tell the DB to sync - if we're deleting something.
	$Slim::DataStores::DBI::DataModel::dirtyCount++;

	# We can't find the file - but don't put it on the zombie list.
	return 0;
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

	# Create a canonical title to search against.
	$attributes->{'TITLESEARCH'} = Slim::Utils::Text::ignoreCaseArticles($attributes->{'TITLE'});

	# Normalize ARTISTSORT in ContributorTrack->add() the tag may need to be split. See bug #295
	#
	# Push these back until we have a Track object.
	for my $tag (qw(
		COMMENT BAND COMPOSER CONDUCTOR GENRE ARTIST ARTISTSORT 
		PIC APIC ALBUM ALBUMSORT DISCC ALBUMARTIST COMPILATION)) {

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

	} elsif (!$create && $isLocal && $genre && $genre ne $track->genre) {

		# Bug 1143: The user has updated the genre tag, and is
		# rescanning We need to remove the previous associations.
		for my $genreObj ($track->genres) {
			$genreObj->delete;
		}

		Slim::DataStores::DBI::GenreTrack->add($genre, $track);
	}

	# Walk through the valid contributor roles, adding them to the database for each track.
	my $contributors     = $self->_mergeAndCreateContributors($track, $attributes);
	my $foundContributor = scalar @$contributors;

	# Create a singleton for "No Artist"
	if ($create && $isLocal && !$foundContributor && !$_unknownArtist) {

		$_unknownArtist = Slim::DataStores::DBI::Contributor->find_or_create({
			'name'       => string('NO_ARTIST'),
			'namesort'   => Slim::Utils::Text::ignoreCaseArticles(string('NO_ARTIST')),
			'namesearch' => Slim::Utils::Text::ignoreCaseArticles(string('NO_ARTIST')),
		});

		Slim::DataStores::DBI::ContributorTrack->add(
			$_unknownArtist,
			$Slim::DataStores::DBI::ContributorTrack::contributorToRoleMap{'ARTIST'},
			$track
		);

		push @$contributors, $_unknownArtist;

	} elsif ($create && $isLocal && !$foundContributor) {

		# Otherwise - reuse the singleton object, since this is the
		# second time through.
		Slim::DataStores::DBI::ContributorTrack->add(
			$_unknownArtist,
			$Slim::DataStores::DBI::ContributorTrack::contributorToRoleMap{'ARTIST'},
			$track
		);

		push @$contributors, $_unknownArtist;
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
			'title'       => string('NO_ALBUM'),
			'titlesort'   => Slim::Utils::Text::ignoreCaseArticles(string('NO_ALBUM')),
			'titlesearch' => Slim::Utils::Text::ignoreCaseArticles(string('NO_ALBUM')),
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
				'title' => $album,
			};

			# Add disc to the search criteria, so we get
			# the right object for multi-disc sets with
			# the same album name.
			# 
			# Don't add this search criteria if there is only one
			# disc in the set - iTunes does this for some bizzare
			# reason.
			if (($disc && $discc && $discc > 1) || ($disc && !$discc)) {
				$search->{'disc'} = $disc;
			}

			# Check if the album name is one of the "common album names"
			# we've identified in prefs. If so, we require a match on
			# both album name and primary artist name.
			if ((grep $album =~ m/^$_$/i, @$common_albums) && $contributors->[0]) {

				$search->{'contributor'} = $contributors->[0]->namesort;

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

			if (!Slim::Music::Import::artwork($albumObj) && !defined $track->thumb()) {

				Slim::Music::Import::artwork($albumObj, $track);
			}
		}

		if ($contributors->[0] && ref($contributors->[0])) {
			$albumObj->contributor($contributors->[0]);
		}

		# Always normalize the sort, as ALBUMSORT could come from a TSOA tag.
		$albumObj->titlesort($sortable_title) if $sortable_title;

		# And our searchable version.
		$albumObj->titlesearch(Slim::Utils::Text::ignoreCaseArticles($album));

		$albumObj->compilation(1) if $attributes->{'COMPILATION'};

		$albumObj->disc($disc) if $disc;
		$albumObj->discc($discc) if $discc;
		$albumObj->year($track->year) if $track->year;
		$albumObj->update();

		$track->album($albumObj);
	}

	# Compute a compound sort key we'll use for queries that involve
	# multiple albums. Rather than requiring a multi-way join to get
	# all the individual sort keys from different tables, this is an
	# optimization that only requires the tracks table.
	$albumObj ||= $track->album();

	my ($albumName, $primaryContributor) = ('', '');

	if (defined $albumObj) {
		$albumName = $albumObj->titlesort;
	}

	# Find a contributor associated with this track.
	my $contributor = shift @$contributors;

	if (defined $contributor && ref($contributor) && $contributor->can('namesort')) {

		$primaryContributor = $contributor->namesort;

	} elsif (defined $albumObj && ref($albumObj) && $albumObj->can('contributor')) {

		$contributor = $albumObj->contributor;

		if (defined $contributor && ref($contributor) && $contributor->can('namesort')) {

			$primaryContributor = $contributor->namesort;
		}
	}

	# Save 2 get calls
	my ($titlesort, $tracknum) = $track->get(qw(titlesort tracknum));

	my @keys = ();

	push @keys, $primaryContributor || '';
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
	@$contributors = ();
}

sub _mergeAndCreateContributors {
	my ($self, $track, $attributes) = @_;

	my @contributors = ();

	# XXXX - 'Treat BAND/TPE2 as ALBUMARTIST'. See Bug 1463
	# If people complain, we can make an option for this.
	if (!defined $attributes->{'ALBUMARTIST'} && defined $attributes->{'BAND'}) {

		$attributes->{'ALBUMARTIST'} = $attributes->{'BAND'};

		delete $attributes->{'BAND'};
	}

	# If we have a compilation tag, either from iTunes, or a Vorbis tag -
	# but no specified ALBUMARTIST - create a localized one.
	# 
	# Should this string come from a Pref? Some people might want "VA", or
	# "Various" or "Various Artists"
	if (!defined $attributes->{'ALBUMARTIST'} && defined $attributes->{'COMPILATION'}) {

		$attributes->{'ALBUMARTIST'} = Slim::Utils::Prefs::get('variousArtistsString') || string('VARIOUSARTISTS');
	}

	# If we have an Album Artist and an Artist, the Artist is moved to be the Track Artist
	if (defined $attributes->{'ALBUMARTIST'} && defined $attributes->{'ARTIST'} && !defined $attributes->{'TRACKARTIST'}) {

		$attributes->{'TRACKARTIST'} = $attributes->{'ARTIST'};

		delete $attributes->{'ARTIST'};
	}

	# XXXX - This order matters! Album artist should always be first,
	# since we grab the 0th element from the contributors array below when
	# creating the Album.
	for my $tag (qw(ALBUMARTIST ARTIST BAND COMPOSER CONDUCTOR TRACKARTIST)) {

		my $contributor = $attributes->{$tag} || next;
		my $forceCreate = 0;

		# Bug 1955 - Previously 'last one in' would win for a
		# contributorTrack - ie: contributor & role combo, if a track
		# had an ARTIST & COMPOSER that were the same value.
		#
		# If we come across that case, force the creation of a second
		# contributorTrack entry.
		if ((grep { /^$contributor$/ } values %{$attributes}) && $tag !~ /ARTIST$/) {

			$forceCreate = 1;
		}

		# Is ARTISTSORT/TSOP always right for non-artist
		# contributors? I think so. ID3 doesn't have
		# "BANDSORT" or similar at any rate.
		push @contributors, Slim::DataStores::DBI::ContributorTrack->add(
			$contributor, 
			$Slim::DataStores::DBI::ContributorTrack::contributorToRoleMap{$tag},
			$track,
			$tag eq 'ARTIST' ? $attributes->{'ARTISTSORT'} : undef,
			$forceCreate,
		);
	}

	return \@contributors;
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

 		$::d_artwork && msg("$type caching $path for $fullpath\n");

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
