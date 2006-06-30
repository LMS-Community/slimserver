package UPnP::Common;

=pod

=head1 NAME

UPnP::Common - Common constants, parameters and functions, including
several internal modules, for the Perl UPnP implementation. Only 
documented functionality should be used outside the Perl UPnP set
of packages.

=head1 DESCRIPTION

This class gives you access constants that can be used to control
aspects of the behavior of Perl UPnP objects.

=over

=item $LOCAL_IP

Perl UPnP needs to have access to the IP address of the network
interface used for UPnP protocol exchanges. Perl UPnP will try to
automatically detect the IP address of the interface if this variable
is not set. However, this variable can be explictly set to the IP
address to use:

  $UPnP::LOCAL_IP = '192.168.0.23';

=item $IP_DETECT_ADDRESS

If the $LOCAL_IP variable has not been explicitly set, the UPnP
implementation attempts to automatically detect the IP address of the
network interface used for UPnP protocol exchanges. It does this by
connecting to a well-known external address and querying the socket
used for the connection. By default, this address is 'www.google.com'
over port 80. An alternate IP address detection address can be 
specified in the following way:

	$UPnP::IP_DETECT_ADDRESS = 'www.yahoo.com:80';

=back

=head1 SEE ALSO

UPnP documentation and resources can be found at L<http://www.upnp.org>.

The C<SOAP::Lite> module can be found at L<http://www.soaplite.com>.

UPnP implementations in other languages include the UPnP SDK for Linux
(L<http://upnp.sourceforge.net/>), Cyberlink for Java
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

use HTTP::Headers;
use IO::Socket qw(:DEFAULT :crlf);
use SOAP::Lite;

use		vars qw(@EXPORT $VERSION @ISA $AUTOLOAD);

require Exporter;

our @ISA = qw(Exporter);
our $VERSION = '0.4';

# Constants exported for all UPnP modules
use constant SSDP_IP => "239.255.255.250";
use constant SSDP_PORT => 1900;
use constant IP_LEVEL => getprotobyname('ip') || 0;

@EXPORT = qw(SSDP_IP SSDP_PORT IP_LEVEL);

# Platform dependent constants that can't automatically be detected.
# We hard-code values for the common platforms, defaulting to the
# Linux values.
my %PLATFORM_CONSTANT_NAMES = (
	'IP_MULTICAST_TTL' => 0,
	'IP_ADD_MEMBERSHIP' => 1
);
my %PLATFORM_CONSTANT_VALUES = (
	'MSWin32' => [10,12],
	'cygwin' => [3,5],
	'darwin' => [10,12],
	'default' => [33,35],
);

sub getPlatformConstant {
	my $name = shift;
	my $index = $PLATFORM_CONSTANT_NAMES{$name};
	return if !defined($index);

	my $ref = $PLATFORM_CONSTANT_VALUES{$^O} || $PLATFORM_CONSTANT_VALUES{'default'};
	return $ref->[$index];
}

BEGIN {
	if ($^O =~ /Win32/) {
		*EINTR       = sub () { 10004 };
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };

	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS EINTR);
	}
}

sub blocking {   
	my $sock = shift;

 	return $sock->blocking(@_) unless $^O =~ /Win32/;

	my $nonblocking = $_[0] ? "0" : "1";
	my $retval = ioctl($sock, 0x8004667e, \$nonblocking);

	if (!defined($retval) && $] >= 5.008) {
		$retval = "0 but true";
	}

	return $retval;
}

# We need to be able to the IP address of the network interface that
# will be used for UPnP. A cheap and cross-platform way of doing this
# is to connect to an external machine and getting the information
# from the connect socket. 
# The following two constants can be changed by the caller.
our $IP_DETECT_ADDRESS = 'www.google.com:80';
our $LOCAL_IP = undef;

sub getLocalIPAddress {
	unless (defined($LOCAL_IP)) {
		my $socket = IO::Socket::INET->new('PeerAddr'  => $IP_DETECT_ADDRESS);
		if ($socket) {
			my ($port, $address) = sockaddr_in( (getsockname($socket))[0] );
			$LOCAL_IP = inet_ntoa($address);
		}
	}

	return $LOCAL_IP;
}

