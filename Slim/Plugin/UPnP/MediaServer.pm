package Slim::Plugin::UPnP::MediaServer;

# $Id$

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

sub init {
	my $class = shift;
	
	# Setup description and service URLs
	Slim::Web::Pages->addPageFunction( 'plugins/UPnP/MediaServer.xml' => \&description );
	
	# Init service modules
	Slim::Plugin::UPnP::MediaServer::ConnectionManager->init;
	Slim::Plugin::UPnP::MediaServer::ContentDirectory->init;
	Slim::Plugin::UPnP::MediaServer::MediaReceiverRegistrar->init;
	
	my $hostport = Slim::Utils::Network::serverAddr() . ':' . $prefs->get('httpport');
	
	Slim::Plugin::UPnP::Discovery->register(
		uuid     => uc( $prefs->get('server_uuid') ),
		url      => "http://$hostport/plugins/UPnP/MediaServer.xml",
		ttl      => 1800,
		device   => 'urn:schemas-upnp-org:device:MediaServer:1',
		services => [
			'urn:schemas-upnp-org:service:ConnectionManager:1',
			'urn:schemas-upnp-org:service:ContentDirectory:1',
		],
	);
	
	$log->info('UPnP MediaServer initialized');
}

sub shutdown {
	my $class = shift;
	
	# Shutdown service modules
	Slim::Plugin::UPnP::MediaServer::ConnectionManager->shutdown;
	Slim::Plugin::UPnP::MediaServer::ContentDirectory->shutdown;
	Slim::Plugin::UPnP::MediaServer::MediaReceiverRegistrar->shutdown;
}

sub description {
	my ( $client, $params ) = @_;
	
	my $hostport  = Slim::Utils::Network::serverAddr() . ':' . $prefs->get('httpport');
	my $eventaddr = Slim::Utils::Network::serverAddr() . ':' . Slim::Plugin::UPnP::Events->port;
	
	my $server_uuid = $prefs->get('server_uuid');
	
	$params->{serverAddr} = $hostport;
	$params->{serverURL}  = 'http://' . $hostport;
	$params->{eventAddr}  = $eventaddr;
	
	$params->{device} = {
		name    => 'Squeezebox Server [' . xmlEscape($prefs->get('libraryname') || Slim::Utils::Network::hostName()) . ']',
		version => $::VERSION . ' r' . $::REVISION,
		serial  => $server_uuid,
		uuid    => uc($server_uuid),
	};
	
	main::DEBUGLOG && $log->is_debug && $log->debug('MediaServer.xml requested by ' . $params->{userAgent});
	
	return Slim::Web::HTTP::filltemplatefile( "plugins/UPnP/MediaServer.xml", $params );
}

1;