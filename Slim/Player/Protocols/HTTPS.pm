package Slim::Player::Protocols::HTTPS;

use base qw(IO::Socket::SSL Slim::Player::Protocols::HTTP);

use List::Util qw(min);

use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = logger('player.streaming.remote');
my $prefs = preferences('server');

sub new {
	my $class = shift;
	my $args  = shift;
	my $url   = $args->{'url'} || '';

	if ($url =~ /^http:/) {
		# only use Slim::Player::Protocols::HTTP methods and we can't just use
		# directly Slim::Player::Protocols::HTTP::new or method resolution will
		# ignore *real* base class and any overloaded one will be missed
		local @ISA = grep { $_ ne 'IO::Socket::SSL' } @ISA;
		return $class->SUPER::new($args);
	}

	# upon redirect, we might be upgraded to HTTPS from the previously downgraded object
	unshift @ISA, 'IO::Socket::SSL' unless grep { $_ eq 'IO::Socket::SSL' } @ISA;
	
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
		( $prefs->get('insecureHTTPS')
		  ? (SSL_verify_mode => Net::SSLeay::VERIFY_NONE())           # SSL_VERIFY_NONE isn't recognized on some platforms?!?, and 0x00 isn't always "right"
		  : () ),
	) or do {
		$log->error("Couldn't create socket binding to $main::localStreamAddr with timeout: $timeout - $!");
		return undef;
	};

	${*$sock}{'client'}  = $args->{'client'};
	${*$sock}{'url'}     = $args->{'url'};
	${*$sock}{'song'}    = $args->{'song'};

	# store a IO::Select object in ourself.
	# used for non blocking I/O
	${*$sock}{'_sel'}    = IO::Select->new($sock);

	return $sock->open($args);
}

sub close {
	my $self = shift;
	$self->SUPER::close;
	# if we are really HTTPS, we also need to call HTTP's close() to let it do cleanup
	# and it will know that it should not call own parent's close()
	$self->Slim::Player::Protocols::HTTP::close if $self->isa('IO::Socket::SSL');
}

# Check whether the current player can stream HTTPS or Url is HTTP
sub canDirectStream {
	my $class = shift;
	my ($client, $url) = @_;

	if ( $client->canHTTPS || $url =~ /^http:/) {
		return $class->SUPER::canDirectStream(@_);
	}

	return 0;
}

# Check whether the current player can stream HTTPS or Url is HTTP
sub canDirectStreamSong {
	my $class = shift;
	my ($client, $song) = @_;

	if ( $client->canHTTPS || $song->streamUrl =~ /^http:/) {
		return $class->SUPER::canDirectStreamSong(@_);
	}

	return 0;
}

sub slimprotoFlags {
	my ($self, $client, $url, $isDirect) = @_;
	# $url might still be HTTP (see new), so need to check that and direct
	return ($isDirect && $url =~ /^https:/) ? 0x20 : 0x00;
}

# we need that call structure to make sure that SUPER calls the
# object's parent, not the package's parent
# see http://modernperlbooks.com/mt/2009/09/when-super-isnt.html
sub _sysread {
	my $self = $_[0];

	# skip what we need until done or EOF	
	if ( ${*$self}{'_skip'} ) {
		my $bytes = $self->SUPER::sysread(my $scratch, min(${*$self}{'_skip'}, 32768));
		return $bytes if defined $bytes && !$bytes;

		# pretend we don't have received anything until we've skipped all
		${*$self}{'_skip'} -= $bytes if $bytes;
		main::INFOLOG && $log->info("Done skipping bytes") unless ${*$self}{'_skip'};

		# we should use EINTR (see S::P::Source) but this is too slow when skipping - will fix in 9.0
		$_[1]= '';
		$! = EWOULDBLOCK;
		return undef;
	}

	my $readLength = $self->SUPER::sysread($_[1], $_[2], $_[3]);

	if (main::ISWINDOWS && !$readLength) {
		$! = EINTR;
	}

	return $readLength;
}

# we need to subclass sysread as HTTPS first inherits from IO::Socket::SSL
sub sysread {
	return Slim::Player::Protocols::HTTP::sysread(@_);
}


1;
