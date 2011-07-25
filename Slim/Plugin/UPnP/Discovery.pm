package Slim::Plugin::UPnP::Discovery;

# $Id$

# This module handles UPnP 1.0 discovery advertisements and responses to search requests
# Reference: http://www.upnp.org/specs/arch/UPnP-arch-DeviceArchitecture-v1.0.pdf
# Section 1. pages 10-22
#
# Note: Version 1.1 of UPnP is available, but is not implemented here.

use strict;

use Digest::MD5 qw(md5_hex);
use HTTP::Date;
use Socket;

use Slim::Networking::Select;
use Slim::Networking::Async::Socket::UDP;
use Slim::Utils::Log;
use Slim::Utils::Timers;

my $log = logger('plugin.upnp');

use constant SSDP_HOST => '239.255.255.250:1900';
use constant SSDP_PORT => 1900;

# socket for both multicasting and unicast replies
my $SOCK;

my $SERVER;

# All devices we're notifying about
my %UUIDS;

sub init {
	my $class = shift;
	
	# Construct Server header for later use
	my $details = Slim::Utils::OSDetect::details();
	$SERVER = $details->{os} . '/' . $details->{osArch} . ' UPnP/1.0 SqueezeboxServer/' . $::VERSION . '/' . $::REVISION;

	# Test if we can use ReusePort
	my $hasReusePort = eval {
		my $s = IO::Socket::INET->new(
			Proto     => 'udp',
			LocalPort => SSDP_PORT,
			ReuseAddr => 1,
			ReusePort => 1,
		);
		$s->close;
		return 1;
	};

	# Setup our multicast socket
	$SOCK = Slim::Networking::Async::Socket::UDP->new(
		LocalPort => SSDP_PORT,
		ReuseAddr => 1,
		ReusePort => $hasReusePort ? 1 : 0,
	);
	
	if ( !$SOCK ) {
		$log->error("Unable to open UPnP multicast discovery socket: ($!) You may have other UPnP software running or a permissions problem.");
		return;
	}
	
	# listen for multicasts on this socket
	$SOCK->mcast_add( SSDP_HOST );
	
	# This socket will continue to live and receive events as
	# long as SqueezeCenter is running
	Slim::Networking::Select::addRead( $SOCK, \&_read );
	
	$log->info('UPnP Discovery initialized');
	
	return 1;
}

# Stop listening for UPnP events
sub shutdown {
	my $class = shift;
	
	# if anything still left in %UUIDS we need to send byebye's for them
	for my $uuid ( keys %UUIDS ) {
		$class->unregister($uuid);
	}
	
	if ( defined $SOCK ) {
		Slim::Networking::Select::removeRead( $SOCK );
	
		$SOCK->close;
	
		$SOCK = undef;
	}
	
	$log->info('UPnP Discovery shutdown');
}

sub server { $SERVER }

sub _read {
	my $sock = shift;
	
	my $addr = recv $sock, my $ssdp, 1024, 0;

	if ( !defined $addr ) {
		$log->is_debug && $log->debug("Read search result failed: $!");
		return;
	}
	
	my ($port, $iaddr) = sockaddr_in($addr);
	$iaddr = inet_ntoa($iaddr);
	
	#main::DEBUGLOG && $log->is_debug && $log->debug( "UPnP Discovery packet from $iaddr:$port:\n$ssdp\n" );
	
	if ( $ssdp =~ /^M-SEARCH/ ) {
		my ($st) = $ssdp =~ /\sST:\s*([^\s]+)/i;
		if ( $st ) {
			# See if the search request matches any of our registered devices/services			
			my ($mx) = $ssdp =~ /MX:\s*([^\s]+)/i;
			
			# Ignore packets without MX
			return unless defined $mx;
			
			$log->is_debug && $log->debug( "M-SEARCH for $st (mx: $mx)" );
			
			# Most devices seem to ignore the mx value and reply quickly
			if ( $mx > 3 ) {
				$mx = 3;
			}
		
			for my $uuid ( keys %UUIDS ) {
				my $msgs = [];
				
				if ( $st eq 'ssdp:all' ) {
					# Send a response for all devices and services
					$msgs = __PACKAGE__->_construct_messages(
						type => 'all',
						%{ $UUIDS{$uuid} },
					);
				}
				elsif ( $st eq 'upnp:rootdevice' ) {
					# Just the root device
					$msgs = __PACKAGE__->_construct_messages(
						type => $st,
						%{ $UUIDS{$uuid} },
					);
				}
				elsif ( $st =~ /uuid:${uuid}/ ) {
					# Just the device matching this UUID
					$msgs = __PACKAGE__->_construct_messages(
						type => 'uuid',
						%{ $UUIDS{$uuid} },
					);
				}
				elsif ( $st =~ /urn:(.+):(\d+)/ ) {
					# A device or service matching this urn, or a prior version
					my $search = $1;
					my $sver   = $2;
					
					if ( $UUIDS{$uuid}->{device} =~ /$search/ ) {
						my ($dver) = $UUIDS{$uuid}->{device} =~ /(\d+)$/;
						if ( $sver <= $dver ) {
							$msgs = __PACKAGE__->_construct_messages(
								type => "urn:$search",
								ver  => $sver,
								%{ $UUIDS{$uuid} },
							);
						}
					}
					else {
						for my $service ( @{ $UUIDS{$uuid}->{services} } ) {
							if ( $service =~ /$search/ ) {
								my ($servver) = $service =~ /(\d+)$/;
								if ( $sver <= $servver ) {
									my $new = __PACKAGE__->_construct_messages(
										type => "urn:$search",
										ver  => $sver,
										%{ $UUIDS{$uuid} },
									);
									
									push @{$msgs}, @{$new};
								}
							}
						}
					}
				}
				
				if ( scalar @{$msgs} ) {					
					my $url = $UUIDS{$uuid}->{url};
					my $ttl = $UUIDS{$uuid}->{ttl};
					
					__PACKAGE__->_advertise(
						type => 'reply',
						dest => {
							addr => $iaddr,
							port => $port,
						},
						msgs => $msgs,
						url  => $url,
						ttl  => $ttl,
						mx   => $mx,
					);
				}				
			}
		}
	}			
}

