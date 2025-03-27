package Slim::Plugin::UPnP::MediaRenderer::ProtocolHandler;

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log = logger('plugin.upnp');

sub isRemote { 1 }

sub getFormatForURL {
	my $class = shift;
	my $url = shift;

	# Previously this just returned 'mp3', this caused some streams to have
	# an incorrect type set. It doesn't seem to have any effect on playback,
	# it just changes the format listed in the SqueezePlay UI when the user
	# selects more info. 

	# attempted to use the built in method below but this caused Lyrion
	# to lock up and consume a lot of memory. It's probably not meant to
	# be used for streams.
	# my $type = Slim::Music::Info::typeFromPath($url, 'mp3');

	my $i = rindex($url, ".");
	if($i ne -1){

		my $ext = substr $url, $i + 1;
		$ext = lc($ext);
		my $return;

		my %code_ref = (

			# Added other formats, it can't hurt right?
			mp3 => sub { $return = 'mp3'; },
			mpeg => sub { $return = 'mp3'; },
			ogg => sub { $return = 'ogg'; },
			flac => sub { $return = 'flc'; },
			flc => sub { $return = 'flc'; },
			wav => sub { $return = 'wav'; },
			aif => sub { $return = 'aif'; },
			aiff => sub { $return = 'aif'; },
			wma => sub { $return = 'wma'; },
			aac => sub { $return = 'aac'; },
			ape => sub { $return = 'ape'; },
			wvpk => sub { $return = 'wvp'; },
			l16 => sub { $return = 'pcm'; },
			l24 => sub { $return = 'pcm'; },
			opus => sub { $return = 'ops'; },
			m4a => sub { $return = 'alc'; },
		);

		if ( exists $code_ref{$ext} ) {

			$code_ref{$ext}->();
			main::DEBUGLOG && $log->is_debug && $log->debug( 'Extension ' . $ext . ' , returned ' . $return . ' : ' . $url );
			return $return;
		}
	}
	# if all else fails, default to mp3 to maintain previous behaviour.
	main::DEBUGLOG && $log->is_debug && $log->debug( 'Extension Default returned mp3 ' . $url);
	return 'mp3';
}

# XXX use DLNA.ORG_OP value, and/or MIME type
sub canSeek { 1 } # We'll assume Range requests are supported by all servers,
                  # and this is also needed for pause to work properly

sub canSeekError { return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', 'UPnP/DLNA' ); }

# To support remote streaming (synced players), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client    = $args->{client};
	my $song      = $args->{song};
	my $streamUrl = $song->streamUrl() || return;
	
	main::DEBUGLOG && $log->is_debug && $log->debug( 'Remote streaming UPnP track: ' . $streamUrl );

	my $sock = $class->SUPER::new( {
		url     => $streamUrl,
		song    => $args->{song},
		client  => $client,
		bitrate => 128_000, # XXX
	} ) || return;
	
	${*$sock}{contentType} = 'audio/mpeg'; # XXX

	return $sock;
}

# Avoid scanning
sub scanUrl {
	my ($class, $url, $args) = @_;
	$args->{cb}->($args->{song}->currentTrack());
}

sub audioScrobblerSource { 'P' }

# XXX parseHeaders, needed?

# XXX parseDirectHeaders, needed?

# XXX seek data, using res@size, res@duration instead of bitrate

sub isRepeatingStream {
	my (undef, $song) = @_;
	
	return 0; # XXX playlists, REPEAT_ONE, REPEAT_ALL, SHUFFLE
}

# XXX getNextTrack (playlists, next track)

sub getMetadataFor {
	my ( $class, $client, $url ) = @_;

	# This returns metadata for any tracks added to the playlist via the plugin.
	# It can only return metadata for CurrentURI and NextURI so the playlist
	# needs to be managed to only show those tracks. Any extra tracks will have
	# the metadata for CurrentURI returned.

	# $url =~ s/^http/upnp/; is returning an empty string for some reason so 
	# stripping upnp/http from url so it can be compared.
	my $strippedUrl = substr $url, 4;
	my $pd   = $client->pluginData();
	my $meta = $pd->{avt_AVTransportURIMetaData_hash};
	my $res  = $meta->{res};
	my $currentUri = substr $res->{uri}, 4;

	# if $url doesn't match CurrentURI check against NextUri
	if( $strippedUrl ne $currentUri){
		my $nextMeta = $pd->{avt_NextAVTransportURIMetaData_hash};

		# check for cleared NextUri
		if( ref($nextMeta) eq 'HASH'){
			my $nextRes = $nextMeta->{res};
			$currentUri = substr $nextRes->{uri}, 4;

			if( $strippedUrl eq $currentUri){
				$meta = $nextMeta;
				$res = $nextRes;
			}
		}
	}
	main::DEBUGLOG && $log->is_debug && $log->debug( 'Metadata returned for  ' . $meta->{title} );

	return {
		artist   => $meta->{artist},
		album    => $meta->{album},
		title    => $meta->{title},
		cover    => $meta->{cover} || '', # XXX default
		icon     => '', # XXX default icon
		duration => $res->{secs} || 0,
		bitrate  => $res->{bitrate} ? ($res->{bitrate} / 1000) . 'kbps' : 0,
		type     => $res->{mime} . ' (UPnP/DLNA)',
	};
}


1;
