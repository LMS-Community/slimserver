package Net::UPnP::Device;

#-----------------------------------------------------------------
# Net::UPnP::Device
#-----------------------------------------------------------------

use strict;
use warnings;

use Net::UPnP::HTTP;
use Net::UPnP::Service;

use vars qw($_SSDP $_DESCRIPTION $_SERVICELIST);

$_SSDP = 'ssdp';
$_DESCRIPTION = 'description';
$_SERVICELIST = 'serviceList';

#------------------------------
# new
#------------------------------

sub new {
	my($class) = shift;
	my($this) = {
		$Net::UPnP::Device::_SSDP => '',
		$Net::UPnP::Device::_DESCRIPTION => '',
		@Net::UPnP::Device::_SERVICELIST  => (),
	};
	bless $this, $class;
}

#------------------------------
# ssdp
#------------------------------

sub setssdp() {
	my($this) = shift;
	$this->{$Net::UPnP::Device::_SSDP} = $_[0];
 }

sub getssdp() {
	my($this) = shift;
	$this->{$Net::UPnP::Device::_SSDP};
 }

#------------------------------
# description
#------------------------------

sub setdescription() {
	my($this) = shift;
	my($description) = $_[0];
	$this->{$Net::UPnP::Device::_DESCRIPTION} = $description;
	$this->setservicefromdescription($description);
 }

sub getdescription() {
	my($this) = shift;
	my %args = (
		name => undef,	
		@_,
	);
	if ($args{name}) {
		unless ($this->{$Net::UPnP::Device::_DESCRIPTION} =~ m/<$args{name}>(.*)<\/$args{name}>/i) {
			return '';
		}
	 	return $1;
	}
	$this->{$Net::UPnP::Device::_DESCRIPTION};
 }

#------------------------------
# service
#------------------------------

sub setservicefromdescription() {
	my($this) = shift;
	my(
		$description,
		$servicelist_description,
		@serviceList,
		$service,
		);

	
	$description = $_[0];
	
	unless ($description =~ m/<serviceList>(.*)<\/serviceList>/si) {
		return;
	}

	$servicelist_description = $1;

	@{$this->{$Net::UPnP::Device::_SERVICELIST}} = ();
	while ($servicelist_description =~ m/<service>(.*?)<\/service>/sgi) {
		$service = Net::UPnP::Service->new();
		$service->setdevicedescription($1);
		$service->setdevice($this);
		push (@{$this->{$Net::UPnP::Device::_SERVICELIST}}, $service);
	}
}

#------------------------------
# serviceList
#------------------------------

sub getservicelist() {
	my($this) = shift;
	@{$this->{$Net::UPnP::Device::_SERVICELIST}};
 }

#------------------------------
# getservicebyname
#------------------------------

sub getservicebyname() {
	my($this) = shift;
	my ($service_name) = @_;
	my (
		@serviceList,
		$service,
		$service_type,
	);
	@serviceList = $this->getservicelist();
	foreach $service (@serviceList) {
		$service_type = $service->getservicetype();
		if ($service_type eq $service_name) {
			return $service;
		}
	}
	return undef;
 }

#------------------------------
# getlocation
#------------------------------

sub getlocation() {
	my($this) = shift;
	unless ($this->{$Net::UPnP::Device::_SSDP} =~ m/LOCATION[ :]+(.*)\r/i) {
		return '';
	}		
 	return $1;
 }

#------------------------------
# getdevicetype
#------------------------------

sub getdevicetype() {
	my($this) = shift;
	$this->getdescription(name => 'deviceType');
 }

#------------------------------
# getfriendlyname
#------------------------------

sub getfriendlyname() {
	my($this) = shift;
	$this->getdescription(name => 'friendlyName');
 }

#------------------------------
# getmanufacturer
#------------------------------

sub getmanufacturer() {
	my($this) = shift;
	$this->getdescription(name => 'manufacturer');
 }

#------------------------------
# getmanufacturerurl
#------------------------------

sub getmanufacturerurl() {
	my($this) = shift;
	$this->getdescription(name => 'manufacturerURL');
 }

#------------------------------
# getmodeldescription
#------------------------------

sub getmodeldescription() {
	my($this) = shift;
	$this->getdescription(name => 'modelDescription');
 }

#------------------------------
# getmodelname
#------------------------------

sub getmodelname() {
	my($this) = shift;
	$this->getdescription(name => 'modelName');
 }

#------------------------------
# getmodelnumber
#------------------------------

sub getmodelnumber() {
	my($this) = shift;
	$this->getdescription(name => 'modelNumber');
 }

#------------------------------
# getmodelurl
#------------------------------

sub getmodelurl() {
	my($this) = shift;
	$this->getdescription(name => 'modelURL');
 }

#------------------------------
# getserialnumber
#------------------------------

sub getserialnumber() {
	my($this) = shift;
	$this->getdescription(name => 'serialNumber');
 }

#------------------------------
# getudn
#------------------------------

sub getudn() {
	my($this) = shift;
	$this->getdescription(name => 'UDN');
 }

#------------------------------
# getupc
#------------------------------

sub getupc() {
	my($this) = shift;
	$this->getdescription(name => 'UPC');
 }

#------------------------------
# geturlbase
#------------------------------

sub geturlbase() {
	my($this) = shift;
	$this->getdescription(name => 'URLBase');
 }

1;

__END__

=head1 NAME

Net::UPnP::Device - Perl extension for UPnP.

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

The package is used a object of UPnP device.

=head1 METHODS

=over 4

=item B<getdescription> - get the description.

    $description = $dev->getdescription(
    	                        name => $name # undef
                             );

Get the device description of the SSDP location header. 
	
The function returns the all description when the name parameter is not specified, otherwise return a value the specified name.

=item B<getdevicetype> - get the device type.

    $description = $dev->getdevicetype();

Get the device type from the device description.

=item B<getfriendlyname> - get the device type.

    $friendlyname = $dev->getfriendlyname();

Get the friendly name from the device description.

=item B<getmanufacturer> - get the manufacturer.

    $manufacturer = $dev->getmanufacturer();

Get the manufacturer name from the device description.

=item B<getmanufacturerrul> - get the manufacturer url.

    $manufacturer_url = $dev->getmanufacturerrul();

Get the manufacturer url from the device description.

=item B<getmodeldescription> - get the model description.

    $model_description = $dev->getmodeldescription();

Get the model description from the device description.

=item B<getmodelname> - get the model name.

    $model_name = $dev->getmodelname();

Get the model name from the device description.

=item B<getmodelnumber> - get the model number.

    $model_number = $dev->getmodelnumber();

Get the model number from the device description.

=item B<getmodelurl> - get the model url.

    $model_url = $dev->getmodelurl();

Get the model url from the device description.

=item B<getserialnumber> - get the serialnumber.

    $serialnumber = $dev->getserialnumber();

Get the model description from the device description.

=item B<getudn> - get the device UDN.

    $udn = $dev->getudn();

Get the UDN from the device description.

=item B<getupc> - get the device UPC.

    $upc = $dev->getupc();

Get the UPC from the device description.

=item B<getservicelist> - get the device type.

    @service_list = $dev->getservicelist();

Get the service list in the device.  Please see L<Net::UPnP::Service> too.

=back

=head1 SEE ALSO

L<Net::UPnP::Service>

=head1 AUTHOR

Satoshi Konno
skonno@cybergarage.org

CyberGarage
http://www.cybergarage.org

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Satoshi Konno

It may be used, redistributed, and/or modified under the terms of BSD License.

=cut
