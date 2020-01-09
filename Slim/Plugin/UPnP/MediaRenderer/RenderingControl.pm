package Slim::Plugin::UPnP::MediaRenderer::RenderingControl;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use URI::Escape qw(uri_unescape);
use XML::Simple qw(XMLout);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Web::HTTP;

use constant EVENT_RATE => 0.2;

my $log   = logger('plugin.upnp');
my $prefs = preferences('server');

sub init {
	my $class = shift;
	
	Slim::Web::Pages->addPageFunction(
		'plugins/UPnP/MediaRenderer/RenderingControl.xml',
		\&description,
	);
	
	# Since prefs change functions are for every client and cannot
	# be removed, we set them up once here.
	
	$prefs->setChange( sub {
		my $client = $_[2];
		# Only notify if player is on when brightness changes
		if ( $client->power ) {
			$client->pluginData('RC_LastChange')->{Brightness} = $_[1];
			$class->event( $client => 'RC_LastChange' );
		}
	}, 'powerOnBrightness' );
	
	$prefs->setChange( sub {
		my $client = $_[2];
		# Only notify if player is off when brightness changes
		if ( !$client->power ) {
			$client->pluginData('RC_LastChange')->{Brightness} = $_[1];
			$class->event( $client => 'RC_LastChange' );
		}
	}, 'powerOffBrightness' );
	
	# XXX idleBrightness?
	
	$prefs->setChange( sub { 
		my $client = $_[2];
		$client->pluginData('RC_LastChange')->{Volume} = $_[1];
		$class->event( $client => 'RC_LastChange' );
	}, 'volume' );
	
	$prefs->setChange( sub { 
		my $client = $_[2];
		$client->pluginData('RC_LastChange')->{Mute} = $_[1];
		$class->event( $client => 'RC_LastChange' );
	}, 'mute' );
}

sub shutdown { }

sub description {
	my ( $client, $params ) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('MediaRenderer RenderingControl.xml requested by ' . $params->{userAgent});
	
	return Slim::Web::HTTP::filltemplatefile( "plugins/UPnP/MediaRenderer/RenderingControl.xml", $params );
}

sub newClient {
	my ( $class, $client ) = @_;
	
	$client->pluginData( RC_LastChange => {} );
}

sub disconnectClient {
	my ( $class, $client ) = @_;
	
	$client->pluginData( RC_LastChange => {} );
}

### Eventing

sub subscribe {
	my ( $class, $client, $uuid ) = @_;
	
	# Bump the number of subscribers for this client
	my $subs = $client->pluginData('rc_subscribers') || 0;
	$client->pluginData( rc_subscribers => ++$subs );
	
	my $cprefs = $prefs->client($client);
	
	# Setup state variables
	my $mute       = $cprefs->get('mute') ? 1 : 0;
	my $brightness = $client->power ? $cprefs->get('powerOnBrightness') : $cprefs->get('powerOffBrightness');
	
	# Send initial notify with complete data
	Slim::Plugin::UPnP::Events->notify(
		service => __PACKAGE__,
		id      => $uuid, # only notify this UUID, since this is an initial notify
		data    => {
			LastChange => _event_xml( {
				PresetNameList => 'FactoryDefaults',
				Brightness     => $brightness,
				Mute           => $mute,
				Volume         => $cprefs->get('volume'),
			} ),
		},
	);
	
	$client->pluginData( rc_lastEvented => Time::HiRes::time() );
}

sub event {
	my ( $class, $client, $var ) = @_;
	
	if ( $client->pluginData('rc_subscribers') ) {
		# Don't send more often than every 0.2 seconds
		Slim::Utils::Timers::killTimers( $client, \&sendEvent );
		
		my $lastAt = $client->pluginData('rc_lastEvented');
		my $sendAt = Time::HiRes::time();
		
		if ( $sendAt - $lastAt < EVENT_RATE ) {
			$sendAt += EVENT_RATE - ($sendAt - $lastAt);
		}
		
		Slim::Utils::Timers::setTimer(
			$client,
			$sendAt,
			\&sendEvent,
			$var,
		);
	}
}

