package Net::UPnP::GW::Gateway;

#-----------------------------------------------------------------
# Net::UPnP::GW::Gateway
#-----------------------------------------------------------------

use strict;
use warnings;

use Net::UPnP::HTTP;
use Net::UPnP::Device;
use Net::UPnP::Service;

use vars qw($_DEVICE $DEVICE_TYPE $WANIPCONNECTION_SERVICE_TYPE);

$_DEVICE = 'device';

$DEVICE_TYPE = 'urn:schemas-upnp-org:device:InternetGatewayDevice:1';
$WANIPCONNECTION_SERVICE_TYPE = 'urn:schemas-upnp-org:service:WANIPConnection:1';

#------------------------------
# new
#------------------------------

sub new {
	my($class) = shift;
	my($this) = {
		$Net::UPnP::GW::Gateway::_DEVICE => undef,
	};
	bless $this, $class;
}

#------------------------------
# device
#------------------------------

sub setdevice() {
	my($this) = shift;
	if (@_) {
		$this->{$Net::UPnP::GW::Gateway::_DEVICE} = $_[0];
	}
}

sub getdevice() {
	my($this) = shift;
	$this->{$Net::UPnP::GW::Gateway::_DEVICE};
}

#------------------------------
# getexternalipaddress
#------------------------------

sub getexternalipaddress {
	my($this) = shift;
	
	my (
		$dev,
		$wanipcon_service,
		$action_res,
		$arg_list,
		$ipaddr,
	);
	
	$dev = $this->getdevice();
	$wanipcon_service = $dev->getservicebyname($Net::UPnP::GW::Gateway::WANIPCONNECTION_SERVICE_TYPE);
	unless ($wanipcon_service) {
		return "";
	}
	$action_res = $wanipcon_service->postaction("GetExternalIPAddress");
	if ($action_res->getstatuscode() != 200) {
		return "";
	}
	$arg_list = $action_res->getargumentlist();
	$ipaddr = $arg_list->{'NewExternalIPAddress'};
	
	return $ipaddr;
}

#------------------------------
# getportmappingnumberofentries
#------------------------------

sub getportmappingnumberofentries{
	my($this) = shift;

	my (
		$dev,
		$wanipcon_service,
		$query_res,
	);
	
	$dev = $this->getdevice();
	$wanipcon_service = $dev->getservicebyname($Net::UPnP::GW::Gateway::WANIPCONNECTION_SERVICE_TYPE);
	unless ($wanipcon_service) {
		return 0;
	}
	
	$query_res = $wanipcon_service->postquery("PortMappingNumberOfEntries");

	if ($query_res->getstatuscode() != 200) {
		return 0;
	}
	
	return $query_res->getvalue();
}


#------------------------------
# getportmapping
#------------------------------

sub getportmappingentry {
	my($this) = shift;
	
	my (
		@port_mapping,
		$dev,
		$port_mapping_num,
		$wanipcon_service,
		$n,
		%req_arg,
		$action_res,
		$arg_list,
		$ipaddr,
	);
	
	@port_mapping = ();
	
	$port_mapping_num = $this->getportmappingnumberofentries();
	if ($port_mapping_num <= 0) {
		return @port_mapping;
	}
		
	$dev = $this->getdevice();
	$wanipcon_service = $dev->getservicebyname($Net::UPnP::GW::Gateway::WANIPCONNECTION_SERVICE_TYPE);
	unless ($wanipcon_service) {
		return @port_mapping ;
	}
	
	for ($n=0; $n<$port_mapping_num; $n++) {
		#print "[$n]";
		%req_arg = (
				'NewPortMappingIndex' => $n,
			);
	
		$action_res = $wanipcon_service->postaction("GetGenericPortMappingEntry", \%req_arg);
		#print "[$n]" .$action_res->getstatuscode()  . "\n";
		#print %req_arg;
		if ($action_res->getstatuscode() != 200) {
			push(@port_mapping, undef);
			next;
		}
		$arg_list = $action_res->getargumentlist();
		#print $arg_list;
		push(@port_mapping, $arg_list);
	}
	
	return @port_mapping;
}

#------------------------------
# addportmapping
#------------------------------

sub addportmapping {
	my($this) = shift;
	my %args = (
		NewRemoteHost => '',
		NewExternalPort => '',	
		NewProtocol => '',
		NewInternalPort => '',
		NewInternalClient => '',
		NewEnabled => 1,
		NewPortMappingDescription => '',
		NewLeaseDuration => 0,
		@_,
	);
	
	my (
		$dev,
		$wanipcon_service,
		$action_res,
		$arg_list,
		$ipaddr,
		%req_arg,
	);
	
	$dev = $this->getdevice();
	$wanipcon_service = $dev->getservicebyname($Net::UPnP::GW::Gateway::WANIPCONNECTION_SERVICE_TYPE);
	unless ($wanipcon_service) {
		return 0;
	}
	
	%req_arg = (
			'NewRemoteHost' => $args{NewRemoteHost},
			'NewExternalPort' => $args{NewExternalPort},
			'NewProtocol' => $args{NewProtocol},
			'NewInternalPort' => $args{NewInternalPort},
			'NewInternalClient' => $args{NewInternalClient},
			'NewEnabled' => $args{NewEnabled},
			'NewPortMappingDescription' => $args{NewPortMappingDescription},
			'NewLeaseDuration' => $args{NewLeaseDuration},
		);
		
	$action_res = $wanipcon_service->postaction("AddPortMapping", \%req_arg);
	if ($action_res->getstatuscode() != 200) {
		return 0;
	}
	return 1;
}

