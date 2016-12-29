package Slim::Player::Protocols::HTTPS;

use base qw(IO::Socket::SSL Slim::Player::Protocols::HTTP);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = logger('player.streaming.remote');
my $prefs = preferences('server');

sub new {
	my $class = shift;
	my $args  = shift;
	my $url   = $args->{'url'} || '';

	my ($server, $port, $path) = Slim::Utils::Misc::crackURL($url);

	if (!$server || !$port) {

		logError("Couldn't find server or port in url: [$url]");
		return;
	}

	my $timeout = $args->{'timeout'} || $prefs->get('remotestreamtimeout');

	main::INFOLOG && $log->is_info && $log->info("Opening connection to $url: [$server on port $port with path $path with timeout $timeout]");

	my $sock = $class->SUPER::new(
		Timeout	 => $timeout,
		PeerAddr => $server,
		PeerPort => $port,
		SSL_startHandshake => 1,
		SSL_verify_mode => SSL_VERIFY_NONE
	) or do {

		$log->error("Couldn't create socket binding to $main::localStreamAddr with timeout: $timeout - $!");
		return undef;
	};

	if (defined($sock)) {
		${*$sock}{'client'}  = $args->{'client'};
		${*$sock}{'url'}     = $args->{'url'};
		${*$sock}{'song'}    = $args->{'song'};

		# store a IO::Select object in ourself.
		# used for non blocking I/O
		${*$sock}{'_sel'}    = IO::Select->new($sock);
	}
				
	return $sock->request($args);
}

# Check whether the current player can stream HTTPS or not 
sub canDirectStream {
	my $self = shift;
	my ($client) = @_;
	
	if ( $client->canHTTPS ) {
		return $self->SUPER::canDirectStream(@_);
	}

	return 0;
}

1;