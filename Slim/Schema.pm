package Slim::Schema;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Schema

=head1 SYNOPSIS

my $track = Slim::Schema->objectForUrl($url);

=head1 DESCRIPTION

L<Slim::Schema> is the main entry point for all interactions with Logitech Media Server's
database backend. It provides an ORM abstraction layer on top of L<DBI>,
acting as a subclass of L<DBIx::Class::Schema>.

=cut

use strict;

use base qw(DBIx::Class::Schema);

use Digest::MD5 qw(md5_hex);
use File::Basename qw(dirname);
use Scalar::Util qw(blessed);
use Tie::Cache::LRU::Expires;
use URI;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Text;
use Slim::Utils::Prefs;

if (main::LIBRARY) {
	require Slim::Schema::Library;
}
else {
	# We don't really need the contributors handling, but some of its helper methods
	require Slim::Schema::Contributor;
}

use Slim::Schema::RemoteTrack;
use Slim::Schema::RemotePlaylist;

my $log = logger('database.info');

my $prefs = preferences('server');

# Optimization to cache content type for track entries rather than look them up everytime.
tie our %contentTypeCache, 'Tie::Cache::LRU::Expires', EXPIRES => 300, ENTRIES => 128;

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

our $initialized         = 0;
our $trackAttrs          = {};
our $trackPersistentAttrs = {};

our %ratingImplementations = (
	'LOCAL_RATING_STORAGE' => \&_defaultRatingImplementation,
);

# Cache the basic top-level ResultSet objects
my %RS_CACHE = ();

# we should never be called!
sub dbh {
	logBacktrace('dbh is not available without library!');
}

=head1 METHODS

All methods below are class methods on L<Slim::Schema>. Please see
L<DBIx::Class::Schema> for methods on the superclass.

=cut

sub hasLibrary {
	return $initialized;
}

=head2 updateDebug

Check and update debug status for the storage class.
Debugging is normally disabled, but must be enabled if either logging for database.sql or perfmon is required

=cut

sub updateDebug { if (main::LIBRARY) {
	my $class  = shift;
	
	# May not have a DB
	return if !hasLibrary();
	
	my $debug  = (main::INFOLOG && logger('database.sql')->is_info) || main::PERFMON;

	$class->storage->debug($debug);
} }

=head2 throw_exception( $self, $msg )

Override L<DBIx::Class::Schema>'s throw_exception method to use our own error
reporting via L<Slim::Utils::Misc::msg>.

=cut

sub throw_exception {
	my ($self, $msg) = @_;

	logBacktrace($msg);
}

=head2 rs( $class )

Returns a L<DBIx::Class::ResultSet> for the specified class.

A shortcut for resultset()

=cut 

sub rs {
	my $class   = shift;
	my $rsClass = ucfirst shift;
	
	if ( !exists $RS_CACHE{$rsClass} ) {
		$RS_CACHE{$rsClass} = $class->resultset($rsClass);
	}

	return $RS_CACHE{$rsClass};
}

=head2 search( $class, $cond, $attr )

Returns a L<DBIx::Class::ResultSet> for the specified class.

A shortcut for resultset($class)->search($cond, $attr)

=cut 

sub search {
	my $class   = shift;
	my $rsClass = shift;

	return $class->rs(ucfirst($rsClass))->search(@_);
}

=head2 single( $class, $cond )

Returns a single result from a search on the specified class' L<DBIx::Class::ResultSet>

A shortcut for resultset($class)->single($cond)

=cut 

sub single {
	my $class   = shift;
	my $rsClass = shift;

	return $class->rs(ucfirst($rsClass))->single(@_);
}

=head2 count( $class, $cond, $attr )

Returns the count result from a search on the specified class' L<DBIx::Class::ResultSet>

A shortcut for resultset($class)->count($cond, $attr)

=cut 

