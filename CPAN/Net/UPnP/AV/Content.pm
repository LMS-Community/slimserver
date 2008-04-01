package Net::UPnP::AV::Content;

#-----------------------------------------------------------------
# Net::UPnP::AV::Content
#-----------------------------------------------------------------

use strict;
use warnings;

use vars qw($_ID $_TITLE $_DATE);

$_ID = '_id';
$_TITLE = '_title';
$_DATE = '_date';

#------------------------------
# new
#------------------------------

sub new {
	my($class) = shift;
	my($this) = {
		$Net::UPnP::AV::Content::_ID => '',
		$Net::UPnP::AV::Content::_TITLE => '',
		$Net::UPnP::AV::Content::_DATE => '',
	};
	bless $this, $class;
}

#------------------------------
# id
#------------------------------

sub setid() {
	my($this) = shift;
	if (@_) {
		$this->{$Net::UPnP::AV::Content::_ID} = $_[0];
	}
}

sub getid() {
	my($this) = shift;
	$this->{$Net::UPnP::AV::Content::_ID};
}

#------------------------------
# title
#------------------------------

sub settitle() {
	my($this) = shift;
	if (@_) {
		$this->{$Net::UPnP::AV::Content::_TITLE} = $_[0];
	}
}

sub gettitle() {
	my($this) = shift;
	$this->{$Net::UPnP::AV::Content::_TITLE};
}

#------------------------------
# date
#------------------------------

sub setdate() {
	my($this) = shift;
	if (@_) {
		$this->{$Net::UPnP::AV::Content::_DATE} = $_[0];
	}
}

sub getdate() {
	my($this) = shift;
	$this->{$Net::UPnP::AV::Content::_DATE};
}

#------------------------------
# is*
#------------------------------

sub iscontainer() {
	0;
}

sub isitem() {
	0;
}

1;

__END__

=head1 NAME

Net::UPnP::AV::Content - Perl extension for UPnP.

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

The package is a extention UPnP/AV media server, and a super class of L<Net::UPnP::AV::Container> and L<Net::UPnP::AV::Item>.

=head1 METHODS

=over 4

=item B<getid> - Get the content ID.

    $id = $item->getid();

Get the content ID.

=item B<gettitle> - Get the content title.

    $title = $item->gettitle();

Get the content title.

=item B<getdate> - Get the content date.

    $date = $item->getdate();

Get the content date.

=back

=head1 SEE ALSO

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
