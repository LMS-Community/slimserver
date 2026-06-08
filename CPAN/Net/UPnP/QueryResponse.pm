package Net::UPnP::QueryResponse;

#-----------------------------------------------------------------
# Net::UPnP::QueryResponse
#-----------------------------------------------------------------

use strict;
use warnings;

use Net::UPnP::HTTP;
use Net::UPnP::HTTPResponse;

use vars qw($_HTTP_RESPONSE);

$_HTTP_RESPONSE = 'httpres';

#------------------------------
# new
#------------------------------

sub new {
	my($class) = shift;
	my($this) = {
		$Net::UPnP::QueryResponse::_HTTP_RESPONSE => undef,
	};
	bless $this, $class;
}

#------------------------------
# header
#------------------------------

sub sethttpresponse() {
	my($this) = shift;
	$this->{$Net::UPnP::QueryResponse::_HTTP_RESPONSE} = $_[0];
 }

sub gethttpresponse() {
	my($this) = shift;
	$this->{$Net::UPnP::QueryResponse::_HTTP_RESPONSE};
 }
 
#------------------------------
# status
#------------------------------

sub getstatus() {
	my($this) = shift;
	my($http_res) = $this->gethttpresponse();
	$http_res->getstatus();
 }

sub getstatuscode() {
	my($this) = shift;
	my($http_res) = $this->gethttpresponse();
	$http_res->getstatuscode();
 }

#------------------------------
# header
#------------------------------

sub getheader() {
	my($this) = shift;
	my($http_res) = $this->gethttpresponse();
	$http_res->getheader();
 }

#------------------------------
# content
#------------------------------

sub getcontent() {
	my($this) = shift;
	my($http_res) = $this->gethttpresponse();
	$http_res->getcontent();
 }

#------------------------------
# content
#------------------------------

sub getvalue() {
	my($this) = shift;
	my(
		$http_res,
		$res_statcode,
		$res_content,
		$value,
	);
	
	$http_res = $this->gethttpresponse();
	
	$res_statcode = $http_res->getstatuscode();
	if ($res_statcode != 200) {
		return "";
	}

	$value = "";
	
	$res_content = $http_res->getcontent();
	if ($res_content =~ m/<return>(.*?)<\/return>/si) {
		$value = $1;
	}

	return $value;
 }

1;

__END__

=head1 NAME

Net::UPnP::QueryResponse - Perl extension for UPnP.

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

The package is used a object of the action response.

=head1 METHODS

=over 4

=item B<getstatuscode> - get the status code.

    $status_code = $queryres->getstatuscode();

Get the status code of the SOAP response.

=item B<getvalue> - get the return value.

    $value = $queryres->getvalue();

Get the value of the SOAP response.

=back

=head1 AUTHOR

Satoshi Konno
skonno@cybergarage.org

CyberGarage
http://www.cybergarage.org

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Satoshi Konno

It may be used, redistributed, and/or modified under the terms of BSD License.

=cut
