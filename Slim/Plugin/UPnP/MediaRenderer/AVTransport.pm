package Slim::Plugin::UPnP::MediaRenderer::AVTransport;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use URI::Escape qw(uri_unescape);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Web::HTTP;

use Slim::Plugin::UPnP::Common::Utils qw(xmlEscape secsToHMS hmsToSecs trackDetails absURL);

use constant EVENT_RATE => 0.2;

my $log   = logger('plugin.upnp');
my $prefs = preferences('server');

sub init {
	my $class = shift;
	
	Slim::Web::Pages->addPageFunction(
		'plugins/UPnP/MediaRenderer/AVTransport.xml',
		\&description,
	);
}

sub shutdown { }

sub description {
	my ( $client, $params ) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('MediaRenderer AVTransport.xml requested by ' . $params->{userAgent});
	
	return Slim::Web::HTTP::filltemplatefile( "plugins/UPnP/MediaRenderer/AVTransport.xml", $params );
}

sub newClient {
	my ( $class, $client ) = @_;
	
	# Initialize all state variables
	$client->pluginData( AVT => _initialState() );
}

sub disconnectClient { }

sub _initialState {
	return {	
		TransportState               => 'NO_MEDIA_PRESENT',
		TransportStatus              => 'OK',
		PlaybackStorageMedium        => 'NONE',
		RecordStorageMedium          => 'NOT_IMPLEMENTED',
		PossiblePlaybackStorageMedia => 'NONE,NETWORK',
		PossibleRecordStorageMedia   => 'NOT_IMPLEMENTED',
		CurrentPlayMode              => 'NORMAL',
		TransportPlaySpeed           => 1,
		RecordMediumWriteStatus      => 'NOT_IMPLEMENTED',
		CurrentRecordQualityMode     => 'NOT_IMPLEMENTED',
		PossibleRecordQualityModes   => 'NOT_IMPLEMENTED',
		NumberOfTracks               => 0,
		CurrentTrack                 => 0,
		CurrentTrackDuration         => '00:00:00',
		CurrentMediaDuration         => '00:00:00',
		CurrentTrackMetaData         => '',
		CurrentTrackURI              => '',
		AVTransportURI               => '',
		AVTransportURIMetaData       => '',
		NextAVTransportURI           => '',
		NextAVTransportURIMetaData   => '',
		CurrentTransportActions      => 'Play,Stop,Pause,Seek,Next,Previous',
	};
	
	# Time/Counter Position variables are intentionally not kept here
}

### Eventing

sub clientEvent {
	my $class   = __PACKAGE__;
	my $request = shift;
	my $client  = $request->client;
	
	my $cmd = $request->getRequest(1);
	
	if ( $cmd eq 'clear' ) {
		main::DEBUGLOG && $log->is_debug && $log->debug('playlist clear event, resetting state');
		
		$class->changeState( $client, _initialState() );
		return;
	}
	
	# Use playmode to handle TransportState changes on any kind of event
	my $mode = Slim::Player::Source::playmode($client);
	
	if ( $mode eq 'stop' ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("playlist $cmd event, changing state to STOPPED");
		
		# Change to STOPPED unless we are in NO_MEDIA_PRESENT
		if ( $client->pluginData()->{AVT}->{TransportState} ne 'NO_MEDIA_PRESENT' ) {
			$class->changeState( $client, {
				TransportState => 'STOPPED',
			} );
		}
	}
	elsif ( $mode eq 'pause' ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("playlist $cmd event, changing state to PAUSED_PLAYBACK");
		
		$class->changeState( $client, {
			TransportState => 'PAUSED_PLAYBACK',
		} );
	}
	elsif ( $mode eq 'play' ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("playlist $cmd event, changing state to PLAYING");
		
		$class->changeState( $client, {
			TransportState => 'PLAYING',
		} );
	}
}

sub subscribe {
	my ( $class, $client, $uuid ) = @_;
	
	# Subscribe to events for this client
	Slim::Control::Request::subscribe(
		\&clientEvent, [['playlist']], $client,
	);
	
	# Bump the number of subscribers for this client
	my $pd = $client->pluginData();
	my $subs = $pd->{AVT_Subscribers} || 0;
	$pd->{AVT_Subscribers} = ++$subs;
	
	# Send initial notify with complete data, only to this UUID
	Slim::Plugin::UPnP::Events->notify(
		service => __PACKAGE__,
		id      => $uuid,
		data    => {
			LastChange => _event_xml( $pd->{AVT} ),
		},
	);
}