sub register {
	my ( $class, %args ) = @_;
	
	# Remember everything about this UUID, used for replies to M-SEARCH
	# and when the device disconnects or the server shuts down
	$UUIDS{ $args{uuid} } = \%args;
	
	# Send a byebye message before any alive messages
	$class->_advertise(
		type => 'byebye',
		msgs => [ {
			NT  => 'upnp:rootdevice',
			USN => 'uuid:' . $args{uuid} . '::upnp:rootdevice',
		} ],
	);
	
	my $msgs = $class->_construct_messages(
		type => 'all',
		%args,
	);
	
	$class->_advertise(
		type => 'alive',
		msgs => $msgs, 
		url  => $args{url},
		ttl  => $args{ttl},
	);
	
	# Schedule resending of alive packets at random interval less than 1/2 the ttl
	my $resend = int( rand( $args{ttl} / 2 ) );
	$log->is_debug && $log->debug( "Will resend notify packets in $resend sec" );
	Slim::Utils::Timers::setTimer(
		$class,
		time() + $resend,
		\&reregister,
		\%args,
	);
}

sub reregister {
	my ( $class, $args ) = @_;
	
	# Make sure UUID still exists, if not the device has disconnected
	if ( exists $UUIDS{ $args->{uuid} } ) {
		my $msgs = $class->_construct_messages(
			type => 'all',
			%{$args},
		);
		
		$class->_advertise(
			type => 'alive',
			msgs => $msgs,
			url  => $args->{url},
			ttl  => $args->{ttl},
		);
		
		my $resend = int( rand( $args->{ttl}/ 2 ) );
		$log->is_debug && $log->debug( "Will resend notify packets in $resend sec" );
		Slim::Utils::Timers::setTimer(
			$class,
			time() + $resend,
			\&reregister,
			$args,
		);
	}
}

sub unregister {
	my ( $class, $uuid ) = @_;
	
	my $msgs = $class->_construct_messages(
		type => 'all',
		%{ $UUIDS{$uuid} },
	);
		
	delete $UUIDS{$uuid};
	
	$class->_advertise(
		type => 'byebye',
		msgs => $msgs,
	);
}

# Generate a static UUID for a client, using UUID or hash of MAC
sub uuid {
	my ( $class, $client ) = @_;
	
	my @string = split //, $client->uuid || md5_hex( $client->id );
	
	splice @string, 8, 0, '-';
	splice @string, 13, 0, '-';
	splice @string, 18, 0, '-';
	splice @string, 23, 0, '-';
	
	return uc( join( '', @string ) );
}

