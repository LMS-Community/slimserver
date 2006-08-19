package Net::UPnP::Service;

#-----------------------------------------------------------------
# Net::Net::UPnP::Service
#-----------------------------------------------------------------

use strict;
use warnings;

use Net::UPnP;
use Net::UPnP::ActionResponse;
use Net::UPnP::QueryResponse;

use vars qw($_DEVICE $_DEVICE_DESCRIPTION $SERVICETYPE $SERVICEID $SCPDURL $CONTROLURL $EVENTSUBURL);

$_DEVICE = 'device';
$_DEVICE_DESCRIPTION = 'device_description';

$SERVICETYPE = 'serviceType';
$SERVICEID = 'serviceId';
$SCPDURL = 'SCPDURL';
$CONTROLURL = 'controlURL';
$EVENTSUBURL = 'eventSubURL';

#------------------------------
# new
#------------------------------

sub new {
	my($class) = shift;
	my($this) = {
		$Net::UPnP::Service::_DEVICE  => undef,
		$Net::UPnP::Service::_DEVICE_DESCRIPTION => '',
	};
	bless $this, $class;
}

#------------------------------
# device
#------------------------------

sub setdevice() {
	my($this) = shift;
	if (@_) {
		$this->{$Net::UPnP::Service::_DEVICE} = $_[0];
	}
}

sub getdevice() {
	my($this) = shift;
	$this->{$Net::UPnP::Service::_DEVICE};
}

#------------------------------
# device description
#------------------------------

sub setdevicedescription() {
	my($this) = shift;
	$this->{$Net::UPnP::Service::_DEVICE_DESCRIPTION} = $_[0];
 }

sub getdevicedescription() {
	my($this) = shift;
	my %args = (
		name => undef,	
		@_,
	);
	if ($args{name}) {
		unless ($this->{$Net::UPnP::Service::_DEVICE_DESCRIPTION} =~ m/<$args{name}>(.*)<\/$args{name}>/i) {
			return '';
		}
	 	return $1;
	}
	$this->{$Net::UPnP::Service::_DEVICE_DESCRIPTION};
 }

#------------------------------
# getservicetype
#------------------------------

sub getservicetype() {
	my($this) = shift;
	$this->getdevicedescription(name => $Net::UPnP::Service::SERVICETYPE);
 }

#------------------------------
# getserviceid
#------------------------------

sub getserviceid() {
	my($this) = shift;
	$this->getdevicedescription(name => $Net::UPnP::Service::SERVICEID);
 }

#------------------------------
# getscpdurl
#------------------------------

sub getscpdurl() {
	my($this) = shift;
	$this->getdevicedescription(name => $Net::UPnP::Service::SCPDURL);
 }

#------------------------------
# getcontrolurl
#------------------------------

sub getcontrolurl() {
	my($this) = shift;
	$this->getdevicedescription(name => $Net::UPnP::Service::CONTROLURL);
 }

#------------------------------
# geteventsuburl
#------------------------------

sub geteventsuburl() {
	my($this) = shift;
	$this->getdevicedescription(name => $Net::UPnP::Service::EVENTSUBURL);
 }

#------------------------------
# getposturl
#------------------------------

sub getposturl() {
	my($this) = shift;
	my ($ctrl_url) = @_;
	my (
		$dev,
		$location_url,
		$url_base,
	);
	
	$dev = $this->getdevice();
	
	$location_url = $dev->getlocation();
	$url_base = $dev->geturlbase();
	$ctrl_url = $this->getcontrolurl();

	#print "$location_url\n";
	#print "$url_base\n";
	#print "$ctrl_url\n";
		
	unless ($ctrl_url =~ m/http:\/\/(.*)/i) {
		if (0 < length($url_base)) {
			# Thanks for Thus0 (2005/01/12)
			if (rindex($url_base, '/') == (length($url_base)-1) && index($ctrl_url, '/') == 0) {
				$ctrl_url = $url_base . substr($ctrl_url, 1);
			} else {
				$ctrl_url = $url_base . $ctrl_url;
			}
		}
		else {
			if ($location_url =~ m/http:\/\/([0-9a-z.]+)[:]*([0-9]*)\/(.*)/i) {
				$ctrl_url = "http:\/\/" . $1 . ":" . $2 . "\/" . $ctrl_url;
			} else {
				$ctrl_url = $location_url .  $ctrl_url;
			}
		}
	}
	
	return $ctrl_url;
}

