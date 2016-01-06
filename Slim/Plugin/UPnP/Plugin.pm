package Slim::Plugin::UPnP::Plugin;

# $Id: /sd/slim/7.6/branches/lms/server/Slim/Plugin/UPnP/Plugin.pm 78831 2011-07-25T16:48:09.710754Z andy  $
#
# UPnP/DLNA Media Interface
# Andy Grundman
# andy@slimdevices.com
#

use strict;
use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
my $prefs = preferences('server');

use Slim::Utils::Log;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.upnp',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_UPNP_MODULE_NAME',
} );

sub initPlugin {
	my $class = shift;
	
	if ( !defined $prefs->get('maxUPnPImageSize')) {
		$prefs->set('maxUPnPImageSize', 1920);
	}
	
	# Modules are loaded using require to save memory in noupnp mode
	
	# Core UPnP function
	require Slim::Plugin::UPnP::Discovery;
	Slim::Plugin::UPnP::Discovery->init || return shutdownPlugin();
	
	require Slim::Plugin::UPnP::Events;
	Slim::Plugin::UPnP::Events->init    || return shutdownPlugin();
	
	require Slim::Plugin::UPnP::SOAPServer;
	Slim::Plugin::UPnP::SOAPServer->init;

	# Devices
	require Slim::Plugin::UPnP::MediaServer;
	Slim::Plugin::UPnP::MediaServer->init;
	
	require Slim::Plugin::UPnP::MediaRenderer;
	Slim::Plugin::UPnP::MediaRenderer->init;

	Slim::Control::Request::addDispatch(['video_titles',   '_index', '_quantity'], [0, 1, 1, \&Slim::Control::Queries::videoTitlesQuery]) if main::VIDEO;
	Slim::Control::Request::addDispatch(['image_titles',   '_index', '_quantity'], [0, 1, 1, \&Slim::Control::Queries::imageTitlesQuery]) if main::IMAGE;
}

sub shutdownPlugin {
	my $class = shift;
	
	Slim::Plugin::UPnP::MediaServer->shutdown;
	Slim::Plugin::UPnP::MediaRenderer->shutdown;
	
	Slim::Plugin::UPnP::SOAPServer->shutdown;
	Slim::Plugin::UPnP::Discovery->shutdown;
	Slim::Plugin::UPnP::Events->shutdown;
}

1;