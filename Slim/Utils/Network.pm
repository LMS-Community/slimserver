package Slim::Utils::Network;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
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
use Slim::Utils::IPDetect;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

=head2 blocking( $sock, [0 | 1] )

Set the passed socket to be blocking (1) or non-blocking (0)

=cut

sub blocking {   
	my $sock = shift;

 	return $sock->blocking(@_) unless main::ISWINDOWS;

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
	my $allowedHosts = shift || preferences('server')->get('allowedHosts');
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
	return Slim::Utils::IPDetect::IP();
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
	return $main::httpaddr || hostAddr();
}

=head2 serverMACAddress

Returns the MAC address the server is listening on (if possible).

This isn't trying as hard as eg. Net::Address::Ethernet, as arp etc.
often would take too much time on the many disconnected interfaces
of nowadays computers. In particular macOS Sierra seems to cause issues. 

=cut

sub serverMACAddress {
	my $addresses;
	eval {
		require Net::Ifconfig::Wrapper;
		$addresses = Net::Ifconfig::Wrapper::Ifconfig('list');
		
		# we're only interested in interfaces which have a known MAC and IP address
		$addresses = [ grep { $_->{inet} && $_->{ether} } values %$addresses ]; 
	};
	
	if ($addresses) {
		my $hostAddr = serverAddr();
		my ($address) = grep { $_->{inet}->{$hostAddr} } @$addresses;
		
		# if we didn't find our IP address, then let's pick just one of the list
		$address ||= $addresses->[0];

		return $address->{ether}; 
	}
}


=head2 serverURL( )

Return the base URL for this server

=cut

sub serverURL {
	return 'http://' . serverAddr() . ':' . preferences('server')->get('httpport');
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

=head1 intip($ip)

Replacement for heavyweight Net::IP->intip. Returns 0 on error.

=cut

sub intip {
	my $ip = shift;
	
	if ( $ip !~ /^[\d\.]+$/ ) {
		return 0;
	}
	
	my $n   = 1;
	my $dec = 0;
	
	for my $octet ( reverse( split /\./, $ip ) ) {
		return 0 if $octet !~ /^\d+$/;
		
		$dec += ( $n * $octet );
		$n *= 256;
	}
	
	return $dec;
}

=head1 ip_is_private($ip)

Replacement for heavyweight Net::IP->iptype.

=cut

sub ip_is_private {
	my $packed_ip = inet_aton(shift) || return 0;
	
	# http://www.perlmonks.org/?node_id=791164
	return $packed_ip =~ m{
        ^
        (?: \x0A             # 10.0.0.0/8
        |   \xAC[\x10-\x1F]  # 172.16.0.0/12
        |   \xC0\xA8         # 192.168.0.0/16
        )
    }x;
}

=head1 ip_is_ipv4($ip)

Low-fat version of Net::IP->ip_is_ipv4

=cut

sub ip_is_ipv4 {
	my $ip = shift;

	# Check for invalid chars
	unless ($ip =~ m/^[\d\.]+$/) {
		return 0;
	}

	# Can't start with a dot
	if ($ip =~ m/^\./) {
		return 0;
	}

	# Can't end with a dot
	if ($ip =~ m/\.$/) {
		return 0;
	}

	# Single Numbers are considered to be IPv4
	if ($ip =~ m/^(\d+)$/ and $1 < 256) { return 1 }

	# Count quads
	my $n = ($ip =~ tr/\./\./);

	# IPv4 must have from 1 to 4 quads
	unless ($n >= 0 and $n < 4) {
		return 0;
	}

	# Check for empty quads
	if ($ip =~ m/\.\./) {
		return 0;
	}

	foreach (split /\./, $ip) {

		# Check for invalid quads
		unless ($_ >= 0 and $_ < 256) {
			return 0;
		}
	}
	
	return 1;
}

=head2 ip_is_host()

Checks whether given IP address is the host's address or localhost

=cut

sub ip_is_host {
	my $ip = shift || return;
	
	return 1 if $ip eq '127.0.0.1';
	return 1 if $ip eq hostAddr();

	return intip($ip) == intip(hostAddr()) ? 1 : 0;
}

=head1 ip_is_gateway($ip)

Try to figure out whether an IP address is the host's gateway

=cut

sub ip_is_gateway {
	my ($ip) = @_;
	
	# Check for invalid chars
	return unless ip_is_ipv4($ip);

	my $gateway = Slim::Utils::IPDetect::defaultGateway();
	
	return unless $gateway;

	return intip($ip) == intip($gateway) ? 1 : 0;
}

=head1 ip_on_different_network($ip)

Try to figure out whether an IP address is on the same network as Logitech Media Server.
It's very simplistic in that it only checks whether we're in a private network, but the
requested IP is not (and vice versa)

=cut

sub ip_on_different_network {
	my ($ip) = @_;
	
	# Check for invalid chars
	return unless ip_is_ipv4($ip);
	
	# if our host IP is 127.0.0.1 (lookup failed), then all networks would be different - ignore
	return if hostAddr() eq '127.0.0.1';

	return ip_is_private(hostAddr()) ? !ip_is_private($ip) : ip_is_private($ip);
}

=head1 SEE ALSO

L<IO::Select>

L<IO::Socket>

L<Sys::Hostname>

=cut

1;

__END__