sub parseHTTPHeaders {
	my $buf = shift;
	my $headers = HTTP::Headers->new;
	
	# Header parsing code borrowed from HTTP::Daemon
	my($key, $val);
  HEADER:
	while ($buf =~ s/^([^\012]*)\012//) {
		$_ = $1;
		s/\015$//;
		if (/^([^:\s]+)\s*:\s*(.*)/) {
			$headers->push_header($key => $val) if $key;
			($key, $val) = ($1, $2);
		}
		elsif (/^\s+(.*)/) {
			$val .= " $1";
		}
		else {
			last HEADER;
		}
	}
	$headers->push_header($key => $val) if $key;

	return $headers;
}

my %typeMap = (
	'ui1' => 'int',
	'ui2' => 'int',
	'ui4' => 'int',
	'i1' => 'int',
	'i2' => 'int',
	'i4' => 'int',
	'int' => 'int',
	'r4' => 'float',
	'r8' => 'float',
	'number' => 'float',
	'fixed' => 'float',
	'float' => 'float',
	'char' => 'string',
	'string' => 'string',
	'date' => 'timeInstant',
	'dateTime.tz' => 'timeInstant',
	'time' => 'timeInstant',
	'time.tz' => 'timeInstant',
	'boolean' => 'boolean',
	'bin.base64' => 'base64Binary',
	'bin.hex' => 'hexBinary',
	'uri' => 'uriReference',
	'uuid' => 'string',
);

sub UPnPToSOAPType {
	my $upnpType = shift;
	return $typeMap{$upnpType};
}

# ----------------------------------------------------------------------

package UPnP::Common::DeviceLoader;

use strict;
use HTML::Entities ();

sub new {
	my $self = shift;
	my $class = ref($self) || $self;

	return bless {
		_parser => UPnP::Common::Parser->new,
	}, $class;
}

sub parser {
	my $self = shift;
	return $self->{_parser};
}

sub parseServiceElement {
	my $self = shift;
	my $element = shift;
	my($name, $attrs, $children) = @$element;

	my $service = $self->newService(%{$_[1]});
	for my $childElement (@$children) {
		my $childName = $childElement->[0];

		if (UPnP::Common::Service::isProperty($childName)) {
			my $value = $childElement->[2];
			$service->$childName($value);
		}
	}

	return $service;
}

sub parseDeviceElement {
	my $self = shift;
	my $element = shift;
	my $parent = shift;
	my($name, $attrs, $children) = @$element;

	my $device = $self->newDevice(%{$_[0]});
	$device->parent($parent);
	for my $childElement (@$children) {
		my $childName = $childElement->[0];

		if ($childName eq 'deviceList') {
			my $childDevices = $childElement->[2];
			for my $deviceElement (@$childDevices) {
				my $childDevice = $self->parseDeviceElement($deviceElement, 
															$device,
															@_);
				if ($childDevice) {
					$device->addChild($childDevice);
				}
			}
		}
		elsif ($childName eq 'serviceList') {
			my $services = $childElement->[2];
			for my $serviceElement (@$services) {
				my $service = $self->parseServiceElement($serviceElement,
														 @_);
				if ($service) {
					$device->addService($service);
				}
			}
		}
		elsif (UPnP::Common::Device::isProperty($childName)) {
			my $value = HTML::Entities::decode( $childElement->[2] );
			$device->$childName($value);
		}
	}

	return $device;
}

sub parseDeviceDescription {
	my $self = shift;
	my $description = shift;
	my ($base, $device);

	my $parser = $self->parser;
	my $element = $parser->parse($description);
	if (defined($element) && ref $element eq 'ARRAY') {
		my($name, $attrs, $children) = @$element;
		for my $child (@$children) {
			my ($childName) = @$child;
			if ($childName eq 'URLBase') {
				$base = $child->[2];
			}
			elsif ($childName eq 'device') {
				$device = $self->parseDeviceElement($child, 
													undef,
													@_);
			}
		}
	}

	return ($device, $base);
}

