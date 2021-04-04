package Slim::Networking::Async::Socket::HTTPSSocks;

use strict;

use base qw(Slim::Networking::Async::Socket::HTTPS IO::Socket::Socks);

sub new {
	my ($class, %args) = @_;

	# gracefully downgrade to equivalent class w/o socks
	return Slim::Networking::Async::Socket::HTTPS->new( %args ) unless $args{ProxyAddr};

	# change PeerAddr to proxy with no handshake (no deepcopy needed)
	my %params = %args;
	$params{PeerAddr} = $args{ProxyAddr};
	$params{PeerPort} = $args{ProxyPort} || 1080;
	$params{SSL_StartHandshake} => 0;

	# and connect parent's class to it
	my $sock = $class->SUPER::new( %params );
	
	# now add SOCKS needed parameters (better block)
	$params{SocksVersion} = $args{Username} ? 5 : 4;
	$params{AuthType} = $args{Username} ? 'userpass' : 'none';
	$params{ConnectAddr} = $args{PeerAddr} || $args{Host};
	$params{ConnectPort} = $args{PeerPort};
	$params{Blocking} => 1;
	
	# and initiate negotiation (we'll become IO::Socket::Socks)	
	$sock = IO::Socket::Socks->start_SOCKS($sock, %params);

	# move to non-blocking
	$sock->blocking(0);

	# we can bless back to parent's as we are IO::Socket::Socks as well
	bless $sock;
}

sub close {
	my $self = shift;

	# remove self from select loop
	Slim::Networking::Select::removeError($self);
	Slim::Networking::Select::removeRead($self);
	Slim::Networking::Select::removeWrite($self);
	Slim::Networking::Select::removeWriteNoBlockQ($self);

	$self->SUPER::close();
}

1;