#------------------------------
# postaction
#------------------------------

sub postaction() {
	my($this) = shift;
	my ($action_name, $action_arg) = @_;
	my (
		$dev,
		$ctrl_url,
		$service_type,
		$soap_action,
		$soap_content,
		$arg_name,
		$arg_value,
		$post_addr,
		$post_port,
		$post_path,
		$http_req,
		$post_res,
		$action_res,
		$key,
	);
	
	$action_res = Net::UPnP::ActionResponse->new();
	
	$dev = $this->getdevice();
	$ctrl_url = $this->getcontrolurl();
	$ctrl_url = $this->getposturl($ctrl_url);
	
	unless ($ctrl_url =~ m/http:\/\/([0-9a-z.]+)[:]*([0-9]*)\/(.*)/i) {
		#print "Invalid URL : $ctrl_url\n";
		$post_res = Net::UPnP::HTTPResponse->new();
		$action_res->sethttpresponse($post_res);
		return $action_res;
	}
	$post_addr = $1;
	$post_port = $2;
	if (index($3, '/') == 0) {
		$post_path = $3;
	}
	else {
		$post_path = "\/" . $3;
	}

	$service_type = $this->getservicetype();
	$soap_action = "\"" . $service_type . "#" . $action_name . "\"";


$soap_content = <<"SOAP_CONTENT";
<?xml version=\"1.0\" encoding=\"utf-8\"?>
<s:Envelope xmlns:s=\"http:\/\/schemas.xmlsoap.org\/soap\/envelope\/\" s:encodingStyle=\"http:\/\/schemas.xmlsoap.org\/soap\/encoding/\">
\t<s:Body>
\t\t<u:$action_name xmlns:u=\"$service_type\">
SOAP_CONTENT

	if (ref $action_arg) {
		while (($arg_name, $arg_value) = each (%{$action_arg} ) ) {
			if (length($arg_value) <= 0) {
				$soap_content .= "\t\t\t<$arg_name \/>\n";
				next;
			}
			$soap_content .= "\t\t\t<$arg_name>$arg_value<\/$arg_name>\n";
		}
	}

$soap_content .= <<"SOAP_CONTENT";
\t\t</u:$action_name>
\t</s:Body>
</s:Envelope>
SOAP_CONTENT

	$http_req = Net::UPnP::HTTP->new();
	$post_res = $http_req->postsoap($post_addr, $post_port, $post_path, $soap_action, $soap_content);

	$action_res->sethttpresponse($post_res);
	
	return $action_res;
}

#------------------------------
# postcontrol
#------------------------------

sub postcontrol() {
	my($this) = shift;
	my ($action_name, $action_arg) = @_;
	return $this->postaction($action_name, $action_arg);
}

#------------------------------
# postquery
#------------------------------

