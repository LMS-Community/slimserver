package Net::UPnP::HTTPResponse;

#-----------------------------------------------------------------
# Net::UPnP::HTTPResponse
#-----------------------------------------------------------------

use strict;
use warnings;

use vars qw($_STATUS $_HEADER $_CONTENT);

$_STATUS = 'status';
$_HEADER = 'header';
$_CONTENT = 'content';

#------------------------------
# new
#------------------------------

sub new {
	my($class) = shift;
	my($this) = {
		$Net::UPnP::HTTPResponse::_STATUS => '',
		$Net::UPnP::HTTPResponse::_HEADER => '',
		$Net::UPnP::HTTPResponse::_CONTENT => '',
	};
	bless $this, $class;
}

#------------------------------
# status
#------------------------------

sub setstatus() {
	my($this) = shift;
	$this->{$Net::UPnP::HTTPResponse::_STATUS} = $_[0];
}

sub getstatus() {
	my($this) = shift;
	$this->{$Net::UPnP::HTTPResponse::_STATUS};
}

sub getstatuscode() {
	my($this) = shift;
	my($status) = $this->{$Net::UPnP::HTTPResponse::_STATUS};
	if (length($status) <= 0) {
		return 0;
	}
	if($status =~ m/^HTTP\/\d.\d\s+(\d+)\s+.*/i ) {
		return $1;
	}
	return 0;
}

#------------------------------
# header
#------------------------------

sub setheader() {
	my($this) = shift;
	$this->{$Net::UPnP::HTTPResponse::_HEADER} = $_[0];
}

sub getheader() {
	my($this) = shift;
	$this->{$Net::UPnP::HTTPResponse::_HEADER};
}

#------------------------------
# content
#------------------------------

sub setcontent() {
	my($this) = shift;
	$this->{$Net::UPnP::HTTPResponse::_CONTENT} = $_[0];
}

sub getcontent() {
	my($this) = shift;
	$this->{$Net::UPnP::HTTPResponse::_CONTENT};
}

1;


__END__

=head1 NAME

Net::UPnP::HTTPResponse - Perl extension for UPnP.

=head1 DESCRIPTION

The package is a inside module.

=head1 AUTHOR

Satoshi Konno
skonno@cybergarage.org

CyberGarage
http://www.cybergarage.org

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Satoshi Konno

It may be used, redistributed, and/or modified under the terms of BSD License.

=cut
