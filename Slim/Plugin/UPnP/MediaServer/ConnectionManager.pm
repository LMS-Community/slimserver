package Slim::Plugin::UPnP::MediaServer::ConnectionManager;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Web::HTTP;

my $log = logger('plugin.upnp');

use constant EVENT_RATE => 0.2;

my $STATE;

sub init {
	my $class = shift;
	
	Slim::Web::Pages->addPageFunction(
		'plugins/UPnP/MediaServer/ConnectionManager.xml',
		\&description,
	);
	
	
 	$STATE = {
		SourceProtocolInfo   => _sourceProtocols(),
		SinkProtocolInfo     => '',
		CurrentConnectionIDs => 0,
		_subscribers         => 0,
		_last_evented        => 0,
	};
	
	# Wipe protocol info after a rescan
	Slim::Control::Request::subscribe( \&refreshSourceProtocolInfo, [['rescan'], ['done']] );
}

sub shutdown { }

sub refreshSourceProtocolInfo {
	$STATE->{SourceProtocolInfo} = _sourceProtocols();
	__PACKAGE__->event('SourceProtocolInfo');
}

sub description {
	my ( $client, $params ) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('MediaServer ConnectionManager.xml requested by ' . $params->{userAgent});
	
	return Slim::Web::HTTP::filltemplatefile( "plugins/UPnP/MediaServer/ConnectionManager.xml", $params );
}

### Eventing

sub subscribe {
	my ( $class, $client, $uuid ) = @_;
	
	# Bump the number of subscribers
	$STATE->{_subscribers}++;
	
	# Send initial event
	sendEvent($uuid);
}

sub event {
	my ( $class, $var ) = @_;
	
	if ( $STATE->{_subscribers} ) {
		# Don't send more often than every 0.2 seconds
		Slim::Utils::Timers::killTimers( undef, \&sendEvent );
		
		my $lastAt = $STATE->{_last_evented};
		my $sendAt = Time::HiRes::time();
		
		if ( $sendAt - $lastAt < EVENT_RATE ) {
			$sendAt += EVENT_RATE - ($sendAt - $lastAt);
		}
		
		Slim::Utils::Timers::setTimer(
			undef,
			$sendAt,
			\&sendEvent,
			$var,
		);
	}
}

sub sendEvent {
	my ( $uuid, $var ) = @_;
	
	if ( $var ) {
		# Event 1 variable
		Slim::Plugin::UPnP::Events->notify(
			service => __PACKAGE__,
			id      => $uuid || 0, # 0 will notify everyone
			data    => {
				$var => $STATE->{$var},
			},
		);
	}
	else {
		# Event all
		Slim::Plugin::UPnP::Events->notify(
			service => __PACKAGE__,
			id      => $uuid || 0, # will notify everyone
			data    => {
				map { $_ => $STATE->{$_} } grep { ! /^_/ } keys %{$STATE}
			},
		);
	}
	
	# Indicate when last event was sent
	$STATE->{_last_evented} = Time::HiRes::time();
}

sub unsubscribe {	
	if ( $STATE->{_subscribers} > 0 ) {
		$STATE->{_subscribers}--;
	}
}

### Action methods

sub GetCurrentConnectionIDs {
	my $class = shift;
	
	return SOAP::Data->name( ConnectionIDs => 0 );
}

sub GetProtocolInfo {
	my $class = shift;
	
	return (
		SOAP::Data->name( Source => $class->_sourceProtocols ),
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
			
			# Bug 17882, use DLNA-required audio/mp4 instead of audio/m4a
			$mime = 'audio/mp4' if $mime eq 'audio/m4a';
		}
		
		my $key = $mime . ($row->{dlna_profile} || '');
		next if $seen{$key}++;
		
		if ( $row->{dlna_profile} ) {
			my $canseek = ($row->{dlna_profile} eq 'MP3' || $row->{dlna_profile} =~ /^WMA/);
			push @formats, "http-get:*:$mime:DLNA.ORG_PN=" . $row->{dlna_profile} . ";DLNA.ORG_OP=" . ($canseek ? '11' : '01') . ";DLNA.ORG_FLAGS=01700000000000000000000000000000";
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
			push @formats, "http-get:*:" . $row->{mime_type} . ":DLNA.ORG_PN=" . $row->{dlna_profile} . ";DLNA.ORG_OP=01;DLNA.ORG_FLAGS=00f00000000000000000000000000000";
		}
		else {
			push @formats, "http-get:*:" . $row->{mime_type} . ":*";
		}
	}
	push @formats, "http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_TN;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=00f00000000000000000000000000000";
	push @formats, "http-get:*:image/png:DLNA.ORG_PN=PNG_TN;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=00f00000000000000000000000000000";
	
	# Video profiles
	for my $row ( @{$videos} ) {
		if ( $row->{dlna_profile} ) {
			push @formats, "http-get:*:" . $row->{mime_type} . ":DLNA.ORG_PN=" . $row->{dlna_profile} . ';DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000';
		}
		else {
			push @formats, "http-get:*:" . $row->{mime_type} . ":*";
		}
	}
	
	# Bug 17885, sort all wildcard formats to the end of the list
	# Based on example at http://perldoc.perl.org/functions/sort.html
	my @sortedFormats = sort {
		($a =~ /(\*)$/)[0] cmp ($b =~ /(\*)$/)[0]
		||
		uc($a) cmp uc($b)
	} @formats;
	
	return join( ',', @sortedFormats );
}		

1;