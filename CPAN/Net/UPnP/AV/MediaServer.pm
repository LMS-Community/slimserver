package Net::UPnP::AV::MediaServer;

#-----------------------------------------------------------------
# Net::UPnP::AV::MediaServer
#-----------------------------------------------------------------

use strict;
use warnings;

use Net::UPnP::HTTP;
use Net::UPnP::Device;
use Net::UPnP::Service;
use Net::UPnP::AV::Container;
use Net::UPnP::AV::Item;

use vars qw($_DEVICE $DEVICE_TYPE $CONTENTDIRECTORY_SERVICE_TYPE);

$_DEVICE = 'device';

$DEVICE_TYPE = 'urn:schemas-upnp-org:device:MediaServer:1';
$CONTENTDIRECTORY_SERVICE_TYPE = 'urn:schemas-upnp-org:service:ContentDirectory:1';

#------------------------------
# new
#------------------------------

sub new {
	my($class) = shift;
	my($this) = {
		$Net::UPnP::AV::MediaServer::_DEVICE => undef,
	};
	bless $this, $class;
}

#------------------------------
# device
#------------------------------

sub setdevice() {
	my($this) = shift;
	if (@_) {
		$this->{$Net::UPnP::AV::MediaServer::_DEVICE} = $_[0];
	}
}

sub getdevice() {
	my($this) = shift;
	$this->{$Net::UPnP::AV::MediaServer::_DEVICE};
}

#------------------------------
# browse
#------------------------------

sub browse {
	my($this) = shift;
	my %args = (
		ObjectID => 0,	
		BrowseFlag => 'BrowseDirectChildren',
		Filter => '*',
		StartingIndex => 0,
		RequestedCount => 0,
		SortCriteria => '',
		@_,
	);
	
	my ($objid, $browseFlag, $filter, $startIdx, $reqCount, $sortCriteria) = @_;
	my (
		$dev,
		$condir_service,
		%req_arg,
		$action_res,
	);
	
	$dev = $this->getdevice();
	$condir_service = $dev->getservicebyname($Net::UPnP::AV::MediaServer::CONTENTDIRECTORY_SERVICE_TYPE);
	
	%req_arg = (
			'ObjectID' => $args{ObjectID},
			'BrowseFlag' => $args{BrowseFlag},
			'Filter' => $args{Filter},
			'StartingIndex' => $args{StartingIndex},
			'RequestedCount' => $args{RequestedCount},
			'SortCriteria' => $args{SortCriteria},
		);
	
	$condir_service->postaction("Browse", \%req_arg);
}

sub browsedirectchildren {
	my($this) = shift;
	my %args = (
		ObjectID => 0,	
		Filter => '*',
		StartingIndex => 0,
		RequestedCount => 0,
		SortCriteria => '',
		@_,
	);
	$this->browse (
			ObjectID => $args{ObjectID},
			BrowseFlag => 'BrowseDirectChildren',
			Filter => $args{Filter},
			StartingIndex => $args{StartingIndex},
			RequestedCount => $args{RequestedCount},
			SortCriteria => $args{SortCriteria}
			);
}

sub browsemetadata {
	my($this) = shift;
	my %args = (
		ObjectID => 0,	
		Filter => '*',
		StartingIndex => 0,
		RequestedCount => 0,
		SortCriteria => '',
		@_,
	);
	$this->browse (
			ObjectID => $args{ObjectID},
			BrowseFlag => 'BrowseMetadata',
			Filter => $args{Filter},
			StartingIndex => $args{StartingIndex},
			RequestedCount => $args{RequestedCount},
			SortCriteria => $args{SortCriteria}
			);
}

#------------------------------
# getdirectchildren
#------------------------------

sub getcontentlist {
	my($this) = shift;
	my %args = (
		ObjectID => 0,	
		Filter => '*',
		StartingIndex => 0,
		RequestedCount => 0,
		SortCriteria => '',
		@_,
	);
	my (
		@content_list,
		$action_res,
		$arg_list,
		$result,
		$content,
		$container,
		$item,
	);
	
	@content_list = ();
	$action_res = $this->browsedirectchildren(
			ObjectID => $args{ObjectID},
			Filter => $args{Filter},
			StartingIndex => $args{StartingIndex},
			RequestedCount => $args{RequestedCount},
			SortCriteria => $args{SortCriteria}
			);
	if ($action_res->getstatuscode() != 200) {
		return @content_list;
	}
	$arg_list = $action_res->getargumentlist();
	unless ($arg_list->{'Result'}) {
		return @content_list;
	}
	$result = $arg_list->{'Result'};

	while ($result =~ m/<container(.*?)<\/container>/sgi) {
		$content = $1;
		$container = Net::UPnP::AV::Container->new();
		if ($content =~ m/id=\"(.*?)\"/si) {
			$container->setid($1);
		}
		if ($content =~ m/<dc:title>(.*)<\/dc:title>/si) {
			$container->settitle($1);
		}
		if ($content =~ m/<dc:date>(.*)<\/dc:date>/si) {
			$container->setdate($1);
		}
		push (@content_list, $container);
		#print "container(" . $container->getid() . ") = " . $container->gettitle() . "\n";
		#print $1;
	}

	while ($result =~ m/<item(.*?)<\/item>/sgi) {
		$content = $1;
		$item= Net::UPnP::AV::Item->new();
		if ($content =~ m/id=\"(.*?)\"/si) {
			$item->setid($1);
		}
		if ($content =~ m/<dc:title>(.*)<\/dc:title>/si) {
			$item->settitle($1);
		}
		if ($content =~ m/<dc:date>(.*)<\/dc:date>/si) {
			$item->setdate($1);
		}
		if ($content =~ m/<res[^>]*>(.*?)<\/res>/si) {
			$item->seturl(Net::UPnP::HTTP::xmldecode($1));
		}
		if ($content =~ m/protocolInfo=\"http-get:[^:]*:([^:]*):.*\"/si) {
			$item->setcontenttype($1);
		}
		elsif ($content =~ m/protocolInfo=\"[^:]*:[^:]:([^:]*):.*\"/si) {
			$item->setcontenttype($1);
		}
		push (@content_list, $item);
	}

	@content_list;
}