sub count {
	my $class   = shift;
	my $rsClass = shift;

	return $class->rs(ucfirst($rsClass))->count(@_);
}

=head2 find( $class, $cond, $attr )

Returns an object result from a search on the specified class'
L<DBIx::Class::ResultSet>. This find is done on the class' primary key.

If the requested class is L<Slim::Schema::Track>, a validity check is dne
before returning.

Overrides L<DBIx::Class::ResultSet::find>

=cut 

sub find {
	my $class   = shift;
	my $rsClass = ucfirst(shift);
	
	# If we only have a single attribute and it is not a reference and it is negative
	# then this indicates a remote track.
	if (@_ == 1 && ! ref $_[0] && $_[0] < 0) {
		return Slim::Schema::RemoteTrack->fetchById($_[0]);
	}
	
	return if !$initialized;

	my $object  = eval { $class->rs($rsClass)->find(@_) };

	if ($@) {

		logBacktrace("Failed: [$@]. Returning undef.");

		return undef;
	}

	# If we're requesting a Track - make sure it's still on disk and valid.
	# Do not do this if we're in the scanner, the artwork scanner calls this
	# but we do not need to stat all the files again
	if ( !main::SCANNER && $rsClass eq 'Track' ) {
		$object = $class->_checkValidity($object)
	}

	return $object;
}

=head2 searchTypes()

Returns commmon searchable types - constant values: contributor, album, track.

=cut

# Return the common searchable types.
sub searchTypes {
	my $class = shift;

	return qw(contributor album genre track);
}

=head2 contentType( $urlOrObj ) 

Fetch the content type for a URL or Track Object.

Try and be smart about the order of operations in order to avoid hitting the
database if we can get a simple file extension match.

=cut

sub contentType {
	my ($self, $urlOrObj) = @_;

	# Bug 15779 - if we have it in the cache then just use it
	# This does not even check that $urlOrObj is actually a URL
	# but there should be no practical chance of a key-space clash if it is not.
	if (defined $contentTypeCache{$urlOrObj}) {
		return $contentTypeCache{$urlOrObj};
	}

	my $defaultType = 'unk';
	my $contentType = $defaultType;

	# See if we were handed a track object already, or just a plain url.
	my ($track, $url, $blessed) = _validTrackOrURL($urlOrObj);

	# We can't get a content type on a undef url
	if (!defined $url) {
		return $defaultType;
	}

	# Try again for a cache hit - return immediately.
	if (defined $contentTypeCache{$url}) {
		return $contentTypeCache{$url};
	}

	# Track will be a blessed object if it's defined.
	# If we have an object - return from that.
	if ($track) {

		$contentType = $track->content_type;

	} else {

		# Otherwise, try and pull the type from the path name and avoid going to the database.
		$contentType = Slim::Music::Info::typeFromPath($url);
	}

	# Nothing from the path, and we don't have a valid track object - fetch one.
	if ((!defined $contentType || $contentType eq $defaultType) && !$track) {

		$track   = $self->objectForUrl($url);

		if (isaTrack($track)) {

			$contentType = $track->content_type;
		}
	}

	# Nothing from the object we already have in the db.
	if ((!defined $contentType || $contentType eq $defaultType) && $blessed) {

		$contentType = Slim::Music::Info::typeFromPath($url);
	} 

	# Only set the cache if we have a valid contentType
	if (defined $contentType && $contentType ne $defaultType) {

		$contentTypeCache{$url} = $contentType;
	}

	return $contentType;
}

# The contentTypeCache can used above can erroneously be set to type inferred from url path - allow it to be cleared
sub clearContentTypeCache {
	my ($self, $urlOrObj) = @_;
	delete $contentTypeCache{$urlOrObj};
}

=head2 objectForUrl( $args )

The workhorse for getting L<Slim::Schema::Track> or L<Slim::Schema::Playlist>
objects from the database.

Based on arguments, will try and search for the url in the database, or
optionally create it if it does not already exist.

