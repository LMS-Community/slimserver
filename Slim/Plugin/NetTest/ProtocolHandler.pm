package Slim::Plugin::NetTest::ProtocolHandler;

use strict;

use base qw(IO::Handle);

use Slim::Utils::Errno;

use constant MAX_CHUNK_SIZE => 16*1024;    # size of test chunk response
use constant WAKE_TIME      => 0.02;       # time to take off select for if going faster than desired rate
use constant AVERAGE_INT    => 1.0;        # interval to average rate calculation over

# accepts urls of the form: teststream://test?rate=X, where X is desired test rate in Kbps
# if rate is not specified or above maxRate for player then defaults to maxRate

sub isAudio { 1 }

sub isRemote { 0 }

sub contentType { 'pcm' }

sub formatOverride { 'test' }

sub new {
	my $class = shift;
	my $args = shift;

	my $self = $class->SUPER::new;

	my $url    = $args->{'url'};
	my $client = $args->{'client'};

	my $testrate;
	my $chunksize;

	if ($url =~ /teststream:\/\/test\?rate=(.*)/) {
		$testrate = $1 * 1000;
	}

	my $maxRate = Slim::Plugin::NetTest::Plugin->maxRate($client);

	if (!$testrate || $testrate > $maxRate) {
		$testrate = $maxRate;
	}

	$chunksize = $testrate / 8 * WAKE_TIME;

	if ($chunksize > MAX_CHUNK_SIZE) {
		$chunksize = MAX_CHUNK_SIZE;
	}

	${*$self}{'testrate'} = $testrate;
	${*$self}{'chunk'}    = chr(0x00) x $chunksize;
	${*$self}{'sent'}     = 0;
	${*$self}{'res'}      = [ { 'time' => Time::HiRes::time(), 'sent' => 0 } ];
	${*$self}{'rate'}     = 0;
	${*$self}{'client'}   = $client;

	return $self;
}

sub sysread {
	my $self = $_[0];

	my $now = Time::HiRes::time();
	my $first = $now - AVERAGE_INT;
	my $res = ${*$self}{'res'};

	# remove result entries before the averaging period
	while (scalar @$res > 1 && $res->[0]->{'time'} < $first) {
		shift @$res;
	}

	# add latest entry to results
	push @$res, { 'time' => $now, 'sent' => ${*$self}{'sent'} };

	# compute rate averaged over first to last entry in result array
	${*$self}{'rate'} = 8 * (${*$self}{'sent'} - $res->[0]->{'sent'}) / ($now - $res->[0]->{'time'});

	if (${*$self}{'rate'} > ${*$self}{'testrate'}) {
		# take ourselves off select and try again later (note this is much faster than default tryStreamingLater timer)
		# returning EINTR avoids processing for EWOULDBLOCK and takes the socket off select
		${*$self}{'timer'} = Slim::Utils::Timers::setTimer(${*$self}{'client'}, $now + WAKE_TIME,
														   \&Slim::Web::HTTP::tryStreamingLater,(${*$self}{'client'}->streamingsocket));
		$! = EINTR;
		return undef;
	}

	# send a new chunk
	$_[1] = ${*$self}{'chunk'};
	${*$self}{'sent'} += length $_[1];

	return length $_[1];
}

sub currentrate { 
	my $self = shift;

	return ${*$self}{'rate'};
}

sub testrate { 
	my $self = shift;

	return ${*$self}{'testrate'};
}

sub getMetadataFor {
	my ($self, $client, $url) = @_;

	my $fd = $client->controller()->songStreamController() ? $client->controller()->songStreamController()->streamHandler() : undef;

	if ($fd && $fd->isa(__PACKAGE__)) {
		return {
			title  => Slim::Utils::Strings::string('PLUGIN_NETTEST'),
			artist => sprintf "%1.3f Mbps", ($fd->currentrate / 1_000_000),
		};
	}

	return {};
}

sub stash {
	my $self = shift;

	if (@_) {
		${*$self}{'stash'} = shift;
	}

	return ${*$self}{'stash'};
}

sub DESTROY {
	my $self = shift;

	Slim::Utils::Timers::killSpecific(${*$self}{'timer'});
	$self->SUPER::DESTROY();
}

1;
