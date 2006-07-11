package Slim::Schema;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(DBIx::Class::Schema);

use DBIx::Migration;
use File::Basename qw(dirname);
use File::Spec::Functions qw(:ALL);
use List::Util qw(max);
use Scalar::Util qw(blessed);
use Tie::Cache::LRU::Expires;
use URI;

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::SQLHelper;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Text;
use Slim::Utils::Unicode;

# Singleton objects for Unknowns
our ($_unknownArtist, $_unknownGenre, $_unknownAlbum) = ('', '', '');

# Optimization to cache content type for track entries rather than look them up everytime.
tie our %contentTypeCache, 'Tie::Cache::LRU::Expires', EXPIRES => 300, ENTRIES => 128;

# For the VA album merging & scheduler globals.
my ($variousAlbumIds, $vaObj);

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

our $initialized = 0;
my $trackAttrs   = {};

sub init {
	my $class = shift;

	my $source   = sprintf(Slim::Utils::Prefs::get('dbsource'), 'slimserver');
	my $username = Slim::Utils::Prefs::get('dbusername');
	my $password = Slim::Utils::Prefs::get('dbpassword');
	my ($driver) = ($source =~ /^dbi:(\w+):/);

	# Bug 3443 - append a socket if needed
	# Windows doesn't use named sockets (it uses TCP instead)
	if (Slim::Utils::OSDetect::OS() ne 'win' && $source =~ /mysql/i && $source !~ /mysql_socket/i) {

		if (Slim::Utils::MySQLHelper->socketFile) {
			$source .= sprintf(':mysql_socket=%s', Slim::Utils::MySQLHelper->socketFile);
		}
	}

	# For custom exceptions
	$class->storage_type('Slim::Schema::Storage');

	$class->connection($source, $username, $password, { 
		RaiseError => 1,
		AutoCommit => 1,
		PrintError => 1,
		Taint      => 1,

	}) or do {

		errorMsg("Couldn't connect to database! Fatal error: [$!] Exiting!\n");
		bt();
		exit;
	};

	my $dbh = $class->storage->dbh || do {

		# Not much we can do if there's no DB.
		errorMsg("Couldn't connect to database! Fatal error: [$!] Exiting!\n");
		bt();
		exit;
	};

	# Tell the DB that we're handing it UTF-8
	# MySQL < 4.1 doesn't support this - which really shouldn't matter to
	# us. But some users *ahem*kdf*ahem* are stuck running 4.0.x
	if (Slim::Utils::MySQLHelper->mysqlVersion($dbh) > 4.0) {

		eval { $dbh->do('SET NAMES UTF8;') };
	}

	# Migrate to the latest schema version - see SQL/$driver/schema_\d+_up.sql
	my $dbix = DBIx::Migration->new({
		'dsn'      => $source,
		'username' => $username,
		'password' => $password,
		'dir'      => catdir(Slim::Utils::OSDetect::dirsFor('SQL'), $driver),
	});

	$dbix->migrate;

	$::d_info && msgf("Connected to database $source - schema version: [%d]\n", $dbix->version);

	# Load the DBIx::Class::Schema classes we've defined.
	# If you add a class to the schema, you must add it here as well.
	$class->load_classes(qw/
		Age
		Album
		Comment
		Contributor
		ContributorAlbum
		ContributorTrack
		Genre
		GenreTrack
		MetaInformation
		Playlist
		PlaylistTrack
		Rescan
		Track 
		Year 
	/);

	# Build all our class accessors and populate them.
	for my $accessor (qw(lastTrackURL lastTrack trackAttrs driver)) {

		$class->mk_classaccessor($accessor);
	}

	for my $name (qw(lastTrack)) {

		$class->$name({});
	}

	$trackAttrs = Slim::Schema::Track->attributes;
	$class->driver($driver);

	$class->toggleDebug($::d_sql);

	$initialized = 1;
}

sub throw_exception {
	my ($self, $msg) = @_;

	# XXXX - txn_do doesn't actually need to be called as an instance
	# method. That check has been removed in -current. However, we'll just
	# ignore it until we upgrade.
	if ($msg ne 'Cannot execute txn_do as a class method') {

		errorMsg($msg);
		errorMsg("Backtrace follows:\n");
		bt();
	}
}

sub toggleDebug {
	my $class = shift;
	my $debug = shift;

	$class->storage->debug($debug);

	if ($::LogTimestamp) {

		$class->storage->debugcb(sub {

			#if ($_[0] eq 'SELECT') {
			#	Slim::Utils::Misc::bt();
			#}

			Slim::Utils::Misc::msg($_[1]);
		});
	}
}