sub sendEvent {
	my ( $class, $client, $id, $changedVars ) = @_;
	
	my $pd = $client->pluginData();
	
	return unless $pd->{AVT_Subscribers};
	
	# Batch multiple calls together
	$pd->{AVT_Pending} = {
		%{ $pd->{AVT_Pending} || {} },
		%{$changedVars},
	};
	
	# Don't send more often than every 0.2 seconds
	Slim::Utils::Timers::killTimers( $client, \&sendPending );
	
	my $lastAt = $pd->{AVT_LastEvented} || 0;
	my $sendAt = Time::HiRes::time;
	
	if ( $sendAt - $lastAt < EVENT_RATE ) {
		$sendAt += EVENT_RATE - ($sendAt - $lastAt);
	}
	
	Slim::Utils::Timers::setTimer( $client, $sendAt, \&sendPending );
}

sub sendPending {
	my $client = shift;
	
	my $pd = $client->pluginData();
	
	Slim::Plugin::UPnP::Events->notify(
		service => __PACKAGE__,
		id      => $client->id,
		data    => {
			LastChange => _event_xml( $pd->{AVT_Pending} ),
		},
	);
	
	$pd->{AVT_Pending} = {};
	
	# Indicate when last event was sent
	$pd->{AVT_LastEvented} = Time::HiRes::time;
}

sub changeState {
	my ( $class, $client, $vars ) = @_;
	
	my $isDebug = main::DEBUGLOG && $log->is_debug;
	
	my $state   = $client->pluginData()->{AVT};
	my $changed = {};
	my $count   = 0;
	
	while ( my ($k, $v) = each %{$vars} ) {
		if ( $v ne $state->{$k} ) {
			$isDebug && $log->debug("State change: $k => $v");
			$state->{$k} = $changed->{$k} = $v;
			$count++;
		}
	}
	
	if ($count) {
		main::INFOLOG && $log->is_info && $log->info( $client->id . ' state change: ' . Data::Dump::dump($changed) );
		$class->sendEvent( $client, $client->id, $changed );
	}
}

sub unsubscribe {
	my ( $class, $client ) = @_;
	
	my $subs = $client->pluginData('AVT_Subscribers');
	
	if ( !$subs ) {
		$subs = 1;
	}
	
	$client->pluginData( AVT_Subscribers => --$subs );
}

### Action methods

