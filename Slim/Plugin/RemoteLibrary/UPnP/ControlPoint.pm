package Slim::Plugin::RemoteLibrary::UPnP::ControlPoint;

# Logitech Media Server Copyright 2001-2016 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# An asynchronous UPnP Control Point 

use strict;

use IO::Socket qw(:DEFAULT :crlf);
use HTML::Entities;
use Net::UPnP;
use Net::UPnP::Device;
use IO::String;
use Socket;

use Slim::Networking::Select;
use Slim::Networking::Async::Socket::UDP;
use Slim::Utils::Log;

my $log = logger('plugin.remotelibrary');

# A global socket that listens for UPnP events
our $sock;

# all devices we currently know about
my $devices = {};

# devices we are currently trying to contact.  This prevents many
# simultaneous requests when a device sends many notify packets at once
my $deviceRequests = {};

# device locations we've retrieved description documents from
my $deviceLocations = {};

# failed devices, we don't check these more than once every X minutes
use constant FAILURE_RETRY_TIME => 60 * 5;
my $failedDevices = {};

# Search for all devices on the network
sub search {
	my ( $class, $args ) = @_;
	
	my $st = $args->{deviceType} || 'upnp:rootdevice';   # search string
	my $mx = $args->{mx} || 3;                           # max wait
	
	my $mcast_addr = $Net::UPnP::SSDP_ADDR . ':' . $Net::UPnP::SSDP_PORT;
	
	my $ssdp_header = 
qq{M-SEARCH * HTTP/1.1
Host: $mcast_addr
Man: "ssdp:discover"
ST: $st
MX: $mx

};

	$ssdp_header =~ s/\r?\n/\015\012/g;
	
	$sock = Slim::Networking::Async::Socket::UDP->new(
		LocalPort => $Net::UPnP::SSDP_PORT,
		ReuseAddr => 1,
	);

	if ( !$sock ) {

		logWarning("Failed to initialize multicast socket, disabling UPnP.");
		return;
	}

	# listen for multicasts on this socket
	$sock->mcast_add( $mcast_addr );
	
	# save arguments in socket
	$sock->set( args => $args );
	
	# This socket will continue to live and receive events as
	# long as the server is running
	Slim::Networking::Select::addRead( $sock, \&_readResult );
	
	# send the search query
	$sock->mcast_send( $ssdp_header, $mcast_addr );
}

# Stop listening for UPnP events
sub shutdown {
	my $class = shift;
	
	if ( defined $sock ) {
		Slim::Networking::Select::removeRead( $sock );
	
		$sock->close;
	
		$sock = undef;
	}
	
	while ( my ($udn, $device) = each %{$devices} ) {
		removeDevice( $device );
	}
}

# A way for other code to remove a device
sub removeDevice {
	my ( $device, $callback ) = @_;
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug("Device went away: " . $device->getfriendlyname);
	}

	if ( $callback ) {
		$callback->( $device, 'remove' );
	}

	delete $devices->{ $device->getudn };
	delete $deviceLocations->{ $device->getlocation };
}

sub _readResult {
	my $sock = shift;
	
	my $ssdp_res_msg;
	
	my $addr = recv( $sock, $ssdp_res_msg, 4096, 0 );

	if ( !defined $addr ) {
		$log->warn("Read search result failed: $!");
		return;
	}
	
	return unless ( $ssdp_res_msg =~ m/LOCATION[ :]+(.*)\r/i );
	my $dev_location = $1;
	
	# Some UPnP devices report a Location of '*' (Xbox 360), so we must check for a proper URL
	return unless $dev_location =~ /^http/i;
	
	my ($USN) = $ssdp_res_msg =~ m/USN[ :]+(.*)\r/i;
	my ($udn) = _parseUSNHeader( $USN );
	
	my $args = $sock->get( 'args' );
	
	if ( $ssdp_res_msg =~ m/NOTIFY/i ) {
		# notify requests
		
		# status message (alive/byebye)
		my ($NTS) = $ssdp_res_msg =~ m/NTS[ :]+(.*)\r/i;
		
		# ignore failed devices
		if ( my $retry = $failedDevices->{ $dev_location } ) {
			if ( time < $retry ) {

				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug(sprintf("Notify from previously failed device at %s, ignoring for %s seconds",
						$dev_location,
						$retry - time,
					));
				}

				return;
			}
			else {
				delete $failedDevices->{ $dev_location };
			}
		}
		
		if ( my $device = $devices->{ $udn } ) {
			# existing device, check for byebye messages
			if ( $NTS =~ /byebye/ ) {
				removeDevice( $device, $args->{callback} );
			}
		}
		else {
			if ( $NTS =~ /alive/ ) {
				# new device, add it
			
				# get the device description if we haven't seen this location before
				if ( !$deviceLocations->{ $dev_location } ) {
				
					$deviceLocations->{ $dev_location } = 1;
				
					my $device = Net::UPnP::Device->new();
					$device->setssdp( $ssdp_res_msg );
					
					if ( main::DEBUGLOG && $log->is_debug ) {
						$log->debug(sprintf("Notify from new device [%s at %s]", $USN, $dev_location));
					}
		
					# make an async request for the device description XML document
					_getDeviceDescription( {
						device   => $device,
						udn      => $udn,
						location => $dev_location,
						callback => $args->{callback},
					} );
				}
			}
		}
	}
	
	# Responses to our initial search query will contain ST: <string we searched for>
	elsif ( my ($st) = $ssdp_res_msg =~ m/ST[ :]+(.*)\r/i ) {
		
		if ( $st eq $args->{deviceType} ) {
		
			my $device = Net::UPnP::Device->new();
			$device->setssdp( $ssdp_res_msg );
		
			# make an async request for the device description XML document
			_getDeviceDescription( {
				device   => $device,
				udn      => $udn,
				location => $dev_location,
				callback => $args->{callback},
			} );
		}
	}
}

