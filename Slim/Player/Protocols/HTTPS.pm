package Slim::Player::Protocols::HTTPS;

use base qw(IO::Socket::SSL Slim::Player::Protocols::HTTP);

use Slim::Utils::Errno;
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
		( $prefs->get('insecureHTTPS')
		  ? (SSL_verify_mode => Net::SSLeay::VERIFY_NONE())           # SSL_VERIFY_NONE isn't recognized on some platforms?!?, and 0x00 isn't always "right"
		  : () ),
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

# as we are inheriting from IO::Socket::SSL first, we have to re-implement Slim::Player::Protocols::HTTP->sysread here
sub sysread {
	my $self = $_[0];
	my $chunkSize = $_[2];
	
	# stitch header if any
	if (my $length = ${*$self}{'initialAudioBlockRemaining'}) {
		
		my $chunkLength = $length;
		my $chunkref;
		
		main::DEBUGLOG && $log->debug("getting initial audio block of size $length");
		
		if ($length > $chunkSize || $length < length(${${*$self}{'initialAudioBlockRef'}})) {
			$chunkLength = $length > $chunkSize ? $chunkSize : $length;
			my $chunk = substr(${${*$self}{'initialAudioBlockRef'}}, -$length, $chunkLength);
			$chunkref = \$chunk;
			${*$self}{'initialAudioBlockRemaining'} = ($length - $chunkLength);
		} else {
			${*$self}{'initialAudioBlockRemaining'} = 0;
			$chunkref = ${*$self}{'initialAudioBlockRef'};
		}
	
		$_[1] = $$chunkref;
		return $chunkLength;
	}

	my $metaInterval = ${*$self}{'metaInterval'};
	my $metaPointer  = ${*$self}{'metaPointer'};

	if ($chunkSize && $metaInterval && ($metaPointer + $chunkSize) > $metaInterval && ($metaInterval - $metaPointer) > 0) {

		$chunkSize = $metaInterval - $metaPointer;

		# This is very verbose...
		#$log->debug("Reduced chunksize to $chunkSize for metadata");
	}
	
	my $readLength;
	
	# do not sysread if we are building-up too much processed audio
	if (${*$self}{'audio_buildup'} > $chunkSize) {
		${*$self}{'audio_buildup'} = ${*$self}{'audio_process'}->(${*$self}{'audio_stash'}, $_[1], $chunkSize); 
	} else {	
		$readLength = $self->SUPER::sysread($_[1], $chunkSize);
		$readLength = $self->_parseStreamHeader($_[1], $readLength);
		${*$self}{'audio_buildup'} = ${*$self}{'audio_process'}->(${*$self}{'audio_stash'}, $_[1], $chunkSize) if ${*$self}{'audio_process'}; 
	}	
	
	# use $readLength from socket for meta interval adjustement
	if ($metaInterval && $readLength) {

		$metaPointer += $readLength;
		${*$self}{'metaPointer'} = $metaPointer;

		# handle instream metadata for shoutcast/icecast
		if ($metaPointer == $metaInterval) {

			$self->readMetaData();

			${*$self}{'metaPointer'} = 0;

		} elsif ($metaPointer > $metaInterval) {

			main::DEBUGLOG && $log->debug("The shoutcast metadata overshot the interval.");
		}	
	}
	
	# when not-empty, chose return buffer length over sysread() 
	$readLength = length $_[1] if length $_[1];

	if (main::ISWINDOWS && !$readLength) {
		$! = EWOULDBLOCK;
	}

	return $readLength;
}
	

1;