sub SetAVTransportURI {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	my $newstate;
	my $mediaDuration;
	my $trackDuration;
	my $medium;
	my $numTracks;
	my $curTrack;
	
	# If we get an empty CurrentURI value, clear the playlist
	if ( exists $args->{CurrentURI} && $args->{CurrentURI} eq '' ) {
		$client->execute( [ 'playlist', 'clear' ] );
		
		$newstate = 'NO_MEDIA_PRESENT';
		$mediaDuration = $trackDuration = '00:00:00';
		$medium = 'NONE';
		$numTracks = 0;
		$curTrack = 0;
	}
	else {	
		my $meta = $class->_DIDLLiteToHash( $args->{CurrentURIMetaData} );
	
		# XXX check upnp:class, parse playlist if necessary, return 716 if not found or other parse error
	
		if ( !$meta->{res} ) {
			return [ 714 => "Illegal MIME-type" ];
		}
	
		my $pd = $client->pluginData();
	
		# Convert URI to protocol handler
		my $upnp_uri = $meta->{res}->{uri};
		$upnp_uri =~ s/^http/upnp/;
	
		Slim::Music::Info::setBitrate( $upnp_uri, $meta->{res}->{bitrate} );
		Slim::Music::Info::setDuration( $upnp_uri, $meta->{res}->{secs} );
		
		$mediaDuration = $meta->{res}->{duration}; # XXX more if URI is a playlist?
		$trackDuration = $mediaDuration;
		$medium    = 'NETWORK';
		$numTracks = 1; # XXX more if playlist
		$curTrack  = 1;
	
		$pd->{avt_AVTransportURIMetaData_hash} = $meta;
	
		my $tstate = $pd->{AVT}->{TransportState};
	
		# This command behaves differently depending on the current transport state
	
		if ( $tstate eq 'NO_MEDIA_PRESENT' || $tstate eq 'STOPPED' ) {
			# Both of these go to STOPPED, so load the track without playing it
			$client->execute( [ 'playlist', 'clear' ] );
			$client->execute( [ 'playlist', 'add', $upnp_uri, $meta->{title} ] );
			$newstate = 'STOPPED';
		}
		elsif ( $tstate eq 'PLAYING' || $tstate eq 'TRANSITIONING' ) {
			# Both of these go to PLAYING with the new URI
			$client->execute( [ 'playlist', 'play', $upnp_uri, $meta->{title} ] );
			$newstate = $tstate;
		}
		elsif ( $tstate eq 'PAUSED_PLAYBACK' ) {
			# A bit strange, this is apparently supposed to load the new track but remains paused
			# We'll set it to STOPPED to keep it simple
			$client->execute( [ 'playlist', 'clear' ] );
			$client->execute( [ 'playlist', 'add', $upnp_uri, $meta->{title} ] );
			$newstate = 'STOPPED';
		}
	}
	
	# Event notification, on a timer so playlist clear comes first and deletes everything
	# then this resets the new data.
	Slim::Utils::Timers::setTimer( undef, Time::HiRes::time, sub {		
		# Change state variables
		$class->changeState( $client, {
			TransportState         => $newstate,
			AVTransportURI         => $args->{CurrentURI},
			CurrentTrackURI        => $args->{CurrentURI}, # XXX different if playlist
			AVTransportURIMetaData => $args->{CurrentURIMetaData},
			CurrentTrackMetaData   => $args->{CurrentURIMetaData}, # XXX different if playlist?
			PlaybackStorageMedium  => $medium,
			CurrentMediaDuration   => $mediaDuration,
			CurrentTrackDuration   => $trackDuration,
			NumberOfTracks         => $numTracks,
			CurrentTrack           => $curTrack,
		} );
	} );
	
	return;
}

sub SetNextAVTransportURI {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	my $meta = $class->_DIDLLiteToHash( $args->{NextURIMetaData} );
	
	# XXX parse playlist?
	
	if ( !$meta->{res} ) {
		return [ 714 => 'Illegal MIME-type' ];
	}
	
	# Save hash version of metadata
	$client->pluginData( avt_NextAVTransportURIMetaData_hash => $meta );
	
	# Change state variables
	$class->changeState( $client, {
		NextAVTransportURI         => $args->{NextURI},
		NextAVTransportURIMetaData => $args->{NextURIMetaData},
	} );
	
	return;
}

sub GetMediaInfo {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	my $state = $client->pluginData()->{AVT};
	
	# XXX this won't work for non-UPnP tracks
	return (
		SOAP::Data->name( NrTracks           => $state->{NumberOfTracks} ),
		SOAP::Data->name( MediaDuration      => $state->{CurrentMediaDuration} ),
		SOAP::Data->name( CurrentURI         => $state->{AVTransportURI} ),
		SOAP::Data->name( CurrentURIMetaData => $state->{AVTransportURIMetaData} ),
		SOAP::Data->name( NextURI            => $state->{NextAVTransportURI} ),
		SOAP::Data->name( NextURIMetaData    => $state->{NextAVTransportURIMetaData} ),
		SOAP::Data->name( PlayMedium         => $state->{PlaybackStorageMedium} ),
		SOAP::Data->name( RecordMedium       => 'NOT_IMPLEMENTED' ),
		SOAP::Data->name( WriteStatus        => 'NOT_IMPLEMENTED' ),
	);
}

sub GetTransportInfo {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	my $state = $client->pluginData()->{AVT};
	
	return (
		SOAP::Data->name( CurrentTransportState  => $state->{TransportState} ),
		SOAP::Data->name( CurrentTransportStatus => $state->{TransportStatus} ),
		SOAP::Data->name( CurrentSpeed           => 1 ),
	);
}