sub disconnect {
	my $class = shift;

	eval { $class->storage->dbh->disconnect };

	$initialized = 0;
}

sub rs {
	my $class   = shift;
	my $rsClass = shift;

	return $class->resultset(ucfirst($rsClass), @_);
}

sub search {
	my $class   = shift;
	my $rsClass = shift;

	return $class->resultset(ucfirst($rsClass))->search(@_);
}

sub single {
	my $class   = shift;
	my $rsClass = shift;

	return $class->resultset(ucfirst($rsClass))->single(@_);
}

sub count {
	my $class   = shift;
	my $rsClass = shift;

	return $class->resultset(ucfirst($rsClass))->count(@_);
}

sub find {
	my $class   = shift;
	my $rsClass = ucfirst(shift);

	my $object  = eval { $class->resultset($rsClass)->find(@_) };

	if ($@) {
		bt();
		errorMsg("Slim::Schema->find() failed: [$@]. Returning undef\n");
		return undef;
	}

	# If we're requesting a Track - make sure it's still on disk and valid.
	if ($rsClass eq 'Track') {
		$object = $class->_checkValidity($object)
	}

	return $object;
}

sub lastRescanTime {
	my $class = shift;

	return $class->single('MetaInformation', { 'name' => 'lastRescanTime' })->value;
}

sub wipeDB {
	my $class = shift;

	$::d_import && msg("Import: Start schema_clear\n");

	$class->txn_do(sub {

		Slim::Utils::SQLHelper->executeSQLFile(
			$class->driver, $class->storage->dbh, "schema_clear.sql"
		);
	});

	$::d_import && msg("Import: End schema_clear\n");
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
	my $self = shift;
	my $args = shift;

	# Handle both old and new calling methods.
	# We silently handle the single arg case to fetch a URL.
	my $url      = $args;
	my $create   = 0;
	my $readTag  = 0;
	my $commit   = 0;
	my $playlist = 0;

	if (@_) {
		bt();
		msg("Warning objectForUrl callers - please update to pass named args!\n");

		($url, $create, $readTag) = ($args, @_);

	} elsif (ref($args) eq 'HASH') {

		$url      = $args->{'url'};
		$create   = $args->{'create'};
		$readTag  = $args->{'readTag'} || $args->{'readTags'};
		$commit   = $args->{'commit'};
		$playlist = $args->{'playlist'};
	}

	# Confirm that the URL itself isn't an object (see bug 1811)
	# XXX - exception should go here. Comming soon.
	if (blessed($url) || ref($url)) {

		# returning already blessed url
		return $url;
	}

	if (!$url) {
		errorMsg("objectForUrl: Null track request!\n"); 
		bt();
		return undef;
	}

	# Create a canonical version, to make sure we only have one copy.
	$url = URI->new($url)->canonical->as_string;

	# Pull the track object for the DB
	my $track = $self->_retrieveTrack($url, $playlist);

	# _retrieveTrack will always return undef or a track object
	if ($track && !$create && !$playlist) {
		$track = $self->_checkValidity($track);
	}

	# _checkValidity will always return undef or a track object
	if (!$track && $create) {

		$track = $self->updateOrCreate({
			'url'      => $url,
			'readTags' => $readTag,
			'commit'   => $commit,
			'playlist' => $playlist,
		});
	}

	return $track;
}

sub objectForId {
	my $self  = shift;

	msg("Warning: objectForId is deprecated. Please use ->find instead.\n");

	return $self->find(@_);
}

