package Slim::Schema::RemoteTrack;

# $Id$

# This is an emulation of the Slim::Schema::Track API for remote tracks

use strict;

use base qw(Slim::Utils::Accessor);

use Scalar::Util qw(blessed);
use Tie::Cache::LRU;

use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $log = logger('formats.metadata');

# Keep a cache of up to 100 remote tracks at a time.
my $cacheSize = 100;

if ( main::SLIM_SERVICE ) {
	# Keep a much larger remote track cache on SN
	$cacheSize = 2000;
}

tie our %Cache, 'Tie::Cache::LRU', $cacheSize;
tie our %idIndex, 'Tie::Cache::LRU', $cacheSize;

my @allAttributes = (qw(
	_url
	content_type
	bitrate
	secs
	
	artistname albumname coverurl type info_link
	
	title titlesort titlesearch album tracknum
	timestamp filesize disc audio audio_size audio_offset year
	cover vbr_scale samplerate samplesize channels block_alignment endian
	bpm tagversion drm musicmagic_mixable
	musicbrainz_id lossless lyrics replay_gain replay_peak extid
	
	rating lastplayed playcount
	
	comment genre
	
	stash
	error
));

{
	__PACKAGE__->mk_accessor('ro',
		'id',
		'remote',

		# Emulate absent relationships
		qw(
			artist
			albumid
		),
	);
	
	__PACKAGE__->mk_accessor('rw', @allAttributes);
}

sub init {
	my $maxPlaylistLengthCB = sub {
		my ($pref, $max) = @_;
		
		$max ||= 500;
		$max = 500 if $max > 500;
		$max = 100 if $max < 100;

		my $cacheObj = tied %Cache;
		if ($cacheObj->max_size != $max) {
			$cacheObj->max_size($max);
		}
	};
	
	my $prefs = preferences('server');
	
	$maxPlaylistLengthCB->(undef, $prefs->get('maxPlaylistLength'));
	
	$prefs->setChange($maxPlaylistLengthCB, 'maxPlaylistLength');
}

# Emulate absent methods - hopefully these can be retired at some time
sub artists {return ();}
sub genres {return ();}
sub coverArtExists {0}

sub isRemoteURL {shift->remote();}

sub path { shift->_url(); }

sub contributorsOfType {}

sub update {}
sub delete {}

sub retrievePersistent {}

sub displayAsHTML {
	return Slim::Schema::Track::displayAsHTML(@_);
}

sub name {
	return shift->title;
}

sub namesort {
	return shift->titlesort;
}

sub contributorRoles {
	my $self = shift;

	return Slim::Schema::Contributor->contributorRoles;
}

sub artistName {
	return shift->artistname(@_);
}

sub coverArt {
	my $self    = shift;
	my $list    = shift || 0;
	
	my ($body, $contentType, $mtime, $path);

#	my $cover = $self->cover;
#	
#	return undef if defined $cover && !$cover;
	
	# Remote files may have embedded cover art
	my $cache = Slim::Utils::Cache->new();
	my $image = $cache->get( 'cover_' . $self->_url );
	
	return undef if !$image;
	
	$body        = $image->{image};
	$contentType = $image->{type};
	$mtime       = time();
	
	if ( !$list && wantarray ) {
		return ( $body, $contentType, time() );
	} else {
		return $body;
	}
}

# Although the URL is the primary key into the cache,
# we allow it to be updated 
sub url {
	my ($self, $new) = @_; 
	
	if ($new) {
		
		# We could leave the old reference in the cache but
		# I am not sure that it is safe.
		delete $Cache{$self->_url};
		
		$self->_url($new);
		$Cache{$new} = $self;
	}
	
	return $self->_url;
}


# Calling conventions:
# class->new($url)
# class->new($url, %attributes)
# class->new(%attributes) -- 'url' attribute in %attributes