#------------------------------
# getsystemupdateid
#------------------------------

sub getsystemupdateid {
	my($this) = shift;

	my (
		$dev,
		$condir_service,
		$query_res,
	);
	
	$dev = $this->getdevice();
	$condir_service = $dev->getservicebyname($Net::UPnP::AV::MediaServer::CONTENTDIRECTORY_SERVICE_TYPE);
	
	$query_res = $condir_service->postquery("SystemUpdateID");

	if ($query_res->getstatuscode() != 200) {
		return "";
	}
	
	return $query_res->getvalue();
}

1;

__END__

=head1 NAME

Net::UPnP::AV::MediaServer - Perl extension for UPnP.

=head1 SYNOPSIS

    use Net::UPnP::ControlPoint;
    use Net::UPnP::AV::MediaServer;

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
        $mediaServer = Net::UPnP::AV::MediaServer->new();
        $mediaServer->setdevice($dev);
        @content_list = $mediaServer->getcontentlist(ObjectID => 0);
        foreach $content (@content_list) {
            print_content($mediaServer, $content, 1);
        }
        $devNum++;
    }

    sub print_content {
        my ($mediaServer, $content, $indent) = @_;
        my $id = $content->getid();
        my $title = $content->gettitle();
        for ($n=0; $n<$indent; $n++) {
            print "\t";
        }
        print "$id = $title";
        if ($content->isitem()) {
            print " (" . $content->geturl();
            if (length($content->getdate())) {
                print " - " . $content->getdate();
            }
            print " - " . $content->getcontenttype() . ")";
        }
        print "\n";
        unless ($content->iscontainer()) {
            return;
        }
        @child_content_list = $mediaServer->getcontentlist(ObjectID => $id );
        if (@child_content_list <= 0) {
            return;
        }
        $indent++;
        foreach my $child_content (@child_content_list) {
            print_content($mediaServer, $child_content, $indent);
        }
    }

=head1 DESCRIPTION

The package is a extention UPnP/AV media server.

=head1 METHODS

=over 4

=item B<new> - create new Net::UPnP::AV::MediaServer.

    $mservier = Net::UPnP::AV::MediaServer();

Creates a new object. Read `perldoc perlboot` if you don't understand that.

The new object is not associated with any UPnP devices. Please use setdevice() to set the device.

=item B<setdevice> - set a UPnP devices

    $mservier->setdevice($dev);

Set a device to the object.

=item B<browse> - browse the content directory.
	
    @action_response = $mservier->browse(
                                        ObjectID => $objid, # 0	
                                        BrowseFlag => $browseFlag, # 'BrowseDirectChildren'
                                        Filter => $filter, # "*'
                                        StartingIndex => $startIndex, # 0
                                        RequestedCount => $reqCount, # 0
                                        SortCriteria => $sortCrit # ''
                                        );

Browse the content directory and return the action response, L<Net::UPnP::ActionResponse>.

=item B<getcontentlist> - get the content list.
	
    @content_list = $mservier->getcontentlist(
                                        ObjectID => $objid, # 0	
                                        Filter => $filter, # "*'
                                        StartingIndex => $startIndex, # 0
                                        RequestedCount => $reqCount, # 0
                                        SortCriteria => $sortCrit # ''
                                        );

Browse the content directory and return the content list. Please see L<Net::UPnP::AV::Content>, L<Net::UPnP::AV::Item> and L<Net::UPnP::AV::Container>.

=back

=head1 SEE ALSO

L<Net::UPnP::AV::Content>

L<Net::UPnP::AV::Item>

L<Net::UPnP::AV::Container>

=head1 AUTHOR

Satoshi Konno
skonno@cybergarage.org

CyberGarage
http://www.cybergarage.org

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Satoshi Konno

It may be used, redistributed, and/or modified under the terms of BSD License.

=cut
