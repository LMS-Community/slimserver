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
use List::Util qw(max);
use Scalar::Util qw(blessed);
use Storable;
use Tie::Cache::LRU::Expires;
use URI;

use Slim::DataStores::DBI::DataModel;

use Slim::DataStores::DBI::Album;
use Slim::DataStores::DBI::Comment;
use Slim::DataStores::DBI::Contributor;
use Slim::DataStores::DBI::ContributorAlbum;
use Slim::DataStores::DBI::Genre;
use Slim::DataStores::DBI::LightWeightTrack;
use Slim::DataStores::DBI::Track;

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Text;
use Slim::Utils::Unicode;

# Singleton objects for Unknowns
our ($_unknownArtist, $_unknownGenre, $_unknownAlbum) = ('', '', '');

# Keep the last 5 find results set in memory and expire them after 60 seconds
tie our %lastFind, 'Tie::Cache::LRU::Expires', EXPIRES => 60, ENTRIES => 5;

# Optimization to cache content type for track entries rather than look them up everytime.
tie our %contentTypeCache, 'Tie::Cache::LRU::Expires', EXPIRES => 300, ENTRIES => 128;

# For the VA album merging & scheduler globals.
my ($variousAlbumIds, $vaObj);

# Abstract to the caller
my %typeToClass = (
	'artist' => 'Slim::DataStores::DBI::Contributor',
	'album'  => 'Slim::DataStores::DBI::Album',
	'track'  => 'Slim::DataStores::DBI::Track',
	'genre'  => 'Slim::DataStores::DBI::Genre',
);

# Map the tags we get from metadata onto the database
my %tagMapping = (
	'size'       => 'audio_size',
	'offset'     => 'audio_offset',
	'rate'       => 'samplerate',
	'age'        => 'timestamp',
	'ct'         => 'content_type',
	'fs'         => 'filesize',
	'blockalign' => 'block_alignment',
);

#
# Readable DataStore interface methods:
#
sub new {
	my $class = shift;

	my $self = {
		# Values persisted in metainformation table
		trackCount   => 0,
		totalTime    => 0,

		# Non-persistent cache to make sure we don't set album artwork too many times.

		artworkCache => {},

		# Optimization to cache last track accessed rather than retrieve it again. 
		lastTrackURL => '',
		lastTrack    => {},

		# Tracks that are out of date and should be deleted the next time
		# we get around to it.
		zombieList   => {},

		# Only do this once.
		trackAttrs   => Slim::DataStores::DBI::Track::attributes(),
	};

	bless $self, $class;

	Slim::DataStores::DBI::DataModel->db_Main(1);
	
	($self->{'trackCount'}, $self->{'totalTime'}) = Slim::DataStores::DBI::DataModel->getMetaInformation();
	
	return $self;
}

sub dbh {
	my $self = shift;

	return Slim::DataStores::DBI::DataModel->dbh;
}

sub driver {
	my $self = shift;

	return Slim::DataStores::DBI::DataModel->driver;
}

# SQLite has some tuning parameters available via it's PRAGMA interface. See
# http://www.sqlite.org/pragma.html for more details.
#
# These wrappers allow us to set the params.
sub modifyDatabaseTempStorage {
	my $self  = shift;
	my $value = shift || Slim::Utils::Prefs::get('databaseTempStorage');

	if ($self->driver eq 'SQLite') {

		eval { $self->dbh->do("PRAGMA temp_store = $value") };

		if ($@) {
			errorMsg("Couldn't change the database temp_store value to: [$value]: [$@]\n");
		}
	}
}

sub modifyDatabaseCacheSize {
	my $self  = shift;
	my $value = shift || Slim::Utils::Prefs::get('databaseCacheSize');

	if ($self->driver eq 'SQLite') {

		eval { $self->dbh->do("PRAGMA cache_size = $value") };

		if ($@) {
			errorMsg("Couldn't change the database cache_size value to: [$value]: [$@]\n");
		}
	}
}

sub classForType {
	my $self = shift;
	my $type = shift;

	return $typeToClass{$type};
}

# Fetch the content type for a URL or Track Object.
#
# Try and be smart about the order of operations in order to avoid hitting the
# database if we can get a simple file extension match.
sub contentType {
	my ($self, $urlOrObj) = @_;

	my $defaultType = 'unk';
	my $contentType = $defaultType;

	# See if we were handed a track object already, or just a plain url.
	my $track       = blessed($urlOrObj) && $urlOrObj->can('id') ? $urlOrObj : undef;
	my $url         = blessed($track) && $track->can('url') ? $track->url : URI->new($urlOrObj)->canonical->as_string;

	# We can't get a content type on a undef url
	if (!defined $url) {
		return $defaultType;
	}

	# Cache hit - return immediately.
	if (defined $contentTypeCache{$url}) {

		return $contentTypeCache{$url};
	}

	# If we have an object - return from that.
	if (blessed($track) && $track->can('content_type')) {

		$contentType = $track->content_type;

	} else {

		# Otherwise, try and pull the type from the path name and avoid going to the database.
		$contentType = Slim::Music::Info::typeFromPath($url);
	}

	# Nothing from the path, and we don't have a valid track object - fetch one.
	if ((!defined $contentType || $contentType eq $defaultType) && !blessed($track)) {

		$track = $self->objectForUrl($url);

		if (blessed($track) && $track->can('content_type')) {

			$contentType = $track->content_type;
		}
	}

	# Nothing from the object we already have in the db.
	if ((!defined $contentType || $contentType eq $defaultType) && blessed($track)) {

		$contentType = Slim::Music::Info::typeFromPath($url);
	} 

	# Only set the cache if we have a valid contentType
	if (defined $contentType && $contentType ne $defaultType) {

		$contentTypeCache{$url} = $contentType;
	}

	return $contentType;
}

