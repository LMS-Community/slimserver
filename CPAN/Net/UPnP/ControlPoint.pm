package Net::UPnP::ControlPoint;

#-----------------------------------------------------------------
# Net::UPnP::ControlPoint
#-----------------------------------------------------------------

use strict;
use warnings;

use Socket;

use Net::UPnP;
use Net::UPnP::HTTP;
use Net::UPnP::Device;

#------------------------------
# new
#------------------------------

sub new {
	my($class) = shift;
	my($this) = {};
	bless $this, $class;
}

#------------------------------
# search
#------------------------------

sub search {
	my($this) = shift;
	my %args = (
		st => 'upnp:rootdevice',	
		mx => 3,
		@_,
	);
	my(
		@dev_list,
		$ssdp_header,
		$ssdp_mcast,
		$rin,
		$rout,
		$ssdp_res_msg,
		$dev_location,
		$dev_addr,
		$dev_port,
		$dev_path,
		$dev_friendly_name,
		$http_req,
		$post_res,
		$post_content,
		$key,
		$dev,
		);
		
$ssdp_header = <<"SSDP_SEARCH_MSG";
M-SEARCH * HTTP/1.1
Host: $Net::UPnP::SSDP_ADDR:$Net::UPnP::SSDP_PORT
Man: "ssdp:discover"
ST: $args{st}
MX: $args{mx}

SSDP_SEARCH_MSG

	$ssdp_header =~ s/\r//g;
	$ssdp_header =~ s/\n/\r\n/g;

	socket(SSDP_SOCK, AF_INET, SOCK_DGRAM, getprotobyname('udp'));
	$ssdp_mcast = sockaddr_in($Net::UPnP::SSDP_PORT, inet_aton($Net::UPnP::SSDP_ADDR));

	send(SSDP_SOCK, $ssdp_header, 0, $ssdp_mcast);

	if ($Net::UPnP::DEBUG) {
		print "$ssdp_header\n";
 	}

	@dev_list = ();
	
	$rin = '';
	vec($rin, fileno(SSDP_SOCK), 1) = 1;
	while( select($rout = $rin, undef, undef, ($args{mx} * 2)) ) {
		recv(SSDP_SOCK, $ssdp_res_msg, 4096, 0);
		
		print "$ssdp_res_msg" if ($Net::UPnP::DEBUG);
		
		unless ($ssdp_res_msg =~ m/LOCATION[ :]+(.*)\r/i) {
			next;
		}		
		$dev_location = $1;
		unless ($dev_location =~ m/http:\/\/([0-9a-z.]+)[:]*([0-9]*)\/(.*)/i) {
			next;
		}
		$dev_addr = $1;
		$dev_port = $2;
		$dev_path = '/' . $3;
		
		$http_req = Net::UPnP::HTTP->new();
		$post_res = $http_req->post($dev_addr, $dev_port, "GET", $dev_path, "", "");

		if ($Net::UPnP::DEBUG) {
			print $post_res->getstatus() . "\n";
			print $post_res->getheader() . "\n";
			print $post_res->getcontent() . "\n";
		}
 
 		$post_content = $post_res->getcontent();

		$dev = Net::UPnP::Device->new();
 		$dev->setssdp($ssdp_res_msg);
		$dev->setdescription($post_content);
	
		if ($Net::UPnP::DEBUG) {
	 		print "friendlyName = $dev_friendly_name\n";
	 		print "ssdp = $ssdp_res_msg\n";
	 		print "description = $post_content\n";
	 	}

		push(@dev_list, $dev);
		
	}

	close(SSDP_SOCK);
	
	@dev_list;
}

1;

__END__

=head1 NAME

Net::UPnP::ControlPoint - Perl extension for UPnP control point.

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

The package can search UPnP devices in the local network and get the device list of L<Net::UPnP::Device>.

=head1 METHODS

=over 4

=item B<new> - create new Net::UPnP::ControlPoint

    $ctrlPoint = Net::UPnP::ControlPoint();

Creates a new object. Read `perldoc perlboot` if you don't understand that.

=item B<search> - search UPnP devices

    @device_list = $ctrlPoint->search();

    @device_list = $ctrlPoint->search(
                [st => $search_target], # 'upnp:rootdevice'
                [mx => $maximum_wait] # 3
                );

Search UPnP devices and return the device list. Please see L<Net::UPnP::Device> too.

=back

=head1 SEE ALSO

L<Net::UPnP::Device>

=head1 AUTHOR

Satoshi Konno
skonno@cybergarage.org

CyberGarage
http://www.cybergarage.org

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Satoshi Konno
	
It may be used, redistributed, and/or modified under the terms of BSD License.

=cut