# ----------------------------------------------------------------------

package UPnP::Common::Device;

use strict;

use Carp;
use Scalar::Util qw(weaken);

use vars qw($AUTOLOAD %deviceProperties);
for my $prop (qw(deviceType friendlyName manufacturer 
				 manufacturerURL modelDescription modelName 
				 modelNumber modelURL serialNumber UDN
				 presentationURL UPC location)) {
	$deviceProperties{$prop}++;
}

sub new {
	my $self = shift;
	my $class = ref($self) || $self;
	my %args = @_;

	$self = bless {}, $class;
	if ($args{Location}) {
		$self->location($args{Location});
	}

	return $self;
}

sub addChild {
	my $self = shift;
	my $child = shift;

	push @{$self->{_children}}, $child;
}

sub addService {
	my $self = shift;
	my $service = shift;

	push @{$self->{_services}}, $service;
}

sub parent {
	my $self = shift;

	if (@_) {
		$self->{_parent} = shift;
		weaken($self->{_parent});
	}

	return $self->{_parent};
}

sub children {
	my $self = shift;
	
	if (ref $self->{_children}) {
		return @{$self->{_children}};
	}

	return ();
}

sub services {
	my $self = shift;
	
	if (ref $self->{_services}) {
		return @{$self->{_services}};
	}

	return ();
}

sub getService {
	my $self = shift;
	my $id = shift;

	for my $service ($self->services) {
		if ($id && 
			($id eq $service->serviceId) ||
			($id eq $service->serviceType)) {
			return $service;
		}
	}

	return undef;
}

sub isProperty {
	my $prop = shift;
	return $deviceProperties{$prop};
}

sub AUTOLOAD {
	my $self = shift;
	my $attr = $AUTOLOAD;
	$attr =~ s/.*:://;
	return if $attr eq 'DESTROY';	

	croak "invalid attribute method: ->$attr()" unless $deviceProperties{$attr};

	$self->{uc $attr} = shift if @_;
	return $self->{uc $attr};
}

# ----------------------------------------------------------------------

package UPnP::Common::Service;

use strict;

use SOAP::Lite;
use Carp;

use vars qw($AUTOLOAD %serviceProperties);
for my $prop (qw(serviceType serviceId SCPDURL controlURL
				 eventSubURL base)) {
	$serviceProperties{$prop}++;
}

sub new {
	my $self = shift;
	my $class = ref($self) || $self;

	return bless {}, $class;
}

sub AUTOLOAD {
	my $self = shift;
	my $attr = $AUTOLOAD;
	$attr =~ s/.*:://;
	return if $attr eq 'DESTROY';	

	croak "invalid attribute method: ->$attr()" unless $serviceProperties{$attr};

	$self->{uc $attr} = shift if @_;
	return $self->{uc $attr};
}

sub isProperty {
	my $prop = shift;
	return $serviceProperties{$prop};
}

sub addAction {
	my $self = shift;
	my $action = shift;

	$self->{_actions}->{$action->name} = $action;
}

sub addStateVariable {
	my $self = shift;
	my $var = shift;

	$self->{_stateVariables}->{$var->name} = $var;
}

sub actions {
	my $self = shift;

	$self->_loadDescription;
	
	if (defined($self->{_actions})) {
		return values %{$self->{_actions}};
	}

	return ();
}

sub getAction {
	my $self = shift;
	my $name = shift;

	$self->_loadDescription;

	if (defined($self->{_actions})) {
		return $self->{_actions}->{$name};
	}

	return undef;
}

sub stateVariables {
	my $self = shift;

	$self->_loadDescription;

	if (defined($self->{_stateVariables})) {
		return values %{$self->{_stateVariables}};
	}

	return ();
}

sub getStateVariable {
	my $self = shift;
	my $name = shift;

	$self->_loadDescription;

	if (defined($self->{_stateVariables})) {
		return $self->{_stateVariables}->{$name};
	}

	return undef;
}