sub _advertise {
	my ( $class, %args ) = @_;
	
	my $type = $args{type};
	my $dest = $args{dest};
	my $msgs = $args{msgs};
	my $url  = $args{url};
	my $ttl  = $args{ttl};
	my $mx   = $args{mx};
	
	my @out;
	
	if ( $type eq 'byebye' ) {
		for my $msg ( @{$msgs} ) {
			push @out, join "\x0D\x0A", (
				'NOTIFY * HTTP/1.1',
				'Host: ' . SSDP_HOST,
				'NT: ' . $msg->{NT},
				'NTS: ssdp:byebye',
				'USN: ' . $msg->{USN},
				'', '',
			);
		}
	}
	elsif ( $type eq 'alive' ) {
		for my $msg ( @{$msgs} ) {	
			push @out, join "\x0D\x0A", (
				'NOTIFY * HTTP/1.1',
				'Host: ' . SSDP_HOST,
				'NT: ' . $msg->{NT},
				'NTS: ssdp:alive',
				'USN: ' . $msg->{USN},
				'Location: ' . $url,
				'Cache-Control: max-age=' . $ttl,
				'Server: ' . $SERVER,
				'',	'',
			);
		}
	}
	elsif ( $type eq 'reply' ) {
		for my $msg ( @{$msgs} ) {
			push @out, join "\x0D\x0A", (
				'HTTP/1.1 200 OK',
				'Cache-Control: max-age=' . $ttl,
				'Date: ' . time2str(time),
				'Ext: ',
				'Location: ' . $url,
				'Server: ' . $SERVER,
				'ST: ' . ( $msg->{ST} || $msg->{NT} ),
				'USN: ' . $msg->{USN},
				'', '',
			);
		}
	}
	
	if ( $type eq 'byebye' ) {
		# Send immediately, each packet twice
		$log->is_debug && $log->debug( 'Sending ' . scalar(@out) . ' byebye packets' );
		
		for my $pkt ( @out ) {
			for ( 1..2 ) {
				$SOCK->mcast_send( $pkt, SSDP_HOST );
			}
		}
	}
	elsif ( $type eq 'alive') {
		# Wait a random interval < 100ms and send the full set of requests
		# Send them again 1/2 second later in case one gets lost
		my $send = sub {
			$log->is_debug && $log->debug( 'Sending ' . scalar(@out) . ' alive packets' );
			for my $pkt ( @out ) {
				$SOCK->mcast_send( $pkt, SSDP_HOST );
			}
		};

		Slim::Utils::Timers::setTimer( undef, Time::HiRes::time() + rand(0.1), $send );
		Slim::Utils::Timers::setTimer( undef, Time::HiRes::time() + 0.5, $send );
	}
	elsif ( $type eq 'reply' ) {
		# send unicast UDP to source IP/port, delayed by random interval less than MX
		my $send = sub {
			$log->is_debug && $log->debug(
				'Replying to ' . $dest->{addr} . ':' . $dest->{port}
				. ' with ' . scalar(@out) . ' packets'
				. ': ' . Data::Dump::dump(\@out)
			);
			
			my $addr = sockaddr_in( $dest->{port}, inet_aton( $dest->{addr} ) );
			
			for my $pkt ( @out ) {
				$SOCK->send( $pkt, 0, $addr ) or die "Unable to send UDP reply packet: $!";
			}
		};
		
		Slim::Utils::Timers::setTimer(
			undef,
			Time::HiRes::time() + rand($mx),
			$send,
		);
	}
}

sub _construct_messages {
	my ( $class, %args ) = @_;
	
	my $type = delete $args{type};
	
	my @msgs;
	
	if ( $type eq 'all' ) {
		# 3 discovery messages for the root device
		push @msgs, {
			NT  => 'upnp:rootdevice',
			USN => 'uuid:' . $args{uuid} . '::upnp:rootdevice',
		};
		
		push @msgs, {
			NT  => 'uuid:' . $args{uuid},
			USN => 'uuid:' . $args{uuid},
		};
		
		push @msgs, {
			NT  => $args{device},
			USN => 'uuid:' . $args{uuid} . '::' . $args{device},
		};
		
		# No support for embedded devices
		
		# 1 discovery message per service
		for my $service ( @{ $args{services} } ) {
			push @msgs, {
				NT  => $service,
				USN => 'uuid:' . $args{uuid} . '::' . $service,
			};
		}
	}
	elsif ( $type eq 'upnp:rootdevice' ) {
		# 1 message for the root device
		push @msgs, {
			NT  => 'upnp:rootdevice',
			USN => 'uuid:' . $args{uuid} . '::upnp:rootdevice',
		};
	}
	elsif ( $type eq 'uuid' ) {
		# 1 message for this UUID
		push @msgs, {
			NT  => 'uuid:' . $args{uuid},
			USN => 'uuid:' . $args{uuid},
		};
	}
	elsif ( $type =~ /^urn:(.+)/ ) {
		# 1 message for this device or service
		my $search = $1;
		my $ver    = $args{ver};
		
		if ( $args{device} =~ /$search/ ) {
			my $nt = 'urn:' . $search . ':' . $ver;
			push @msgs, {
				NT  => $nt,
				USN => 'uuid:' . $args{uuid} . '::' . $nt,
			};
		}
		else {
			for my $service ( @{ $args{services} } ) {
				if ( $service =~ /$search/ ) {
					my $nt = 'urn:' . $search . ':' . $ver;
					push @msgs, {
						NT  => $nt,
						USN => 'uuid:' . $args{uuid} . '::' . $nt,
					};
				}
			}
		}
	}
	
	return \@msgs;
}

1;