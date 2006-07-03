package Net::UPnP::HTTP;

#-----------------------------------------------------------------
# Net::UPnP::HTTP
#-----------------------------------------------------------------

use strict;
use warnings;

use Socket;

use Net::UPnP;
use Net::UPnP::HTTPResponse;

use vars qw($STATUS_CODE $STATUS $HEADER $CONTENT $POST $GET);

$POST = 'POST';
$GET = 'GET';

$STATUS_CODE = 'status_code';
$STATUS = 'status';
$HEADER = 'header';
$CONTENT = 'content';

#------------------------------
# new
#------------------------------

sub new {
	my($class) = shift;
	my($this) = {};
	bless $this, $class;
}

#------------------------------
# post
#------------------------------

sub post {
	my($this) = shift;
	if (@_ <  6) {
		return "";
	}
	my ($post_addr, $post_port, $method, $path, $add_header, $req_content) = @_;
	my (
		$post_sockaddr,
		$req_content_len,
		$add_header_name,
		$add_header_value,
		$req_header,
		$res_status,
		$res_header_cnt,
		$res_header,
		$res_content_len,
		$res_content,
		$res,
		);

	$req_content_len = length($req_content);
	
$req_header = <<"REQUEST_HEADER";
$method $path HTTP/1.0
Host: $post_addr:$post_port
Content-Length: $req_content_len
REQUEST_HEADER

	#print "header = " . %{$add_header} . "\n";
	#%add_header = %{$add_header_ref};
	if (ref $add_header) {
		while ( ($add_header_name, $add_header_value) =  each %{$add_header}) {
			$req_header .= "$add_header_name: $add_header_value\n";
		}
	}

	$req_header .= "\n";
	$req_header =~ s/\r//g;
	$req_header =~ s/\n/\r\n/g;

	$post_sockaddr = sockaddr_in($post_port, inet_aton($post_addr));
	socket(HTTP_SOCK, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
	connect(HTTP_SOCK, $post_sockaddr);
	select(HTTP_SOCK); $|=1; select(STDOUT);

	if ($Net::UPnP::DEBUG) {
		print $req_header;
		print $req_content;
	}
	
	print HTTP_SOCK $req_header;
	print HTTP_SOCK $req_content;

	$res_status = "";
	$res_header = "";
	$res_header_cnt = 0;
	while(<HTTP_SOCK>) {
		if (m/^\r\n$/) {
			last;
		}
		$res_header_cnt++;
		if ($res_header_cnt == 1) {
			$res_status .= $_;
			next;
		}
		$res_header .= $_;
	}

	$res_content_len = 0;
	if($res_header =~ m/^Content-Length[: ]*(\d+)/i ) {
		$res_content_len = $1
	}
	
	$res_content = "";
	if ($res_content_len) {
		read(HTTP_SOCK, $res_content, $res_content_len);
	}
	else {
		while(<HTTP_SOCK>) {
			$res_content .= $_;
		}
	}

	close(HTTP_SOCK);

	$res = Net::UPnP::HTTPResponse->new();
	$res->setstatus($res_status);
	$res->setheader($res_header);
	$res->setcontent($res_content);

	if ($Net::UPnP::DEBUG) {
		print $res_status;
		print $res_header;
		print $res_content;
	}

	return $res;
}

#------------------------------
# postsoap
#------------------------------

sub postsoap {
	my($this) = shift;
	my ($post_addr, $post_port, $path, $action_name, $action_content) = @_;
	my (
		%soap_header,
		$name,
		$value
	);
	
	%soap_header = (
		'Content-Type' => "text/xml; charset=\"utf-8\"",
		'SOAPACTION' => $action_name,
	);
	
	$this->post($post_addr, $post_port, $Net::UPnP::HTTP::POST, $path, \%soap_header, $action_content);
}

#------------------------------
# postsoap
#------------------------------

sub xmldecode {
	my (
		$str
	);
	if (ref $_[0]) {
		$str = $_[1];
	}
	else {
		$str = $_[0];
	}
	$str =~ s/\&gt;/>/g;
	$str =~ s/\&lt;/</g;
	$str =~ s/\&quot;/\"/g;
	$str =~ s/\&amp;/\&/g;
	$str;
}

1;

__END__

=head1 NAME

Net::UPnP::HTTP - Perl extension for UPnP.

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