Required $args:

=over 4

=item * 

The URL to look for.

=back

Optional $args:

=over 4

=item * create

Create the object (defaults to L<Slim::Schema::Track>) if it does not exist.

=item * readTags

Read metadata tags from the specified file or url.

=item * commit

Commit to the database (if not in AutoCommit mode).

=item * playlist

Find or create the object as a L<Slim::Schema::Playlist>.

=back

Returns a new L<Slim::Schema::Track> or L<Slim::Schema::Playlist> object on success.

=cut

sub objectForUrl {
	my $self = shift;
	my $args = shift;

	# Handle both old and new calling methods.
	# We silently handle the single arg case to fetch a URL.
	my $url        = $args;
	my $create     = 0;
	my $readTag    = 0;
	my $commit     = 0;
	my $playlist   = 0;
	my $checkMTime = 1;
	my $playlistId;

	if (@_) {

		logBacktrace("Callers - please update to pass named args!");

		($url, $create, $readTag) = ($args, @_);

	} elsif (ref($args) eq 'HASH') {

		$url        = $args->{'url'};
		$create     = $args->{'create'};
		$readTag    = $args->{'readTag'} || $args->{'readTags'};
		$commit     = $args->{'commit'};
		$playlist   = $args->{'playlist'};
		$checkMTime = $args->{'checkMTime'} if defined $args->{'checkMTime'};
		$playlistId = $args->{'playlistId'};
	}

	# Confirm that the URL itself isn't an object (see bug 1811)
	# XXX - exception should go here. Coming soon.
	if (blessed($url) || ref($url)) {

		# returning already blessed url
		return $url;
	}

	if (!$url) {

		logBacktrace("Null track request! Returning undef."); 
		return undef;
	}

	# Create a canonical version, to make sure we only have one copy.
	if ( $url =~ /^(file|http)/i ) {
		$url = URI->new($url)->canonical->as_string;
	}

	# Pull the track object for the DB
	my $track = $self->_retrieveTrack($url, $playlist);
	
	# Bug 14648: Check to see if we have a playlist with remote tracks
	if (!$track && defined $playlistId && Slim::Music::Info::isRemoteURL($url)) {

		if (my $playlistObj = $self->find('Playlist', $playlistId)) {
			# Parse the playlist file to cause the RemoteTrack objects to be created
			Slim::Formats::Playlists->parseList($playlistObj->url);
			
			# try again
			$track = $self->_retrieveTrack($url, $playlist);
		}
	}

	# _retrieveTrack will always return undef or a track object
	elsif ($track && $checkMTime && !$create && !$playlist) {
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

=head2 updateOrCreate( $args )

Update the attributes of a track or create one if one doesn't already exist.

Required $args:

=over 4

=item * url

The URL to find or create in the database.

=back

Optional $args:

=over 4

=item * attributes

A hash ref with data to populate the object.

=item * readTags

Read metadata tags from the specified file or url.

=item * commit

Commit to the database (if not in AutoCommit mode).

=item * playlist

Find or create the object as a L<Slim::Schema::Playlist>.

=item * checkMTime

Check to see if the track has changed, if not - don't update.

=back

Returns a new L<Slim::Schema::Track> or L<Slim::Schema::Playlist> object on success.

=cut

sub updateOrCreate {
	my $self = shift;
	my $args = shift;

	my $trackIdOrTrack = $self->updateOrCreateBase($args);
	
	return undef if !defined $trackIdOrTrack;
	
	return $trackIdOrTrack if blessed $trackIdOrTrack;
	
	return Slim::Schema->rs($args->{'playlist'} ? 'Playlist' : 'Track')->find($trackIdOrTrack);
}

# Tries to avoid instantiating a Track object if not needed
sub updateOrCreateBase {
	my $self = shift;
	my $args = shift;

	#
	my $urlOrObj      = $args->{'url'};
	my $attributeHash = $args->{'attributes'} || {};
	my $commit        = $args->{'commit'};
	my $readTags      = $args->{'readTags'} || 0;
	my $checkMTime    = $args->{'checkMTime'};
	my $playlist      = $args->{'playlist'};
	my $isNew         = $args->{'new'} || 0; # save a query if caller knows the track is new

	my $trackId;
	
	# XXX - exception should go here. Coming soon.
	my ($track, $url, $blessed) = _validTrackOrURL($urlOrObj);

	if (!defined($url) || ref($url)) {

		logBacktrace("No URL specified! Returning undef.");
		logError(Data::Dump::dump($attributeHash)) if main::DEBUGLOG && !$::quiet;

		return undef;
	}

	# make sure we always have an up to date md5 hash value
	$attributeHash->{urlmd5} = md5_hex($url);

	# Short-circuit for remote tracks
	if (Slim::Music::Info::isRemoteURL($url)) {
		my $class = $playlist ? 'Slim::Schema::RemotePlaylist' : 'Slim::Schema::RemoteTrack';

		($attributeHash, undef) = $self->_preCheckAttributes({
			'url'        => $url,
			'attributes' => $attributeHash,
		});
		
		return $class->updateOrCreate($track ? $track : $url, $attributeHash);
	}
	
	return $track unless main::LIBRARY;

	# Track will be defined or not based on the assignment above.
	if ( !defined $track && !$isNew ) {
		$track = $self->_retrieveTrack($url, $playlist);
	}
	
	# XXX - exception should go here. Coming soon.
	# _retrieveTrack will always return undef or a track object
	if ($track) {

		# Check the timestamp & size to make sure they've not changed.
		if ($checkMTime && Slim::Music::Info::isFileURL($url) && !$self->_hasChanged($track, $url)) {

			main::INFOLOG && $log->is_info && $log->info("Track is still valid! Skipping update! $url");

			return $track;
		}

		# Pull the track metadata object for the DB if available
		my $trackPersistent;
		if ( main::STATISTICS ) {
			# XXX native DBI
			$trackPersistent = $track->retrievePersistent();
		}
	
		# Bug: 2335 - readTags is set in Slim::Formats::Playlists::CUE - when
		# we create/update a cue sheet to have a CT of 'cur'
		if (defined $attributeHash->{'CONTENT_TYPE'} && $attributeHash->{'CONTENT_TYPE'} eq 'cur') {
			$readTags = 0;
		}

		main::INFOLOG && $log->is_info && $log->info("Merging entry for $url readTags is: [$readTags]");

		# Force a re-read if requested.
		# But not for non-audio files.
		if ($readTags && $track->get('audio')) {

			$attributeHash = { %{Slim::Formats->readTags($url)}, %$attributeHash  };
		}

		my $deferredAttributes;
		($attributeHash, $deferredAttributes) = $self->_preCheckAttributes({
			'url'        => $url,
			'attributes' => $attributeHash,
		});
		
		# Update timestamp
		$attributeHash->{updated_time} = time();

		while (my ($key, $val) = each %$attributeHash) {

			$key = lc($key);

			if (defined $val && $val ne '' && exists $trackAttrs->{$key}) {

				main::INFOLOG && $log->is_info && $log->info("Updating $url : $key to $val");

				$track->set_column($key, $val);
			}

			# Metadata is only included if it contains a non zero value
			if ( main::STATISTICS && $val && blessed($trackPersistent) && exists $trackPersistentAttrs->{$key} ) {

				main::INFOLOG && $log->is_info && $log->info("Updating persistent $url : $key to $val");

				$trackPersistent->set_column( $key => $val );
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
		
		if ($track && $attributeHash->{'CONTENT_TYPE'}) {
			$contentTypeCache{$url} = $attributeHash->{'CONTENT_TYPE'};
		}

	} else {

		$trackId = $self->_newTrack({
			'url'        => $url,
			'attributes' => $attributeHash,
			'readTags'   => $readTags,
			'commit'     => $commit,
			'playlist'   => $playlist,
		});

	}

	return $track || $trackId;
}

=head2 wipeCaches()

Clears the lastTrack caches, and forces a database commit.

=cut

sub wipeCaches {
	my $self = shift;

	%contentTypeCache = ();

	main::INFOLOG && logger('scan.import')->info("Wiped all in-memory caches.");
}

sub registerRatingImplementation {
	my ( $class, $source, $impl ) = @_;

	if ( ref $impl eq 'CODE' ) {
		$ratingImplementations{$source} = $impl;
	}
}

sub ratingImplementations {
	return [ sort keys %ratingImplementations ];
}

sub rating {}

#
# Private methods:
#

sub _defaultRatingImplementation {
	my ( $track, $rating ) = @_;

	if ( defined $rating ) {
		$track->rating($rating);
		$track->update;
		Slim::Schema->forceCommit;
	}
	
	return $track->rating;
}

sub _retrieveTrack {
	my ($self, $url, $playlist) = @_;

	return undef if !$url;
	return undef if ref($url);

	my $track;
	
	if (Slim::Music::Info::isRemoteURL($url)) {
		return Slim::Schema::RemoteTrack->fetch($url, $playlist);
	}

	# Keep the last track per dirname.
	my $dirname = dirname($url);
	my $source  = $playlist ? 'Playlist' : 'Track';

	if (!$playlist && defined $self->lastTrackURL && $url eq $self->lastTrackURL) {

		$track = $self->lastTrack->{$dirname};

	} else {

		$track = $self->rs($source)->single({ 'url' => $url });
	}

	# XXX - exception should go here. Coming soon.
	if (blessed($track)) {

		if (!$playlist || $track->audio) {
			$self->lastTrackURL($url);
			$self->lastTrack->{$dirname} = $track;
			
			# Set the contentTypeCache entry here is case 
			# it was guessed earlier without knowing the real type
			$contentTypeCache{$url} = $track->content_type;
		}

		return $track;
	}

	return undef;
}

=pod
sub _retrieveTrackMetadata {
	my ($self, $url, $musicbrainz_id) = @_;

	return undef if !$url;
	return undef if ref($url);

	my $trackMetadata;

	$trackMetadata = $self->rs('TrackMetadata')->single({ 'url' => $url });

	if (blessed($trackMetadata)) {
		return $trackMetadata;
	}elsif($musicbrainz_id) {
		$trackMetadata = $self->rs('TrackMetadata')->single({ 'musicbrainz_id' => $musicbrainz_id });
		return $trackMetadata if blessed($trackMetadata);
	}

	return undef;
}
=cut

sub _checkValidity {
	my $self  = shift;
	my $track = shift;

	# XXX - exception should go here. Coming soon.
	return undef unless blessed($track);
	return undef unless $track->can('get');
	
	# Remote tracks are always assumed to be valid
	# Maybe we will add a timeout mechanism later
	return $track if $track->isRemoteURL() || !main::LIBRARY;
	
	my $isDebug = main::DEBUGLOG && $log->is_debug;

	my $url = $track->get('url');

	# Don't check for things that aren't audio
	if ($track->get('audio') && $self->_hasChanged($track, $url)) {

		main::DEBUGLOG && $isDebug && $log->debug("Re-reading tags from $url as it has changed.");

		my $oldid = $track->id;
		
		# Do a cascading delete for has_many relationships - this will
		# clear out Contributors, Genres, etc.
		$track->delete;
		
		# Add the track back into database with the same id as the record deleted.
		my $trackId = $self->_newTrack({
			'id'       => $oldid,
			'url'      => $url,
			'readTags' => 1,
			'commit'   => 1,
		});
		
		$track = Slim::Schema->rs('Track')->find($trackId) if (defined $trackId);
	}
	
	# Track may have been deleted by _hasChanged
	return undef unless $track->in_storage;

	return undef unless blessed($track);
	return undef unless $track->can('url');

	return $track;
}

sub _preCheckAttributes {
	my $self = shift;
	my $args = shift;

	my $url    = $args->{'url'};

	my $deferredAttributes = {};

	# Copy the incoming hash, so we don't modify it
	my $attributes = {};
	my %mappedValues;

	# Normalize attribute names
	while ( my ($key, $val) = each %{ $args->{'attributes'} } ) {
		# don't overwrite mapped values
		next if $mappedValues{$key};

		if ( my $mappedKey = $tagMapping{lc($key)} ) {
			$mappedValues{ uc($mappedKey) } = $attributes->{ uc($mappedKey) } = $val;
		}
		else {
			$attributes->{ $key } = $val;
		}
	}
	
	# Bug 9359, don't allow tags named 'ID'
	if ( exists $attributes->{'ID'} ) {
		delete $attributes->{'ID'};
	}

	# We've seen people with multiple TITLE tags in the wild.. why I don't
	# know. Merge them. Do the same for ALBUM, as you never know.
	for my $tag (qw(TITLE ALBUM)) {

		if ($attributes->{$tag} && ref($attributes->{$tag}) eq 'ARRAY') {

			$attributes->{$tag} = join(' / ', @{$attributes->{$tag}});
		}
	}

	if ($attributes->{'TITLE'}) {
		# Create a canonical title to search against.
		$attributes->{'TITLESEARCH'} = Slim::Utils::Text::ignoreCase($attributes->{'TITLE'}, 1);
	
		if (!$attributes->{'TITLESORT'}) {
			$attributes->{'TITLESORT'} = Slim::Utils::Text::ignoreCaseArticles($attributes->{'TITLE'});
		} else {
			# Always normalize the sort, as TITLESORT could come from a TSOT tag.
			$attributes->{'TITLESORT'} = Slim::Utils::Text::ignoreCaseArticles($attributes->{'TITLESORT'});
		}
	}

	# Remote index.
	$attributes->{'REMOTE'} = Slim::Music::Info::isRemoteURL($url) ? 1 : 0;

	# Some formats stick a DISC tag such as 1/2 or 1-2 into the field.
	if ($attributes->{'DISC'} && $attributes->{'DISC'} =~ m|^(\d+)[-/](\d+)$|) {
		$attributes->{'DISC'}  = $1;
		$attributes->{'DISCC'} ||= $2;
	}

	# Some tag formats - APE? store the type of channels instead of the number of channels.
	if (defined $attributes->{'CHANNELS'}) { 
		if ($attributes->{'CHANNELS'} =~ /stereo/i) {
			$attributes->{'CHANNELS'} = 2;
		} elsif ($attributes->{'CHANNELS'} =~ /mono/i) {
			$attributes->{'CHANNELS'} = 1;
		}
	}

	# Don't insert non-numeric or '0' YEAR fields into the database. Bug: 2610
	# Same for DISC - Bug 2821
	for my $tag (qw(YEAR DISC DISCC BPM CHANNELS)) {

		if ( 
		    defined $attributes->{$tag} 
		    &&
		    ( $attributes->{$tag} !~ /^\d+$/ || $attributes->{$tag} == 0 ) 
		) {
			delete $attributes->{$tag};
		}
	}

	# Bug 4823 - check boundaries set by our tinyint schema.
	for my $tag (qw(DISC DISCC)) {
		next if (!defined $attributes->{$tag});
		$attributes->{$tag} = 254 if ($attributes->{$tag} > 254);
		$attributes->{$tag} = 0 if ($attributes->{$tag} < 0);
	}

	# Bug 3759 - Set undef years to 0, so they're included in the count.
	# Bug 3643 - rating is specified as a tinyint - users running their
	# own SQL server may have strict mode turned on.
	for my $tag (qw(YEAR RATING)) {
		$attributes->{$tag} ||= 0;
	}
	
	# Bug 4803, ensure rating is an integer that fits into tinyint
	if ( $attributes->{RATING} && ($attributes->{RATING} !~ /^\d+$/ || $attributes->{RATING} > 255) ) {
		logWarning("Invalid RATING tag '" . $attributes->{RATING} . "' in " . Slim::Utils::Misc::pathFromFileURL($url));
		$attributes->{RATING} = 0;
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
			$attributes->{$shortTag} =~ s/\s//g;  # bug 15965
			$attributes->{$shortTag} =~ s/,/\./g; # bug 6900, change comma to period
			
			# Bug 15483, remove non-numeric gain tags
			if ( $attributes->{$shortTag} !~ /^[\d\-\+\.]+$/ ) {
				my $file = Slim::Utils::Misc::pathFromFileURL($url);
				$log->error("Invalid ReplayGain tag found in $file: $gainTag -> " . $attributes->{$shortTag} );
				
				delete $attributes->{$shortTag};
			}
		}
	}

	# We can take an array too - from vorbis comments, so be sure to handle that.
	my $comments = [];
	my $rawcomments = [];

	if ($attributes->{'COMMENT'} && !ref($attributes->{'COMMENT'})) {

		$rawcomments = [ $attributes->{'COMMENT'} ];

	} elsif (ref($attributes->{'COMMENT'}) eq 'ARRAY') {

		$rawcomments = $attributes->{'COMMENT'};
	}

	# Bug: 2605 - Get URL out of the attributes - some programs, and
	# services such as www.allofmp3.com add it.
	if ($attributes->{'URL'}) {

		push @$rawcomments, delete $attributes->{'URL'};
	}

	# Look for tags we don't want to expose in comments, and splice them out.
	for my $c ( @{$rawcomments} ) {
		next unless defined $c;
		
		# Bug 15630, ignore strings which have the utf8 flag on but are in fact invalid utf8
		# XXX - I can no longer reproduce the issues reported in 15630, but it's causing bug 17863 -michael
		#next if utf8::is_utf8($c) && !Slim::Utils::Unicode::looks_like_utf8($c);

		#ignore SoundJam and iTunes CDDB comments, iTunSMPB, iTunPGAP
		if ($c =~ /SoundJam_CDDB_/ ||
		    $c =~ /iTunes_CDDB_/ ||
		    $c =~ /^iTun[A-Z]{4}/ ||
		    $c =~ /^\s*[0-9A-Fa-f]{8}(\+|\s)/ ||
		    $c =~ /^\s*[0-9A-Fa-f]{2}\+[0-9A-Fa-f]{32}/) {

			next;
		}
		
		push @$comments, $c;
	}

	$attributes->{'COMMENT'} = $comments;

	# Bug: 4282 - we've seen multiple lyrics tags
	if ($attributes->{'LYRICS'} && ref($attributes->{'LYRICS'}) eq 'ARRAY') {

		$attributes->{'LYRICS'} = join("\n", @{$attributes->{'LYRICS'}});
	}

	# The ARTISTSORT and ALBUMARTISTSORT tags are normalized in Contributor->add()
	# since the tag may need to be split.  See bugs #295 and #4584.
	#
	# Push these back until we have a Track object.
	for my $tag (Slim::Schema::Contributor->contributorRoles, qw(
		COMMENT GENRE ARTISTSORT PIC APIC ALBUM ALBUMSORT DISCC
		COMPILATION REPLAYGAIN_ALBUM_PEAK REPLAYGAIN_ALBUM_GAIN 
		MUSICBRAINZ_ARTIST_ID MUSICBRAINZ_ALBUMARTIST_ID MUSICBRAINZ_ALBUM_ID 
		MUSICBRAINZ_ALBUM_TYPE MUSICBRAINZ_ALBUM_STATUS
		ALBUMARTISTSORT COMPOSERSORT CONDUCTORSORT BANDSORT
	)) {

		next unless defined $attributes->{$tag};

		$deferredAttributes->{$tag} = delete $attributes->{$tag};
	}
	
	# If embedded artwork was found, store the length of the artwork
	if ( $attributes->{'COVER_LENGTH'} ) {
		$attributes->{'COVER'} = delete $attributes->{'COVER_LENGTH'};
	}

	# We also need these in _postCheckAttributes, but they should be set during create()
	$deferredAttributes->{'DISC'} = $attributes->{'DISC'} if $attributes->{'DISC'};

	# thumb has gone away, since we have GD resizing.
	delete $attributes->{'THUMB'};
	
	# RemoteTrack also wants artist and album names
	if ($attributes->{'REMOTE'}) {
		foreach (qw/TRACKARTIST ARTIST ALBUMARTIST/) {
			if (my $a = $deferredAttributes->{$_}) {
				$a = join (' / ', @$a) if ref $a eq 'ARRAY';
				$attributes->{'ARTISTNAME'} = $a;
				last;
			}
		}
		$attributes->{'ALBUMNAME'} = $deferredAttributes->{'ALBUM'} if $deferredAttributes->{'ALBUM'};
		
		# XXX maybe also want COMMENT & GENRE
	}

	if (main::DEBUGLOG && $log->is_debug) {

		$log->debug("Report for $url:");
		$log->debug("* Attributes *");

		while (my ($tag, $value) = each %{$attributes}) {

			# Artwork dump is unreadable in logs, so replace with a text tag.  More thorough artwork
			# debugging is available using artwork setting and this avoids pointless log bloat.
			$log->debug(".. $tag : ", ($tag eq 'ARTWORK' ? "[Binary Image Data]" : $value)) if defined $value;
		}

		$log->debug("* Deferred Attributes *");

		while (my ($tag, $value) = each %{$deferredAttributes}) {

			# Artwork dump is unreadable in logs, so replace with a text tag.  Mor thorough artwork
			# debugging is available using artwork setting and this avoids pointless log bloat.
			$log->debug(".. $tag : ", ($tag eq 'ARTWORK' ? "[Binary Image Data]" : $value)) if defined $value;
		}
	}

	return ($attributes, $deferredAttributes);
}

my %lastTrackOrUrl = (
	obj => ''
);

sub _validTrackOrURL {
	my $urlOrObj = shift;
	
	if ($lastTrackOrUrl{obj} eq $urlOrObj) {
		return ($lastTrackOrUrl{track}, $lastTrackOrUrl{url}, $lastTrackOrUrl{blessed});
	}

	my $track   = undef;
	my $url     = undef;
	my $blessed = blessed($urlOrObj);

	if (isaTrack($urlOrObj)) {

		$track = $urlOrObj;
		$url   = $track->url;

	}
	elsif ( $urlOrObj && !$blessed ) {

		if ( $urlOrObj =~ /^(file|http)/i ) {
			$url = URI->new($urlOrObj)->canonical->as_string;
		}
		else {
			$url = $urlOrObj;
		}
	}
	
	%lastTrackOrUrl = (
		obj => $urlOrObj,
		track => $track,
		url => $url,
		blessed => $blessed
	) unless ref $urlOrObj;

	return ($track, $url, $blessed);
}

sub isaTrack {
	my $obj = shift;
	
	return $obj && blessed $obj && ($obj->isa('Slim::Schema::Track') || $obj->isa('Slim::Schema::RemoteTrack'));
}

=head1 SEE ALSO

L<DBIx::Class>

L<DBIx::Class::Schema>

L<DBIx::Class::ResultSet>,

L<Slim::Schema::Track>

L<Slim::Schema::Playlist>

L<Slim::Music::Info>

L<DBIx::Migration>

=cut

1;

__END__