sub postquery() {
	my($this) = shift;
	my ($var_name) = @_;
	my (
		$dev,
		$ctrl_url,
		$service_type,
		$soap_action,
		$soap_content,
		$post_addr,
		$post_port,
		$post_path,
		$http_req,
		$post_res,
		$query_res,
	);
	
	$query_res = Net::UPnP::QueryResponse->new();
	
	$dev = $this->getdevice();
	$ctrl_url = $this->getcontrolurl();
	$ctrl_url = $this->getposturl($ctrl_url);
	
	unless ($ctrl_url =~ m/http:\/\/([0-9a-z.]+)[:]*([0-9]*)\/(.*)/i) {
		#print "Invalid URL : $ctrl_url\n";
		$post_res = Net::UPnP::HTTPResponse->new();
		$query_res->sethttpresponse($post_res);
		return $query_res;
	}
	$post_addr = $1;
	$post_port = $2;
	if (index($3, '/') == 0) {
		$post_path = $3;
	}
	else {
		$post_path = "\/" . $3;
	}
	
	$service_type = $this->getservicetype();
	$soap_action = "\"urn:schemas-upnp-org:control-1-0#QueryStateVariable\"";

$soap_content = <<"SOAP_CONTENT";
<?xml version=\"1.0\" encoding=\"utf-8\"?>
<s:Envelope xmlns:s=\"http:\/\/schemas.xmlsoap.org\/soap\/envelope\/\" s:encodingStyle=\"http:\/\/schemas.xmlsoap.org\/soap\/encoding/\">
\t<s:Body>
\t\t<u:QueryStateVariable xmlns:u=\"urn:schemas-upnp-org:control-1-0\">
\t\t\t<u:varName>$var_name</u:varName>
\t\t</u:QueryStateVariable>
\t</s:Body>
</s:Envelope>
SOAP_CONTENT

	$http_req = Net::UPnP::HTTP->new();
	$post_res = $http_req->postsoap($post_addr, $post_port, $post_path, $soap_action, $soap_content);

	$query_res->sethttpresponse($post_res);
	
	return $query_res;
}

1;

__END__

=head1 NAME

Net::UPnP::Service - Perl extension for UPnP.

=head1 SYNOPSIS

    use Net::UPnP::ControlPoint;

    my $obj = Net::UPnP::ControlPoint->new();

    @dev_list = $obj->search(st =>'upnp:rootdevice', mx => 3);

    $devNum= 0;
    foreach $dev (@dev_list) {
        $device_type = $dev->getdevicetype();
        if  ($device_type ne 'urn:schemas-upnp-org:device:MediaServer:1') {
            next;
        }
        print "[$devNum] : " . $dev->getfriendlyname() . "\n";
        unless ($dev->getservicebyname('urn:schemas-upnp-org:service:ContentDirectory:1')) {
            next;
        }
        $condir_service = $dev->getservicebyname('urn:schemas-upnp-org:service:ContentDirectory:1');
        unless (defined(condir_service)) {
            next;
        }
        %action_in_arg = (
                'ObjectID' => 0,
                'BrowseFlag' => 'BrowseDirectChildren',
                'Filter' => '*',
                'StartingIndex' => 0,
                'RequestedCount' => 0,
                'SortCriteria' => '',
            );
        $action_res = $condir_service->postcontrol('Browse', \%action_in_arg);
        unless ($action_res->getstatuscode() == 200) {
        	next;
        }
        $actrion_out_arg = $action_res->getargumentlist();
        unless ($actrion_out_arg->{'Result'}) {
            next;
        }
        $result = $actrion_out_arg->{'Result'};
        while ($result =~ m/<dc:title>(.*?)<\/dc:title>/sgi) {
            print "\t$1\n";
        }
        $devNum++;
    }

=head1 DESCRIPTION

The package is used a object of UPnP service.

=head1 METHODS

=over 4

=item B<getdevice> - get the device.

    $description = $service->getdevice();

Get the parent device of the service.

=item B<getdevicedescription> - get the service description of the device description.

    $description = $service->getdevicedescription(
    	                        name => $name # undef
                             );

Get the service description of the device description. 
	
The function returns the all description when the name parameter is not specified, otherwise return a value the specified name.

=item B<getservicetype> - get the service type.

    $service_type = $service->getservicetype();

Get the service type.

=item B<getserviceid> - get the service id.

    $service_id = $service->getserviceid();

Get the service id.

=item B<postaction> - post a action control.

    $action_res = $service->postcontrol($action_name, \%action_arg);

Post a action control to the device, and return L<Net::UPnP::ActionResponse>.

The method was renamed from postcontrol(), but the old name is deprecated.
	
=item B<postquery> - post a query control.

    $query_res = $service->postcontrol($var_name);

Post a query control to the device, and return L<Net::UPnP::QueryResponse>.

=back

=head1 SEE ALSO

L<Net::UPnP::ActionResponse>

=head1 AUTHOR

Satoshi Konno
skonno@cybergarage.org

CyberGarage
http://www.cybergarage.org

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Satoshi Konno

It may be used, redistributed, and/or modified under the terms of BSD License.

=cut