# Create a new track with the given attributes
sub newTrack {
	my $self = shift;
	my $args = shift;

	my $url           = $args->{'url'};
	my $attributeHash = $args->{'attributes'} || {};
	my $playlist      = $args->{'playlist'} || 0;
	my $source        = $playlist ? 'Playlist' : 'Track';

	my $deferredAttributes = {};

	if (!$url) {
		errorMsg("objectForUrl: Null track request!\n"); 
		bt();
		return undef;
	}

	$::d_info && msg("New $source for $url\n");

	# Default the tag reading behaviour if not explicitly set
	if (!defined $args->{'readTags'}) {
		$args->{'readTags'} = 'default';
	}

	# Read the tag, and start populating the database.
	if ($args->{'readTags'}) {

		$::d_info && msg("readTag was ". $args->{'readTags'}  ." for $url\n");

		$attributeHash = { %{$self->_readTags($url)}, %$attributeHash  };
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

		if (defined $val && exists $trackAttrs->{$key}) {

			$::d_info && msg("Adding $url : $key to $val\n");

			$columnValueHash->{$key} = $val;
		}
	}

	# Tag and rename set URL to the Amazon image path. Smack that.
	# We don't use it anyways.
	$columnValueHash->{'url'} = $url;

	# Create the track - or bail. ->throw_exception will emit a backtrace.
	my $track = Slim::Schema->resultset($source)->create($columnValueHash);

	if ($@ || !$track) {
		errorMsg("newTrack: Couldn't create $source for $url : $@\n");
		return;
	}

	# Now that we've created the track, and possibly an album object -
	# update genres, etc - that we need the track ID for.
	if (!$playlist) {

		$self->_postCheckAttributes({
			'track'      => $track,
			'attributes' => $deferredAttributes,
			'create'     => 1,
		});

		if ($columnValueHash->{'audio'}) {

			$self->lastTrackURL($url);
			$self->lastTrack->{dirname($url)} = $track;
		}
	}

	$self->forceCommit if $args->{'commit'};

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
	my $playlist      = $args->{'playlist'};

	# XXX - exception should go here. Comming soon.
	my $track = blessed($urlOrObj) ? $urlOrObj : undef;
	my $url   = blessed($track) && $track->can('get') ? $track->get('url') : URI->new($urlOrObj)->canonical->as_string;

	if (!defined($url) || ref($url)) {
		require Data::Dumper;
		print Data::Dumper::Dumper($attributeHash);
		errorMsg("updateOrCreate: No URL specified for updateOrCreate\n");
		bt();
		return undef;
	}

	# Track will be defined or not based on the assignment above.
	if (!defined $track) {
		$track = $self->_retrieveTrack($url, $playlist);
	}

	# XXX - exception should go here. Comming soon.
	# _retrieveTrack will always return undef or a track object
	if ($track) {

		# Check the timestamp & size to make sure they've not changed.
		if ($checkMTime && Slim::Music::Info::isFileURL($url) && !$self->_hasChanged($track, $url)) {

			$::d_info && msg("Track is still valid! Skipping update! $url\n");

			return $track;
		}

		# Bug: 2335 - readTags is set in Slim::Formats::Playlists::CUE - when
		# we create/update a cue sheet to have a CT of 'cur'
		if (defined $attributeHash->{'CONTENT_TYPE'} && $attributeHash->{'CONTENT_TYPE'} eq 'cur') {
			$readTags = 0;
		}

		$::d_info && msg("Merging entry for $url readTags is: [$readTags]\n");

		# Force a re-read if requested.
		# But not for remote / non-audio files.
		if ($readTags && $track->get('audio') && !$track->get('remote')) {

			$attributeHash = { %{$self->_readTags($url)}, %$attributeHash  };
		}

		my $deferredAttributes;
		($attributeHash, $deferredAttributes) = $self->_preCheckAttributes({
			'url'        => $url,
			'attributes' => $attributeHash,
		});

		while (my ($key, $val) = each %$attributeHash) {

			$key = lc($key);

			if (defined $val && $val ne '' && exists $trackAttrs->{$key}) {

				$::d_info && msg("Updating $url : $key to $val\n");

				$track->set_column($key, $val);
			}
		}

		# _postCheckAttributes does an update
		if (!$playlist) {

			$self->_postCheckAttributes({
				'track'      => $track,
				'attributes' => $deferredAttributes,
			});
		}

		$self->forceCommit if $commit;

	} else {

		$track = $self->newTrack({
			'url'        => $url,
			'attributes' => $attributeHash,
			'readTags'   => $readTags,
			'commit'     => $commit,
			'playlist'   => $playlist,
		});
	}

	if ($track && $attributeHash->{'CONTENT_TYPE'}) {
		$contentTypeCache{$url} = $attributeHash->{'CONTENT_TYPE'};
	}

	return $track;
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

	$::d_import && msg("Import: Starting db garbage collection..\n");

	my $iterator = $self->search('Track', { 'audio' => 1 });
	my $count    = $iterator->count;
	my $progress = Slim::Utils::ProgressBar->new({ 'total' => $count });

	# fetch one at a time to keep memory usage in check.
	while (my $track = $iterator->next) {

		# _hasChanged will delete tracks
		if ($self->_hasChanged($track, $track->get('url'))) {

			$track = undef;
		}

		$progress->update if $progress;
	}

	$progress->final($count) if $progress;

	$::d_import && msg("Import: Finished with stale track cleanup.\n");

	# Walk the Album, Contributor and Genre tables to see if we have any dangling
	# entries, pointing to non-existant tracks.
	Slim::Schema::Contributor->removeStaleDBEntries('contributorTracks');
	Slim::Schema::Album->removeStaleDBEntries('tracks');
	Slim::Schema::Genre->removeStaleDBEntries('genreTracks');

	# We're done.
	$self->forceCommit;

	Slim::Music::Import->endImporter('cleanupStaleEntries');

	return 1;
}