sub new {
	my $class  = shift;
	my $attributes = shift;
	
	my $url;
	
	if (ref $attributes ne 'HASH') {
		$url = $attributes;
		$attributes = shift || {};
		$attributes->{'url'} = $url;
	} else {
		$url = $attributes->{'url'};
	}
	
	if (!defined $url) {
		$log->error('No url!');
		return undef;
	}
	
	my $self = $class->SUPER::new;

	main::DEBUGLOG && $log->is_debug && $log->debug("$class, $url");
#	main::DEBUGLOG && $log->logBacktrace();
	
	$self->init_accessor(_url => $url, id => -int($self), secs => 0, stash => {});
	$self->init_accessor(remote => Slim::Music::Info::isRemoteURL($url));
	$self->setAttributes($attributes);
	
	$Cache{$url} = $self;
	$idIndex{$self->id} = $self;
	
	return $self;
}

# Probably do not need all of these any more
my %localTagMapping = (
	artist                 => 'artistname',
	albumartist            => 'artistname',
	trackartist            => 'artistname',
	album                  => 'albumname',
	composer               => undef,
	conductor              => undef,
	band                   => undef,
	remote                 => undef,
	urlmd5                 => undef,
);

sub setAttributes {
	my ($self, $attributes) = @_;
	
#	main::DEBUGLOG && $log->debug("$url: $self => ", Data::Dump::dump($attributes));
	
	while (my($key, $value) = each %{$attributes}) {
		next if !defined $value; # XXX not sure about this
		$key = lc($key);
		$key = $localTagMapping{$key} if exists $localTagMapping{$key};
		next if !defined($key) || $key eq 'url';
		
		main::DEBUGLOG && $log->is_debug && defined $self->$key() && $self->$key() ne $value &&
			$log->debug("$key: ", $self->$key(), "=>$value");
		
		$self->$key($value);
	}
}

sub updateOrCreate {
	my ($class, $objOrUrl, $attributes) = @_;

	my $self;
	my $url;

	if (blessed($objOrUrl) && ($objOrUrl->isa(__PACKAGE__))) {
		$self = $objOrUrl;
		$url = $self->_url();
	} else {
		$url = $objOrUrl;
		$self = $Cache{$url};
		my $id = $idIndex{$self->id} if $self; # refresh ID index cache
	}
	
	main::DEBUGLOG && $log->is_debug && $log->debug($url);
	
	if ($self) {
		$self->setAttributes($attributes);
	} else {
		$self = $class->new($url, $attributes);
	}
	
	return $self;
}

sub fetch {
	my ($class, $url, $playlist) = @_;
	
	
	my $self = $Cache{$url};
	my $id = $idIndex{$self->id} if $self; # refresh ID index cache
	
	if ($self && $playlist && !$self->isa('Slim::Schema::RemotePlaylist')) {
		main::DEBUGLOG && $log->is_debug && $log->debug("$url upcast to RemotePlaylist");
		bless $self, 'Slim::Schema::RemotePlaylist';
	}
	
	return $self;
}

sub fetchById {
	my ($class, $id) = @_;
	
	return $idIndex{$id};
}

sub get {
	my ($self, $attribute) = @_;

	main::DEBUGLOG && $log->is_debug && $log->debug($self->_url, ', ', $attribute, '->', $self->$attribute());
	
	return($self->$attribute());
}

sub get_column {
	return get(@_);
}

sub prettyBitRate {
	my $self = shift;

	my $bitrate  = $self->bitrate;
	my $vbrScale = $self->vbr_scale;

	my $mode = defined $vbrScale ? 'VBR' : 'CBR';

	if ($bitrate) {
		return int ($bitrate/1000) . Slim::Utils::Strings::string('KBPS') . ' ' . $mode;
	}

	return 0;
}

sub duration {
	my $self = shift;

	my $secs = $self->secs;

	return sprintf('%s:%02s', int($secs / 60), $secs % 60) if defined $secs && $secs > 0;
}

sub coverid { $_[0]->id }

1;