sub getArgumentType {
	my $self = shift;
	my $arg = shift;

	$self->_loadDescription;

	my $var = $self->getStateVariable($arg->relatedStateVariable);
	if ($var) {
		return $var->SOAPType;
	}

	return undef;
}

sub _parseArgumentList {
	my $self = shift;
	my $list = shift;
	my $action = shift;

	for my $argumentElement (@$list) {
		my($name, $attrs, $children) = @$argumentElement;
		if ($name eq 'argument') {
			my $argument = UPnP::Common::Argument->new;
			for my $argumentChild (@$children) {
				my ($childName) = @$argumentChild;
				if ($childName eq 'name') {
					$argument->name($argumentChild->[2]);
				}
				elsif ($childName eq 'direction') {
					my $direction = $argumentChild->[2];
					if ($direction eq 'in') {
						$action->addInArgument($argument);
					}
					elsif ($direction eq 'out') {
						$action->addOutArgument($argument);
					}
				}
				elsif ($childName eq 'relatedStateVariable') {
					$argument->relatedStateVariable($argumentChild->[2]);
				}
				elsif ($childName eq 'retval') {
					$action->retval($argument);
				}
			}
		}
	}
}

sub _parseActionList {
	my $self = shift;
	my $list = shift;

	for my $actionElement (@$list) {
		my($name, $attrs, $children) = @$actionElement;
		if ($name eq 'action') {
			my $action = UPnP::Common::Action->new;
			for my $actionChild (@$children) {
				my ($childName) = @$actionChild;
				if ($childName eq 'name') {
					$action->name($actionChild->[2]);
				}
				elsif ($childName eq 'argumentList') {
					$self->_parseArgumentList($actionChild->[2],
											  $action);
				}
			}
			$self->addAction($action);
		}
	}
}

sub _parseStateTable {
	my $self = shift;
	my $list = shift;

	for my $varElement (@$list) {
		my($name, $attrs, $children) = @$varElement;
		if ($name eq 'stateVariable') {
			my $var = UPnP::Common::StateVariable->new($attrs->{sendEvents} eq
													   'yes');
			for my $varChild (@$children) {
				my ($childName) = @$varChild;
				if ($childName eq 'name') {
					$var->name($varChild->[2]);
				}
				elsif ($childName eq 'dataType') {
					$var->type($varChild->[2]);
				}
			}
			$self->addStateVariable($var);
		}
	}
}

sub parseServiceDescription {
	my $self = shift;
	my $parser = shift;
	my $description = shift;

	my $element = $parser->parse($description);
	if (defined($element) && ref $element eq 'ARRAY') {
		my($name, $attrs, $children) = @$element;
		for my $child (@$children) {
			my ($childName) = @$child;
			if ($childName eq 'actionList') {
				$self->_parseActionList($child->[2]);
			}
			elsif ($childName eq 'serviceStateTable') {
				$self->_parseStateTable($child->[2]);
			}
		}
	}
	else {
		carp("Malformed SCPD document");
	}
}

# ----------------------------------------------------------------------

package UPnP::Common::Action;

use strict;

use Carp;

use vars qw($AUTOLOAD %actionProperties);
for my $prop (qw(name retval)) {
	$actionProperties{$prop}++;
}

sub new {
	return bless {}, shift;
}

sub AUTOLOAD {
	my $self = shift;
	my $attr = $AUTOLOAD;
	$attr =~ s/.*:://;
	return if $attr eq 'DESTROY';	

	croak "invalid attribute method: ->$attr()" unless $actionProperties{$attr};

	$self->{uc $attr} = shift if @_;
	return $self->{uc $attr};
}

sub addInArgument {
	my $self = shift;
	my $argument = shift;

	push @{$self->{_inArguments}}, $argument;
}

sub addOutArgument {
	my $self = shift;
	my $argument = shift;

	push @{$self->{_outArguments}}, $argument;
}

