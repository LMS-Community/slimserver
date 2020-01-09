package Slim::Plugin::UPnP::MediaRenderer::ConnectionManager;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Utils::Log;
use Slim::Web::HTTP;

my $log = logger('plugin.upnp');

sub init {
	my $class = shift;
	
	Slim::Web::Pages->addPageFunction(
		'plugins/UPnP/MediaRenderer/ConnectionManager.xml',
		\&description,
	);
}

sub shutdown { }

sub description {
	my ( $client, $params ) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('MediaRenderer ConnectionManager.xml requested by ' . $params->{userAgent});
	
	return Slim::Web::HTTP::filltemplatefile( "plugins/UPnP/MediaRenderer/ConnectionManager.xml", $params );
}

### Eventing

sub subscribe {
	my ( $class, $client, $uuid ) = @_;
	
	my $sink = $class->_sinkProtocols($client);
	
	# Send initial notify with complete data
	Slim::Plugin::UPnP::Events->notify(
		service => $class,
		id      => $uuid, # only notify this UUID, since this is an initial notify
		data    => {
			SourceProtocolInfo   => '',
			SinkProtocolInfo     => join( ',', @{$sink} ),
			CurrentConnectionIDs => 0,
		},
	);
}

sub unsubscribe {
	# Nothing to do
}

### Action methods

sub GetCurrentConnectionIDs {
	my $class = shift;
	
	return (
		SOAP::Data->name( ConnectionIDs => 0 ),
	);
}

sub GetProtocolInfo {
	my ( $class, $client ) = @_;
	
	my $sink = $class->_sinkProtocols($client);
	
	return (
		SOAP::Data->name( Source => '' ),
		SOAP::Data->name( Sink   => join ',', @{$sink} ),
	);
}

sub GetCurrentConnectionInfo {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{ConnectionID} != 0 ) {
		return [ 706 => 'Invalid connection reference' ];
	}
	
	my $sink = $client->pluginData->{CM_SinkProtocolInfo};
	if ( !$sink ) {
		$class->GetProtocolInfo($client);
		$sink = $client->pluginData->{CM_SinkProtocolInfo};
	}
	
	# Get mime type of currently playing song if any
	# XXX needs to interface with AVTransport
	my $type = '';
	if ( my $song = $client->playingSong() ) {
		if ( my $format = $song->streamformat() ) {
			my $mime = $Slim::Music::Info::types{ $format };
			($type) = grep { /$mime/ } @{$sink};
		}
	}
	
	return (
		SOAP::Data->name( RcsID                 => 0 ),
		SOAP::Data->name( AVTransportID         => 0 ),
		SOAP::Data->name( ProtocolInfo          => $type ),
		SOAP::Data->name( PeerConnectionManager => '' ),
		SOAP::Data->name( PeerConnectionID      => -1 ),
		SOAP::Data->name( Direction             => 'Input' ),
		SOAP::Data->name( Status                => 'OK' ),
	);
}

### Helpers

