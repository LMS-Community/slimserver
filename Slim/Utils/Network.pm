package Slim::Utils::Network;

# $Id$

# SlimServer Copyright (c) 2001-2005 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::Network

=head1 DESCRIPTION

A collection of network & socket related utilities.

=head1 METHODS

=cut

use strict;
use Exporter::Lite;

our @EXPORT = qw(hostAddr hostName addrToHost hostToAddr);

use IO::Select;
use IO::Socket;
use Sys::Hostname;
use Socket qw(inet_ntoa inet_aton);
use Symbol qw(qualify_to_ref);
use Time::HiRes;

use Slim::Utils::Errno;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

=head2 blocking( $sock, [0 | 1] )

Set the passed socket to be blocking (1) or non-blocking (0)

=cut

sub blocking {   
	my $sock = shift;

 	return $sock->blocking(@_) unless $^O =~ /Win32/;

	my $nonblocking = $_[0] ? "0" : "1";
	my $retval = ioctl($sock, 0x8004667e, \$nonblocking);

	if (!defined($retval) && $] >= 5.008) {
		$retval = "0 but true";
	}

	return $retval;
}

=head2 isAllowedHost( $host, [ $allowedHosts ] )

Check for allowed source IPs, called via L<Slim::Plugin::CLI> and L<Slim::Web::HTTP>

A list of comma separated allowed hosts can be passed in, or the
'allowedHosts' pref will be used by default.

Returns true or false, if the host or allowed is not.

=cut

sub isAllowedHost {
	my $host = shift;
	my $allowedHosts = shift || Slim::Utils::Prefs::get('allowedHosts');
	my @rules = split /\,/, $allowedHosts;

	foreach my $item (@rules) {

		# hack to allow hostnames in allowedHosts list
		if ((index($item, "*") == -1) && ($item !~ /\d{1,3}\.\d{1,3}\.\d{1,3}-\d{1,3}/)) {
			my $packed = gethostbyname($item) or return 0;
			$item = inet_ntoa($packed);
		}

		if ($item eq $host) {
			# If the host matches a specific IP, return valid
			return 1;
		}

		my @matched = (0,0,0,0);
		
		#Get each octet
		my @allowedoctets = split /\./, $item;
		my @hostoctets = split /\./, $host;

		for (my $i = 0; $i < 4; ++$i) {

			$allowedoctets[$i] =~ s/\s+//g;

			# if the octet is * or a specific match, pass octet match
			if (($allowedoctets[$i] eq "*") || ($allowedoctets[$i] eq $hostoctets[$i])) {

				$matched[$i] = 1;

			} elsif ($allowedoctets[$i] =~ /-/) {	#Look for a range formatted octet rule

				my ($low, $high) = split /-/,$allowedoctets[$i];

				if (($hostoctets[$i] >= $low) && ($hostoctets[$i] <= $high)) {

					# if it matches the range, pass octet match
					$matched[$i] = 1;
				}
			} 
		}

		#check if all octets passed
		if (($matched[0] eq '1') && ($matched[1] eq '1') &&
		    ($matched[2] eq '1') && ($matched[3] eq '1')) {
			return 1;
		}
	}
	
	# No rules matched, return invalid source
	return 0;
}

=head2 hostAddr()

Returns the local host's IP address.

=cut

sub hostAddr {
	my @hostAddr = ();

	my @hostnames = ('localhost', hostname());
	
	foreach my $hostname (@hostnames) {

		next if !$hostname;

		if ($hostname =~ /^\d+(?:\.\d+(?:\.\d+(?:\.\d+)?)?)?$/) {
			push @hostAddr, addrToHost($hostname);
		} else {
			push @hostAddr, hostToAddr($hostname);
		}
	}

	return @hostAddr;
}

=head2 hostName( )

Returns the name of the local host.

=cut

sub hostName {
	return hostname();
}

=head2 serverAddr( )

Returns the IP that the server is bound to.

=cut

sub serverAddr {

	if ($main::httpaddr) {
		return $main::httpaddr;
	}

	my $ip = Slim::Utils::IPDetect::IP();

	if ($ip) {
		return $ip;
	}

	my @addrs = Slim::Utils::Network::hostAddr();

	return $addrs[1] || $addrs[0] || '127.0.0.1';
}

=head2 hostToAddr( $host )

Does a blocking DNS lookup for a host to an IP address.

=cut

sub hostToAddr {
	my $host  = shift;
	my @addrs = (gethostbyname($host))[4];

	my $addr  = defined $addrs[0] ? inet_ntoa($addrs[0]) : $host;

	return $addr;
}

=head2 addrToHost( $addr )

Does a blocking DNS reverse lookup for an IP address to hostname.

=cut

sub addrToHost {
	my $addr = shift;
	my $aton = inet_aton($addr);

	return $addr unless defined $aton;

	my $host = (gethostbyaddr($aton, Socket::AF_INET()))[0];

	return $host if defined $host;
	return $addr;
}

=head2 paddr2ipaddress( $paddr )

Does a blocking DNS lookup based on the IP of the paddr structure passed.

Returns a value in the form of: ip:port

=cut

sub paddr2ipaddress {
	my ($port, $nip) = sockaddr_in(shift);

	return join(':', inet_ntoa($nip), $port);
}

=head2 ipaddress2paddr( $ipaddress )

Given a value in the form of: ip:port, return a packed paddr structure.

=cut

sub ipaddress2paddr {
        my ($ip, $port) = split( /:/, shift);

	if (!defined $ip || !defined $port) {
		return;
	}

        return pack_sockaddr_in($port, (inet_aton($ip) || $ip));
}

sub _at_eol($) {
	$_[0] =~ /\n\z/
}

=head2 sysreadline( $fh, $maxnap)

Does a non-blocking readline on a filehandle or socket.

This function is based on a posting by Tom Christiansen:
L<http://www.mail-archive.com/perl5-porters@perl.org/msg71350.html>

=cut

sub sysreadline(*;$) { 
	my ($handle, $maxnap) = @_;

	$handle = qualify_to_ref($handle, caller());

	return undef unless $handle;

	my $infinitely_patient = @_ == 1;

	my $start_time = Time::HiRes::time();

	# Try to use an existing IO::Select object if we have one.
	my $selector = ${*$handle}{'_sel'} || IO::Select->new($handle);

	my $line = '';
	my $result;

	SLEEP:
	until (_at_eol($line)) {

		unless ($infinitely_patient) {

			if (Time::HiRes::time() > $start_time + $maxnap) {
				return $line;
			} 
		} 

		my @ready_handles;

		unless (@ready_handles = $selector->can_read(.1)) {  # seconds

			unless ($infinitely_patient) {
				my $time_left = $start_time + $maxnap - Time::HiRes::time();
			} 

			next SLEEP;
		}

		INPUT_READY:
		while (() = $selector->can_read(0.0)) {

			my $was_blocking = blocking($handle,0);

			CHAR:
			while ($result = sysread($handle, my $char, 1)) {
				$line .= $char;
				last CHAR if $char eq "\n";
			} 

			my $err = $!;

			next CHAR if (!defined($result) and $err == EINTR);

			blocking($handle, $was_blocking);

			unless (_at_eol($line)) {

				if (!defined($result) && $err != EWOULDBLOCK) {
					return undef;
				}

				if (defined($result) and $result == 0) {

					# part of a line may have been read...
					# but we got eof before end of line...
					return undef;
				}

				next SLEEP;
			} 

			last INPUT_READY;
		}
	} 

	return $line;
}

=head1 SEE ALSO

L<IO::Select>

L<IO::Socket>

L<Sys::Hostname>

=cut

1;

__END__