sub GetPositionInfo {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	my $state = $client->pluginData()->{AVT};
	
	# position data is not stored in the state, it changes too fast
	my $position = $class->_relativeTimePosition($client);
	my $counterPosition = $class->_relativeCounterPosition($client);
	
	return (
		SOAP::Data->name( Track         => $state->{CurrentTrack} ),
		SOAP::Data->name( TrackDuration => $state->{CurrentTrackDuration} ),
		SOAP::Data->name( TrackMetaData => $state->{CurrentTrackMetaData} ),
		SOAP::Data->name( TrackURI      => $state->{CurrentTrackURI} ),
		SOAP::Data->name( RelTime       => $position ),
		SOAP::Data->name( AbsTime       => $position ),
		SOAP::Data->name( RelCount      => $counterPosition ),
		SOAP::Data->name( AbsCount      => $counterPosition ),
	);
}

sub GetDeviceCapabilities {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	return (
		SOAP::Data->name( PlayMedia       => 'NONE,HDD,NETWORK,UNKNOWN' ),
		SOAP::Data->name( RecMedia        => 'NOT_IMPLEMENTED' ),
		SOAP::Data->name( RecQualityModes => 'NOT_IMPLEMENTED' ),
	);
}

sub GetTransportSettings {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	my $state = $client->pluginData()->{AVT};
	
	return (
		SOAP::Data->name( PlayMode       => $state->{CurrentPlayMode} ),
		SOAP::Data->name( RecQualityMode => 'NOT_IMPLEMENTED' ),
	);
}

sub Stop {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	# Stop is not allowed with no media
	if ( $client->pluginData()->{AVT}->{TransportState} eq 'NO_MEDIA_PRESENT' ) {
		return [ 701 => 'Transition not available' ];
	}
	
	$client->execute(['stop']);
	
	return;
}

sub Play {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	if ( $args->{Speed} != 1 ) {
		return [ 717 => 'Play speed not supported' ];
	}
	
	my $state = $client->pluginData()->{AVT};
	
	# Make sure we have an AVTransportURI loaded
	if ( !$state->{AVTransportURI} ) {
		return [ 716 => 'Resource not found' ];
	}
	
	my $transportState = $state->{TransportState};
	
	my $upnp_uri = $state->{AVTransportURI};
	$upnp_uri =~ s/^http/upnp/;
	
	if ( $transportState eq 'PLAYING' || $transportState eq 'TRANSITIONING' ) {
		# Check if same track is already playing
		my $playingURI = $client->playingSong->currentTrack->url;
		if ( $upnp_uri eq $playingURI ) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Play for $upnp_uri ignored, already playing");
			return;
		}
	}
	elsif ( $transportState eq 'PAUSED_PLAYBACK' ) {
		# Check if we should just unpause
		my $playingURI = $client->playingSong->currentTrack->url;
		if ( $upnp_uri eq $playingURI ) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Play for $upnp_uri triggering unpause");
			
			$client->execute(['play']); # will resume
			
			return;
		}
	}
	
	# All other cases, start playing the current transport URI
	# which has already been loaded to index 0 by SetAVTransportURI
	$client->execute([ 'playlist', 'jump', 0 ]);
	
	# State changes to TRANSITIONING, after playlist jump
	# is handled it will be changed to PLAYING
	$class->changeState( $client, {
		TransportState => 'TRANSITIONING',
	} );
	
	return;
}

sub Pause {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	# XXX not allowed in some states
	
	$client->execute(['pause']);
	
	$class->changeState( $client, {
		TransportState => 'PAUSED_PLAYBACK',
	} );
	
	return;
}

sub Seek {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	my $unit   = $args->{Unit};
	my $target = $args->{Target};
	
	if ( !$target ) {
		return [ 711 => 'Illegal seek target' ];
	}
	
	# XXX: support TRACK_NR mode for playlists
	
	if ( $unit eq 'ABS_TIME' || $unit eq 'REL_TIME' ) {
		# Seek to time
		my $seeksecs = hmsToSecs($target);
		my $tracksecs = hmsToSecs( $client->pluginData()->{AVT}->{CurrentTrackDuration} );
		
		if ( $seeksecs > $tracksecs ) {
			return [ 711 => "Illegal seek target ($seeksecs out of range, max: $tracksecs)" ];
		}
		
		$client->execute(['time', $seeksecs]);
		
		# State changes to TRANSITIONING, after playlist newsong
		# is handled it will be changed to PLAYING
		$class->changeState( $client, {
			TransportState => 'TRANSITIONING',
		} );
	}
	else {
		return [ 710 => 'Seek mode not supported' ];
	}
	
	return;
}

