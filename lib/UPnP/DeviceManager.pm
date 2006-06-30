package UPnP::DeviceManager;

=pod

=head1 NAME

UPnP::DeviceManager - A UPnP Device host implementation.

=head1 SYNOPSIS

  use UPnP;

  my $dm = UPnP::DeviceManager->new;
  my $device = $dm->registerDevice(DescriptionFile => 'description.xml',
								   ResourceDirectory => '.');
  my $service = $device->getService('urn:schemas-upnp-org:service:TestService:1');
  $service->dispatchTo('MyPackage::MyClass');
  $service->setValue('TestVariable', 'foo');
  $dm->handle;

=head1 DESCRIPTION

Implements a UPnP Device host. This module implements the various
aspects of the UPnP architecture from the standpoint of a host of
one or more devices:

=over 4

=item * Discovery

Devices registered with the DeviceManager will automatically advertise
themselves and respond to UPnP searches.

=item * Description 

Devices register themselves with description documents. These
descriptions are served via HTTP to interested ControlPoints.

=item * Control 

Devices respond to action invocations and state queries from
ControlPoints.

=item * Eventing 

Changes to device state result in events sent to interested
subscribers.

=back

Since the UPnP architecture leverages several existing protocols such
as TCP, UDP, HTTP and SOAP, this module requires several Perl modules
that implement these protocols. These include
L<IO::Socket::INET|IO::Socket::INET>,
L<LWP::UserAgent|LWP::UserAgent>, L<HTTP::Daemon|HTTP::Daemon> and
C<SOAP::Lite> (L<http://www.soaplite.com>).

=head1 METHODS

=head2 UPnP::DeviceManager

A Device implementor will generally create a single instance of
the C<UPnP::DeviceManager> class and register one or more devices
with it.

=over 4

=item new ( [ARGS] )

Creates a C<UPnP::DeviceManager> object. Accepts the following
key-value pairs as optional arguments (default values are listed
below):


	NotificationPort  Port from which SSDP notifications are made	 4003

A DeviceManager only becomes functional after devices are registered
with it using the C<registerDevice> method and the sockets it creates
are serviced. Socket management can be done in one of two ways: by
invoking the C<handle> method; or by externally selecting the
DeviceManage's C<sockets>, invoking the C<handleOnce> method as each
becomes ready for reading, and invoking the C<heartbeat> method on a
time to send out any pending device notifications.

=item registerDevice ( [ARGS] )

Registers a device with the DeviceManager. This call takes the
following optional key-value pairs as arguments (default values are
listed below):

	DevicePort		Port on which the device serves requests		4004
	DescriptionURI	The relative URI for the description document	/description.xml
	LeaseTime		The length of the device's lease				1800

The call also takes the following B<required> arguments:

	Description		   A string containing the XML device description
	DescriptionFile	   The path to a file containing the XML device description
	ResourceDirectory  The path to a directory containing resources referred
					   to in the device description

Only one of the Description or DescriptionFile arguments should be
specified.

If successful, returns a
L<C<UPnP::DeviceManager::Device>|/UPnP::DeviceManager::Device> object.
The device itself does not advertise itself till its C<start> method
is invoked.

=item devices

Returns a list of registered devices.

=item sockets

Returns a list of sockets that need to be serviced for the
DeviceManager to correctly function. This method is generally used in
conjunction with the C<handleOnce> method by users who want to run
their own C<select> loop.  This list of sockets should be selected for
reading and C<handleOnce> is invoked for each socket as it beoms ready
for reading. This method should only be called I<after> all devices
have been registered.

=item handleOnce ( SOCKET )

Handles the function of reading from a DeviceManager socket when it is
ready (as indicated by a C<select>). This method is used by developers
who want to run their own C<select> loop.

=item heartbeat

Sends any pending notifications and returns a timeout value after
which this method should be invoked again. This method is used by
developers who want to run their own C<select> loop.

=item handle

Takes over handling of all ControlPoint sockets. Runs its own
C<select> loop, handling individual sockets as they become available
for reading and invoking the C<heartbeat> call at the required
interval.  Returns only when a call to C<stopHandling> is made
(generally from a Device callback or a signal handler). This
method is an alternative to using the C<sockets>, C<handleOnce>
and C<heartbeat> methods.

=item stopHandling

Ends the C<select> loop run by C<handle>. This method is generally
invoked from a Device callback or a signal handler.

=back

=head2 UPnP::DeviceManager::Device

A C<UPnP::DeviceManager::Device> object is obtained by registering a
device with a DeviceManager. This class should not be directly
instantiated.

=over 4

=item start

Called to start a device. Sends out the SSDP initial announcement of
the device's presence and allows the device to respond to SSDP
queries.

=item stop

Called to stop a device. Sends out an SSDP byebye announcement.

=item advertise

Called to manually send out an SSDP announcement for the device, its
child devices, and its services. Can be called if SSDP announcements
should be sent out more frequently than the device's lease
time. Otherwise, announcements are sent automatically when the
device's lease runs out.

=item leastTime

The lease length of the device.

=item services

A list of L<C<UPnP::ControlPoint::Service>|/UPnP::ControlPoint::Service>
objects corresponding to the services implemented by this device.

=item getService ( ID )

If the device implements a service whose serviceType or serviceId is
equal to the C<ID> parameter, the corresponding
L<C<UPnP::ControlPoint::Service>|/UPnP::ControlPoint::Service> object
is returned. Otherwise returns C<undef>.

=back

=head2 UPnP::DeviceManager::Service

A C<UPnP::DeviceManager::Service> is generally obtained from a
L<C<UPnP::DeviceManager::Device>|/UPnP::DeviceManager::Device> object
using the C<services> or C<getServiceById> methods. This class should
not be directly instantiated.

=over 4

=item dispatchTo ( MODULE )

Used to specify the name of a module which implements all control
actions for this service. When an action invocation comes in, the
corresponding function in the module will be invoked. The parameters
to the function are the module name I<(Ed: should get rid of this
SOAP::Lite vestige)> and the parameters passed in the SOAP
invocation. The function should return a list of all out parameters to
be sent to the invoker. For example, a hypothetical UPnP thermometer
might implement a GetTemperature action:

  $service->dispatchTo('Thermometer');
  ...
  package Thermometer;

  sub GetTemperature {
	my $class = shift;
	my $scale = shift;

	Code to look up temperature and return in the given scale...

	return $temp;
  }
 

A mutually exclusive alternative to directly dispatching to a module
is to use the C<onAction> callback method.

=item setValue ( [NAME => VALUE]+ )

Used to set the values of state variables for the service. The
parameters to this call should be name-value pairs for one or more
evented state variables for the service. Results in GENA
notifications to any subscribers to this service. 

The value of the state variable is remembered by the service
instance. Device implementors who do not need to dynamically look up
their state variables using the C<onQuery> callback below can set the
values of state variables before starting a device. All state queries
will then be automatically dealt with.

=item onAction ( CALLBACK )

Can be used to specify a callback function for dealing with action
invocations. The C<CALLBACK> parameter must be a CODE ref. This is a
mutually exclusive alternative to directly dispatching actions to a
Perl module. The callback is invoked anytime the DeviceManager
receives a control SOAP call. Parameters to the callback are the
service object, the action name and the parameters sent over SOAP. The
equivalent to the hypothetical thermometer implementation described
above is:

  $service->onAction(\&actionSub);
  ...
  sub actionSub {
	my $service = shift;
	my $action = shift;
  
	if ($action eq 'GetTemperature') {
	  my $scale = shift;
	  Code to look up temperature and return in the given scale...
	  return $temp;
	}

	return undef;
  }

=item onQuery ( CALLBACK )

Can be used to specify a callback function for dealing with state
queries.  The C<CALLBACK> parameter must be a CODE ref. This is an
alternative to setting the values of state variables up-front and
allows state to be looked up dynamically. The callback will be invoked
once per state variable query. For event subscriptions, the callback
will be invoked for each of the evented state variables. Paramters to
the callback are the service, the name of the state variable and the
last known value of the variable (returned from a previous call to the
onQuery callback or set using the C<setValue> method).

  $service->onAction(\&querySub);

  sub onquery {
	my ($service, $name, $val) = @_;

	Code to look up value of state variable...

	return $newval;
  }

=back

=head1 SEE ALSO

UPnP documentation and resources can be found at L<http://www.upnp.org>.

The C<SOAP::Lite> module can be found at L<http://www.soaplite.com>.

UPnP Device management implementations in other languages include the
UPnP SDK for Linux (L<http://upnp.sourceforge.net/>), Cyberlink for
Java (L<http://www.cybergarage.org/net/upnp/java/index.html>) and C++
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
use Scalar::Util;
use Time::HiRes;
use UPnP::Common;
use HTTP::Response;

use		vars qw($VERSION @ISA);

require Exporter;

our @ISA = qw(Exporter UPnP::Common::DeviceLoader);
our $VERSION = $UPnP::Common::VERSION;

use constant DEFAULT_DEVICE_PORT => 4004;
use constant DEFAULT_DESCRIPTION_URI => '/description.xml';
use constant DEFAULT_LEASE_TIME => 1800;
use constant DEFAULT_NOTIFICATION_PORT => 4003;

sub new {
	my($self, %args) = @_;
	my $class = ref($self) || $self;

	$self = $class->SUPER::new(%args);

	my $notificationPort = $args{NotificationPort} || 
		DEFAULT_NOTIFICATION_PORT;

	# Create the socket on which SSDP notifications go out
	$self->{_ssdpNotificationSocket} = IO::Socket::INET->new(
											Reuse => 1,
											Proto => 'udp',
											LocalPort => $notificationPort) ||
		croak("Error creating SSDP notification socket: $!\n");
	setsockopt($self->{_ssdpNotificationSocket}, 
			   IP_LEVEL,
			   UPnP::Common::getPlatformConstant('IP_MULTICAST_TTL'),
			   pack 'I', 4);
	UPnP::Common::blocking($self->{_ssdpNotificationSocket}, 0);

	# Create the socket on which we'll listen for SSDP queries.
	$self->{_ssdpListenSocket} = IO::Socket::INET->new(
													 Proto => 'udp',
													 Reuse => 1,
													 LocalPort => SSDP_PORT) ||
		croak("Error creating SSDP multicast listen socket: $!\n");
	my $ip_mreq = inet_aton(SSDP_IP) . INADDR_ANY;
	setsockopt($self->{_ssdpListenSocket}, 
			   IP_LEVEL,
			   UPnP::Common::getPlatformConstant('IP_ADD_MEMBERSHIP'),
			   $ip_mreq);
	setsockopt($self->{_ssdpListenSocket}, 
			   IP_LEVEL,
			   UPnP::Common::getPlatformConstant('IP_MULTICAST_TTL'),
			   pack 'I', 4);
	UPnP::Common::blocking($self->{_ssdpListenSocket},0);
	
	$self->{_pendingNotifications} = [];
	$self->{_devices} = [];

	return $self;
}

sub registerDevice {
	my ($self, %args) = @_;

	my $devicePort = $args{DevicePort} || DEFAULT_DEVICE_PORT;
	my $descriptionURI = $args{DescriptionURI} || DEFAULT_DESCRIPTION_URI;
	my $leaseTime = $args{LeaseTime} || DEFAULT_LEASE_TIME;
	my $description = $args{Description};
	my $file = $args{DescriptionFile};
	my $resourceDir = $args{ResourceDirectory} ||
		croak("Resource directory must be specified for device registration");

	unless ($description || $file) {
		croak("Device must have a device description");
	}

	if ($file) {
		$description = loadFile($file);
	}

	# Set the location of the device
	my $base = 'http://' . UPnP::Common::getLocalIPAddress() . ':' . $devicePort;
	my $location = URI->new_abs($descriptionURI, $base);

	my ($device) = $self->parseDeviceDescription($description,
											   {DeviceManager => $self,
												Location => "$location",
												LeaseTime => $leaseTime},
											   {DeviceManager => $self,
												ResourceDir => $resourceDir});

	if ($device) {
		# Update the description with a URLBase element containing the
		# location
		$description =~ s/<\/root>/<URLBase>$base<\/URLBase><\/root>/;

		# Create HTTP handler for the device's various URLs.
		my $handler = UPnP::DeviceManager::HTTPHandler->new(
									   DevicePort => $devicePort,
									   DescriptionURI => $descriptionURI,
									   DeviceDescription => $description,
									   ResourceDirectory => $resourceDir,
									   Device => $device,
									   Server => $self->server);			   
		$device->handler($handler);
		$self->{_handlers}->{$handler->socket} = $handler;
		push @{$self->{_devices}}, $device;
	}

	return $device;
}

sub sockets {
	my $self = shift;

	return ($self->{_ssdpListenSocket}, 
			map { $_->socket } values %{$self->{_handlers}});
}

sub devices {
	my $self = shift;
	return @{$self->{_devices}};
}

sub handleOnce {
	my $self = shift;
	my $socket = shift;

	if ($socket) {
		if ($socket == $self->{_ssdpListenSocket}) {
			$self->_receiveSSDPEvent($socket);
		}
		elsif (my $handler = $self->{_handlers}->{$socket}) {
			$handler->handle();
		}
	}
	
	return $self->heartbeat;
}

sub heartbeat {
	my $self = shift;
	my $interval = DEFAULT_LEASE_TIME;
	my $now = Time::HiRes::time();

	while (scalar(@{$self->{_pendingNotifications}})) {
		my $notification = $self->{_pendingNotifications}->[0];
		my $left = $notification->{Time} - $now;
		if ($left <= 0) {
			&{$notification->{NotifierSub}}();
			shift @{$self->{_pendingNotifications}};
		}
		else {
			$interval = $left if $left < $interval;
			last;
		}
	}

	for my $device (@{$self->{_devices}}) {
		if (defined($device->leaseExpiration)) {
			my $left = $device->leaseExpiration - $now;
			if ($left <= 0) {
				$device->advertise;
				$left = $device->leaseExpiration - $now;
			}

			$interval = $left if $left < $interval;
		}
	}

	return $interval;
}

sub handle {
	my $self = shift;
	my @mysockets = $self->sockets();
	my $select = IO::Select->new(@mysockets);

	$self->{_handling} = 1;
	while ($self->{_handling}) {
		my @sockets = $select->can_read($self->heartbeat);
		for my $sock (@sockets) {
			$self->handleOnce($sock);
		}
	}
}

sub stopHandling {
	my $self = shift;
	$self->{_handling} = 0;
}

sub newService {
	my $self = shift;

	return UPnP::DeviceManager::Service->new(@_);;
}

sub newDevice {
	my $self = shift;

	return UPnP::DeviceManager::Device->new(@_);
}

sub addNotification {
	my ($self, $when, $notifiersub) = @_;

	push @{$self->{_pendingNotifications}}, {
		Time => $when,
		NotifierSub => $notifiersub,
	};

	$self->{_pendingNotifications} = [sort { $a->{Time} <=>
											 $b->{Time} } 
								  @{$self->{_pendingNotifications}}];
}

sub _receiveSSDPEvent {
	my $self = shift;
	my $socket = shift;

	my $buf = '';

	my $peer = recv($socket, $buf, 2048, 0);

	if ($buf !~ /\015?\012\015?\012/) {
		return;
	}

	$buf =~ s/^(?:\015?\012)+//;  # ignore leading blank lines
	if (!($buf =~ s/^(\S+)[ \t]+(\S+)(?:[ \t]+(HTTP\/\d+\.\d+))?[^\012]*\012//)) {
		# Bad header
		return;
	}

	my $method = $1;
	if ($method ne 'M-SEARCH') {
		# We only care about searches
		return;
	}

	my $headers = UPnP::Common::parseHTTPHeaders($buf);
	my $target = $headers->header('ST');
	my $mx = $headers->header('MX');
	
	my @matches;
	for my $device (@{$self->{_devices}}) {
		push @matches, $device->matches($target);
	}

	if (scalar(@matches)) {
		my $now = Time::HiRes::time();
		my $interval = rand($mx);
		for my $ref (@matches) {
			my ($device, $usn, $st) = @$ref;
			$self->addNotification($now + $interval,
								   sub {
									   $self->_sendSearchResponse({
										   ST => $st,
										   Location => $device->location,
										   Cache => 'max-age=' . $device->leaseTime,
										   USN => $usn,
										   Destination => $peer,
									   });
								   });
		}
	}
}

sub _sendSearchResponse {
	my $self = shift;
	my $response = shift;

	my $r = HTTP::Response->new(HTTP::Status::RC_OK);
	$r->protocol('HTTP/1.1');
	$r->header('Location', $response->{Location});
	$r->header('Server', $self->server);
	$r->header('USN', $response->{USN});
	$r->header('Cache-control', $response->{Cache});
	$r->header('ST', $response->{ST});
	$r->header('EXT', '');

	send($self->{_ssdpNotificationSocket}, $r->as_string, 0, 
		 $response->{Destination});
}

sub sendAdvertisement {
	my $self = shift;
	my $device = shift;
	my $alive = shift;

	my $request = HTTP::Request->new('NOTIFY' => '*');
	$request->protocol('HTTP/1.1');
	$request->header('Location', $device->location);
	$request->header('Host', SSDP_IP . ':' . SSDP_PORT);
	$request->header('Server', $self->server);
	$request->header('NTS', $alive ? 'ssdp:alive' : 'ssdp:byebye');
	$request->header('Cache-control', 'max-age = ' . $device->leaseTime);
	
	my $destaddr = sockaddr_in(SSDP_PORT, inet_aton(SSDP_IP));
	
	if (!defined($device->parent)) {
		$request->header('NT', 'upnp:rootdevice');
		$request->header('USN', $device->UDN . '::upnp:rootdevice');
		send($self->{_ssdpNotificationSocket}, $request->as_string, 0, 
			 $destaddr);
	}

	$request->header('NT', $device->UDN);
	$request->header('USN', $device->UDN);
	send($self->{_ssdpNotificationSocket}, $request->as_string, 0, $destaddr);

	$request->header('NT', $device->deviceType);
	$request->header('USN', $device->UDN . '::' . 
					 $device->deviceType );
	send($self->{_ssdpNotificationSocket}, $request->as_string, 0, $destaddr);

	for my $service ($device->services) {
		$request->header('NT', $service->serviceType);
		$request->header('USN', $device->UDN . '::' . 
						 $service->serviceType);
		send($self->{_ssdpNotificationSocket}, $request->as_string, 0, 
			 $destaddr);
	}
}

sub loadFile {
	my $file = shift;
	my $str = '';

	open FH, "< $file" || croak "Couldn't open file $file: $!";
	while (<FH>) {
		$str .= $_;
	}
	
	return $str;
}

sub server {
	return $^O . ', UPnP/1.0, Perl UPnP Stack/' . $VERSION;
}

# ----------------------------------------------------------------------

package UPnP::DeviceManager::Device;

use strict;

use vars qw(@ISA);

use Scalar::Util qw(weaken);
use Time::HiRes;
use UPnP::Common;

our @ISA = qw(UPnP::Common::Device);

sub new {
	my $self = shift;
	my $class = ref($self) || $self;
	my %args = @_;

	$self = $class->SUPER::new(%args);
	if ($args{DeviceManager}) {
		weaken($self->{_deviceManager} = $args{DeviceManager});
	}
	if ($args{LeaseTime}) {
		$self->{_leaseTime} = $args{LeaseTime};
	}

	return $self;
}

sub start {
	my $self = shift;

	if ($self->{_deviceManager}) {
		# The Vendors Implementation Guide recommends waiting a small
		# random time before a device announces itself to prevent
		# network saturation when many devices come up together.
		my $interval = rand(2);
		$self->{_deviceManager}->addNotification(
											Time::HiRes::time() + $interval,
											sub {
												$self->advertise(1);
											});
	}
}

sub stop {
	my $self = shift;

	$self->advertise(0);
}

sub leaseTime {
	my $self = shift;

	$self->{_leaseTime} = shift if @_;

	return $self->{_leaseTime};
}

sub leaseExpiration {
	my $self = shift;

	$self->{_leaseExpiration} = shift if @_;

	return $self->{_leaseExpiration};
}

sub advertise {
	my $self = shift;
	my $alive = shift;
	
	if (defined($self->{_deviceManager})) {
		$self->{_deviceManager}->sendAdvertisement($self, 
											   defined($alive) ? $alive : 1);
		$self->leaseExpiration(Time::HiRes::time() + $self->leaseTime);
	}
}

sub matches {
	my $self = shift;
	my $target = shift;
	my @matches = ();

	if ($target eq 'ssdp:all') {
		push @matches, [$self, $self->UDN . '::upnp:rootdevice',
						'upnp:rootdevice'];
		push @matches, [$self, $self->UDN, $self->UDN];
		push @matches, [$self, $self->UDN . '::' . 
						$self->deviceType, $self->deviceType];
		for my $service ($self->services) {
			push @matches, [$self, $self->UDN . '::' . 
							$service->serviceType, $service->serviceType];
		}
	}
	elsif ($target eq 'upnp:rootdevice') {
		if (!defined($self->parent)) {
			push @matches, [$self, $self->UDN . '::upnp:rootdevice',
							$target];
		}
	}
	elsif ($target eq $self->UDN) {
		push @matches, [$self, $self->UDN, $target];
	}
	elsif ($target eq $self->deviceType) {
		push @matches, [$self, $self->UDN . '::' . $target, $target];
	}
	else {
		for my $service ($self->services) {
			if ($target eq $service->serviceType) {
				push @matches, [$self, 
								$self->UDN . '::' . 
								$service->serviceType, $target];
			}
		}
	}

	return @matches;
}

sub handler {
	my $self = shift;
	my $handler = shift;

	if (defined($handler)) {
		weaken($self->{_handler} = $handler);
		
		for my $device ($self->children) {
			$device->handler($handler);
		}

		for my $service ($self->services) {
			$service->handler($handler);
		}
	}

	return $self->{_leaseTime};
}

# ----------------------------------------------------------------------

package UPnP::DeviceManager::Service;

use strict;

use vars qw(@ISA);

use Carp;
use Scalar::Util qw(weaken);
use File::Spec::Functions qw(:ALL);
use Time::HiRes;
use UPnP::Common;

our @ISA = qw(UPnP::Common::Service);

sub new {
	my $self = shift;
	my $class = ref($self) || $self;
	my %args = @_;

	$self = $class->SUPER::new;
	if ($args{DeviceManager}) {
		weaken($self->{_deviceManager} = $args{DeviceManager});
	}
	if ($args{ResourceDir}) {
		$self->{_resourceDir} = $args{ResourceDir};
	}

	$self->{_stateVariableValues} = {};
	$self->{_subscribers} = {};
	$self->{_nextSID} = 0;

	return $self;
}

sub dispatchTo {
	my $self = shift;

	if (@_) {
		$self->{_dispatchTo} = shift;
		if ($self->{_handler}) {
			my $dw = $self->{_handler}->dispatch_with;
			$dw->{$self->serviceType} = $self->{_dispatchTo};
			$self->{_handler}->dispatch_with($dw);
		}
	}

	return $self->{_dispatchTo};
}

sub onAction {
	my $self = shift;
	
	if (@_) {
		my $ref = shift;
		if (ref $ref eq 'CODE') {
			$self->{_onAction} = $ref;
		}
		else {
			croak("onAction handler must be a code ref");
		}
	}

	return $self->{_onAction};
}

sub onQuery {
	my $self = shift;
	
	if (@_) {
		my $ref = shift;
		if (ref $ref eq 'CODE') {
			$self->{_onQuery} = $ref;
		}
		else {
			croak("onQuery handler must be a code ref");
		}
	}

	return $self->{_onQuery};
}

sub setValue {
	my $self = shift;
	my %variables = @_;
	my @subscribers = $self->subscribers;

	for (my ($name, $val) = each %variables) {
		$self->{_stateVariableValues}->{$name} = $val;
	}

	for my $subscriber (@subscribers) {
		$subscriber->notify(%variables);
	}
}

sub getValue {
	my $self = shift;
	my $name = shift;
	my $var = $self->getStateVariable($name);
	my $val;

	my $onquery = $self->onQuery;
	if ($var->evented) {
		$val = $self->{_stateVariableValues}->{$name};
		if ($onquery) {
			$self->{_stateVariableValues}->{$name} = $val = &$onquery($self,
																	  $name,
																	  $val);
		}
	}

	return $val;
}

sub handler {
	my $self = shift;

	weaken($self->{_handler} = shift) if @_;

	return $self->{_handler};
}

sub _loadDescription {
	my $self = shift;

	if ($self->{_loadedDescription}) {
		return;
	}

	my $uri = $self->SCPDURL;
	my $dm = $self->{_deviceManager};
	unless (defined($uri) && defined($dm)) {
		return;
	}
	my $parser = $dm->parser;

	$uri =~ s/^\///;	
	my $file = rel2abs($uri, $self->{_resourceDir});
	if (-e $file) {
		my $content = UPnP::DeviceManager::loadFile($file);
		$self->parseServiceDescription($parser, $content);
	}

	$self->{_loadedDescription} = 1;
}

sub subscribers {
	my $self = shift;
	
	return values %{$self->{_subscribers}};
}

sub getSubscriber {
	my $self = shift;
	my $sid = shift;

	return $self->{_subscribers}->{$sid};
}

sub addSubscriber {
	my $self = shift;
	my $subscriber = shift;
	my $sid = 'uuid:' . $self->{_nextSID}++;
	
	$subscriber->sid($sid);
	$self->{_subscribers}->{$sid} = $subscriber;
	if ($self->{_deviceManager}) {
		my $now = Time::HiRes::time();
		$self->{_deviceManager}->addNotification($now,
								sub {
									$self->initialNotification($subscriber);
								});
	}
	
	return $sid;
}

sub removeSubscriber {
	my $self = shift;
	my $sid = shift;
	
	$self->{_subscribers}->{$sid} = undef;
}

sub initialNotification {
	my $self = shift;
	my $subscriber = shift;
	my %variables;

	my $onquery = $self->onQuery;
	for my $var ($self->stateVariables) {
		if ($var->evented) {
			my $name = $var->name;
			$variables{$name} = $self->getValue($name) || '';
		}
	}

	$subscriber->notify(%variables);
}


# ----------------------------------------------------------------------

package UPnP::DeviceManager::HTTPHandler;

use strict;

use Carp;
use HTTP::Daemon;
use SOAP::Lite;
use SOAP::Transport::HTTP;
use File::Spec::Functions qw(:ALL);

use		vars qw($AUTOLOAD @ISA);

our @ISA = qw(SOAP::Transport::HTTP::Server);

sub new {
	my $self = shift;

	unless (ref $self) {
		my $class = ref($self) || $self;
		my %args = @_;

		my $serializer = UPnP::DeviceManager::Serializer->new;
		$self = $class->SUPER::new(
						  serializer => $serializer,
						  on_dispatch => sub {
							  $serializer->onDispatch(@_);
						  },
						  dispatch_to => ('UPnP::DeviceManager::Serializer'),);
		$self->on_action(sub {});
		$self->{_daemon} = HTTP::Daemon->new(Reuse => 1,
											 LocalPort => $args{DevicePort}) ||
			croak("Failed to create HTTP::Daemon: $!");
		$self->{_descriptionURI} = $args{DescriptionURI};
		$self->{_description} = $args{DeviceDescription};
		$self->{_resourceDir} = $args{ResourceDirectory};
		$self->{_server} = $args{Server};
		$self->_fillServiceTables($args{Device});
	}

	return $self;
}

sub _fillServiceTables {
	my $self = shift;
	my $device = shift;

	for my $service ($device->services) {
		$self->{_SCPDURLs}->{$service->SCPDURL}++;
		$self->{_controlURLs}->{$service->controlURL} = $service;
		$self->{_eventSubURLs}->{$service->eventSubURL} = $service;
	}

	for my $devices ($device->children) {
		$self->_fillServiceTables($device);
	}
}

sub socket {
	return shift->{_daemon};
}

sub _parseCallbackHeader {
	my $header = shift;
	my @callbacks = ();
	if ($header) {
		while ($header =~ s/<(\S+?)>//) {
			push @callbacks, $1;
		}
	}

	return @callbacks;
}

sub _parseTimeoutHeader {
	my $header = shift;
	my $timeout = 1800;
	
	if ($header && $header =~ /^Seconds-(\d+)$/) {
		$timeout = $1;
	}
	
	return $timeout;
}

sub handle {
	my $self = shift;
	my $socket = $self->{_daemon};
	my $c = $socket->accept;
	my $r = $c->get_request;
	my $uri = $r->uri;

	my $service;
	my $response = HTTP::Response->new;
	$response->protocol('HTTP/1.1');
	if ($uri eq $self->{_descriptionURI}) {
		$response->code(HTTP::Status::RC_OK);
		$response->content($self->{_description});
		$response->header('Content-type', 'text/xml');
	}
	elsif ($self->{_SCPDURLs}->{$uri}) {
		$uri =~ s/^\///;	
		my $file = rel2abs($uri, $self->{_resourceDir});
		if (-e $file) {
			$response->code(HTTP::Status::RC_OK);
			$response->content(UPnP::DeviceManager::loadFile($file));
			$response->header('Content-type', 'text/xml');
		}	
		else {
			$response->code(HTTP::Status::RC_NOT_FOUND);
		}
	}
	elsif ($service = $self->{_controlURLs}->{$uri}) {
		if ($r->header('SOAPAction') =~ /#(.+?)"?$/) {
			my $actionName = $1;
			my $action;
			if ($actionName ne 'QueryStateVariable') {
				$action = $service->getAction($actionName);
			}
			$self->serializer->context($service, $action, $actionName);
			$self->request($r);
			$self->SUPER::handle;
			$self->response->header('EXT', '');
			$self->response->header('Server', $self->{_server});
			$response = $self->response;
		}
		else {
			$response->code(HTTP::Status::RC_NOT_FOUND);
		}
	}
	elsif ($service = $self->{_eventSubURLs}->{$uri}) {
		my $sid = $r->header('SID');
		my $subscriber;
		if (defined($sid) && 
			!defined($subscriber = $service->getSubscriber($sid))) {
			$response->code(HTTP::Status::RC_BAD_REQUEST,
							"Unknown SID");
		}
		elsif ($r->method eq 'SUBSCRIBE') {
			if ($subscriber) {
				$subscriber->renew;
				$response->code(HTTP::Status::RC_OK);
			}
			else {
				my @callbacks = _parseCallbackHeader($r->header('Callback'));
				if (!scalar(@callbacks)) {
					$response->code(HTTP::Status::RC_PRECONDITION_FAILED,
									"Missing or invalid CALLBACK");
				}
				elsif (!defined($r->header('NT')) ||
					   !$r->header('NT') eq 'upnp:event') {
					$response->code(HTTP::Status::RC_PRECONDITION_FAILED,
									"Invalid NT");
				}
				else {
					my $timeout = _parseTimeoutHeader($r->header('Timeout'));
					$subscriber = UPnP::DeviceManager::Subscriber->new(
										   Callbacks => \@callbacks,
										   Timeout => $timeout,);
					$sid = $service->addSubscriber($subscriber);
					$response->code(HTTP::Status::RC_OK);
				}
			}
			$response->header('SID', $sid);
			$response->header('Timeout', 'Second-' . $subscriber->timeout);
		}
		elsif ($r->method eq 'UNSUBSCRIBE') {
			if ($subscriber) {
				$service->removeSubscriber($sid);
				$response->code(HTTP::Status::RC_OK);
				$response->header('SID', $sid);
			}
			else {
				$response->code(HTTP::Status::RC_BAD_REQUEST,
								"SID required for unsubscribe");
			}
		}
		else {
			$response->code(HTTP::Status::RC_BAD_REQUEST,
							"Unsupported HTTP method for event suscription");
		}
	}
	else {
		$response->code(HTTP::Status::RC_NOT_FOUND);
	}

	$c->send_response($response);
	$c->close;
}

sub AUTOLOAD {
  my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
  return if $method eq 'DESTROY';

  no strict 'refs';
  *$AUTOLOAD = sub { shift->{_daemon}->$method(@_) };
  goto &$AUTOLOAD;
}

# ----------------------------------------------------------------------

package UPnP::DeviceManager::Serializer;

use strict;

use HTTP::Daemon;
use SOAP::Lite;
use SOAP::Transport::HTTP;

use		vars qw(@ISA);

our @ISA = qw(SOAP::Serializer);

sub context {
	my $self = shift;

	$self->{_service} = shift;
	$self->{_action} = shift;
	$self->{_actionName} = shift;
}

sub onDispatch {
	my $self = shift;
	my $request = shift;

	if ($self->{_service}->onAction || 
		$self->{_actionName} eq 'QueryStateVariable') {
		my @paramsin = $request->paramsin;
		$self->{_paramsin} = \@paramsin;
		my $class = ref $self;
		for ($class) { s!::!/!g; }
		return ('http://www.upnp.org/' . $class, 'stub');
	}

	return ();
}

sub stub {
	return ();
}

sub envelope {
	my $self = shift->new;
	my $type = shift;
	my $service = $self->{_service};

	if (($type eq 'response') && $service) {
		my $method = shift;
		my @parameters = ();
		if ($self->{_actionName} eq 'QueryStateVariable') {
			my $paramsin = $self->{_paramsin};
			if (my $param = $paramsin->[0]) {
				my $var = $service->getStateVariable($param);
				if ($var->evented) {
					my $value = $service->getValue($param);
					push @parameters, 
						 SOAP::Data->type($var->SOAPType => $value)
							 ->name('return');
				}
			}
			$method = SOAP::Data->name('QueryStateVariableResponse')
				->uri('urn:schemas-upnp-org:control-1-0');
		}
		elsif (my $action = $self->{_action}) {
			my @paramsout;
			if ($service->dispatchTo) {
				@paramsout = @_;
			}
			elsif (my $onaction = $service->onAction) {
				my $action = $self->{_action}->name;
				my $paramsin = $self->{_paramsin};
				@paramsout = &{$onaction}($service,
										  $action,
										  @$paramsin);
			}

			for my $arg ($action->outArguments) {
				my $type = $service->getArgumentType($arg);
				push @parameters, SOAP::Data->type($type => shift @paramsout)
					->name($arg->name);
			}
			$self->{_service} = undef;
			$self->{_action} = undef;
			$self->{_paramsin} = undef;
			$method = SOAP::Data->name($self->{_actionName} . 'Response')
				->uri($service->serviceType);
		}
			
		return $self->SUPER::envelope(
							   $type => $method, 
							   @parameters);
	}

	return $self->SUPER::envelope($type, @_);
}

# ----------------------------------------------------------------------

package UPnP::DeviceManager::Subscriber;

use strict;

use Time::HiRes;

sub new {
	my $self = shift;
	my $class = ref($self) || $self;
	my %args = @_;

	$self = bless {}, $class;
	$self->{_callbacks} = $args{Callbacks};
	$self->{_timeout} = $args{Timeout}; 
	$self->{_expiration} = Time::HiRes::time() + $self->{_timeout};
	$self->{_seq} = 0;

	return $self;
}

sub timeout {
	my $self = shift;

	$self->{_timeout} = shift if @_;

	return $self->{_timeout};
}

sub callbacks {
	my $self = shift;

	if (@_) {
		$self->{_callback} = [];
		for my $callback (@_) { push @{$self->{_callback}}, $callback; }
	}

	return $self->{_callbacks};
}

sub sid {
	my $self = shift;

	$self->{_sid} = shift if @_;

	return $self->{_sid};
}

sub renew {
	my $self = shift;

	$self->{_expiration} = Time::HiRes::time() + $self->{_timeout};
}

sub notify {
	my $self = shift;
	my %variables = @_;

	my $content = "<e:propertyset xmlns:e=\"urn:schemas-upnp-org:event-1-0\">\n";
	while (my ($name, $value) = each %variables) {
		$content .= "\t<e:property>\n\t\t<$name>$value</$name>\n\t</e:property>\n";
	}
	$content .= "</e:propertyset>\n";
	
	my $seq = $self->{_seq}++;
	my $ua = LWP::UserAgent->new;
	$ua->timeout(2);
	for my $callback (@{$self->callbacks}) {
		my $uri = URI->new($callback);
		next if (!defined($uri));
		my $request = HTTP::Request->new('NOTIFY' => $callback);
		$request->protocol('HTTP/1.1');
		$request->header('Host', $uri->host_port);
		$request->header('NT', 'upnp:event');
		$request->header('NTS', 'upnp:propchange');
		$request->header('SID', $self->sid);
		$request->header('SEQ', $seq);
		$request->header('Content-Type', 'text/xml');
		$request->header('Content-Length', length $content);
		$request->content($content);

		my $response = $ua->request($request);
		
		# Other than checking for success, don't worry about the
		# details of the response.
		last if ($response->is_success);
	}
}

1;
__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
