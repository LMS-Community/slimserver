package Slim::Plugin::UPnP::MediaServer::ConnectionManager;

# $Id: /sd/slim/7.6/branches/lms/server/Slim/Plugin/UPnP/MediaServer/ConnectionManager.pm 75368 2010-12-16T04:09:11.731914Z andy  $

use strict;

use Slim::Music::Info;
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
	
	# Wipe protocol info after a rescan
	Slim::Control::Request::subscribe( \&refreshSourceProtocolInfo, [['rescan'], ['done']] );
}

sub shutdown { }

sub refreshSourceProtocolInfo {
	$SourceProtocolInfo = undef;
	# XXX needs evented
}

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
	
	if ( !exists $args->{ConnectionID} ) {
		return [ 402 ];
	}
	
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
		my @formats;
		
		# There are just too many profiles to list them all by default, so scan the database
		# for all the ones we have actually scanned
		my $dbh = Slim::Schema->dbh;
		
		my $audio = $dbh->selectall_arrayref( qq{
			SELECT dlna_profile, content_type, samplerate, channels
			FROM tracks
			WHERE audio = 1
		}, { Slice => {} } );
		
		my $images = $dbh->selectall_arrayref( qq{
			SELECT DISTINCT(dlna_profile), mime_type
			FROM images
		}, { Slice => {} } );
		
		my $videos = $dbh->selectall_arrayref( qq{
			SELECT DISTINCT(dlna_profile), mime_type
			FROM videos
		}, { Slice => {} } );

		# Audio profiles, will have duplicates...
		my %seen = ();
		for my $row ( @{$audio} ) {
			my $mime;			
			if ( $row->{content_type} =~ /^(?:wav|aif|pcm)$/ ) {
				$mime = 'audio/L16;rate=' . $row->{samplerate} . ';channels=' . $row->{channels};
			}
			else {
				$mime = $Slim::Music::Info::types{ $row->{content_type} };
			}
			
			my $key = $mime . $row->{dlna_profile};
			next if $seen{$key}++;
			
			if ( $row->{dlna_profile} ) {
				push @formats, "http-get:*:$mime:DLNA.ORG_PN=" . $row->{dlna_profile};
			}
			else {
				push @formats, "http-get:*:$mime:*";
			}
		}
		
		# Special audio transcoding profile for PCM
		if ( !exists $seen{ 'audio/L16;rate=44100;channels=2LPCM' } ) {
			push @formats, "http-get:*:audio/L16;rate=44100;channels=2:DLNA.ORG_PN=LPCM";
		}
		
		# Image profiles
		for my $row ( @{$images} ) {
			if ( $row->{dlna_profile} ) {
				push @formats, "http-get:*:" . $row->{mime_type} . ":DLNA.ORG_PN=" . $row->{dlna_profile};
			}
			else {
				push @formats, "http-get:*:" . $row->{mime_type} . ":*";
			}
		}
		
		# Video profiles
		for my $row ( @{$videos} ) {
			if ( $row->{dlna_profile} ) {
				push @formats, "http-get:*:" . $row->{mime_type} . ":DLNA.ORG_PN=" . $row->{dlna_profile};
			}
			else {
				push @formats, "http-get:*:" . $row->{mime_type} . ":*";
			}
		}
		
		$SourceProtocolInfo = \@formats;
	}
	
	return $SourceProtocolInfo;
}		

1;