sub variousArtistsObject {
	my $self = shift;

	my $vaString = Slim::Music::Info::variousArtistString();

	# Fetch a VA object and/or update it's name if the user has changed it.
	# XXX - exception should go here. Comming soon.
	if (!blessed($vaObj) || !$vaObj->can('name')) {

		$vaObj  = $self->resultset('Contributor')->find_or_create({
			'name'       => $vaString,
			'namesearch' => Slim::Utils::Text::ignoreCaseArticles($vaString),
			'namesort'   => Slim::Utils::Text::ignoreCaseArticles($vaString),
		}, { 'key' => 'namesearch' });
	}

	if ($vaObj && $vaObj->name ne $vaString) {

		$vaObj->name($vaString);
		$vaObj->namesort( Slim::Utils::Text::ignoreCaseArticles($vaString) );
		$vaObj->namesearch( Slim::Utils::Text::ignoreCaseArticles($vaString) );
		$vaObj->update;
	}

	return $vaObj;
}

# Wrapper for the common case of checking the level below the current one
# (always Albums), to see if any VA albums exist.
sub variousArtistsAlbumCount {
	my $class = shift;
	my $find  = shift;

	my %attr = ( 'group_by' => 'me.id' );
	my @join = ( 'contributorAlbums' );

	# We always want to search for compilation
	$find->{'me.compilation'} = 1;

	# And the VA object.
	$find->{'contributorAlbums.contributor'} = $class->variousArtistsObject->id;

	if (exists $find->{'genre.id'}) {

		$find->{'genreTracks.genre'} = delete $find->{'genre.id'};
		push @join, { 'tracks' => 'genreTracks' };

	} elsif (exists $find->{'genre.name'}) {

		push @join, { 'tracks' => { 'genreTracks' => 'genre' } };
	}

	if (my $roles = $class->artistOnlyRoles) {

		$find->{'contributorAlbums.role'} = { 'in' => $roles };
	}

	$attr{'join'} = \@join;

	return $class->count('Album', $find, \%attr);
}

sub trackCount {
	my $self = shift;

	return $self->count('Track');
}

sub totalTime {
	my $self = shift;

	# Pull out the total time dynamically.
	# What a breath of fresh air. :)
	return $self->search('Track', undef, {

		'select' => [ \'SUM(secs)' ],
		'as'     => [ 'sum' ],

	})->single->get_column('sum');
}

# This is a post-process on the albums and contributor_tracks tables, in order
# to identify albums which are compilations / various artist albums - by
# virtue of having more than one artist.
sub mergeVariousArtistsAlbums {
        my $self = shift;

	my $vaObjId = $self->variousArtistsObject->id;
	my $role    = Slim::Schema::Contributor->typeToRole('ARTIST');

	my $cursor  = $self->search('Album', {

		'me.compilation' => undef,
		'me.title'       => { '!=' => string('NO_ALBUM') },

	})->distinct;

	my $progress = undef;
	my $count    = $cursor->count;

	if ($count) {
		$progress = Slim::Utils::ProgressBar->new({ 'total' => $count });
	}

	# fetch one at a time to keep memory usage in check.
	while (my $albumObj = $cursor->next) {

		my %trackArtists      = ();
		my $markAsCompilation = 0;

		# Bug 2066: If the user has an explict Album Artist set -
		# don't try to mark it as a compilation. So only fetch ARTIST roles.
		my $tracks = $albumObj->tracks({ 'contributorTracks.role' => $role }, { 'prefetch' => 'contributorTracks' });

		while (my $track = $tracks->next) {

			# Don't inflate the contributor object.
			my @contributors = sort map {
				$_->get_column('contributor')
			} $track->search_related('contributorTracks')->all;

			# Create a composite of the artists for the track to compare below.
			$trackArtists{ join(':', @contributors) } = 1;
		}

		# Bug 2418 - If the tracks have a hardcoded artist of 'Various Artists' - mark the album as a compilation.
		if (scalar values %trackArtists > 1) {

			$markAsCompilation = 1;

		} else {

			my ($artistId) = keys %trackArtists;

			# Use eq here instead of ==, because the artistId
			# might be a composite from above, if all of the
			# tracks in an album have the same (multiple) artists.
			if ($artistId && $artistId eq $vaObjId) {

				$markAsCompilation = 1;
			}
		}

		if ($markAsCompilation) {

			$::d_import && msgf("Import: Marking album: [%s] as Various Artists.\n", $albumObj->title);

			$albumObj->compilation(1);
			$albumObj->contributor($vaObjId);
			$albumObj->update;

			# And update the contributor_albums table.
			$self->resultset('ContributorAlbum')->find_or_create({
				'album'       => $albumObj->id,
				'contributor' => $vaObjId,
				'role'        => $role,
			});

		}

		$progress->update if $progress;
	}

	$progress->final($count) if $progress;

	Slim::Music::Import->endImporter('mergeVariousAlbums');
}

