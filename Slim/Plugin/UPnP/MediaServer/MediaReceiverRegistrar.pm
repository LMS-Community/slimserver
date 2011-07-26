package Slim::Plugin::UPnP::MediaServer::MediaReceiverRegistrar;

# $Id: /sd/slim/7.6/branches/lms/server/Slim/Plugin/UPnP/MediaServer/MediaReceiverRegistrar.pm 75368 2010-12-16T04:09:11.731914Z andy  $

use strict;

use Slim::Utils::Log;
use Slim::Web::HTTP;

my $log = logger('plugin.upnp');

sub init {
	my $class = shift;
	
	Slim::Web::Pages->addPageFunction(
		'plugins/UPnP/MediaServer/MediaReceiverRegistrar.xml',
		\&description,
	);
}

sub shutdown { }

sub description {
	my ( $client, $params ) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('MediaServer MediaReceiverRegistrar.xml requested by ' . $params->{userAgent});
	
	return Slim::Web::HTTP::filltemplatefile( "plugins/UPnP/MediaServer/MediaReceiverRegistrar.xml", $params );
}

### Eventing

sub subscribe {
	my ( $class, $client, $uuid ) = @_;
	
	# Send initial notify with complete data
	Slim::Plugin::UPnP::Events->notify(
		service => $class,
		id      => $uuid, # only notify this UUID, since this is an initial notify
		data    => {
			AuthorizationGrantedUpdateID => 0, # XXX what should these be?
			AuthorizationDeniedUpdateID  => 0,
			ValidationSucceededUpdateID  => 0,
			ValidationRevokedUpdateID    => 0,
		},
	);
}

sub unsubscribe {
	# Nothing to do
}

### Action methods

sub IsAuthorized {
	return (
		SOAP::Data->name( Result => 1 ),
	);
}

sub IsValidated {
	return (
		SOAP::Data->name( Result => 1 ),
	);
}

sub RegisterDevice {
	return (
		SOAP::Data->name( RegistrationRespMsg => 1 ),
	);
}

1;