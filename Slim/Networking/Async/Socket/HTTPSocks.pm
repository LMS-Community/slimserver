package Slim::Networking::Async::Socket::HTTPSocks;

use strict;

use base qw(IO::Socket::Socks Net::HTTP::Methods Slim::Networking::Async::Socket);

use Slim::Networking::Async::Socket::HTTP;

sub new {
	my ($class, %args) = @_;
	
	# gracefully downgrade to equivalent class w/o socks
	return Slim::Networking::Async::Socket::HTTP->new( %args ) unless $args{ProxyAddr};

	my %params = (
		%args,
		SocksVersion => $args{Username} ? 5 : 4,
		AuthType => $args{Username} ? 'userpass' : 'none',
		ConnectAddr	=> $args{PeerAddr} || $args{Host},
		ConnectPort => $args{PeerPort},		
		Blocking => 1,
	);	
	
	$params{ProxyPort} ||= 1080;
	
	my $sock = $class->SUPER::new(%params) || return;
	$sock->blocking(0);

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