sub wipeCaches {
	my $self = shift;

	$self->forceCommit;

	%contentTypeCache = ();

	# clear the references to these singletons
	$vaObj            = undef;

	$self->lastTrackURL('');
	$self->lastTrack({});

	$::d_import && msg("Import: Wiped all in-memory caches.\n");
}

# Wipe all data in the database
sub wipeAllData {
	my $self = shift;

	# clear the references to these singletons
	$_unknownArtist = '';
	$_unknownGenre  = '';
	$_unknownAlbum  = '';

	$self->wipeCaches;
	$self->wipeDB;

	$::d_import && msg("Import: Wiped info database\n");
}

# Force a commit of the database
sub forceCommit {
	my $self = shift;

	if (!$initialized) {

		errorMsg("forceCommit: Trying to commit transactions before DB is initialized!\n");
		return;
	}

	$self->lastTrackURL('');
	$self->lastTrack({});

	if (!$self->storage->dbh->{'AutoCommit'}) {

		$::d_info && msg("forceCommit: syncing to the database.\n");

		eval { $self->storage->dbh->commit };

		if ($@) {
			errorMsg("forceCommit: Couldn't commit transactions to DB: [$@]\n");
			return;
		}
	}
}

sub _readTags {
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

	# Populate the DB with information for the remote URL now - and not at the time we play.
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
			if ($INC{'MP3/Info.pm'} && defined($MP3::Info::mp3_genres[$1])) {

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

	# Bug 2996 - check for multiple DISC tags.
	if (ref($attributesHash->{'DISC'}) eq 'ARRAY') {

		$attributesHash->{'DISC'} = $attributesHash->{'DISC'}->[0];
	}

	if (-e $filepath) {
		# cache the file size & date
		($attributesHash->{'FILESIZE'}, $attributesHash->{'TIMESTAMP'}) = (stat($filepath))[7,9];
	}

	# Only set if we couldn't read it from the file.
	$attributesHash->{'CONTENT_TYPE'} ||= $type;

	# Bug: 2381 - FooBar2k seems to add UTF8 boms to their values.
	while (my ($tag, $value) = each %{$attributesHash}) {

		if (defined $attributesHash->{$tag}) {
			$attributesHash->{$tag} =~ s/$Slim::Utils::Unicode::bomRE//;
		}
	}

	return $attributesHash;
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
	if (scalar keys %roles != Slim::Schema::Contributor->totalContributorRoles) {

		return [ sort map { Slim::Schema::Contributor->typeToRole($_) } keys %roles ];
	}

	return undef;
}

#
# Private methods:
#

sub _retrieveTrack {
	my ($self, $url, $playlist) = @_;

	return undef if !$url;
	return undef if ref($url);

	my $track;

	# Keep the last track per dirname.
	my $dirname = dirname($url);
	my $source  = $playlist ? 'Playlist' : 'Track';

	if (defined $self->lastTrackURL && $url eq $self->lastTrackURL) {

		$track = $self->lastTrack->{$dirname};

	} else {

		$track = $self->resultset($source)->single({ 'url' => $url });
	}

	# XXX - exception should go here. Comming soon.
	if (blessed($track)) {

		if (!$playlist || $track->audio) {
			$self->lastTrackURL($url);
			$self->lastTrack->{$dirname} = $track;
		}

		return $track;
	}

	return undef;
}

sub _checkValidity {
	my $self  = shift;
	my $track = shift;

	# XXX - exception should go here. Comming soon.
	return undef unless blessed($track);
	return undef unless $track->can('get');

	my $url = $track->get('url');

	$::d_info && msg("_checkValidity: Checking to see if $url has changed.\n");

	# Don't check for remote tracks, or things that aren't audio
	if ($track->get('audio') && !$track->get('remote') && $self->_hasChanged($track, $url)) {

		$::d_info && msg("_checkValidity: Re-reading tags from $url as it has changed.\n");

		# Do a cascading delete for has_many relationships - this will
		# clear out Contributors, Genres, etc.
		$track->delete;

		$track = $self->updateOrCreate({
			'url'      => $url,
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

		my $filesize  = $track->get('filesize');
		my $timestamp = $track->get('timestamp');

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

		# Be sure to clear the track out of the cache as well.
		if ($self->lastTrackURL && $url eq $self->lastTrackURL) {
			$self->lastTrackURL('');
		}

		my $dirname = dirname($url);

		if (defined $self->lastTrack->{$dirname} && $self->lastTrack->{$dirname}->url eq $url) {
			delete $self->lastTrack->{$dirname};
		}

		$track->delete;
		$track = undef;

		$self->forceCommit;

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

			$attributes->{ uc($tagMapping{lc $key}) } = delete $attributes->{$key};
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
	for my $tag (qw(YEAR DISC DISCC)) {

		if (defined $attributes->{$tag} && $attributes->{$tag} !~ /^\d+$/) {

			delete $attributes->{$tag};
		}
	}

	if (defined $attributes->{'TRACKNUM'}) {
		$attributes->{'TRACKNUM'} = Slim::Music::Info::cleanTrackNumber($attributes->{'TRACKNUM'});
	}

	# Munge the replaygain values a little
	for my $gainTag (qw(REPLAYGAIN_TRACK_GAIN REPLAYGAIN_TRACK_PEAK)) {

		my $shortTag = $gainTag;
		   $shortTag =~ s/^REPLAYGAIN_TRACK_(\w+)$/REPLAY_$1/;

		if (defined $attributes->{$gainTag}) {

			$attributes->{$shortTag} = delete $attributes->{$gainTag};
			$attributes->{$shortTag} =~ s/\s*dB//gi;
		}
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
	if (!blessed($track) || !$track->can('get_columns')) {
		return undef;
	}

	# Don't bother with directories / lnks. This makes sure "No Artist",
	# etc don't show up if you don't have any.
	my %cols = $track->get_columns;

	my ($trackId, $trackUrl, $trackType, $trackAudio, $trackRemote) = 
		(@cols{qw/id url content_type audio remote/});

	if (!defined $trackType || $trackType eq 'dir' || $trackType eq 'lnk') {

		$track->update;

		return undef;
	}

	# Make a local variable for COMPILATION, that is easier to handle
	my $isCompilation = undef;

	if (defined $attributes->{'COMPILATION'}) {

		if ($attributes->{'COMPILATION'} =~ /^yes$/i || $attributes->{'COMPILATION'} == 1) {

			$isCompilation = 1;

		} elsif ($attributes->{'COMPILATION'} =~ /^no$/i || $attributes->{'COMPILATION'} == 0) {

			$isCompilation = 0;
		}
	}

	# We don't want to add "No ..." entries for remote URLs, or meta
	# tracks like iTunes playlists.
	my $isLocal = $trackAudio && !$trackRemote ? 1 : 0;

	# Genre addition. If there's no genre for this track, and no 'No Genre' object, create one.
	my $genre = $attributes->{'GENRE'};

	if ($create && $isLocal && !$genre && (!defined $_unknownGenre || ref($_unknownGenre) ne 'Slim::Schema::Genre')) {

		$_unknownGenre = $self->resultset('Genre')->find_or_create({
			'name'       => string('NO_GENRE'),
			'namesort'   => Slim::Utils::Text::ignoreCaseArticles(string('NO_GENRE')),
			'namesearch' => Slim::Utils::Text::ignoreCaseArticles(string('NO_GENRE')),
		}, { 'key' => 'namesearch' });

		Slim::Schema::Genre->add($_unknownGenre->name, $track);

	} elsif ($create && $isLocal && !$genre) {

		Slim::Schema::Genre->add($_unknownGenre->name, $track);

	} elsif ($create && $isLocal && $genre) {

		Slim::Schema::Genre->add($genre, $track);

	} elsif (!$create && $isLocal && $genre && $genre ne $track->genres->single->name) {

		# Bug 1143: The user has updated the genre tag, and is
		# rescanning We need to remove the previous associations.
		$track->genreTracks->delete_all;

		Slim::Schema::Genre->add($genre, $track);
	}

	# Walk through the valid contributor roles, adding them to the database for each track.
	my $contributors     = $self->_mergeAndCreateContributors($track, $attributes, $isCompilation, $isLocal);
	my $foundContributor = scalar keys %{$contributors};

	# Create a singleton for "No Artist"
	if ($create && $isLocal && !$foundContributor && !$_unknownArtist) {

		$_unknownArtist = $self->resultset('Contributor')->find_or_create({
			'name'       => string('NO_ARTIST'),
			'namesort'   => Slim::Utils::Text::ignoreCaseArticles(string('NO_ARTIST')),
			'namesearch' => Slim::Utils::Text::ignoreCaseArticles(string('NO_ARTIST')),
		}, { 'key' => 'namesearch' });

		Slim::Schema::Contributor->add({
			'artist' => $_unknownArtist->name,
			'role'   => Slim::Schema::Contributor->typeToRole('ARTIST'),
			'track'  => $trackId,
		});

		push @{ $contributors->{'ARTIST'} }, $_unknownArtist;

	} elsif ($create && $isLocal && !$foundContributor) {

		# Otherwise - reuse the singleton object, since this is the
		# second time through.
		Slim::Schema::Contributor->add({
			'artist' => $_unknownArtist->name,
			'role'   => Slim::Schema::Contributor->typeToRole('ARTIST'),
			'track'  => $trackId,
		});

		push @{ $contributors->{'ARTIST'} }, $_unknownArtist;
	}

	# The "primary" contributor
	my $contributor = ($contributors->{'ALBUMARTIST'}->[0] || $contributors->{'ARTIST'}->[0]);

	# Now handle Album creation
	my $album    = $attributes->{'ALBUM'};
	my $disc     = $attributes->{'DISC'};
	my $discc    = $attributes->{'DISCC'};

	# we may have an album object already..
	# But mark it undef first - bug 3685
	my $albumObj = undef;

	if (!$create && $isLocal) {
		$albumObj = $track->album;
	}

	# Create a singleton for "No Album"
	# Album should probably have an add() method
	if ($create && $isLocal && !$album && !$_unknownAlbum) {

		$_unknownAlbum = $self->resultset('Album')->find_or_create({
			'title'       => string('NO_ALBUM'),
			'titlesort'   => Slim::Utils::Text::ignoreCaseArticles(string('NO_ALBUM')),
			'titlesearch' => Slim::Utils::Text::ignoreCaseArticles(string('NO_ALBUM')),
			'compilation' => $isCompilation,
		}, { 'key' => 'titlesearch' });

		$track->album($_unknownAlbum->id);
		$albumObj = $_unknownAlbum;

	} elsif ($create && $isLocal && !$album && blessed($_unknownAlbum)) {

		$track->album($_unknownAlbum->id);
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
		#
		# For some reason here we do not apply the same criterias as below:
		# Path, compilation, etc are ignored...
		#
		# Be sure to use get_column() for the title equality check, as
		# get() doesn't run the UTF-8 trigger, and ->title() calls
		# Slim::Schema::Album->title() which has different behavior.

		my ($t, $a); # temp vars to make the conditional sane
		if (
			($t = $self->lastTrack->{$basename}) && 
			$t->get('album') &&
			blessed($a = $t->album) eq 'Slim::Schema::Album' &&
			$a->get_column('title') eq $album &&
			(!$checkDisc || ($disc eq ($a->disc || 0)))

			) {

			$albumObj = $a;

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

			# Bug 3662 - Only check for undefined/null values if the
			# values are undefined.
			$search->{'disc'}  = undef if !defined $disc; 
			$search->{'discc'} = undef if !defined $disc && !defined $discc;

			# If we have a compilation bit set - use that instead
			# of trying to match on the artist. Having the
			# compilation bit means that this is 99% of the time a
			# Various Artist album, so a contributor match would fail.
			if (defined $isCompilation) {

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

			$albumObj = $self->single('Album', $search);

			$::d_info && msg("_postCheckAttributes: Searched for album '$album'\n");

			# We've found an album above - and we're not looking
			# for a multi-disc or compilation album, check to see
			# if that album already has a track number that
			# corresponds to our current working track and that
			# the other track is not in our current directory. If
			# so, then we need to create a new album. If not, the
			# album object is valid.
			if ($albumObj && $checkDisc && !defined $isCompilation) {

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

				$albumObj = $self->resultset('Album')->create({ 'title' => $album });
			}
		}
	}

	if (blessed($albumObj) && !$self->_albumIsUnknownAlbum($albumObj)) {

		my $sortable_title = Slim::Utils::Text::ignoreCaseArticles($attributes->{'ALBUMSORT'} || $album);

		my %set = ();

		# Add an album artist if it exists.
		# But set the album artist to various if there is no album artist.
		if ($isCompilation && !$contributors->{'ALBUMARTIST'}) {

			$set{'contributor'} = $self->variousArtistsObject->id;

		} elsif (blessed($contributor)) {

			$set{'contributor'} = $contributor->id;
		}

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

			$discc = max(($disc || 0), ($discc || 0), ($albumObj->discc || 0));

			if ($discc == 0) {
				$discc = undef;
			}
		}

		# Check that these are the correct types. Otherwise MySQL will not accept the values.
		if (defined $disc && $disc =~ /^\d+$/) {
			$set{'disc'} = $disc;
		} else {
			$set{'disc'} = undef;
		}

		if (defined $discc && $discc =~ /^\d+$/) {
			$set{'discc'} = $discc;
		} else {
			$set{'discc'} = undef;
		}

		if (defined $track->year && $track->year =~ /^\d+$/) {
			$set{'year'} = $track->year;
		} else {
			$set{'year'} = undef;
		}

		if (!$albumObj->artwork && (!$track->thumb || !$track->cover)) {

			$set{'artwork'} = $track->id;
		}

		$albumObj->set_columns(\%set);
	}

	# Always do this, no matter if we don't have an Album title.
	if (blessed($albumObj)) {

		# Don't add an album to container tracks - See bug 2337
		if (!Slim::Music::Info::isContainer($track, $trackType)) {

			$track->album($albumObj->id);
		}

		# Now create a contributors <-> album mapping
		if (!$create && !$self->_albumIsUnknownAlbum($albumObj)) {

			# Update the album title - the user might have changed it.
			$albumObj->title($album);

			# Remove all the previous mappings
			$self->search('ContributorAlbum', { 'album' => $albumObj->id })->delete_all;
		}

		while (my ($role, $contributors) = each %{$contributors}) {

			for my $contributorObj (@{$contributors}) {

				# XXXX - is this correct? VA albums need to be
				# added to the contributor_album table somehow.
				if ($isCompilation) {
					$contributorObj = $self->variousArtistsObject;
				}

				$self->resultset('ContributorAlbum')->find_or_create({
					'album'       => $albumObj->id,
					'contributor' => $contributorObj->id,
					'role'        => Slim::Schema::Contributor->typeToRole($role),
				});
			}
		}

		$albumObj->update;
	}

	# Save any changes - such as album.
	$track->update;

	# Add comments if we have them:
	for my $comment (@{$attributes->{'COMMENT'}}) {

		$self->resultset('Comment')->find_or_create({
			'track' => $trackId,
			'value' => $comment,
		});
	}

	# refcount--
	%{$contributors} = ();
}

sub _albumIsUnknownAlbum {
	my ($self, $albumObj) = @_;

	if (blessed($_unknownAlbum) && 
	    $albumObj->get_column('title') eq $_unknownAlbum->get_column('title')) {

		return 1;
	}

	return 0;
}

sub _mergeAndCreateContributors {
	my ($self, $track, $attributes, $isCompilation, $isLocal) = @_;

	if (!$isLocal) {
		return;
	}

	my %contributors = ();

	my @tags = qw(ALBUMARTIST ARTIST TRACKARTIST BAND COMPOSER CONDUCTOR);

	# Bug: 2317 & 2638
	#
	# Bring back the TRACKARTIST role.
	#
	# If the user has not explictly set a compilation flag, _and_ the user
	# has explict album artist(s) set, make the artist(s) tags become
	# TRACKARTIST contributors for this track.
	if (!defined $isCompilation) {

		if ($attributes->{'ARTIST'} && $attributes->{'ALBUMARTIST'}) {

			$attributes->{'TRACKARTIST'} = delete $attributes->{'ARTIST'};
		}
	}

	for my $tag (@tags) {

		my $contributor = $attributes->{$tag} || next;

		# Is ARTISTSORT/TSOP always right for non-artist
		# contributors? I think so. ID3 doesn't have
		# "BANDSORT" or similar at any rate.
		push @{ $contributors{$tag} }, Slim::Schema::Contributor->add({
			'artist'   => $contributor, 
			'brainzID' => $attributes->{"MUSICBRAINZ_${tag}_ID"},
			'role'     => Slim::Schema::Contributor->typeToRole($tag),
			'track'    => $track,
			'sortBy'   => $attributes->{$tag.'SORT'},
		});
	}

	return \%contributors;
}

1;

__END__