sub inArguments {
	my $self = shift;

	return @{$self->{_inArguments}} if $self->{_inArguments};
	return ();
}

sub outArguments {
	my $self = shift;

	return @{$self->{_outArguments}} if $self->{_outArguments};
	return ();
}

sub arguments {
	my $self = shift;

	return ($self->inArguments, $self->outArguments);
}

# ----------------------------------------------------------------------

package UPnP::Common::Argument;

use strict;

use Carp;

use vars qw($AUTOLOAD %argumentProperties);
for my $prop (qw(name relatedStateVariable)) {
	$argumentProperties{$prop}++;
}

sub new {
	return bless {}, shift;
}

sub AUTOLOAD {
	my $self = shift;
	my $attr = $AUTOLOAD;
	$attr =~ s/.*:://;
	return if $attr eq 'DESTROY';	

	croak "invalid attribute method: ->$attr()" unless $argumentProperties{$attr};

	$self->{uc $attr} = shift if @_;
	return $self->{uc $attr};
}

# ----------------------------------------------------------------------

package UPnP::Common::StateVariable;

use strict;

use Carp;

use vars qw($AUTOLOAD %varProperties);
for my $prop (qw(name type evented)) {
	$varProperties{$prop}++;
}

sub new {
	my $self = bless {}, shift;
	$self->evented(shift);
	return $self;
}

sub SOAPType {
	my $self = shift;
	return UPnP::Common::UPnPToSOAPType($self->type);
}

sub AUTOLOAD {
	my $self = shift;
	my $attr = $AUTOLOAD;
	$attr =~ s/.*:://;
	return if $attr eq 'DESTROY';	

	croak "invalid attribute method: ->$attr()" unless $varProperties{$attr};

	$self->{uc $attr} = shift if @_;
	return $self->{uc $attr};
}


# ----------------------------------------------------------------------

package UPnP::Common::Parser;

use XML::Parser::Lite;

# Parser code borrowed from SOAP::Lite. This package uses the
# event-driven XML::Parser::Lite parser to construct a nested data
# structure - a poor man's DOM. Each XML element in the data structure
# is represented by an array ref, with the values (listed by subscript
# below) corresponding with:
# 0 - The element name.
# 1 - A hash ref representing the element attributes.
# 2 - An array ref holding either child elements or concatenated
#	  character data.

sub new {
	my $class = shift;

	return bless { _parser => XML::Parser::Lite->new }, $class;
}

sub parse { 
	my $self = shift;
	my $parser = $self->{_parser};

	$parser->setHandlers(Final => sub { shift; $self->final(@_) },
						 Start => sub { shift; $self->start(@_) },
						 End   => sub { shift; $self->end(@_)	},
						 Char  => sub { shift; $self->char(@_)	},);
						
	# XML::Parser::Lite has poor error handling and just dies on invalid XML
	my $result;
	my $content = shift;
	eval {
		$result = $parser->parse($content);
	};
	if ($@) {
		warn "UPnP::Common::Parser: Failed to parse:\n$content\nError: $@\n";
	}
	return $result;
}

sub final { 
  my $self = shift; 
  my $parser = $self->{_parser};

  # clean handlers, otherwise ControlPoint::Parser won't be deleted: 
  # it refers to XML::Parser which refers to subs from ControlPoint::Parser
  undef $self->{_values};
  $parser->setHandlers(Final => undef, 
					   Start => undef, 
					   End	 => undef, 
					   Char	 => undef,);
  $self->{_done};
}

sub start { push @{shift->{_values}}, [shift, {@_}] }

sub char { push @{shift->{_values}->[-1]->[3]}, shift }

sub end { 
  my $self = shift; 
  my $done = pop @{$self->{_values}};
  $done->[2] = defined $done->[3] ? join('',@{$done->[3]}) : '' unless ref $done->[2];
  undef $done->[3]; 
  @{$self->{_values}} ? (push @{$self->{_values}->[-1]->[2]}, $done)
					  : ($self->{_done} = $done);
}

1;
__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
