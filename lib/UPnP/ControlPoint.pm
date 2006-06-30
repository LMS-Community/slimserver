package UPnP::ControlPoint;
=pod

=head1 NAME

UPnP::ControlPoint - A UPnP ControlPoint implementation.

=head1 SYNOPSIS

  use UPnP::ControlPoint;

  my $cp = UPnP::ControlPoint->new;
  my $search = $cp->searchByType("urn:schemas-upnp-org:device:TestDevice:1", 
								 \&callback);
  $cp->handle;

  sub callback {
	my ($search, $device, $action) = @_;

	if ($action eq 'deviceAdded') {
	  print("Device: " . $device->friendlyName . " added. Device contains:\n");
	  for my $service ($device->services) {
		print("\tService: " . $service->serviceType . "\n");
	  }
	}
	elsif ($action eq 'deviceRemoved') {
	  print("Device: " . $device->friendlyName . " removed\n");
	}
  }

=head1 DESCRIPTION

Implements a UPnP ControlPoint. This module implements the various
aspects of the UPnP architecture from the standpoint of a ControlPoint:

=over 4

=item 1. Discovery 

A ControlPoint can be used to actively search for devices and services
on a local network or listen for announcements as devices enter and
leave the network. The protocol used for discovery is the Simple
Service Discovery Protocol (SSDP).

=item 2. Description 

A ControlPoint can get information describing devices and
services. Devices can be queried for services and vendor-specific
information. Services can be queried for actions and state variables.

=item 3. Control 

A ControlPoint can invoke actions on services and poll for state
variable values. Control-related calls are generally made using the
Simple Object Access Protocol (SOAP).

=item 4. Eventing 

ControlPoints can listen for events describing state changes in
devices and services. Subscription requests and state change events
are generally sent using the General Event Notification Architecture
(GENA).

=back