sub Next {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	my $state = $client->pluginData()->{AVT};
	
	if ( $state->{NumberOfTracks} <= 1 ) {
		return [ 711 => 'Illegal seek target' ];
	}
	
	# XXX skip to the next track in the playlist
	
	return;
}

sub Previous {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	my $state = $client->pluginData()->{AVT};
	
	if ( $state->{NumberOfTracks} <= 1 ) {
		return [ 711 => 'Illegal seek target' ];
	}
	
	# XXX skip to the previous track in the playlist
	
	return;
}

sub SetPlayMode {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	my $mode = $args->{NewPlayMode};
	
	if ( !$mode || $mode !~ /^(?:NORMAL|SHUFFLE|REPEAT_ONE|REPEAT_ALL)$/ ) {
		return [ 712 => 'Play mode not supported' ];
	}
	
	$class->changeState( $client, {
		CurrentPlayMode => $mode,
	} );
	
	return;
}

sub GetCurrentTransportActions {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 718 => 'Invalid InstanceID' ];
	}
	
	return (
		SOAP::Data->name( Actions => $client->pluginData()->{AVT}->{CurrentTransportActions} ),
	);
}

### Helper methods

# Elapsed time in H:MM:SS[.F+] format
sub _relativeTimePosition {
	my ( $class, $client ) = @_;
	
	my $elapsed = '00:00:00';
	
	if ( my $secs = $client->controller->playingSongElapsed() ) {
		$elapsed = secsToHMS($secs);
	}
	
	return $elapsed;
}

# A 'dimensionless counter' as an integer, we'll just return the integer seconds elapsed
sub _relativeCounterPosition {
	my ( $class, $client ) = @_;
	
	return sprintf "%d", $client->controller->playingSongElapsed();
}

my $xs;
sub _xml_simple {
	return XML::Simple->new(
		RootName      => undef,
		XMLDecl       => undef,
		SuppressEmpty => undef,
		ForceContent  => 1,
		ForceArray    => [
			'upnp:artist',
			'upnp:albumArtURI',
			'res',
		],
	);
}

sub _DIDLLiteToHash {
	my ( $class, $xml ) = @_;
	
	return {} unless $xml;
	
	$xs ||= _xml_simple();
	
	my $x = eval { $xs->XMLin($xml) };
	if ( $@ ) {
		$log->error("Unable to parse DIDL-Lite XML: $@");
		return {};
	}
	
	# Create a saner structure, as the DIDL-Lite can be very complex
	$x = $x->{item};
	
	my $meta = {};
	
	if ( $x->{'upnp:artist'} ) {
		$meta->{artist} = $x->{'upnp:artist'}->[0]->{content};
	}
	else {
		$meta->{artist} = $x->{'dc:creator'} ? $x->{'dc:creator'}->{content} : 'Unknown Artist';
	}
	
	$meta->{album} = $x->{'upnp:album'} ? $x->{'upnp:album'}->{content} : 'Unknown Album';
	$meta->{title} = $x->{'dc:title'}->{content} || '',
	$meta->{cover} = $x->{'upnp:albumArtURI'} ? $x->{'upnp:albumArtURI'}->[0]->{content} : '';
	
	# Find the best res item to play
	for my $r ( @{ $x->{res} } ) {
		my ($mime) = $r->{protocolInfo} =~ /[^:]+:[^:]+:([^:+]+):/;
		next if !$mime || !Slim::Music::Info::mimeToType($mime);

		# Some servers must have missed the (really stupid) part in
		# the spec where bitrate is defined as bytes/sec, not bits/sec
		# We try to handle this for common MP3 bitrates
		my $bitrate = $r->{bitrate};
		if ( $bitrate =~ /^(?:64|96|128|160|192|256|320)000$/ ) {
			$bitrate /= 8;
		}
	
		$meta->{res} = {
			uri          => $r->{content},
			mime         => $mime,
			protocolInfo => $r->{protocolInfo},
			bitrate      => $bitrate * 8,
			secs         => hmsToSecs( $r->{duration} ),
			duration     => $r->{duration} || '',
		};
		
		last;
	}
	
	return $meta;
}

