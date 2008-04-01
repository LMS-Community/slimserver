package Net::UPnP;

#-----------------------------------------------------------------
# UPnP
#-----------------------------------------------------------------

use strict;
use warnings;

use vars qw($VERSION $DEBUG $SSDP_ADDR $SSDP_PORT);

$VERSION  = '1.2.1';
$DEBUG = 0;

$SSDP_ADDR = '239.255.255.250';
$SSDP_PORT = 1900;

1;

__END__

=head1 NAME

Net::UPnP - Perl extension for UPnP

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

This package provides some functions to control UPnP devices.

Currently, the package provides only functions for the control point.  
To control UPnP devices, see L<Net::UPnP::ControlPoint>.

As a sample of the control point, the package provides 
L<Net::UPnP::AV::MediaServer> to control the devices such as
DLNA media servers. As the example, please dms2vodcast.pl
that converts from the MPEG2 movies to the MPEG4 one and 
outputs the RSS file for Vodcasting.

=head1 SEE ALSO

L<Net::UPnP::ControlPoint>

L<Net::UPnP::AV::MediaServer>

=head1 AUTHOR

Satoshi Konno
skonno@cybergarage.org

CyberGarage
http://www.cybergarage.org

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Satoshi Konno
	
It may be used, redistributed, and/or modified under the terms of BSD License.

=cut