Since the UPnP architecture leverages several existing protocols such
as TCP, UDP, HTTP and SOAP, this module requires several Perl modules
that implement these protocols. These include
L<IO::Socket::INET|IO::Socket::INET>,
L<LWP::UserAgent|LWP::UserAgent>,
L<HTTP::Daemon|HTTP::Daemon> and
C<SOAP::Lite> (L<http://www.soaplite.com>).

=head1 METHODS

=head2 UPnP::ControlPoint

A ControlPoint implementor will generally create a single instance of
the C<UPnP::ControlPoint> class (though more than one can exist within
a process assuming that they have been set up to avoid port
conflicts).

=over 4

=item new ( [ARGS] )

Creates a C<UPnP::ControlPoint> object. Accepts the following
key-value pairs as optional arguments (default values are listed
below):


	SearchPort		  Port on which search requests are received	   8008
	SubscriptionPort  Port on which event notification are received	   8058
	SubscriptionURL	  URL on which event notification are received	   /eventSub
	MaxWait			  Max wait before search responses should be sent  3

While this call creates the sockets necessary for the ControlPoint to
function, the ControlPoint is not active until its sockets are
actually serviced, either by invoking the C<handle>
method or by externally selecting using the ControlPoint's
C<sockets> and invoking the
C<handleOnce> method as each becomes ready for
reading.

=item sockets

Returns a list of sockets that need to be serviced for the
ControlPoint to correctly function. This method is generally used in
conjunction with the C<handleOnce> method by users who want to run
their own C<select> loop.  This list of sockets should be selected for
reading and C<handleOnce> is invoked for each socket as it beoms ready
for reading.

=item handleOnce ( SOCKET )

Handles the function of reading from a ControlPoint socket when it is
ready (as indicated by a C<select>). This method is used by developers
who want to run their own C<select> loop.

=item handle

Takes over handling of all ControlPoint sockets. Runs its own
C<select> loop, handling individual sockets as they become available
for reading.  Returns only when a call to
C<stopHandling> is made (generally from a
ControlPoint callback or a signal handler). This method is an
alternative to using the C<sockets> and
C<handleOnce> methods.

=item stopHandling

Ends the C<select> loop run by C<handle>. This method is generally
invoked from a ControlPoint callback or a signal handler.

=item searchByType ( TYPE, CALLBACK )

Used to start a search for devices on the local network by device or
service type. The C<TYPE> parameter is a string inidicating a device
or service type. Specifically, it is the string that will be put into
the C<ST> header of the SSDP C<M-SEARCH> request that is sent out. The
C<CALLBACK> parameter is a code reference to a callback that is
invoked when a device matching the search criterion is found (or a
SSDP announcement is received that such a device is entering or
leaving the network).  This method returns a
L<C<UPnP::ControlPoint::Search>|/UPnP::ControlPoint::Search> object.

The arguments to the C<CALLBACK> are the search object, the device
that has been found or newly added to or removed from the network, and
an action string which is one of 'deviceAdded' or 'deviceRemoved'. The
callback is invoked separately for each device that matches the search
criterion.


  sub callback {
	my ($search, $device, $action) = @_;

	if ($action eq 'deviceAdded') {
	  print("Device: " . $device->friendlyName . " added.\n");
	}
	elsif ($action eq 'deviceRemoved') {
	  print("Device: " . $device->friendlyName . " removed\n");
	}
  }


=item searchByUDN ( UDN, CALLBACK )

Used to start a search for devices on the local network by Unique
Device Name (UDN). Similar to C<searchByType>, this method sends
out a SSDP C<M-SEARCH> request with a C<ST> header of
C<upnp:rootdevice>. All responses to the search (and subsequent SSDP
announcements to the network) are filtered by the C<UDN> parameter
before resulting in C<CALLBACK> invocation. The parameters to the
callback are the same as described in C<searchByType>.

=item searchByFriendlyName ( NAME, CALLBACK )

Used to start a search for devices on the local network by device
friendy name. Similar to C<searchByType>, this method sends out a
SSDP C<M-SEARCH> request with a C<ST> header of
C<upnp:rootdevice>. All responses to the search (and subsequent SSDP
announcements to the network) are filtered by the C<NAME> parameter
before resulting in C<CALLBACK> invocation. The parameters to the
callback are the same as described in C<searchByType>.

=item stopSearch ( SEARCH )

The C<SEARCH> parameter is a
L<C<UPnP::ControlPoint::Search>|/UPnP::ControlPoint::Search> object
returned by one of the search methods. This method stops forwarding
SSDP events that match the search criteria of the specified search.

=back

=head2 UPnP::ControlPoint::Device

A C<UPnP::ControlPoint::Device> is generally obtained using one of the
L<C<UPnP::ControlPoint>|/UPnP::ControlPoint> search methods and should
not be directly instantiated.

=over 4

=item deviceType 

=item friendlyName 

=item manufacturer 

=item manufacturerURL 

=item modelDescription 

=item modelName 

=item modelNumber 

=item modelURL 

=item serialNumber 

=item UDN

=item presentationURL 

=item UPC

Properties received from the device's description document. The
returned values are all strings.

=item location

A URI representing the location of the device on the network.

=item parent

The parent device of this device. The value C<undef> if this device
is a root device.

=item children

A list of child devices. The empty list if the device has no
children.

=item services

A list of L<C<UPnP::ControlPoint::Service>|/UPnP::ControlPoint::Service>
objects corresponding to the services implemented by this device.

=item getService ( ID )

If the device implements a service whose serviceType or serviceId is
equal to the C<ID> parameter, the corresponding
L<C<UPnP::ControlPoint::Service>|/UPnP::ControlPoint::Service> object
is returned. Otherwise returns C<undef>.

=back

=head2 UPnP::ControlPoint::Service

A C<UPnP::ControlPoint::Service> is generally obtained from a
L<C<UPnP::ControlPoint::Device>|/UPnP::ControlPoint::Device> object
using the C<services> or C<getServiceById> methods. This class should
not be directly instantiated.

=over 4

=item serviceType 

=item serviceId 

=item SCPDURL 

=item controlURL

=item eventSubURL

Properties corresponding to the service received from the containing
device's description document. The returned values are all strings
except for the URL properties, which are absolute URIs.

=item actions

A list of L<C<UPnP::Common::Action>|/UPnP::Common::Action>
objects corresponding to the actions implemented by this service.

=item getAction ( NAME )

Returns the
L<C<UPnP::Common::Action>|/UPnP::Common::Action> object
corresponding to the action specified by the C<NAME> parameter.
Returns C<undef> if no such action exists.

=item stateVariables

A list of
L<C<UPnP::Common::StateVariable>|/UPnP::Common::StateVariable>
objects corresponding to the state variables implemented by this
service.

=item getStateVariable ( NAME )

Returns the
L<C<UPnP::Common::StateVariable>|/UPnP::Common::StateVariable>
object corresponding to the state variable specified by the C<NAME>
parameter.	Returns C<undef> if no such state variable exists.

=item controlProxy

Returns a
L<C<UPnP::ControlPoint::ControlProxy>|/UPnP::ControlPoint::ControlProxy>
object that can be used to invoke actions on the service.

=item queryStateVariable ( NAME )

Generates a SOAP call to the remote service to query the value of the
state variable specified by C<NAME>. Returns the value of the
variable. Returns C<undef> if no such state variable exists or the
variable is not evented.

=item subscribe ( CALLBACK )

Registers an event subscription with the remote service. The code
reference specied by the C<CALLBACK> parameter is invoked when GENA
events are received from the service. This call returns a
L<C<UPnP::ControlPoint::Subscription>|/UPnP::ControlPoint::Subscription>
object corresponding to the subscription. The subscription can later
be canceled using the C<unsubscribe> method.  The parameters to the
callback are the service object and a list of name-value pairs for all
of the state variables whose values are included in the corresponding
GENA event:

  sub eventCallback {
	my ($service, %properties) = @_;

	print("Event received for service " . $service->serviceId . "\n");
	while (my ($key, $val) = each %properties) {
	  print("\tProperty ${key}'s value is " . $val . "\n");
	}
  }


=item unsubscribe ( SUBSCRIPTION )

Unsubscribe from a service. This method takes the
L</UPnP::ControlPoint::Subscription>
object returned from a previous call to C<subscribe>. This method
is equivalent to calling the C<unsubscribe> method on the subscription
object itself and is included for symmetry and convenience.

=back

=head2 UPnP::Common::Action

A C<UPnP::Common::Action> is generally obtained from a
L<C<UPnP::ControlPoint::Service>|/UPnP::ControlPoint::Service> object
using its C<actions> or C<getAction> methods. It corresponds to an
action implemented by the service. Action information is retrieved
from the service's description document. This class should not be
directly instantiated.

=over 4

=item name

The name of the action returned as a string.

=item retval

A L<C<UPnP::Common::Argument>|/UPnP::Common::Argument> object that
corresponds to the action argument that is specified in the service
description document as the return value for this action. Returns
C<undef> if there is no specified return value.

=item arguments

A list of L<C<UPnP::Common::Argument>|/UPnP::Common::Argument> objects
corresponding to the arguments of the action.

=item inArguments

A list of L<C<UPnP::Common::Argument>|/UPnP::Common::Argument> objects
corresponding to the input arguments of the action.

=item outArguments

A list of L<C<UPnP::Common::Argument>|/UPnP::Common::Argument> objects
corresponding to the output arguments of the action.

=back

=head2 UPnP::Common::Argument

A C<UPnP::Common::Argument> is generally obtained from a
L<C<UPnP::Common::Action>|/UPnP::Common::Action> object using its
C<arguments>, C<inArguments> or C<outArguments> methods. An instance
of this class corresponds to an argument of a service action, as
specified in the service's description document. This class should not
be directly instantiated.

=over 4

=item name

The name of the argument returned as a string.

=item relatedStateVariable

The name of the related state variable (which can be used to find the 
type of the argument) returned as a string.

=back

=head2 UPnP::Common::StateVariable

A C<UPnP::Common::StateVariable> is generally obtained from a
L<C<UPnP::ControlPoint::Service>|/UPnP::ControlPoint::Service> object
using its C<stateVariables> or C<getStateVariable> methods. It
corresponds to a state variable implemented by the service. State
variable information is retrieved from the service's description
document. This class should not be directly instantiated.

=over 4

=item name

The name of the state variable returned as a string.

=item evented

Whether the state variable is evented or not.

=item type

The listed UPnP type of the state variable returned as a string.

=item SOAPType

The corresponding SOAP type of the state variable returned as a
string.

=back

=head2 UPnP::ControlPoint::ControlProxy

A proxy that can be used to invoke actions on a UPnP service. An
instance of this class is generally obtained from the C<controlProxy>
method of the corresponding
L<C<UPnP::ControlPoint::Service>|/UPnP::ControlPoint::Service>
object. This class should not be directly instantiated.

An instance of this class is a wrapper on a C<SOAP::Lite> proxy. An
action is invoked as if it were a method of the proxy
object. Parameters to the action should be passed to the method. They
will automatically be coerced to the correct type. For example, to
invoke the C<Browse> method on a UPnP ContentDirectory service to get
the children of the root directory, one would say:


  my $proxy = $service->controlProxy;
  my $result = $proxy->Browse('0', 'BrowseDirectChildren', '*', 0, 0, "");

The result of a action invocation is an instance of the
L<C<UPnP::ControlPoint::ActionResult>|/UPnP::ControlPoint::ActionResult>
class.

=head2 UPnP::ControlPoint::ActionResult

An instance of this class is returned from an action invocation made
through a
L<C<UPnP::ControlPoint::ControlProxy>|/UPnP::ControlPoint::ControlProxy>
object. It is a loose wrapper on the C<SOAP::SOM> object returned from
the call made through the C<SOAP::Lite> module. All methods not
recognized by this class will be forwarded directly to the
C<SOAP::SOM> class. This class should not be directly instantiated.

=over 4

=item isSuccessful

Was the invocation successful or did it result in a fault.

=item getValue ( NAME )

Gets the value of an out argument of the action invocation. The
C<NAME> parameter specifies which out argument value should be 
returned. The type of the returned value depends on the type
specified in the service description file.

=back

=head2 UPnP::ControlPoint::Search

A C<UPnP::ControlPoint::Search> object is returned from any successful
calls to the L<C<UPnP::ControlPoint>|/UPnP::ControlPoint> search
methods. It has no methods of its own, but can be used as a token to
pass to any subsequent C<stopSearch> calls. This class should not be
directly instantiated.

=head2 UPnP::ControlPoint::Subscription

A C<UPnP::ControlPoint::Search> object is returned from any successful
calls to the
L<C<UPnP::ControlPoint::Service>|/UPnP::ControlPoint::Service>
C<subscribe> method. This class should not be directly instantiated.

=over 4

=item SID

The subscription ID returned from the remote service, returned as a
string.

=item timeout

The timeout value returned from the remote service, returned as a
number.

=item expired

Has the subscription expired yet?

=item renew 

Renews a subscription with the remote service by sending a GENA
subscription event.

=item unsubscribe

Unsubscribes from the remote service by sending a GENA unsubscription
event.

=back

=head1 SEE ALSO

UPnP documentation and resources can be found at L<http://www.upnp.org>.

The C<SOAP::Lite> module can be found at L<http://www.soaplite.com>.

UPnP ControlPoint implementations in other languages include the UPnP
SDK for Linux (L<http://upnp.sourceforge.net/>), Cyberlink for Java
(L<http://www.cybergarage.org/net/upnp/java/index.html>) and C++
(L<http://sourceforge.net/projects/clinkcc/>), and the Microsoft UPnP
SDK
(L<http://msdn.microsoft.com/library/default.asp?url=/library/en-us/upnp/upnp/universal_plug_and_play_start_page.asp>).

=head1 AUTHOR

Vidur Apparao (vidurapparao@users.sourceforge.net)

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004-2005 by Vidur Apparao

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

use 5.006;
use strict;
use warnings;

use Carp;
use IO::Socket qw(:DEFAULT :crlf);
use Socket;
use IO::Select;
use HTTP::Daemon;
use HTTP::Headers;
use LWP::UserAgent;
use UPnP::Common;

use		vars qw($VERSION @ISA);

require Exporter;

our @ISA = qw(Exporter UPnP::Common::DeviceLoader);
our $VERSION = $UPnP::Common::VERSION;

use constant DEFAULT_SSDP_SEARCH_PORT => 8008;
use constant DEFAULT_SUBSCRIPTION_PORT => 8058;
use constant DEFAULT_SUBSCRIPTION_URL => '/eventSub';

sub new {
	my($self, %args) = @_;
	my $class = ref($self) || $self;

	$self = $class->SUPER::new(%args);

	my $searchPort = $args{SearchPort} || DEFAULT_SSDP_SEARCH_PORT;
	my $subscriptionPort = $args{SubscriptionPort} || DEFAULT_SUBSCRIPTION_PORT;
	my $maxWait = $args{MaxWait} || 3;

	# Create the socket on which search requests go out
	$self->{_searchSocket} = IO::Socket::INET->new(Proto => 'udp',
												   Reuse => 1,
												   LocalPort => $searchPort) ||
	croak("Error creating search socket: $!\n");
	setsockopt($self->{_searchSocket}, 
			   IP_LEVEL,
			   UPnP::Common::getPlatformConstant('IP_MULTICAST_TTL'),
			   pack 'I', 4) || croak("Error setting multicast ttl sockopt: $!");
	UPnP::Common::blocking($self->{_searchSocket},0);
	$self->{_maxWait} = $maxWait;

	# Create the socket on which we'll listen for events to which we are
	# subscribed.
	$self->{_subscriptionSocket} = HTTP::Daemon->new(
											 Reuse => 1,
											 LocalPort => $subscriptionPort) ||
	croak("Error creating subscription socket: $!\n");
	$self->{_subscriptionURL} = $args{SubscriptionURL} || DEFAULT_SUBSCRIPTION_URL;
	$self->{_subscriptionPort} = $subscriptionPort;

	# Create the socket on which we'll listen for SSDP Notifications.
	$self->{_ssdpMulticastSocket} = IO::Socket::INET->new(
													 Proto => 'udp',
													 Reuse => 1,
													 LocalPort => SSDP_PORT) ||
	croak("Error creating SSDP multicast listen socket: $!\n");
	my $ip_mreq = inet_aton(SSDP_IP) . INADDR_ANY;
	
	setsockopt($self->{_ssdpMulticastSocket}, 
			   IP_LEVEL,
			   UPnP::Common::getPlatformConstant('IP_ADD_MEMBERSHIP'),
			   $ip_mreq) || croak("Error setting multicast sockopt: $!");
	setsockopt($self->{_ssdpMulticastSocket}, 
			   IP_LEVEL,
			   UPnP::Common::getPlatformConstant('IP_MULTICAST_TTL'),
			   pack 'I', 4) || croak("Error setting multicast ttl sockopt: $!");
	UPnP::Common::blocking($self->{_ssdpMulticastSocket}, 0);
	
	# Keep track of failed devices so we don't keep trying them too often
	$self->{failedDevices} = {};
	
	return $self;
}

sub DESTROY {
	my $self = shift;

	for my $subscription (values %{$self->{_subscriptions}}) {
		if ($subscription) {
			$subscription->unsubscribe;
		}
	}
}

sub searchByType {
	my $self = shift;
	my $type = shift;
	my $callback = shift;

	my $search = UPnP::ControlPoint::Search->new(Callback => $callback,
												 Type => $type);
	$self->{_activeSearches}->{$search} = $search;
	$self->_startSearch($type);
	return $search;
}

sub searchByUDN {
	my $self = shift;
	my $udn = shift;
	my $callback = shift;

	my $search = UPnP::ControlPoint::Search->new(Callback => $callback,
												 UDN => $udn);
	$self->{_activeSearches}->{$search} = $search;
	$self->_startSearch("upnp:rootdevice");
	$search;
}

sub searchByFriendlyName {
	my $self = shift;
	my $name = shift;
	my $callback = shift;

	my $search = UPnP::ControlPoint::Search->new(Callback => $callback,
												 FriendlyName => $name);
	$self->{_activeSearches}->{$search} = $search;
	$self->_startSearch("upnp:rootdevice");
	$search;
}

sub stopSearch {
	my $self = shift;
	my $search = shift;

	delete $self->{_activeSearches}->{$search};
}

sub sockets {
	my $self = shift;

	return ($self->{_subscriptionSocket},
			$self->{_ssdpMulticastSocket},
			$self->{_searchSocket},);
}

sub handleOnce {
	my $self = shift;
	my $socket = shift;
	if ($socket == $self->{_searchSocket}) {
		$self->_receiveSearchResponse($socket);
	}
	elsif ($socket == $self->{_ssdpMulticastSocket}) {
		$self->_receiveSSDPEvent($socket);
	}
	elsif ($socket == $self->{_subscriptionSocket}) {
		if (my $connect = $socket->accept()) {
			$self->_receiveSubscriptionNotification($connect);
		}
	}
}

sub handle {
	my $self = shift;
	my @mysockets = $self->sockets();
	my $select = IO::Select->new(@mysockets);

	$self->{_handling} = 1;
	while ($self->{_handling}) {
		my @sockets = $select->can_read(1);
		for my $sock (@sockets) {
			$self->handleOnce($sock);
		}
	}
}

sub stopHandling {
	my $self = shift;
	$self->{_handling} = 0;
}

sub subscriptionURL {
	my $self = shift;
	return URI->new_abs($self->{_subscriptionURL},
						'http://' . UPnP::Common::getLocalIPAddress() . ':' .
						$self->{_subscriptionPort});
}

sub addSubscription {
	my $self = shift;
	my $subscription = shift;

	$self->{_subscriptions}->{$subscription->SID} = $subscription;
}

sub removeSubscription {
	my $self = shift;
	my $subscription = shift;

	delete $self->{_subscriptions}->{$subscription->SID};
}

sub _startSearch {
	my $self = shift;
	my $target = shift;

	my $header = 'M-SEARCH * HTTP/1.1' . CRLF .
		'HOST: ' . SSDP_IP . ':' . SSDP_PORT . CRLF .
		'MAN: "ssdp:discover"' . CRLF .
		'ST: ' . $target . CRLF .
		'MX: ' . $self->{_maxWait} . CRLF .
		CRLF;

	my $destaddr = sockaddr_in(SSDP_PORT, inet_aton(SSDP_IP));
	send($self->{_searchSocket}, $header, 0, $destaddr);
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

sub _firstLocation {
	my $headers = shift;
	my $location = $headers->header('Location');
	
	return $location if $location;

	my $al = $headers->header('AL');
	if ($al && $al =~ /^<(\S+?)>/) {
		return $1;
	}

	return undef;
}

sub newService {
	my $self = shift;

	return UPnP::ControlPoint::Service->new(@_);
}

sub newDevice {
	my $self = shift;

	return UPnP::ControlPoint::Device->new(@_);
}

sub _createDevice {
	my $self = shift;
	my $location = shift;
	my $device;
	
	# If this device failed within the last 10 minutes, don't try it again
	if ( my $lastFailure = $self->{failedDevices}->{$location} ) {
		if ( time - $lastFailure < 60 * 10 ) {
			return;
		}
	}

	# We've found examples of where devices claim to do transfer
	# encoding, but wind up sending chunks without chunk size headers.
	# This code temporarily disables the TE header in the request.
	push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, SendTE => 0);
	my $ua = LWP::UserAgent->new;
	
	# Multicast may find devices on unreachable subnets, so
	# we use a small timeout to keep them from taking forever to fail.
	# 2 seconds should be more than enough time to connect on a LAN
	$ua->timeout(2);
	
	my $response = $ua->get($location);

	my $base;
	if ($response->is_success) {
		delete $self->{failedDevices}->{$location};
		
		($device, $base) = $self->parseDeviceDescription($response->content,
													  {Location => $location},
													  {ControlPoint => $self});
	}
	else {
		$self->{failedDevices}->{$location} = time;
		
		carp("Loading device description failed with error: " . 
			 $response->code . " " . $response->message .
			" Device may be down or on an unreachable subnet.");
	}
	pop(@LWP::Protocol::http::EXTRA_SOCK_OPTS);

	if ($device) {
		$device->base($base ? $base : $location);
	}

	return $device;
}

sub _getDeviceFromHeaders {
	my $self = shift;
	my $headers = shift;
	my $create = shift;

	my $location = _firstLocation($headers);
	my ($udn, $deviceType, $serviceType) = 
		_parseUSNHeader($headers->header('USN'));
	my $device = $self->{_devices}->{$udn};
	if (!defined($device) && $create) {
		$device = $self->_createDevice($location);
		if ($device) {
			$self->{_devices}->{$udn} = $device;
		}
	}
	
	return $device;
}

sub _deviceAdded {
	my $self = shift;
	my $device = shift;
	
	for my $search (values %{$self->{_activeSearches}}) {
		$search->deviceAdded($device);
	}
}

sub _deviceRemoved {
	my $self = shift;
	my $device = shift;

	for my $search (values %{$self->{_activeSearches}}) {
		$search->deviceRemoved($device);
	}
}

sub _receiveSearchResponse {
	my $self = shift;
	my $socket = shift;
	my $buf = '';
	
	recv($socket, $buf, 4096, 0);
	
	if ($buf !~ /\015?\012\015?\012/) {
		return;
	}
	$buf =~ s/^(?:\015?\012)+//;  # ignore leading blank lines
	unless ($buf =~ s/^(\S+)[ \t]+(\S+)[ \t]+(\S+)[^\012]*\012//) {
		# Bad header
		return;
	}

	my $code = $2;
	if ($code ne '200') {
		# We expect a success response code
		return;
	}
	my $headers = UPnP::Common::parseHTTPHeaders($buf);
	my $device = $self->_getDeviceFromHeaders($headers, 1);
	if ($device) {
		$self->_deviceAdded($device);
	}
}

sub _receiveSSDPEvent {
	my $self = shift;
	my $socket = shift;
	my $buf = '';
	
	recv($socket, $buf, 4096, 0);
	
	if ($buf !~ /\015?\012\015?\012/) {
		return;
	}

	$buf =~ s/^(?:\015?\012)+//;  # ignore leading blank lines
	unless ($buf =~ s/^(\S+)[ \t]+(\S+)(?:[ \t]+(HTTP\/\d+\.\d+))?[^\012]*\012//) {
		# Bad header
		return;
	}

	my $method = $1;
	if ($method ne 'NOTIFY') {
		# We only care about notifications
		return;
	}

	my $headers = UPnP::Common::parseHTTPHeaders($buf);
	my $eventType = $headers->header('NTS');
	my $device = $self->_getDeviceFromHeaders($headers, 
											  $eventType =~ /alive/ ?
											  1 : 0);

	if ($device) {
		if ($eventType =~ /alive/) {
			$self->_deviceAdded($device);
		}
		elsif ($eventType =~ /byebye/) {
			$self->_deviceRemoved($device);
			$self->{_devices}->{$device->UDN()} = undef;
		}
	}
}

sub _parseProperty {
	my $self = shift;
	my $element = shift;
	my ($name, $attrs, $children) = @$element;
	my ($key, $value);

	if ($name =~ /property/) {
		my $childElement = $children->[0];
		$key = $childElement->[0];
		$value = $childElement->[2];
	}

	($key, $value);
}


sub _parsePropertySet {
	my $self = shift;
	my $content = shift;
	my %properties = ();

	my $parser = $self->parser;
	my $element = $parser->parse($content);
	if (defined($element) && (ref $element eq 'ARRAY') &&
		$element->[0] =~ /propertyset/) {
		my($name, $attrs, $children) = @$element;
		for my $child (@$children) {
			my ($key, $value) = $self->_parseProperty($child);
			if ($key) {
				$properties{$key} = $value;
			}
		}
	}

	return %properties;
}

sub _receiveSubscriptionNotification {
	my $self = shift;
	my $connect = shift;

	my $request = $connect->get_request();
	if ($request && ($request->method eq 'NOTIFY') &&
		($request->header('NT') eq 'upnp:event') && 
		($request->header('NTS') eq 'upnp:propchange')) {
		my $sid = $request->header('SID');
		my $subscription = $self->{_subscriptions}->{$sid};
		if ($subscription) {
			my %propSet = $self->_parsePropertySet($request->content);
			$subscription->propChange(%propSet);
		}
	}

	$connect->send_response(HTTP::Response->new(HTTP::Status::RC_OK));
	$connect->close;
}


# ----------------------------------------------------------------------

package UPnP::ControlPoint::Device;

use strict;

use vars qw(@ISA);

use UPnP::Common;

our @ISA = qw(UPnP::Common::Device);

sub base {
	my $self = shift;
	my $base = shift;

	if (defined($base)) {
		$self->{_base} = $base;
		
		for my $service ($self->services) {
			$service->base($base);
		}
		
		for my $device ($self->children) {
			$device->base($base);
		}
	}

	return $self->{_base};
}

# ----------------------------------------------------------------------

package UPnP::ControlPoint::Service;

use strict;

use Scalar::Util qw(weaken);
use SOAP::Lite;
use Carp;

use vars qw($AUTOLOAD @ISA %urlProperties);

use UPnP::Common;

our @ISA = qw(UPnP::Common::Service);

for my $prop (qw(SCPDURL controlURL eventSubURL)) {
	$urlProperties{$prop}++;
}

sub new {
	my ($self, %args) = @_;
	my $class = ref($self) || $self;

	$self = $class->SUPER::new(%args);
	if ($args{ControlPoint}) {
		$self->{_controlPoint} = $args{ControlPoint};
		weaken($self->{_controlPoint});
	}

	return $self;
}

sub AUTOLOAD {
	my $self = shift;
	my $attr = $AUTOLOAD;
	$attr =~ s/.*:://;
	return if $attr eq 'DESTROY';	

	my $superior = "SUPER::$attr";
	my $val = $self->$superior(@_);
	if ($urlProperties{$attr}) {
		my $base = $self->base;
		if ($base) {
			return URI->new_abs($val, $base);
		}

		return URI->new($val);
	}

	return $val;
}

sub controlProxy {
	my $self = shift;

	$self->_loadDescription;

	return UPnP::ControlPoint::ControlProxy->new($self);
}

sub queryStateVariable {
	my $self = shift;
	my $name = shift;

	$self->_loadDescription;

	my $var = $self->getStateVariable($name);
	if (!$var) { croak("No such state variable $name"); }
	if (!$var->evented) { croak("Variable $name is not evented"); }

	my $result = SOAP::Lite
		->uri('urn:schemas-upnp-org:control-1-0')
		->proxy($self->controlURL)
		->call('QueryStateVariable' => 
			   SOAP::Data->name('varName')
					   ->uri('urn:schemas-upnp-org:control-1-0')
					   ->value($name));

	if ($result->fault()) {
		carp("Query failed with fault " . $result->faultstring());
		return undef;
	}

	return $result->result;
}

sub subscribe {
	my $self = shift;
	my $callback = shift;
	my $timeout = shift;
	my $cp = $self->{_controlPoint};

	if (defined($cp)) {
		my $url = $self->eventSubURL;
		my $request = HTTP::Request->new('SUBSCRIBE', 
										 "$url");
		$request->header('NT', 'upnp:event');
		$request->header('Callback', '<' . $cp->subscriptionURL . '>');
		$request->header('Timeout', 
						 'Second-' . defined($timeout) ?  $timeout : 'infinite');
		my $ua = LWP::UserAgent->new;
		$ua->timeout(2);
		my $response = $ua->request($request);

		if ($response->is_success &&
			$response->code == 200) {
			my $sid = $response->header('SID');
			$timeout = $response->header('Timeout');
			if ($timeout =~ /^Second-(\d+)$/) {
				$timeout = $1;
			}

			my $subscription = UPnP::ControlPoint::Subscription->new(
										   Service => $self,
										   Callback => $callback,
										   SID => $sid,
										   Timeout => $timeout,
										   EventSubURL => "$url");
			$cp->addSubscription($subscription);
			return $subscription;
		} 
		else {
			carp("Subscription request failed with error: " . 
				 $response->code . " " . $response->message);
		}
	}

	return undef;
}

sub unsubscribe {
	my $self = shift;
	my $subscription = shift;

	my $url = $self->eventSubURL;
	my $request = HTTP::Request->new('UNSUBSCRIBE', 
									 "$url");
	$request->header('SID', $subscription->SID);
	my $ua = LWP::UserAgent->new;
	$ua->timeout(2);
	my $response = $ua->request($request);
	
	if ($response->is_success) {
		my $cp = $self->{_controlPoint};
		
		if (defined($cp)) {
			$cp->removeSubscription($subscription);
		}
	}
	else {
		carp("Unsubscription request failed with error: " . 
			 $response->code . " " . $response->message);
	}
}

sub _loadDescription {
	my $self = shift;

	if ($self->{_loadedDescription}) {
		return;
	}

	my $location = $self->SCPDURL;
	my $cp = $self->{_controlPoint};
	unless (defined($location)) {
		carp("Service doesn't have a SCPD location");
		return;
	}
	unless (defined($cp)) {
		carp("ControlPoint instance no longer exists");
		return;
	}
	my $parser = $cp->parser;

	push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, SendTE => 0);
	my $ua = LWP::UserAgent->new;
	$ua->timeout(2);
	my $response = $ua->get($location);
	
	if ($response->is_success) {
		$self->parseServiceDescription($parser, $response->content);
	}
	else {
		carp("Error loading SCPD document: $!");
	}

	pop(@LWP::Protocol::http::EXTRA_SOCK_OPTS);

	$self->{_loadedDescription} = 1;
}

# ----------------------------------------------------------------------

package UPnP::ControlPoint::ControlProxy;

use strict;

use SOAP::Lite;
use Carp;

use vars qw($AUTOLOAD);


sub new {
	my($class, $service) = @_;

	return bless {
		_service => $service,
		_proxy => SOAP::Lite->uri($service->serviceType)->proxy($service->controlURL, timeout => 5),
	}, $class;
}

sub AUTOLOAD {
	my $self = shift;
	my $service = $self->{_service};
	my $proxy = $self->{_proxy};
	my $method = $AUTOLOAD;
	$method =~ s/.*:://;
	return if $method eq 'DESTROY';	  

	my $action = $service->getAction($method);
	croak "invalid method: ->$method()" unless $action;

	my @inArgs;
	for my $arg ($action->inArguments) {
		my $val = shift;
		my $type = $service->getArgumentType($arg);
		push @inArgs, SOAP::Data->type($type => $val)->name($arg->name);
	}
	
	my $result;
	eval {
	  $result = UPnP::ControlPoint::ActionResult->new(
									  Action => $action,
									  Service => $service,
									  SOM => $proxy->call($method => @inArgs));
	};
	
	return $result;
}

# ----------------------------------------------------------------------

package UPnP::ControlPoint::ActionResult;

use strict;

use SOAP::Lite;
use HTML::Entities ();
use Carp;

use vars qw($AUTOLOAD);

sub new {
	my($class, %args) = @_;
	my $som = $args{SOM};
	
	my $self = bless {
		_som => $som,
	}, $class;

	unless (defined($som->fault())) {
		for my $out ($args{Action}->outArguments) {
			my $name = $out->name;
			my $data = $som->match('/Envelope/Body//' . $name)->dataof();
			if ($data) {
				my $type = $args{Service}->getArgumentType($out);
				$data->type($type);
				if ($type eq 'string') {
					$self->{_results}->{$name} = HTML::Entities::decode(
															   $data->value);
				}
				else {
					$self->{_results}->{$name} = $data->value;
				}
			}
		}
	}

	return $self;
}

sub isSuccessful {
	my $self = shift;

	return !defined($self->{_som}->fault());
}

sub getValue {
	my $self = shift;
	my $name = shift;

	if (defined($self->{_results})) {
		return $self->{_results}->{$name};
	}

	return undef;
}

sub AUTOLOAD {
	my $self = shift;
	my $method = $AUTOLOAD;
	$method =~ s/.*:://;
	return if $method eq 'DESTROY';	  

	return $self->{_som}->$method(@_);
}

# ----------------------------------------------------------------------

package UPnP::ControlPoint::Search;

use strict;

sub new {
	my($class, %args) = @_;

	return bless {
		_callback => $args{Callback},
		_type => $args{Type},
		_udn => $args{UDN},
		_friendlyName => $args{FriendlyName},
	}, $class;
}

sub _passesFilter {
	my $self = shift;
	my $device = shift;
	
	my $type = $self->{_type};
	my $name = $self->{_friendlyName};
	my $udn = $self->{_udn};

	if ((!defined($type) || ($type eq $device->deviceType()) || 
		 ($type eq 'ssdp:all')) &&
		(!defined($name) || ($name eq $device->friendlyName())) &&
		(!defined($udn) || ($udn eq $device->udn()))) {
		return 1;
	}

	return 0;
}

sub deviceAdded {
	my $self = shift;
	my $device = shift;

	if ($self->_passesFilter($device) &&
		!$self->{_devices}->{$device}) {
		&{$self->{_callback}}($self, $device, 'deviceAdded');
		$self->{_devices}->{$device}++;
	}
}

sub deviceRemoved {
	my $self = shift;
	my $device = shift;

	if ($self->_passesFilter($device) &&
		$self->{_devices}->{$device}) {
		&{$self->{_callback}}($self, $device, 'deviceRemoved');
		delete $self->{_devices}->{$device};
	}
}

# ----------------------------------------------------------------------

package UPnP::ControlPoint::Subscription;

use strict;

use Time::HiRes;
use Scalar::Util qw(weaken);
use Carp;

sub new {
	my($class, %args) = @_;

	my $self = bless {
		_callback => $args{Callback},
		_sid => $args{SID},
		_timeout => $args{Timeout},
		_startTime => Time::HiRes::time(),
		_eventSubURL => $args{EventSubURL},
	}, $class;
	weaken($self->{_service} = $args{Service});

	return $self;
}

sub SID {
	my $self = shift;

	return $self->{_sid};
}

sub timeout {
	my $self = shift;

	return $self->{_timeout};
}

sub expired {
	my $self = shift;

	if ($self->{_timeout} eq 'INFINITE') {
		return 0;
	}

	my $now = Time::HiRes::time();
	if ($now - $self->{_startTime} > $self->{_timeout}) {
		return 1;
	}

	return 0;
}

sub renew {
	my $self = shift;
	my $timeout = shift;

	my $url = $self->{_eventSubURL};
	my $request = HTTP::Request->new('SUBSCRIBE', 
									 "$url");
	$request->header('SID', $self->{_sid});
	$request->header('Timeout', 
					 'Second-' . defined($timeout) ? $timeout : 'infinite');

	my $ua = LWP::UserAgent->new;
	$ua->timeout(2);
	my $response = $ua->request($request);

	if ($response->is_success) {
		$timeout = $response->header('Timeout');
		if ($timeout =~ /^Second-(\d+)$/) {
			$timeout = $1;
		}

		$self->{_timeout} = $timeout;
		$self->{_startTime} = Time::HiRes::time();
	}
	else {
		carp("Renewal of subscription failed with error: " . 
			 $response->code . " " . $response->message);
	}
	
	return $self;
}

sub unsubscribe {
	my $self = shift;

	if ($self->{_service}) {
		$self->{_service}->unsubscribe($self);
	}
}

sub propChange {
	my $self = shift;
	my %properties = @_;

	if ($self->{_service}) {
		&{$self->{_callback}}($self->{_service}, %properties);
	}
}

1;
__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