sub _getDeviceDescription {
	my $args = shift;
	
	if ( !$deviceRequests->{ $args->{location} } ) {
		$deviceRequests->{ $args->{location} } = 1;
	
		my $http = Slim::Networking::SimpleAsyncHTTP->new(
			\&_gotDeviceDescription,
			\&_gotError,
			{
				args    => $args,
				Timeout => 5,
			},
		);
		$http->get( $args->{location} );
	}
}

sub _gotDeviceDescription {
	my $http = shift;
	my $args = $http->params('args');
	
	delete $deviceRequests->{ $args->{location} };
	
	my $device = $args->{device};
	$device->setdescription( $http->content );
	
	my $udn = $device->getudn;
	
	# is it new?
	if ( !$devices->{ $udn } ) {
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug(sprintf("New device found: %s [%s]",
				$device->getfriendlyname,
				$device->getlocation,
			));
		}
		
		# add the device to our list of known devices
		$devices->{ $udn } = $device;

		# callback
		my $callback = $args->{callback};
		$callback->( $device, 'add' );
	}
}

sub _gotError {
	my $http  = shift;
	my $error = $http->error;
	my $args  = $http->params('args');
	
	delete $deviceRequests->{ $args->{location} };
	delete $deviceLocations->{ $args->{location} };
	
	# keep track of failures
	$failedDevices->{ $args->{location} } = time + FAILURE_RETRY_TIME;
	
	$log->error("Error retrieving device description: $error");
}

sub _parseUSNHeader {
	my $usn = shift;

	my ($udn, $deviceType, $serviceType);

	if ($usn =~ /^uuid:schemas(.*?):device(.*?):(.*?):(.+)$/) {
		$udn = 'uuid:' . $4;
		$deviceType = 'urn:schemas' . $1 . ':device' . $2 . ':' . $3;
	}
	elsif ($usn =~ /^uuid:(.+?)::/) {
		$udn = 'uuid:' . $1;
		if ($usn =~ /urn:(.+)$/) {
			my $urn = $1;
			if ($usn =~ /:service:/) {
				$serviceType = 'urn:' . $urn;
			}
			elsif ($usn =~ /:device:/) {
				$deviceType = 'urn:' . $urn;
			}
		}
	}
	else {
		$udn = $usn;
	}

	return ($udn, $deviceType, $serviceType);
}

sub browse {
	my ( $class, $args ) = @_;
	
	if ( my $device = $devices->{ $args->{udn} } ) {
		my ( $url, $action, $content ) = $class->_soap_request( $device, "Browse", $args );
	
		my $http = Slim::Networking::SimpleAsyncHTTP->new(
			\&gotResponse,
			\&gotError,
			{
				args => $args,
			}
		);
	
		$http->post( 
			$url,
			'Content-Type' => 'text/xml; charset="utf-8"',
			SOAPACTION     => $action, 
			$content
		);
	}
}

sub gotResponse {
	my $http = shift;
	my $args = $http->params('args');
	
	# To save memory, we return only a filehandle
	my $contentRef = $http->contentRef;
	HTML::Entities::decode( $$contentRef );
	my $io = IO::String->new( $contentRef );
	
	my $callback    = $args->{callback};
	my $passthrough = $args->{passthrough} || [];
	$callback->( $io, @{$passthrough} );
}

sub gotError {
	my $http = shift;
	
	my $args  = $http->params('args');
	my $error = $http->error;
	my $url   = $http->url;
	
	logger("")->error("Error retrieving $url: $error");
	
	my $callback    = $args->{callback};
	my $passthrough = $args->{passthrough} || [];
	$callback->( undef, @{$passthrough} );
}

# Build a SOAP request by hand
# Based on Net::UPnP::Service::postaction
sub _soap_request {
	my ( $class, $device, $action_name, $action_arg ) = @_;
	
	my $service = $device->getservicebyname( $action_arg->{service} );

	my $ctrl_url = $service->getposturl();
	
	# Make sure we don't have double-slashes in the URL
	my $uri = URI->new($ctrl_url)->canonical;
	my $path_query = $uri->path_query;
	$path_query =~ s{//}{/}g;
	$uri->path_query($path_query);
	$ctrl_url = $uri->as_string;
	
	my $service_type = $service->getservicetype();
	my $soap_action = "\"" . $service_type . "#" . $action_name . "\"";

	my $soap_content = qq{<?xml version="1.0" encoding="utf-8"?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
   <s:Body>
      <u:$action_name xmlns:u="$service_type">
};

	if ( ref $action_arg ) {
		while ( my ($arg_name, $arg_value) = each %{$action_arg} ) {
			
			# skip internal items that don't belong in a SOAP request 
			# (anything not starting with a capital letter)
			next if $arg_name !~ /^[A-Z]/;
			
			if ( length($arg_value) <= 0 ) {
				$soap_content .= qq{         <$arg_name />} . "\n";
				next;
			}
			$soap_content .= qq{         <$arg_name>$arg_value</$arg_name>} . "\n";
		}
	}

	$soap_content .= qq{      </u:$action_name>
   </s:Body>
</s:Envelope>
};

	# Make sure we have correct line-endings
	$soap_content =~ s/\r?\n/\r\n/g;

	return ( $ctrl_url, $soap_action, $soap_content );
}

1;