#------------------------------
# deleteportmapping
#------------------------------

sub deleteportmapping {
	my($this) = shift;
	my %args = (
		NewRemoteHost => '',
		NewExternalPort => '',	
		NewProtocol => '',
		@_,
	);
	
	my (
		$dev,
		$wanipcon_service,
		$action_res,
		$arg_list,
		$ipaddr,
		%req_arg,
	);
	
	$dev = $this->getdevice();
	$wanipcon_service = $dev->getservicebyname($Net::UPnP::GW::Gateway::WANIPCONNECTION_SERVICE_TYPE);
	unless ($wanipcon_service) {
		return 0;
	}
	
	%req_arg = (
			'NewRemoteHost' => $args{NewRemoteHost},
			'NewExternalPort' => $args{NewExternalPort},
			'NewProtocol' => $args{NewProtocol},
		);
		
	$action_res = $wanipcon_service->postaction("DeletePortMapping", \%req_arg);
	if ($action_res->getstatuscode() != 200) {
		return 0;
	}
	return 1;
}

1;

__END__

=head1 NAME

Net::UPnP::GW::Gateway - Perl extension for UPnP.

=head1 SYNOPSIS

	use Net::UPnP::ControlPoint;
	use Net::UPnP::GW::Gateway;
	
	my $obj = Net::UPnP::ControlPoint->new();
	
	@dev_list = ();
	while (@dev_list <= 0 || $retry_cnt > 5) {
	#	@dev_list = $obj->search(st =>'urn:schemas-upnp-org:device:InternetGatewayDevice:1', mx => 10);
		@dev_list = $obj->search(st =>'upnp:rootdevice', mx => 3);
		$retry_cnt++;
	} 
	
	$devNum= 0;
	foreach $dev (@dev_list) {
		my $device_type = $dev->getdevicetype();
		if  ($device_type ne 'urn:schemas-upnp-org:device:InternetGatewayDevice:1') {
			next;
		}
		print "[$devNum] : " . $dev->getfriendlyname() . "\n";
		unless ($dev->getservicebyname('urn:schemas-upnp-org:service:WANIPConnection:1')) {
			next;
		}
		my $gwdev = Net::UPnP::GW::Gateway->new();
		$gwdev->setdevice($dev);
		print "\tExternalIPAddress = " . $gwdev->getexternalipaddress() . "\n";
		print "\tPortMappingNumberOfEntries = " . $gwdev->getportmappingnumberofentries() . "\n";
		@port_mapping = $gwdev->getportmappingentry();
		$port_num = 0;
		foreach $port_entry (@port_mapping) {
			if ($port_entry) {
				$port_map_name = $port_entry->{'NewPortMappingDescription'};
				if (length($port_map_name) <= 0) {
					$port_map_name = "(No name)";
				}
				print "  [$port_num] : $port_map_name\n";
				foreach $name ( keys %{$port_entry} ) {
					print "    $name = $port_entry->{$name}\n";
				}
			}
			else {
				print "  [$port_num] : Unknown\n";
			}
			$port_num++;
		}
	}

=head1 DESCRIPTION

The package is a extention UPnP/GW.

=head1 METHODS

=over 4

=item B<new> - create new Net::UPnP::GW::Gateway.

    $mservier = Net::UPnP::GW::Gateway();

Creates a new object. Read `perldoc perlboot` if you don't understand that.

The new object is not associated with any UPnP devices. Please use setdevice() to set the device.

=item B<setdevice> - set a UPnP devices

    $gw->setdevice($dev);

Set a device to the object.

=item B<getexternalipaddress> - External IP address

    $gw->getexternalipaddress();

Get the external IP address.

=item B<getportmappingnumberofentries> - PortMappingNumberOfEntries

    $gw->getexternalipaddress();

Get the number of the port mapping entries.

=item B<getportmappingentry> - PortMappingEntry

    $gw->getexternalipaddress();

Get the port mapping entries.

=item B<addportmapping> - add new port mapping.

    $result = gw->addportmapping(
                              NewRemoteHost # '',
                              NewExternalPort # '',	
                              NewProtocol # '',
                              NewInternalPort # '',
                              NewInternalClient # '',
                              NewEnabled #1,
                              NewPortMappingDescription # '',
                              NewLeaseDuration # 0);

Add a new specified port mapping.

=item B<deleteportmapping> - delete a port mapping.

    $result = gw->deleteportmapping(
                              NewRemoteHost # '',
                              NewExternalPort # '',	
                              NewProtocol # '');

Delete the specified port mapping.

=back

=head1 SEE ALSO

L<Net::UPnP::GW::Content>

L<Net::UPnP::GW::Item>

L<Net::UPnP::GW::Container>

=head1 AUTHOR

Satoshi Konno
skonno@cybergarage.org

CyberGarage
http://www.cybergarage.org

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Satoshi Konno

It may be used, redistributed, and/or modified under the terms of BSD License.

=cut