sub _event_xml {
	my $data = shift;
	
	$xs ||= _xml_simple();
	
	my $out = {};
	
	while ( my ($k, $v) = each %{$data} ) {
		$out->{$k} = {
			val => $v,
		};
	}
	
	# Can't figure out how to produce this with XML::Simple
	my $xml 
		= '<Event xmlns="urn:schemas-upnp-org:metadata-1-0/AVT/">'
		. "<InstanceID val=\"0\">\n"
		. $xs->XMLout( $out ) 
		. '</InstanceID>'
		. '</Event>';
		
	return $xml;
}

=pod XXX
sub _currentTrackURI {
	my ( $class, $client ) = @_;
	
	my $uri = '';
	
	if ( my $song = ($client->playingSong() || $client->streamingSong()) ) {
		# Return the URL an external client would use to stream this song
		my $track = $song->currentTrack;
		
		my $id = $track->id;
		if ( $id > 0 ) {
			$uri = absURL('/music/' . $id . '/download');
		}
		else {
			# Remote URL
			$uri = $track->url;
			
			# URL may be from UPnP
			$uri =~ s/^upnp/http/;
		}
	}
	
	# Check for a UPnP track set via SetAVTransport
	elsif ( my $avtu = $client->pluginData('avt_AVTransportURI') ) {
		$uri = $avtu;
	}
	
	$client->pluginData( avt_AVTransportURI => $uri );
	
	return $uri;
}

sub _currentTrackMetaData {
	my ( $class, $client, $refresh ) = @_;
	
	# Check for a UPnP track set via SetAVTransport (or cached from below)
	if ( !$refresh ) {
		if ( my $xml = $client->pluginData('avt_AVTransportURIMetaData') ) {
			return $xml;
		}
	}
	
	my $meta = '';
	
	if ( my $song = ($client->playingSong() || $client->streamingSong()) ) {
		my $track = $song->currentTrack;
		
		# XXX could construct real /a/<id>/l/<id>/t/<id> path but is this needed?
		my $tid = '/t/' . $track->id;
		my $pid = '/t';
		
		$meta = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
			. qq{<item id="${tid}" parentID="${pid}" restricted="1">}
			. trackDetails($track, '*')
			. '</item></DIDL-Lite>';
		
		# Cache this in pluginData to avoid database queries every time it's called
		$client->pluginData( avt_AVTransportURIMetaData      => $meta );
		$client->pluginData( avt_AVTransportURIMetaData_hash => $class->_DIDLLiteToHash($meta) );
	}
	
	return $meta;
}

sub _currentTransportActions {
	my ( $class, $client ) = @_;
	
	my $actions = 'PLAY,STOP';
	
	if ( my $song = $client->controller()->playingSong() ) {
		if ( $song->canSeek() ) {
			$actions .= ',SEEK';
		}
		
		my $controller = $client->controller();
		
		my $isPlaying = $controller->isPlaying();
		
		if ( my $handler = $song->currentTrackHandler() ) {
			if ( $handler->can('canDoAction') ) {
				# Some restrictive plugins, check for allowed actions
				my $master = $controller->master;
				my $url    = $song->currentTrack()->url;
				
				if ( $handler->canDoAction($master, $url, 'pause') && $isPlaying ) {
					$actions .= ',PAUSE';
				}
				
				if ( $handler->canDoAction($master, $url, 'stop') ) {
					$actions .= ',NEXT';
				}
				
				if ( $handler->canDoAction($master, $url, 'rew') ) {
					$actions .= ',PREVIOUS';
				}
			}
			else {
				# Not a restrictive handler
				$actions .= ',PAUSE' if $isPlaying;
				$actions .= ',NEXT,PREVIOUS';
			}
		}
		else {
			$actions .= ',PAUSE' if $isPlaying;
			$actions .= ',NEXT,PREVIOUS';
		}
	}
	
	return $actions;
}
=cut

1;