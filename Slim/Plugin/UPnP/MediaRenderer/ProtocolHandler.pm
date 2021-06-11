package Slim::Plugin::UPnP::MediaRenderer::ProtocolHandler;

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log = logger('plugin.upnp');

sub isRemote { 1 }

sub getFormatForURL { 'mp3' } # XXX

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
	
	my $pd   = $client->pluginData();
	my $meta = $pd->{avt_AVTransportURIMetaData_hash};
	my $res  = $meta->{res};
	
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