=pod
/* DLNA.ORG_FLAGS, padded with 24 trailing 0s
 *     80000000  31  senderPaced
 *     40000000  30  lsopTimeBasedSeekSupported
 *     20000000  29  lsopByteBasedSeekSupported
 *     10000000  28  playcontainerSupported
 *      8000000  27  s0IncreasingSupported
 *      4000000  26  sNIncreasingSupported
 *      2000000  25  rtspPauseSupported
 *      1000000  24  streamingTransferModeSupported
 *       800000  23  interactiveTransferModeSupported
 *       400000  22  backgroundTransferModeSupported
 *       200000  21  connectionStallingSupported
 *       100000  20  dlnaVersion15Supported
 *
 *     Example: (1 << 24) | (1 << 22) | (1 << 21) | (1 << 20)
 *       DLNA.ORG_FLAGS=01700000[000000000000000000000000] // [] show padding
=cut

sub _sinkProtocols {
	my ( $class, $client ) = @_;
	
	my $sink = $client->pluginData->{CM_SinkProtocolInfo};
	if ( !$sink ) {
		my $flags = sprintf "%.8x%.24x",
			(1 << 24) | (1 << 22) | (1 << 21) | (1 << 20), 0;
		
		# MP3 supported by everything
		my @formats = (
			"http-get:*:audio/mpeg:DLNA.ORG_PN=MP3;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
		);
		
		# Natively supported formats
		my @cf = $client->formats;
		
		my $hasPCM = grep { /pcm/ } @cf;
		my $hasAAC = grep { /aac/ } @cf;
		my $hasWMA = grep { /wma/ } @cf;
		my $hasWMAP = grep { /wmap/ } @cf;
		my $hasOgg = grep { /ogg/ } @cf;
		my $hasFLAC = grep { /flc/ } @cf;
		
		# Transcoder-supported formats
		my $canTranscode = sub {
			my $format = shift;
			
			my $profile
				= $hasFLAC ? "${format}-flc-*-*"
				: $hasPCM ? "${format}-pcm-*-*"
				: "${format}-mp3-*-*";
			
			return main::TRANSCODING && Slim::Player::TranscodingHelper::isEnabled($profile);
		};
		
		if ( $hasPCM ) {
			push @formats, (
				"http-get:*:audio/L16;rate=8000;channels=1:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=8000;channels=2:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=11025;channels=1:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=11025;channels=2:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=12000;channels=1:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=12000;channels=2:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=16000;channels=1:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=16000;channels=2:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=22050;channels=1:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=22050;channels=2:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=24000;channels=1:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=24000;channels=2:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=32000;channels=1:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=32000;channels=2:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=44100;channels=1:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=44100;channels=2:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=48000;channels=1:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/L16;rate=48000;channels=2:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=01,DLNA.ORG_FLAGS=$flags",
			);
		}
		
		if ( $hasAAC || $canTranscode->('aac') ) {
			push @formats, (		
				"http-get:*:audio/vnd.dlna.adts:DLNA.ORG_PN=AAC_ADTS;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/vnd.dlna.adts:DLNA.ORG_PN=HEAAC_L2_ADTS;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
			);
		}
		
		if ( $hasAAC || $canTranscode->('mp4') ) {
			# Seeking not supported for remote MP4 content (OP=00)
			push @formats, (
				"http-get:*:audio/mp4:DLNA.ORG_PN=AAC_ISO;DLNA.ORG_OP=00;DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/mp4:DLNA.ORG_PN=AAC_ISO_320;DLNA.ORG_OP=00;DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/mp4:DLNA.ORG_PN=HEAAC_L2_ISO;DLNA.ORG_OP=00;DLNA.ORG_FLAGS=$flags",
			);
		}
		
		if ( $hasWMA || $canTranscode->('wma') ) {
			push @formats, (
				"http-get:*:audio/x-ms-wma:DLNA.ORG_PN=WMABASE;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
				"http-get:*:audio/x-ms-wma:DLNA.ORG_PN=WMAFULL;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
			);
		}
		
		if ( $hasWMAP || $canTranscode->('wmap') ) {
			push @formats, (
				"http-get:*:audio/x-ms-wma:DLNA.ORG_PN=WMAPRO;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
			);
		}
		
		if ( $hasOgg || $canTranscode->('ogg') ) {
			# Seeking not supported for remote Vorbis content (OP=00)
			push @formats, (
				"http-get:*:application/ogg:DLNA.ORG_OP=00;DLNA.ORG_FLAGS=$flags",
			);
		}
		
		if ( $hasFLAC || $canTranscode->('flc') ) {
			# Seeking not supported for remote FLAC content (OP=00)
			push @formats, (
				"http-get:*:audio/x-flac:DLNA.ORG_OP=00;DLNA.ORG_FLAGS=$flags",
			);
		}
		
		# XXX Disable DLNA stuff for now
		for ( @formats ) {
			s/:DLNA.+/:\*/;
		}
		
		$sink = $client->pluginData( CM_SinkProtocolInfo => \@formats );
	}
	
	return $sink;
}

1;