sub objectForUrl {
	my $self   = shift;
	my $url    = shift;
	my $create = shift;
	my $readTag = shift;
	my $lightweight = shift;

	# Confirm that the URL itself isn't an object (see bug 1811)
	# XXX - exception should go here. Comming soon.
	if (blessed($url) =~ /Track/) {
		return $url;
	}

	if (!defined($url)) {
		msg("Null track request!\n"); 
		bt();
		return undef;
	}

	# Create a canonical version, to make sure we only have one copy.
	$url = URI->new($url)->canonical->as_string;

	my $track = $self->_retrieveTrack($url, $lightweight);

	if (blessed($track) && $track->can('url') && !$create && !$lightweight) {
		$track = $self->_checkValidity($track);
	}

	# Handle the case where an object has been deleted out from under us.
	# XXX - exception should go here. Comming soon.
	if (blessed($track) eq 'Class::DBI::Object::Has::Been::Deleted') {

		$track  = undef;
		$create = 1;
	}

	if (!defined $track && $create) {

		$track = $self->updateOrCreate({
			'url'      => $url,
			'readTags' => $readTag,
		});
	}

	delete $self->{'zombieList'}->{$url};

	return $track;
}

sub objectForId {
	my $self  = shift;
	my $field = shift;
	my $id    = shift;

	if ($field eq 'track' || $field eq 'playlist') {

		my $track = Slim::DataStores::DBI::Track->retrieve($id) || return;

		return $self->_checkValidity($track);

	} elsif ($field eq 'lightweighttrack') {

		return Slim::DataStores::DBI::LightWeightTrack->retrieve($id);

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

	# Only pull out items that are audio for a track search.
	if ($args->{'field'} && $args->{'field'} =~ /track$/) {

		$args->{'find'}->{'audio'} = 1;
	}

	# Try and keep the last result set in memory - so if the user is
	# paging through, we don't keep hitting the database.
	#
	# Can't easily use $limit/offset for the page bars, because they
	# require knowing the entire result set.
	my $findKey = Storable::freeze($args);

	#$::d_sql && msg("Generated findKey: [$findKey]\n");

	if (!defined $lastFind{$findKey} || (defined $args->{'cache'} && $args->{'cache'} == 0)) {

		# refcnt-- if we can, to prevent leaks.
		if ($Class::DBI::Weaken_Is_Available && !$args->{'count'}) {

			Scalar::Util::weaken($lastFind{$findKey} = Slim::DataStores::DBI::DataModel->find($args));

		} else {

			$lastFind{$findKey} = Slim::DataStores::DBI::DataModel->find($args);
		}

	} else {

		$::d_sql && msg("Used previous results for findKey\n");
	}

	my $items = $lastFind{$findKey};

	if (!$args->{'count'} && !$args->{'idOnly'} && defined($items) && $args->{'field'} =~ /track$/) {

		# Does the track still exist?
		if ($args->{'field'} ne 'lightweighttrack') {

			for (my $i = 0; $i < scalar @$items; $i++) {

				$items->[$i] = $self->_checkValidity($items->[$i]);
			}

			# Weed out any potential undefs
			@$items = grep { defined($_) } @$items;
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

	if ($field eq 'artist') {
		$field = 'contributor';
	}

	# The user may not want to include all the composers / conductors
	#
	# But don't restrict if we have an album (this may be wrong) - 
	# for VA albums, we want the correct count.
	if ($field eq 'contributor' && !$findCriteria{'album'} && !$findCriteria{'genre'}) {

		if (my $roles = $self->artistOnlyRoles) {

			$findCriteria{'contributor.role'} = $roles;
		}

		if (Slim::Utils::Prefs::get('variousArtistAutoIdentification') && !exists $findCriteria{'album.compilation'}) {

			$findCriteria{'album.compilation'} = 0;
		}
	}

	# Optimize the all case
	if (scalar(keys %findCriteria) == 0) {

		if ($field eq 'track') {

			return $self->{'trackCount'};

		} elsif ($field eq 'genre') {

			return Slim::DataStores::DBI::Genre->count_all;

		} elsif ($field eq 'album') {

			return Slim::DataStores::DBI::Album->count_all;

		} elsif ($field eq 'contributor') {

			return Slim::DataStores::DBI::Contributor->count_all;
		}
	}

	return $self->find({
		'field' => $field,
		'find'  => \%findCriteria,
		'count' => 1,
	});
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
	my ($self, $track, $commit) = @_;

	$track->update;

	$self->dbh->commit if $commit;
}

# Create a new track with the given attributes
sub newTrack {
	my $self = shift;
	my $args = shift;

	#
	my $url           = $args->{'url'};
 	my $attributeHash = $args->{'attributes'} || {};

	# Not sure how we can get here - but we can.
	if (!$url || $url =~ /^\s*$/ || ref($url)) {

		msg("newTrack: Bogus value for 'url'\n");
		require Data::Dumper;
		print Data::Dumper::Dumper($url);
		bt();

		return undef;
	}

	my $deferredAttributes;

	# Create a canonical version, to make sure we only have one copy.
	$url = URI->new($url)->canonical->as_string;

	$::d_info && msg("New track for $url\n");

	# Default the tag reading behaviour if not explicitly set
	if (!defined $args->{'readTags'}) {
		$args->{'readTags'} = "default";
	}

	# Read the tag, and start populating the database.
	if ($args->{'readTags'}) {

		$::d_info && msg("readTag was ". $args->{'readTags'}  ." for $url\n");

		$attributeHash = { %{$self->readTags($url)}, %$attributeHash  };
	}

	# Abort early and don't add the track if it's DRM'd
	if ($attributeHash->{'DRM'}) {
		
		$::d_info && msg("newTrack: Skipping [$url] - It's DRM hampered.\n");
		return;
	}

	($attributeHash, $deferredAttributes) = $self->_preCheckAttributes({
		'url'        => $url,
		'attributes' => $attributeHash,
		'create'     => 1,
	});

	# Creating the track only wants lower case values from valid columns.
	my $columnValueHash = {};

	# Walk our list of valid attributes, and turn them into something ->create() can use.
	while (my ($key, $val) = each %$attributeHash) {

		$key = lc($key);

		if (defined $val && exists $self->{'trackAttrs'}->{$key}) {

			$::d_info && msg("Adding $url : $key to $val\n");

			$columnValueHash->{$key} = $val;
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
	$self->_postCheckAttributes({
		'track'      => $track,
		'attributes' => $deferredAttributes,
		'create'     => 1,
	});

	if ($columnValueHash->{'audio'}) {

		$self->{'lastTrackURL'} = $url;
		$self->{'lastTrack'}->{dirname($url)} = $track;

		my $time = $columnValueHash->{'secs'};

		if ($time) {
			$self->{'totalTime'} += $time;
		}

		$self->{'trackCount'}++;
	}

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
	my $checkMTime    = $args->{'checkMTime'};

	# XXX - exception should go here. Comming soon.
	my $track = blessed($urlOrObj) ? $urlOrObj : undef;
	my $url   = blessed($track) && $track->can('url') ? $track->url : URI->new($urlOrObj)->canonical->as_string;

	if (!defined($url)) {
		require Data::Dumper;
		print Data::Dumper::Dumper($attributeHash);
		msg("No URL specified for updateOrCreate\n");
		bt();
		return undef;
	}

	# Always remove from the zombie list, since we're about to update or
	# create this item.
	delete $self->{'zombieList'}->{$url};

	# Track will be defined or not based on the blessed() assignment above.
	if (!defined $track) {
		$track = $self->_retrieveTrack($url);
	}

	# XXX - exception should go here. Comming soon.
	if (blessed($track) && $track->can('url')) {

		# Check the timestamp & size to make sure they've not changed.
		if ($checkMTime && Slim::Music::Info::isFileURL($url) && !$self->_hasChanged($track, $url)) {

			$::d_info && msg("Track is still valid! Skipping update! $url\n");

			return $track;
		}

		$::d_info && msg("Merging entry for $url\n");

		# Force a re-read if requested.
		# But not for remote / non-audio files.
		# 
		# Bug: 2335 - readTags is set in Slim::Formats::Playlists::CUE - when
		# we create/update a cue sheet to have a CT of 'cur'
		if ($readTags && $track->audio && !$track->remote && $attributeHash->{'CONTENT_TYPE'} ne 'cur') {

			$attributeHash = { %{$self->readTags($url)}, %$attributeHash  };
		}

		my $deferredAttributes;
		($attributeHash, $deferredAttributes) = $self->_preCheckAttributes({
			'url'        => $url,
			'attributes' => $attributeHash,
		});

		my %set = ();

		while (my ($key, $val) = each %$attributeHash) {

			$key = lc($key);

			if (defined $val && $val ne '' && exists $self->{'trackAttrs'}->{$key}) {

				$::d_info && msg("Updating $url : $key to $val\n");

				$set{$key} = $val;
			}
		}

		# Just make one call.
		$track->set(%set);

		# _postCheckAttributes does an update
		$self->_postCheckAttributes({
			'track'      => $track,
			'attributes' => $deferredAttributes,
		});

		$self->dbh->commit if $commit;

	} else {

		$track = $self->newTrack({
			'url'        => $url,
			'attributes' => $attributeHash,
			'readTags'   => $readTags,
			'commit'     => $commit,
		});
	}

	if ($track && $attributeHash->{'CONTENT_TYPE'}) {
		$contentTypeCache{$url} = $attributeHash->{'CONTENT_TYPE'};
	}

	return $track;
}

# Delete a track from the database.
sub delete {
	my $self = shift;
	my $urlOrObj = shift;
	my $commit = shift;

	# XXX - exception should go here. Comming soon.
	my $track = blessed($urlOrObj) ? $urlOrObj : undef;
	my $url   = blessed($track) && $track->can('url') ? $track->url : $urlOrObj;

	if (!defined($track)) {
		$track = $self->_retrieveTrack($url);		
	}

	# XXX - exception should go here. Comming soon.
	if (blessed($track) && $track->can('url')) {

		# XXX - make sure that playlisttracks are deleted on cascade 
		# otherwise call $track->setTracks() with an empty list
		my ($audio, $secs) = $track->getFast(qw(audio secs));

		if ($audio) {

			$self->{'trackCount'}--;

			if ($secs) {
				$self->{'totalTime'} -= $secs;
			}
		}

		# Be sure to clear the track out of the cache as well.
		if ($url eq $self->{'lastTrackURL'}) {
			$self->{'lastTrackURL'} = '';
		}

		my $dirname = dirname($url);

		if (defined $self->{'lastTrack'}->{$dirname} && $self->{'lastTrack'}->{$dirname}->url eq $url) {
			delete $self->{'lastTrack'}->{$dirname};
		}

		$track->delete;

		$self->dbh->commit if $commit;

		$track = undef;

		$::d_info && msg("cleared $url from database\n");
	}
}

# Mark all track entries as being stale in preparation for scanning for validity.
sub markAllEntriesStale {
	my $self = shift;

	%lastFind         = ();
	%contentTypeCache = ();

	$self->{'artworkCache'} = {};
}

# Mark a track entry as valid.
sub markEntryAsValid {
	my $self = shift;
	my $url = shift;

	delete $self->{'zombieList'}->{$url};
}

# Mark a track entry as invalid.
# Does the reverse of above.
sub markEntryAsInvalid {
	my $self = shift;
	my $url  = shift || return undef;

	$self->{'zombieList'}->{$url} = 1;
}

sub cleanupStaleTrackEntries {
	my $self = shift;

	# Cleanup any stale entries in the database.
	# 
	# First walk the list of tracks, checking to see if the
	# file/directory/shortcut still exists on disk. If it doesn't, delete
	# it. This will cascade ::Track's has_many relationships, including
	# contributor_track, etc.
	#
	# After that, walk the Album, Contributor & Genre tables, to see if
	# each item has valid tracks still. If it doesn't, remove the object.
	#
	# At Some Point in the Future(tm), Class::DBI should be modified, so
	# that retrieve_all() is lazy, and only fetches a $sth->row when
	# $obj->next is called.
	#
	# Or just move to DBIx::Class

	$::d_import && msg("Import: Starting db garbage collection..\n");

	my $cleanupIds = Slim::DataStores::DBI::Track->retrieveAllOnlyIds;

	# fetch one at a time to keep memory usage in check.
	for my $id (@{$cleanupIds}) { 

		next unless defined $id;

		my $track = Slim::DataStores::DBI::Track->retrieve($id);

		# Not sure how we get here, but we can. See bug 1756
		# XXX - exception should go here. Comming soon.
		if (!blessed($track) || !$track->can('audio')) {
			next;
		}

		if (!$track->audio) {
			next;
		}

		# _hasChanged will delete tracks
		if ($self->_hasChanged($track, $track->url)) {

			$track = undef;
		}
	}

	$::d_import && msg(
		"Import: Finished with stale track cleanup. Adding tasks for Contributors, Albums & Genres.\n"
	);

	$cleanupIds = undef;

	# Walk the Album, Contributor and Genre tables to see if we have any dangling
	# entries, pointing to non-existant tracks.
	Slim::DataStores::DBI::Contributor->removeStaleDBEntries('contributorTracks');
	Slim::DataStores::DBI::Album->removeStaleDBEntries('tracks');
	Slim::DataStores::DBI::Genre->removeStaleDBEntries('genreTracks');

	# We're done.
	$self->dbh->commit;

	Slim::Music::Import->endImporter('cleanupStaleEntries');

	%lastFind = ();

	return 1;
}

sub variousArtistsObject {
	my $self = shift;

	my $vaString = Slim::Music::Info::variousArtistString();

	# Fetch a VA object and/or update it's name if the user has changed it.
	# XXX - exception should go here. Comming soon.
	if (!blessed($vaObj) || !$vaObj->can('name')) {

		$vaObj  = Slim::DataStores::DBI::Contributor->find_or_create({
			'name' => $vaString,
		});
	}

	if ($vaObj && $vaObj->name ne $vaString) {

		$vaObj->name($vaString);
		$vaObj->namesort( Slim::Utils::Text::ignoreCaseArticles($vaString) );
		$vaObj->namesearch( Slim::Utils::Text::ignoreCaseArticles($vaString) );
		$vaObj->update;
	}

	return $vaObj;
}

# This is a post-process on the albums and contributor_tracks tables, in order
# to identify albums which are compilations / various artist albums - by
# virtue of having more than one artist.
sub mergeVariousArtistsAlbums {
        my $self = shift;

	my $variousAlbumIds = Slim::DataStores::DBI::Album->retrieveAllOnlyIds;

	# fetch one at a time to keep memory usage in check.
	ALBUM: for my $id (@{$variousAlbumIds}) {

		next unless defined $id;

		my $albumObj = Slim::DataStores::DBI::Album->retrieve($id);

		# XXX - exception should go here. Comming soon.
		if (!blessed($albumObj) || !$albumObj->can('tracks')) {

			$::d_import && msg("Import: mergeVariousArtistsAlbums: Couldn't fetch album for id: [$id]\n");

			next;
		}

		# This is a catch all - but don't mark it as VA.
		next if $albumObj->title eq string('NO_ALBUM');

		# Don't need to process something we've already marked as a compilation.
		next if $albumObj->compilation;

		my %trackArtists      = ();
		my $markAsCompilation = 0;

		for my $track ($albumObj->tracks) {

			# Bug 2066: If the user has an explict Album Artist set -
			# don't try to mark it as a compilation.
			for my $artist ($track->contributorsOfType('ALBUMARTIST')) {

				next ALBUM;
			}

			# Create a composite of the artists for the track to compare below.
			my $artistComposite = join(':', sort map { $_->id } $track->contributorsOfType('ARTIST'));

			$trackArtists{$artistComposite} = 1;
		}

		# Bug 2418 - If the tracks have a hardcoded artist of 'Various Artists' - mark the album as a compilation.
		if (scalar values %trackArtists > 1) {

			$markAsCompilation = 1;

		} else {

			my ($artistId) = keys %trackArtists;

			if ($artistId == $self->variousArtistsObject->id) {

				$markAsCompilation = 1;
			}
		}

		if ($markAsCompilation) {

			$::d_import && msgf("Import: Marking album: [%s] as Various Artists.\n", $albumObj->title);

			$albumObj->compilation(1);
			$albumObj->update;
		}
	}

	$variousAlbumIds = ();

	Slim::Music::Import->endImporter('mergeVariousAlbums');
}

sub wipeCaches {
	my $self = shift;

	$self->forceCommit;

	%contentTypeCache = ();
	%lastFind         = ();

	# clear the references to these singletons
	$vaObj            = undef;

	$self->{'artworkCache'} = {};
	$self->{'lastTrackURL'} = '';
	$self->{'lastTrack'}    = {};
	$self->{'zombieList'}   = {};

	Slim::DataStores::DBI::DataModel->clearObjectCaches;

	$::d_import && msg("Import: Wiped all in-memory caches.\n");
}

# Wipe all data in the database
sub wipeAllData {
	my $self = shift;

	# clear the references to these singletons
	$_unknownArtist = '';
	$_unknownGenre  = '';
	$_unknownAlbum  = '';

	$self->{'totalTime'}    = 0;
	$self->{'trackCount'}   = 0;

	$self->wipeCaches;

	Slim::DataStores::DBI::DataModel->wipeDB;

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
	for my $track ($self->getPlaylists('external')) {

		# XXX - exception should go here. Comming soon.
		if (!blessed($track) || !$track->can('url')) {
			next;
		}

		$track->delete if (defined $url ? $track->url =~ /^$url/ : 1);
	}

	$self->forceCommit;
}

sub clearInternalPlaylists {
	my $self = shift;

	for my $track ($self->getPlaylists('internal')) {

		# XXX - exception should go here. Comming soon.
		if (!blessed($track) || !$track->can('delete')) {
			next;
		}

		$track->delete;
	}

	$self->forceCommit;
}

# Get the playlists
# param $type is 'all' for all playlists, 'internal' for internal playlists
# 'external' for external playlists. Default is 'all'.
# param $search is a search term on the playlist title.

sub getPlaylists {
	my $self = shift;
	my $type = shift || 'all';
	my $search = shift;

	my @playlists = ();
	
	if ($type eq 'all' || $type eq 'internal') {
		push @playlists, $Slim::Music::Info::suffixes{'playlist:'};
	}
	
	my $find = {};
	
	# Don't search for playlists if the plugin isn't enabled.
	if ($type eq 'all' || $type eq 'external') {
		for my $importer (qw(itunes moodlogic musicmagic)) {
	
			if (Slim::Utils::Prefs::get($importer)) {
	
				push @playlists, $Slim::Music::Info::suffixes{sprintf('%splaylist:', $importer)};
			}
		}
	}

	return () unless (scalar @playlists);

	# Add search criteria for playlists
	$find->{'content_type'} = \@playlists;
		
	# Add title search if any
	$find->{'track.titlesearch'} = $search if (defined $search);
	
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
	my $type   = Slim::Music::Info::typeFromPath($filepath);
	my $remote = Slim::Music::Info::isRemoteURL($file);

	if (Slim::Music::Info::isSong($file, $type) && !$remote) {

		# Extract tag and audio info per format
		if (my $tagReaderClass = Slim::Music::Info::classForFormat($type)) {

			# Dynamically load the module in.
			Slim::Music::Info::loadTagFormatForType($type);

			$attributesHash = eval { $tagReaderClass->getTag($filepath, $anchor) };
		}

		if ($@) {
			errorMsg("readTags: While trying to ->getTag($filepath) : $@\n");
			bt();
		}

		$::d_info && !defined($attributesHash) && msg("Info: no tags found for $filepath\n");

		# Return early if we have a DRM track
		if ($attributesHash->{'DRM'}) {
			return $attributesHash;
		}

		if (defined $attributesHash->{'TRACKNUM'}) {
			$attributesHash->{'TRACKNUM'} = Slim::Music::Info::cleanTrackNumber($attributesHash->{'TRACKNUM'});
		}

		# Turn the tag SET into DISC and DISCC if it looks like # or #/#
		if ($attributesHash->{'SET'} and $attributesHash->{'SET'} =~ /(\d+)(?:\/(\d+))?/) {

			# Strip leading 0s so that numeric compare at the db level works.
			$attributesHash->{'DISC'}  = int($1);
			$attributesHash->{'DISCC'} = int($2) if defined $2;
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
			if ($INC{'MP3::Info'} && defined($MP3::Info::mp3_genres[$1])) {

				$attributesHash->{'GENRE'} = $MP3::Info::mp3_genres[$1];
			}
		}

		# Mark it as audio in the database.
		if (!defined $attributesHash->{'AUDIO'}) {

			$attributesHash->{'AUDIO'} = 1;
		}

		# Set some defaults for the track if the tag reader didn't pull them.
		for my $key (qw(DRM LOSSLESS)) {

			$attributesHash->{$key} ||= 0;
		}
	}

	# Last resort
	if (!defined $attributesHash->{'TITLE'} || $attributesHash->{'TITLE'} =~ /^\s*$/) {

		$::d_info && msg("Info: no title found, calculating title from url for $file\n");

		$attributesHash->{'TITLE'} = Slim::Music::Info::plainTitle($file, $type);
	}

	if (-e $filepath) {
		# cache the file size & date
		($attributesHash->{'FILESIZE'}, $attributesHash->{'TIMESTAMP'}) = (stat($filepath))[7,9];
	}

	# Only set if we couldn't read it from the file.
	$attributesHash->{'CONTENT_TYPE'} ||= $type;

	# note that we've read in the tags.
	$attributesHash->{'TAG'} = 1;

	# Bug: 2381 - FooBar2k seems to add UTF8 boms to their values.
	while (my ($tag, $value) = each %{$attributesHash}) {

		$attributesHash->{$tag} =~ s/$Slim::Utils::Unicode::bomRE//;
	}

	return $attributesHash;
}

sub setAlbumArtwork {
	my $self  = shift;
	my $track = shift;
	
	if (!Slim::Utils::Prefs::get('lookForArtwork')) {
		return undef
	}

	# XXX - exception should go here. Comming soon.
	if (!blessed($track) || !$track->can('album')) {
		return undef;
	}

	my $album   = $track->album;
	my $albumId = $album->id if blessed($album);

	# only cache albums once each
	if ($albumId && !exists $self->{'artworkCache'}->{$albumId}) {

		$::d_artwork && msg("Updating $album artwork cache: $track\n");

		$self->{'artworkCache'}->{$albumId} = 1;

		$album->artwork($track->id);
		$album->update;
	}
}

# The user may want to constrain their browse view by either or both of
# 'composer' and 'track artists'.
sub artistOnlyRoles {
	my $self  = shift;

	my %roles = (
		'ARTIST'      => 1,
		'ALBUMARTIST' => 1,
	);

	# Loop through each pref to see if the user wants to show that contributor role.
	for my $role (qw(COMPOSER CONDUCTOR BAND)) {

		my $pref = sprintf('%sInArtists', lc($role));

		if (Slim::Utils::Prefs::get($pref)) {

			$roles{$role} = 1;
		}
	}

	# If we're using all roles, don't bother with the constraint.
	if (scalar keys %roles != Slim::DataStores::DBI::Contributor->totalContributorRoles) {

		return [ sort map { Slim::DataStores::DBI::Contributor->typeToRole($_) } keys %roles ];
	}

	return undef;
}

#
# Private methods:
#

sub _retrieveTrack {
	my $self = shift;
	my $url  = shift;
	my $lightweight = shift;

	return undef if ref($url);
	return undef if $self->{'zombieList'}->{$url};

	my $track;

	# Keep the last track per dirname.
	my $dirname = dirname($url);

	if ($url eq $self->{'lastTrackURL'}) {

		$track = $self->{'lastTrack'}->{$dirname};

	} elsif ($lightweight) {

		($track) = Slim::DataStores::DBI::LightWeightTrack->search('url' => $url);

	} else {

		($track) = Slim::DataStores::DBI::Track->search('url' => $url);
	}

	# XXX - exception should go here. Comming soon.
	if (!$lightweight && blessed($track) && $track->can('audio') && $track->audio) {

		$self->{'lastTrackURL'} = $url;
		$self->{'lastTrack'}->{$dirname} = $track;
	}

	return $track;
}

sub _checkValidity {
	my $self  = shift;
	my $track = shift;

	# XXX - exception should go here. Comming soon.
	return undef unless blessed($track);
	return undef unless $track->can('url');

	my ($url, $audio, $remote) = $track->getFast(qw(url audio remote));

	return undef if $self->{'zombieList'}->{$url};

	$::d_info && msg("_checkValidity: Checking to see if $url has changed.\n");

	# Don't check for remote tracks, or things that aren't audio
	if ($audio && !$remote && $self->_hasChanged($track, $url)) {

		$::d_info && msg("_checkValidity: Re-reading tags from $url as it has changed.\n");

		# Do a cascading delete for has_many relationships - this will
		# clear out Contributors, Genres, etc.
		$track->call_trigger('before_delete');
		$track->update;

		$track = $self->updateOrCreate({
			'url'      => $track,
			'readTags' => 1,
			'commit'   => 1,
		});
	}

	return undef unless blessed($track);
	return undef unless $track->can('url');

	return $track;
}

sub _hasChanged {
	my ($self, $track, $url) = @_;

	# We return 0 if the file hasn't changed
	#    return 1 if the file has been changed.

	# Don't check anchors - only the top level file.
	return 0 if Slim::Utils::Misc::anchorFromURL($url);

	my $filepath = Slim::Utils::Misc::pathFromFileURL($url);

	$::d_info && msg("_hasChanged: Checking for [$filepath] - size & timestamp.\n");

	# Return if it's a directory - they expire themselves 
	# Todo - move directory expire code here?
	return 0 if -d $filepath;
	return 0 if $filepath =~ /\.lnk$/i;

	# See if the file exists
	#
	# Reuse _, as we only need to stat() once.
	if (-e $filepath) {

		my ($filesize, $timestamp) = $track->getFast(qw(filesize timestamp));

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

		return 1;

	} else {

		$::d_info && msg("_hasChanged: removing [$filepath] from the db as it no longer exists.\n");

		$self->delete($track, 1);

		$track = undef;

		return 0;
	}
}

sub _preCheckAttributes {
	my $self = shift;
	my $args = shift;

	my $url    = $args->{'url'};
	my $create = $args->{'create'} || 0;

	my $deferredAttributes = {};

	# Copy the incoming hash, so we don't modify it
	my $attributes = { %{ $args->{'attributes'} } };

	# Normalize attribute names
	while (my ($key, $val) = each %$attributes) {

		if (exists $tagMapping{lc $key}) {

			$attributes->{ $tagMapping{lc $key} } = delete $attributes->{$key};
		}
	}

	# We also need these in _postCheckAttributes, but they should be set during create()
	$deferredAttributes->{'COVER'}   = $attributes->{'COVER'};
	$deferredAttributes->{'THUMB'}   = $attributes->{'THUMB'};
	$deferredAttributes->{'DISC'}    = $attributes->{'DISC'};
	
	# We've seen people with multiple TITLE tags in the wild.. why I don't
	# know. Merge them. Do the same for ALBUM, as you never know.
	for my $tag (qw(TITLE ALBUM)) {

		if ($attributes->{$tag} && ref($attributes->{$tag}) eq 'ARRAY') {

			$attributes->{$tag} = join(' / ', @{$attributes->{$tag}});
		}
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

	# Remote index.
	$attributes->{'REMOTE'} = Slim::Music::Info::isRemoteURL($url) ? 1 : 0;

	# Don't insert non-numeric YEAR fields into the database. Bug: 2610
	# Same for DISC - Bug 2821
	for my $tag (qw(YEAR DISC DISCC TRACKNUM)) {

		if (defined $attributes->{$tag} && $attributes->{$tag} !~ /^\d+$/) {

			delete $attributes->{$tag};
		}
	}

	# Munge the replaygain values a little
	for my $gainTag (qw(REPLAYGAIN_TRACK_GAIN REPLAYGAIN_TRACK_PEAK)) {

		my $shortTag = $gainTag;
		   $shortTag =~ s/^REPLAYGAIN_TRACK_(\w+)$/REPLAY_$1/;

		$attributes->{$shortTag} = delete $attributes->{$gainTag};
		$attributes->{$shortTag} =~ s/\s*dB//gi;
	}

	# We can take an array too - from vorbis comments, so be sure to handle that.
	my $comments = [];

	if ($attributes->{'COMMENT'} && !ref($attributes->{'COMMENT'})) {

		$comments = [ $attributes->{'COMMENT'} ];

	} elsif (ref($attributes->{'COMMENT'}) eq 'ARRAY') {

		$comments = $attributes->{'COMMENT'};
	}

	# Bug: 2605 - Get URL out of the attributes - some programs, and
	# services such as www.allofmp3.com add it.
	if ($attributes->{'URL'}) {

		push @$comments, delete $attributes->{'URL'};
	}

	$attributes->{'COMMENT'} = $comments;

	# Normalize ARTISTSORT in Contributor->add() the tag may need to be split. See bug #295
	#
	# Push these back until we have a Track object.
	for my $tag (qw(
		COMMENT BAND COMPOSER CONDUCTOR GENRE ARTIST ARTISTSORT 
		PIC APIC ALBUM ALBUMSORT DISCC ALBUMARTIST COMPILATION
		REPLAYGAIN_ALBUM_PEAK REPLAYGAIN_ALBUM_GAIN
		MUSICBRAINZ_ARTIST_ID MUSICBRAINZ_ALBUM_ARTIST_ID
		MUSICBRAINZ_ALBUM_ID MUSICBRAINZ_ALBUM_TYPE MUSICBRAINZ_ALBUM_STATUS
	)) {

		next unless defined $attributes->{$tag};

		$deferredAttributes->{$tag} = delete $attributes->{$tag};
	}

	return ($attributes, $deferredAttributes);
}

sub _postCheckAttributes {
	my $self = shift;
	my $args = shift;

	my $track      = $args->{'track'};
	my $attributes = $args->{'attributes'};
	my $create     = $args->{'create'} || 0;

	# XXX - exception should go here. Comming soon.
	if (!blessed($track) || !$track->can('get')) {
		return undef;
	}

	# Don't bother with directories / lnks. This makes sure "No Artist",
	# etc don't show up if you don't have any.
	my ($trackId, $trackUrl, $trackType, $trackAudio, $trackRemote) = $track->getFast(qw(id url content_type audio remote));

	if ($trackType eq 'dir' || $trackType eq 'lnk') {

		$track->update;

		return undef;
	}

	# We don't want to add "No ..." entries for remote URLs, or meta
	# tracks like iTunes playlists.
	my $isLocal = Slim::Music::Info::isSong($trackUrl) && !Slim::Music::Info::isRemoteURL($trackUrl);

	# Genre addition. If there's no genre for this track, and no 'No Genre' object, create one.
	my $genre = $attributes->{'GENRE'};

	if ($create && $isLocal && !$genre && (!defined $_unknownGenre || ref($_unknownGenre) ne 'Slim::DataStores::DBI::Genre')) {

		$_unknownGenre = Slim::DataStores::DBI::Genre->find_or_create({
			'name'     => string('NO_GENRE'),
			'namesort' => Slim::Utils::Text::ignoreCaseArticles(string('NO_GENRE')),
		});

		Slim::DataStores::DBI::Genre->add($_unknownGenre, $track);

	} elsif ($create && $isLocal && !$genre) {

		Slim::DataStores::DBI::Genre->add($_unknownGenre, $track);

	} elsif ($create && $isLocal && $genre) {

		Slim::DataStores::DBI::Genre->add($genre, $track);

	} elsif (!$create && $isLocal && $genre && $genre ne $track->genre) {

		# Bug 1143: The user has updated the genre tag, and is
		# rescanning We need to remove the previous associations.
		Slim::DataStores::DBI::GenreTrack->sql_fastDelete->execute($track->id);

		Slim::DataStores::DBI::Genre->add($genre, $track);
	}

	# Walk through the valid contributor roles, adding them to the database for each track.
	my $contributors     = $self->_mergeAndCreateContributors($track, $attributes);
	my $foundContributor = scalar keys %{$contributors};

	# Create a singleton for "No Artist"
	if ($create && $isLocal && !$foundContributor && !$_unknownArtist) {

		$_unknownArtist = Slim::DataStores::DBI::Contributor->find_or_create({
			'name'       => string('NO_ARTIST'),
			'namesort'   => Slim::Utils::Text::ignoreCaseArticles(string('NO_ARTIST')),
			'namesearch' => Slim::Utils::Text::ignoreCaseArticles(string('NO_ARTIST')),
		});

		Slim::DataStores::DBI::Contributor->add({
			'artist' => $_unknownArtist->name,
			'role'   => Slim::DataStores::DBI::Contributor->typeToRole('ARTIST'),
			'track'  => $track->id,
		});

		push @{ $contributors->{'ARTIST'} }, $_unknownArtist;

	} elsif ($create && $isLocal && !$foundContributor) {

		# Otherwise - reuse the singleton object, since this is the
		# second time through.
		Slim::DataStores::DBI::Contributor->add({
			'artist' => $_unknownArtist->name,
			'role'   => Slim::DataStores::DBI::Contributor->typeToRole('ARTIST'),
			'track'  => $track->id,
		});

		push @{ $contributors->{'ARTIST'} }, $_unknownArtist;
	}

	# The "primary" contributor
	my $contributor = ($contributors->{'ALBUMARTIST'}->[0] || $contributors->{'ARTIST'}->[0]);

	# Now handle Album creation
	my $album    = $attributes->{'ALBUM'};
	my $disc     = $attributes->{'DISC'};
	my $discc    = $attributes->{'DISCC'};

	# Make a local variable for COMPILATION, that is easier to handle
	my $isCompilation = 0;

	if (defined $attributes->{'COMPILATION'} && 
		$attributes->{'COMPILATION'} =~ /^yes$/i || 
		$attributes->{'COMPILATION'} == 1) {

		$isCompilation = 1;
	}

	# we may have an album object already..
	my $albumObj = $track->album if !$create;
	
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

	} elsif ($create && $isLocal && !$album && blessed($_unknownAlbum)) {

		$track->album($_unknownAlbum);
		$albumObj = $_unknownAlbum;

	} elsif ($create && $isLocal && $album) {

		# Used for keeping track of the album name.
		my $basename = dirname($trackUrl);
		
		# Calculate once if we need/want to test for disc
		# Check only if asked to treat discs as separate and
		# if we have a disc, provided we're not in the iTunes situation (disc == discc == 1)
		my $checkDisc = 0;

		if (!Slim::Utils::Prefs::get('groupdiscs') && 
			(($disc && $discc && $discc > 1) || ($disc && !$discc))) {

			$checkDisc = 1;
		}

		# Go through some contortions to see if the album we're in
		# already exists. Because we keep contributors now, but an
		# album can have many contributors, check the disc and
		# album name, to see if we're actually the same.
		
		# For some reason here we do not apply the same criterias as below:
		# Path, compilation, etc are ignored...

		if (
			$self->{'lastTrack'}->{$basename} && 
			$self->{'lastTrack'}->{$basename}->albumid &&
			blessed($self->{'lastTrack'}->{$basename}->album) eq 'Slim::DataStores::DBI::Album' &&
			$self->{'lastTrack'}->{$basename}->album->get('title') eq $album &&
			(!$checkDisc || ($disc eq $self->{'lastTrack'}->{$basename}->album->disc))

			) {

			$albumObj = $self->{'lastTrack'}->{$basename}->album;

			$::d_info && msg("_postCheckAttributes: Same album '$album' than previous track\n");

		} else {

			# Don't use year as a search criteria. Compilations in particular
			# may have different dates for each track...
			# If re-added here then it should be checked also above, otherwise
			# the server behaviour changes depending on the track order!
			# Maybe we need a preference?
			my $search = {
				'title' => $album,
				#'year'  => $track->year,
			};

			# Add disc to the search criteria if needed
			if ($checkDisc) {

				$search->{'disc'} = $disc;

			} elsif ($discc && $discc > 1) {

				# If we're not checking discs - ie: we're in
				# groupdiscs mode, check discc if it exists,
				# in the case where there are multiple albums
				# of the same name by the same artist. bug3254
				$search->{'discc'} = $discc;
			}

			# If we have a compilation bit set - use that instead
			# of trying to match on the artist. Having the
			# compilation bit means that this is 99% of the time a
			# Various Artist album, so a contributor match would fail.
			if ($isCompilation) {

				# in the database this is 0 or 1
				$search->{'compilation'} = $isCompilation;

			} else {

				# Check if the album name is one of the "common album names"
				# we've identified in prefs. If so, we require a match on
				# both album name and primary artist name.
				if (blessed($contributor)) {
					$search->{'contributor'} = $contributor->id;
				}
			}

			($albumObj) = eval { Slim::DataStores::DBI::Album->search($search) };

			$::d_info && msg("_postCheckAttributes: Searched for album '$album'\n") if $albumObj;

			if ($@) {
				msg("_postCheckAttributes: There was an error searching for an album match!\n");
				msg("_postCheckAttributes: Error message: [$@]\n");
				require Data::Dumper;
				print Data::Dumper::Dumper($search);
			}

			# We've found an album above - and we're not looking
			# for a multi-disc or compilation album, check to see
			# if that album already has a track number that
			# corresponds to our current working track and that
			# the other track is not in our current directory. If
			# so, then we need to create a new album. If not, the
			# album object is valid.
			if ($albumObj && $checkDisc && !$isCompilation) {

				my %tracks     = map { $_->tracknum, $_ } $albumObj->tracks;
				my $matchTrack = $tracks{ $track->tracknum };

				if (defined $matchTrack && dirname($matchTrack->url) ne dirname($track->url)) {

					$albumObj = undef;

					$::d_info && msg("_postCheckAttributes: Wrong album '$album' found\n");
				}
			}

			# Didn't match anything? It's a new album - create it.
			if (!$albumObj) {
				
				$::d_info && msg("_postCheckAttributes: Creating album '$album'\n");

				$albumObj = Slim::DataStores::DBI::Album->create({ 
					title => $album,
				});
			}
		}

		# Associate cover art with this album, and keep it cached.
		if (!$self->{'artworkCache'}->{$albumObj->id}) {

			if (!Slim::Music::Import->artwork($albumObj) && (!$track->thumb || !$track->cover)) {

				Slim::Music::Import->artwork($albumObj, $track);
			}
		}
	}

	if (defined($album) && blessed($albumObj) && (!blessed($_unknownAlbum) || $albumObj->title ne $_unknownAlbum->title)) {

		my $sortable_title = Slim::Utils::Text::ignoreCaseArticles($attributes->{'ALBUMSORT'} || $album);

		my %set = ();

		# Add an album artist if it exists.
		$set{'contributor'} = $contributor->id if blessed($contributor);

		# Always normalize the sort, as ALBUMSORT could come from a TSOA tag.
		$set{'titlesort'}   = $sortable_title;

		# And our searchable version.
		$set{'titlesearch'} = Slim::Utils::Text::ignoreCaseArticles($album);

		# Bug 2393 - was fixed here (now obsolete due to further code rework)
		$set{'compilation'} = $isCompilation;

		$set{'musicbrainz_id'} = $attributes->{'MUSICBRAINZ_ALBUM_ID'};

		# Handle album gain tags.
		for my $gainTag (qw(REPLAYGAIN_ALBUM_GAIN REPLAYGAIN_ALBUM_PEAK)) {

			my $shortTag = lc($gainTag);
			   $shortTag =~ s/^replaygain_album_(\w+)$/replay_$1/;

			if ($attributes->{$gainTag}) {

				$attributes->{$gainTag} =~ s/\s*dB//gi;

				$set{$shortTag} = $attributes->{$gainTag};

			} else {

				$set{$shortTag} = undef;
			}
		}

		# Make sure we have a good value for DISCC if grouping
		# or if one is supplied
		if (Slim::Utils::Prefs::get('groupdiscs') || $discc) {
			$discc = max($disc, $discc, $albumObj->discc);
		}

		# Check that these are the correct types. Otherwise MySQL will
		# not accept the values.
		if (defined $disc && $disc =~ /^\d+$/) {
			$set{'disc'} = $disc;
		}

		if (defined $discc && $discc =~ /^\d+$/) {
			$set{'discc'} = $discc;
		}

		if (defined $track->year && $track->year =~ /^\d+$/) {
			$set{'year'} = $track->year;
		}

		$albumObj->set(%set);
		$albumObj->update;

		# Don't add an album to container tracks - See bug 2337
		if (!Slim::Music::Info::isContainer($track, $trackType)) {

			$track->album($albumObj);
		}

		# Now create a contributors <-> album mapping
		if (!$create) {

			# Did the user change the album title?
			if ($albumObj->title ne $album) {

				$albumObj->set('title', $album);
			}

			# Remove all the previous mappings
			Slim::DataStores::DBI::ContributorAlbum->search('album' => $albumObj)->delete_all;

			$albumObj->update;
		}

		while (my ($role, $contributors) = each %{$contributors}) {

			for my $contributor (@{$contributors}) {

				Slim::DataStores::DBI::ContributorAlbum->find_or_create({
					album       => $albumObj,
					contributor => $contributor,
					role        => Slim::DataStores::DBI::Contributor->typeToRole($role),
				});
			}
		}
	}

	# Save any changes - such as album.
	$track->update;

	# Add comments if we have them:
	for my $comment (@{$attributes->{'COMMENT'}}) {

		Slim::DataStores::DBI::Comment->find_or_create({
			'track' => $trackId,
			'value' => $comment,
		});
	}

	# refcount--
	%{$contributors} = ();
}

sub _mergeAndCreateContributors {
	my ($self, $track, $attributes) = @_;

	my %contributors = ();

	# XXXX - This order matters! Album artist should always be first,
	# since we grab the 0th element from the contributors array below when
	# creating the Album.
	my @tags = qw(ALBUMARTIST ARTIST BAND COMPOSER CONDUCTOR);

	for my $tag (@tags) {

		my $contributor = $attributes->{$tag} || next;

		# Is ARTISTSORT/TSOP always right for non-artist
		# contributors? I think so. ID3 doesn't have
		# "BANDSORT" or similar at any rate.
		push @{ $contributors{$tag} }, Slim::DataStores::DBI::Contributor->add({
			'artist'   => $contributor, 
			'brainzID' => $attributes->{"MUSICBRAINZ_${tag}_ID"},
			'role'     => Slim::DataStores::DBI::Contributor->typeToRole($tag),
			'track'    => $track,
			'sortBy'   => $attributes->{$tag.'SORT'},
		});
	}

	return \%contributors;
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
