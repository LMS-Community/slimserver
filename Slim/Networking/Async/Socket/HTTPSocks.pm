package Slim::Networking::Async::Socket::HTTPSocks;

use strict;

use base qw(Slim::Networking::Async::Socket::HTTP IO::Socket::Socks);

sub new {
	my ($class, %args) = @_;
	
	# gracefully downgrade to equivalent class w/o socks
	return Slim::Networking::Async::Socket::HTTP->new( %args ) unless $args{ProxyAddr};

	# change PeerAddr to proxy (no deepcopy needed)
	my %params = %args;
	$params{PeerAddr} = $args{ProxyAddr};
	$params{PeerPort} = $args{ProxyPort} || 1080;
	$params{Blocking} => 1;
	
	# and connect parent's class to it (better block)
	my $sock = $class->SUPER::new( %params ) || return;
	
	# now add SOCKS needed parameters
	$params{SocksVersion} = $args{Username} ? 5 : 4;
	$params{AuthType} = $args{Username} ? 'userpass' : 'none';
	$params{ConnectAddr} = $args{PeerAddr} || $args{Host};
	$params{ConnectPort} = $args{PeerPort};
	
	# and initiate negotiation (we'll become IO::Socket::Socks)	
	$sock = IO::Socket::Socks->start_SOCKS($sock, %params) || return;

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