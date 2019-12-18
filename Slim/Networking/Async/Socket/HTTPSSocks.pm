package Slim::Networking::Async::Socket::HTTPSSocks;

use strict;
use IO::Socket::Socks;

use base qw(IO::Socket::SSL IO::Socket::Socks Net::HTTP::Methods Slim::Networking::Async::Socket);

use Slim::Networking::Async::Socket::HTTPS;

sub new {
	my ($class, %args) = @_;
	
	# gracefully downgrade to equivalent class w/o socks
	return Slim::Networking::Async::Socket::HTTPS->new( %args ) unless $args{ProxyAddr};
	
	my %params = (
		%args,
		SocksVersion => $args{Username} ? 5 : 4,
		AuthType => $args{Username} ? 'userpass' : 'none',
		ConnectAddr => $args{PeerAddr} || $args{Host},
		ConnectPort => $args{PeerPort},		
		Blocking => 1,
	);	
	
	$params{ProxyPort} ||= 1080;	
	
	# create the SOCKS object and connect
	my $sock = IO::Socket::Socks->new(%params) || return;
	$sock->blocking(0);
		
	# once connected SOCKS is a normal socket, so we can use start_SSL
	IO::Socket::SSL->start_SSL($sock, @_);
		
	# as we inherit from IO::Socket::SSL, we can bless to our base class
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