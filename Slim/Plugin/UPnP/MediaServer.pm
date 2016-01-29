package Slim::Plugin::UPnP::MediaServer;

# $Id: /sd/slim/7.6/branches/lms/server/Slim/Plugin/UPnP/MediaServer.pm 78831 2011-07-25T16:48:09.710754Z andy  $

use strict;

use Slim::Plugin::UPnP::Discovery;
use Slim::Plugin::UPnP::MediaServer::ConnectionManager;
use Slim::Plugin::UPnP::MediaServer::ContentDirectory;
use Slim::Plugin::UPnP::MediaServer::MediaReceiverRegistrar;
use Slim::Plugin::UPnP::Common::Utils qw(xmlEscape);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Web::HTTP;

my $log = logger('plugin.upnp');
my $prefs = preferences('server');

# Need a global flag so we don't call setChange multiple times
my $prefChangeSet = 0;

sub init {
	my $class = shift;
	
	# Setup description and service URLs
	Slim::Web::Pages->addPageFunction( 'plugins/UPnP/MediaServer.xml' => \&description );
	
	# Init service modules
	Slim::Plugin::UPnP::MediaServer::ConnectionManager->init;
	Slim::Plugin::UPnP::MediaServer::ContentDirectory->init;
	Slim::Plugin::UPnP::MediaServer::MediaReceiverRegistrar->init;
	
	Slim::Plugin::UPnP::Discovery->register(
		uuid     => uc( $prefs->get('server_uuid') ),
		url      => '/plugins/UPnP/MediaServer.xml',
		ttl      => 1800,
		device   => 'urn:schemas-upnp-org:device:MediaServer:1',
		services => [
			'urn:schemas-upnp-org:service:ConnectionManager:1',
			'urn:schemas-upnp-org:service:ContentDirectory:1',
			'urn:microsoft.com:service:X_MS_MediaReceiverRegistrar:1',
		],
	);
	
	if ( !$prefChangeSet ) {
		# Watch if the user changes the library name, so we can reinit
		$prefs->setChange( \&reinit, 'libraryname' );
		$prefChangeSet = 1;
	}
	
	main::INFOLOG && $log->is_info && $log->info('UPnP MediaServer initialized');
}

sub reinit {	
	main::DEBUGLOG && $log->is_debug && $log->debug("libraryname pref changed, re-initializing UPnP MediaServer");
	
	__PACKAGE__->shutdown;
	__PACKAGE__->init;
}

sub shutdown {
	my $class = shift;
	
	# Shutdown service modules
	Slim::Plugin::UPnP::MediaServer::ConnectionManager->shutdown;
	Slim::Plugin::UPnP::MediaServer::ContentDirectory->shutdown;
	Slim::Plugin::UPnP::MediaServer::MediaReceiverRegistrar->shutdown;
	
	Slim::Plugin::UPnP::Discovery->unregister( uc( $prefs->get('server_uuid') ) );
}

sub description {
	my ( $client, $params ) = @_;
	
	# Use the IP the request came in on, for proper multi-homed support
	my ($addr) = split /:/, $params->{host};
	my $hostport  = $addr . ':' . $prefs->get('httpport');
	my $eventaddr = $addr . ':' . Slim::Plugin::UPnP::Events->port;
	
	my $server_uuid = $prefs->get('server_uuid');
	
	$params->{serverAddr} = $hostport;
	$params->{serverURL}  = 'http://' . $hostport;
	$params->{eventAddr}  = $eventaddr;
	
	# Replace the first 8 chars of server_uuid with a constant value that identifies this
	# as an LMS server. This is used by LMP to trigger some special processing.
	my $serial = $server_uuid;
	substr $serial, 0, 8, '106173c8';
	
	$params->{device} = {
		name    => 'Logitech Media Server [' . xmlEscape(Slim::Utils::Misc::getLibraryName()) . ']',
		version => $::VERSION . $::REVISION,
		serial  => $serial,
		uuid    => uc($server_uuid),
	};
	
	main::DEBUGLOG && $log->is_debug && $log->debug('MediaServer.xml requested by ' . $params->{userAgent});
	
	return Slim::Web::HTTP::filltemplatefile( "plugins/UPnP/MediaServer.xml", $params );
}

1;