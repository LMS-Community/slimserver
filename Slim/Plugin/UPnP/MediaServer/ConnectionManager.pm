package Slim::Plugin::UPnP::MediaServer::ConnectionManager;

# $Id: /sd/slim/7.6/branches/lms/server/Slim/Plugin/UPnP/MediaServer/ConnectionManager.pm 75368 2010-12-16T04:09:11.731914Z andy  $

use strict;

use Slim::Utils::Log;
use Slim::Web::HTTP;

my $log = logger('plugin.upnp');

my $SourceProtocolInfo;

sub init {
	my $class = shift;
	
	Slim::Web::Pages->addPageFunction(
		'plugins/UPnP/MediaServer/ConnectionManager.xml',
		\&description,
	);
}

sub shutdown { }

sub description {
	my ( $client, $params ) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('MediaServer ConnectionManager.xml requested by ' . $params->{userAgent});
	
	return Slim::Web::HTTP::filltemplatefile( "plugins/UPnP/MediaServer/ConnectionManager.xml", $params );
}

### Eventing

sub subscribe {
	my ( $class, $client, $uuid ) = @_;
	
	my $source = $class->_sourceProtocols;
	
	# Send initial notify with complete data
	Slim::Plugin::UPnP::Events->notify(
		service => $class,
		id      => $uuid, # only notify this UUID, since this is an initial notify
		data    => {
			SourceProtocolInfo   => join( ',', @{$source} ),
			SinkProtocolInfo     => '',
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
	
	return SOAP::Data->name( ConnectionIDs => 0 );
}

sub GetProtocolInfo {
	my $class = shift;
	
	my $source = $class->_sourceProtocols;
	
	return (
		SOAP::Data->name( Source => join ',', @{$source} ),
		SOAP::Data->name( Sink   => '' ),
	);
}

sub GetCurrentConnectionInfo {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{ConnectionID} != 0 ) {
		return [ 706 => 'Invalid connection reference' ];
	}
	
	return (
		SOAP::Data->name( RcsID                 => -1 ),
		SOAP::Data->name( AVTransportID         => -1 ),
		SOAP::Data->name( ProtocolInfo          => '' ),
		SOAP::Data->name( PeerConnectionManager => '' ),
		SOAP::Data->name( PeerConnectionID      => -1 ),
		SOAP::Data->name( Direction             => 'Output' ),
		SOAP::Data->name( Status                => 'OK' ),
	);
}

### Helpers

sub _sourceProtocols {
	my $class = shift;
	
	if ( !$SourceProtocolInfo ) {
		my $flags = sprintf "%.8x%.24x",
			(1 << 24) | (1 << 22) | (1 << 21) | (1 << 20), 0;

		my @formats = (
			"http-get:*:audio/mpeg:DLNA.ORG_PN=MP3;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
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
			"http-get:*:audio/vnd.dlna.adts:DLNA.ORG_PN=AAC_ADTS;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
			"http-get:*:audio/vnd.dlna.adts:DLNA.ORG_PN=HEAAC_L2_ADTS;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
			"http-get:*:audio/mp4:DLNA.ORG_PN=AAC_ISO;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
			"http-get:*:audio/mp4:DLNA.ORG_PN=AAC_ISO_320;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
			"http-get:*:audio/mp4:DLNA.ORG_PN=HEAAC_L2_ISO;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
			"http-get:*:audio/x-ms-wma:DLNA.ORG_PN=WMABASE;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
			"http-get:*:audio/x-ms-wma:DLNA.ORG_PN=WMAFULL;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
			"http-get:*:audio/x-ms-wma:DLNA.ORG_PN=WMAPRO;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
			"http-get:*:application/ogg:DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
			"http-get:*:audio/x-flac:DLNA.ORG_OP=01;DLNA.ORG_FLAGS=$flags",
		);
		
		# XXX Disable DLNA stuff for now
		for ( @formats ) {
			s/:DLNA.+/:\*/;
		}
		
		$SourceProtocolInfo = \@formats;
	}
	
	return $SourceProtocolInfo;
}		

1;