sub sendEvent {
	my ( $client, $var ) = @_;
	
	Slim::Plugin::UPnP::Events->notify(
		service => __PACKAGE__,
		id      => $client->id,
		data    => {
			LastChange => _event_xml( $client->pluginData($var) ),
		},
	);
	
	# Clear the RC_LastChange state
	$client->pluginData( $var => {} );
	
	# Indicate when last event was sent
	$client->pluginData( rc_lastEvented => Time::HiRes::time() );
}

sub unsubscribe {
	my ( $class, $client ) = @_;
	
	my $subs = $client->pluginData('rc_subscribers');
	
	if ( !$subs ) {
		$subs = 1;
	}
	
	$client->pluginData( rc_subscribers => --$subs );
}

### Action methods

sub ListPresets {
	my ( $class, $client, $args ) = @_;
	
	return SOAP::Data->name(
		CurrentPresetNameList => 'FactoryDefaults',
	);
}

sub SelectPreset {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{PresetName} eq 'FactoryDefaults' ) {
		# FactoryDefaults is no mute, 50 volume
		# XXX brightness?
		$prefs->client($client)->set( mute => 0 );
		$prefs->client($client)->set( volume => 50 );
	}
	else {
		return [ 701 => 'Invalid Name' ];
	}
	
	return;
}

sub GetBrightness {
	my ( $class, $client, $args ) = @_;
	
	return SOAP::Data->name( CurrentBrightness => $client->currBrightness() );
}

sub SetBrightness {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 702 => 'Invalid InstanceID' ];
	}
	
	if ( $args->{DesiredBrightness} >= 0 && $args->{DesiredBrightness} <= $client->maxBrightness ) {
		# set brightness pref depending on mode
		my $pref = $client->power ? 'powerOnBrightness' : 'powerOffBrightness';
		$prefs->client($client)->set( $pref => $args->{DesiredBrightness} );
	}
	
	return;
}

sub GetMute {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{Channel} ne 'Master' ) {
		return [ 703 => 'Invalid Channel' ];
	}
	
	my $mute = $prefs->client($client)->get('mute') ? 1 : 0;
	return SOAP::Data->name( CurrentMute => $mute );
}

sub SetMute {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 702 => 'Invalid InstanceID' ];
	}
	
	if ( $args->{Channel} ne 'Master' ) {
		return [ 703 => 'Invalid Channel' ];
	}
	
	my $mute = $args->{DesiredMute} == 0 ? 0 : 1;
	
	$client->execute(['mixer', 'muting', $mute]);
	
	return;
}

sub GetVolume {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{Channel} ne 'Master' ) {
		return [ 703 => 'Invalid Channel' ];
	}
	
	my $vol = $prefs->client($client)->get('volume');
	return SOAP::Data->name( CurrentVolume => $vol );
}

sub SetVolume {
	my ( $class, $client, $args ) = @_;
	
	if ( $args->{InstanceID} != 0 ) {
		return [ 702 => 'Invalid InstanceID' ];
	}
	
	if ( $args->{Channel} ne 'Master' ) {
		return [ 703 => 'Invalid Channel' ];
	}
	
	if ( $args->{DesiredVolume} >= 0 && $args->{DesiredVolume} <= 100 ) {
		$client->volume( $args->{DesiredVolume} );
	}
	
	return;
}

my $xs;
sub _event_xml {
	my $data = shift;
	
	$xs ||= XML::Simple->new(
		RootName      => undef,
		XMLDecl       => undef,
		SuppressEmpty => undef,
	);
	
	my $out = {};
	
	while ( my ($k, $v) = each %{$data} ) {
		if ( $k eq 'Mute' || $k eq 'Volume' ) {
			$out->{$k} = {
				channel => 'Master',
				val     => $v,
			};
		}
		else {
			$out->{$k} = {
				val => $v,
			};
		}
	}
	
	# Can't figure out how to produce this with XML::Simple
	my $xml 
		= '<Event xmlns="urn:schemas-upnp-org:metadata-1-0/RCS/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="urn:schemas-upnp-org:metadata-1-0/RCS/ http://www.upnp.org/schemas/av/rcs-event-v1-20060531.xsd">'
		. "<InstanceID val=\"0\">\n"
		. $xs->XMLout( $out ) 
		. '</InstanceID>'
		. '</Event>';
	
	main::DEBUGLOG && $log->is_debug && $log->debug("RenderingControl event: $xml");
	
	return $xml;
}

1;