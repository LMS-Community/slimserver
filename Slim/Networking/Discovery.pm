package Slim::Networking::Discovery;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Network;

# the fake version number we're going to give non-patched Radios to make them believe we're compatible
use constant RADIO_COMPATIBLE_VERSION => '7.999.999';

my $log = logger('network.protocol');

my $prefs = preferences('server');

=head1 NAME

Slim::Networking::Discovery

=head1 DESCRIPTION

This module implements a UDP discovery protocol, used by Squeezebox, SLIMP3 and Transporter hardware.

=head1 FUNCTIONS

=head2 serverHostname()

Return a 17 character hostname, suitable for display on a client device.

=cut

sub serverHostname {
	my $hostname = Slim::Utils::Misc::getLibraryName();

	# Hostname needs to be in ISO-8859-1 encoding to support the ip3k firmware font
	$hostname = Slim::Utils::Unicode::encode('iso-8859-1', $hostname);

	# just take the first 16 characters, since that's all the space we have
	$hostname = substr $hostname, 0, 16;

	# pad it out to 17 characters total
	$hostname .= pack('C', 0) x (17 - (length $hostname));

	if ( main::INFOLOG && $log->is_info ) {
		$log->info(" calculated $hostname length: " . length($hostname));
	}

	return $hostname;
}

=head2 sayHello( $udpsock, $paddr )

Say hello to a client.

Send the client on the other end of the $udpsock a hello packet.

=cut

sub sayHello {
	my ($udpsock, $paddr) = @_;

	main::INFOLOG && $log->info(" Saying hello!");

	$udpsock->send( 'h'. pack('C', 0) x 17, 0, $paddr);
}

=head2 gotDiscoveryRequest( $udpsock, $clientpaddr, $deviceid, $revision, $mac )

Respond to a discovery request from a client device, sending it the hostname we found.

=cut

sub gotDiscoveryRequest {
	my ($udpsock, $clientpaddr, $deviceid, $revision, $mac) = @_;

	$revision = join('.', int($revision / 16), ($revision % 16));

	main::INFOLOG && $log->info("gotDiscoveryRequest: deviceid = $deviceid, revision = $revision, MAC = $mac");

	my $response = undef;

	if ($deviceid == 1) {

		main::INFOLOG && $log->info("It's a SLIMP3 (note: firmware v2.2 always sends revision of 1.1).");

		$response = 'D'. pack('C', 0) x 17;

	} elsif ($deviceid >= 2 || $deviceid <= 4) {  ## FIXME always true

		main::INFOLOG && $log->info("It's a Squeezebox");

		$response = 'D'. serverHostname();

	} else {

		main::INFOLOG && $log->info("Unknown device.");
	}

	$udpsock->send($response, 0, $clientpaddr);

	main::INFOLOG && $log->info("gotDiscoveryRequest: Sent discovery response.");
}

my $needsFakeVersion;
my %TLVhandlers = (
	# Requests
	'NAME' => sub {
		return Slim::Utils::Misc::getLibraryName()
	},                                                 # send full host name - no truncation
	'IPAD' => sub { $::httpaddr },                     # send ipaddress as a string only if it is set
	'JSON' => sub { $prefs->get('httpport') },         # send port as a string
	'VERS' => sub { $needsFakeVersion
		? RADIO_COMPATIBLE_VERSION
		: $::VERSION
	},                                                 # send server version
	'UUID' => sub { $prefs->get('server_uuid') },	   # send server uuid
	# Info only
	'JVID' => sub { main::INFOLOG && $log->is_info && $log->info("Jive: " . join(':', unpack( 'H2H2H2H2H2H2', shift))); return undef; },
);

# We used to signal a Radio version 7 when connecting to early LMS 8.
# But we're now working around that limitation in the Radio's firmware.
# We're no longer warning about a potential incompatibility - it was
# causing too much confusion. Simply fake a compatible version number.
sub getFakeVersion {
	$needsFakeVersion = 1;
	return RADIO_COMPATIBLE_VERSION;
}

sub needsFakeVersion { $needsFakeVersion ? 1 : 0 }

=head2 addTLVHandler( $hash )

Add entries to tlv handler in format { $key => $handler }

=cut

sub addTLVHandler {
	my $hash = shift;

	for my $key (keys %$hash) {
		$TLVhandlers{$key} = $hash->{$key};
	}
}

=head2 gotTLVRequest( $udpsock, $clientpaddr, $msg )

Process TLV based discovery request and send appropriate response.

=cut

sub gotTLVRequest {
	my ($udpsock, $clientpaddr, $msg) = @_;

	use bytes;

	# Discovery request and responses contain TLVs of the format:
	# T (4 bytes), L (1 byte unsigned), V (0-255 bytes)
	# To escape from previous discovery format, request are prepended by 'e', responses by 'E'

	unless ($msg =~ /^e/) {
		$log->warn("bad discovery packet - ignoring");
		return;
	}

	if (main::DEBUGLOG && $log->is_debug) {
		$log->debug("discovery packet:" . Data::Dump::dump($msg));
	}

	# chop of leading character
	$msg = substr($msg, 1);

	my $len = length($msg);
	my ($t, $l, $v);
	my $response = 'E';

	# parse TLVs
	while ($len >= 5) {
		$t = substr($msg, 0, 4);
		$l = unpack("xxxxC", $msg);
		$v = $l ? substr($msg, 5, $l) : undef;

		main::DEBUGLOG && $log->debug(" TLV: $t len: $l");

		if ($TLVhandlers{$t}) {
			if (my $r = $TLVhandlers{$t}->($v)) {
				if (length $r > 255) {
					$log->warn("Response: $t too long truncating!");
					$r = substr($r, 0, 255);
				}
				$response .= $t . pack("C", length $r) . $r;
			}
		}

		$msg = substr($msg, $l + 5);
		$len = $len - $l - 5;
	}

	if (length $response > 1450) {
		$log->warn("Response packet too long not sending!");
		return;
	}

	main::INFOLOG && $log->info("sending response");

	$udpsock->send($response, 0, $clientpaddr);
}


=head1 SEE ALSO

L<Slim::Networking::UDP>

L<Slim::Networking::SliMP3::Protocol>

=cut

1;
