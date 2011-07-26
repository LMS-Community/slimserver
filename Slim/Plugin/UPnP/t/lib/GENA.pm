package GENA;

# Very basic GENA client for testing

use strict;

use Data::Dump qw(dump);
use IO::Select;
use IO::Socket::INET;
use HTTP::Daemon;
use URI;
use XML::Simple qw(XMLin);

use constant TIMEOUT => 5;

my $SERVER;
my %SUBS;

sub new {
	my ( $class, $url, $cb ) = @_;
	
	# Setup a server for callbacks
	$SERVER ||= HTTP::Daemon->new(
		Listen    => SOMAXCONN,
		ReuseAddr => 1,
		Reuse     => 1,
		Timeout   => 1,
	);
	
	if ( !$SERVER ) {
		die "Unable to open GENA callback socket: $!\n";
	}

	my $self = bless {
		evt_url => URI->new($url),
		cb_url  => 'http://' . _detect_ip() . ':' . $SERVER->sockport . '/',
		cb      => $cb || sub { die "No callback registered for $url, did you forget to unsubscribe?\n" },
	}, $class;
	
	$self->subscribe() || return;
	
	$SUBS{ $self->{sid} } = $self;
	
	return $self;
}

sub clear_callback {
	my $self = shift;
	
	$self->{cb} = sub { die "No callback registered for " . $self->{evt_url} . "\n" };
}

sub set_callback {
	my ( $self, $cb ) = @_;
	
	$self->{cb} = $cb;
}
		
sub subscribe {
	my $self = shift;
	
	my $uri = $self->{evt_url};
	
	my $req = join "\x0D\x0A", (
		'SUBSCRIBE ' . $uri->path_query . ' HTTP/1.1',
		'Host: ' . $uri->host_port,
		'Callback: <' . $self->{cb_url} . '>',
		'NT: upnp:event',
		'Timeout: Second-300',
		'', '',
	);
	
	my $sock = IO::Socket::INET->new(
		PeerAddr => $uri->host,
		PeerPort => $uri->port,
		Timeout  => TIMEOUT,
	) || die "Unable to connect to $uri: $!\n";
	
	syswrite $sock, $req || die "Unable to write to $uri: $!\n";
	
	sysread $sock, my $res, 4096 || die "Unable to read from $uri: $!\n";
	
	close $sock;
	
	if ( $res =~ m{^HTTP/1.1 200 OK} ) {
		($self->{sid}) = $res =~ /SID:\s+(uuid:.+)\x0D/;
		return 1;
	}
	else {
		my ($status) = $res =~ /(.+)\x0D/;
		$self->{error} = $status;
		return;
	}
}

sub renew {
	my $self = shift;
	
	my $uri = $self->{evt_url};
	
	my $req = join "\x0D\x0A", (
		'SUBSCRIBE ' . $uri->path_query . ' HTTP/1.1',
		'Host: ' . $uri->host_port,
		'SID: ' . $self->{sid},
		'Timeout: Second-300',
		'', '',
	);
	
	my $sock = IO::Socket::INET->new(
		PeerAddr => $uri->host,
		PeerPort => $uri->port,
		Timeout  => TIMEOUT,
	) || die "Unable to connect to $uri: $!\n";
	
	syswrite $sock, $req || die "Unable to write to $uri: $!\n";
	
	sysread $sock, my $res, 4096 || die "Unable to read from $uri: $!\n";
	
	close $sock;
	
	my $sid = $self->{sid};
	if ( $res =~ m{SID:\s+$sid} ) {
		return 1;
	}
	else {
		my ($status) = $res =~ /(.+)\x0D/;
		$self->{error} = $status;
		return;
	}
}

sub unsubscribe {
	my $self = shift;
	
	if ( delete $SUBS{ $self->{sid} } ) {	
		my $uri = $self->{evt_url};
	
		my $req = join "\x0D\x0A", (
			'UNSUBSCRIBE ' . $uri->path_query . ' HTTP/1.1',
			'Host: ' . $uri->host_port,
			'SID: ' . $self->{sid},
			'', '',
		);
	
		my $sock = IO::Socket::INET->new(
			PeerAddr => $uri->host,
			PeerPort => $uri->port,
			Timeout  => TIMEOUT,
		) || die "Unable to connect to $uri: $!\n";
	
		syswrite $sock, $req || die "Unable to write to $uri: $!\n";
	
		sysread $sock, my $res, 4096 || die "Unable to read from $uri: $!\n";
	
		close $sock;
	
		if ( $res =~ m{^HTTP/1.1 200 OK} ) {
			$self->{sid} = 0;
			return 1;
		}
		else {
			my ($status) = $res =~ /(.+)\x0D/;
			$self->{error} = $status;
			return;
		}
	}
}

sub wait {
	my ( $class, $wanted ) = @_;
	
	my $sel = IO::Select->new($SERVER);
	
	while ( $sel->can_read(TIMEOUT) ) {
		my $client = $SERVER->accept || die "Unable to accept(): $!\n";
		
		my $request = $client->get_request;
		
		if ( !$request ) {
			warn "# invalid GENA request: " . $client->reason . "\n";
			syswrite $client, "HTTP/1.1 400 Bad Request\r\n\r\n";
			close $client;
			next;
		}
		
		my $instance = $SUBS{ $request->header('SID') };
		if ( !$instance ) {
			warn "# invalid SID in request: " . dump($request) . "\n";
			syswrite $client, "HTTP/1.1 400 Bad Request\r\n\r\n";
			close $client;
			next;
		}
		
		syswrite $client, "HTTP/1.1 200 OK\r\n\r\n";
		close $client;
		
		# Clean up the property data
		my $props = {};
		#warn dump($request->content);
		my $evt = eval { XMLin( $request->content, ForceArray => [ 'e:property' ] ) };
		if ( $@ ) {
			die "GENA XML parse error: $@\n";
		}

		for my $prop ( @{ $evt->{'e:property'} } ) {
			for my $k ( keys %{$prop} ) {
				$props->{$k} = ref $prop->{$k} eq 'HASH' ? '' : $prop->{$k};
			}
		}
	
		$instance->{cb}->( $request, $props );
		
		# Break out if we've received enough events
		last unless --$wanted;
	}
}

sub _detect_ip {
	# From IPDetect
	my $raddr = '192.43.244.18';
	my $rport = 123;

	my $proto = (getprotobyname('udp'))[2];
	my $pname = (getprotobynumber($proto))[0];
	my $sock  = Symbol::gensym();
	my $iaddr = inet_aton($raddr);
	my $paddr = sockaddr_in($rport, $iaddr);
	socket($sock, PF_INET, SOCK_DGRAM, $proto);
	connect($sock, $paddr);
	my ($port, $address) = sockaddr_in( (getsockname($sock))[0] );
	
	return inet_ntoa($address);
}

1;
