package Slim::Formats::RemoteStream;
		  
# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License, version 2.  

# This is a base class for remote stream formats to pull their metadata.

use strict;
use base qw(IO::Socket::INET);

# Avoid IO::Socket's import method
sub import {}

use IO::Socket qw(
	:crlf
	pack_sockaddr_in
	inet_aton
);
use IO::Select;

use Slim::Music::Info;
use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Prefs;

use constant MAXCHUNKSIZE => 32768;

my $log = logger('player.streaming.remote');

my $prefs = preferences('server');

sub isRemote {
	return 1;
}

sub open {
	my $class = shift;
	my $args  = shift;

	my $url   = $args->{'url'};

	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);

	if (!$server || !$port) {

		logError("Couldn't find server or port in url: [$url]");
		return;
	}

	my $timeout = $args->{'timeout'} || $prefs->get('remotestreamtimeout');
	my $proxy   = $prefs->get('webproxy');

	my $peeraddr = "$server:$port";

	# Don't proxy for localhost requests.
	if ($proxy && $server ne 'localhost' && $server ne '127.0.0.1') {

		$peeraddr = $proxy;
		($server, $port) = split /:/, $proxy;

		main::INFOLOG && $log->info("Opening connection using proxy $proxy");
	}

	main::INFOLOG && $log->is_info && $log->info("Opening connection to $url: [$server on port $port with path $path with timeout $timeout]");

	my $sock = $class->SUPER::new(
		LocalAddr => $main::localStreamAddr,
		Timeout	  => $timeout,

	) or do {

		logError("Couldn't create socket binding to $main::localStreamAddr with timeout: $timeout - $!");
		return undef;
	};

	# store a IO::Select object in ourself.
	# used for non blocking I/O
	${*$sock}{'_sel'} = IO::Select->new($sock);

	# Manually connect, so we can set blocking.
	# I hate Windows.
	Slim::Utils::Network::blocking($sock, 0) || do {

		$log->warn("Warning: Couldn't set non-blocking on socket!");
	};

	my $in_addr = inet_aton($server) || do {

		logError("Couldn't resolve IP address for: $server");
		close $sock;
		return undef;
	};

	$sock->connect(pack_sockaddr_in($port, $in_addr)) || do {

		my $errnum = 0 + $!;

		if ($errnum != EWOULDBLOCK && $errnum != EINPROGRESS && $errnum != EINTR) {

			$log->error("Can't open socket to [$server:$port]: $errnum: $!");

			close $sock;
			return undef;
		}

		() = ${*$sock}{'_sel'}->can_write($timeout) or do {

			$log->error("Timeout on connect to [$server:$port]: $errnum: $!");

			close $sock;
			return undef;
		};
	};
	
	${*$sock}{'song'} = $args->{'song'};

	return $sock->request($args);

}

sub request {
	my $self = shift;
	my $args = shift;

	my $url     = ${*$self}{'url'} = $args->{'url'};
	my $post    = $args->{'post'};

	my $class   = ref $self;
	my $request = $self->requestString($args->{'client'}, $url, $post, $args->{'song'} ? $args->{'song'}->seekdata() : undef);
	
	${*$self}{'client'}  = $args->{'client'};
	${*$self}{'bitrate'} = $args->{'bitrate'};
	${*$self}{'infoUrl'} = $args->{'infoUrl'};
	
	main::INFOLOG && $log->info("Request: $request");

	$self->syswrite($request);

	my $timeout  = $self->timeout();
	my $response = Slim::Utils::Network::sysreadline($self, $timeout);

	main::INFOLOG && $log->info("Response: $response");

	if (!$response || $response !~ / (\d\d\d)/) {

		$log->warn("Warning: Invalid response code ($response) from remote stream $url");

		$self->close();

		return undef; 	
	} 

	$response = $1;
	
	if ($response < 200 || $response > 399) {

		$log->warn("Warning: Invalid response code ($response) from remote stream $url");

		$self->close();

		return undef;
	}

	my $redir = '';
	my $ct    = Slim::Music::Info::typeFromPath($url, 'mp3');

	# Set the content type for this object.
	${*$self}{'contentType'} = $ct;

	my @headers = ();

	while(my $header = Slim::Utils::Network::sysreadline($self, $timeout)) {

		# Stop at the end of the headers
		if ($header =~ /^[\r\n]+$/) {
			last;
		}

		push @headers, $header;
	}

	$self->parseHeaders(@headers);

	if (my $redir = $self->redirect) {
		# Redirect -- maybe recursively?

		# Close the existing handle and refcnt-- to avoid keeping the
		# socket in a CLOSE_WAIT state and leaking.
		$self->close();

		main::INFOLOG && $log->info("Redirect to: $redir");

		return $class->open({
			'url'     => $redir,
			'song'    => $args->{'song'},
			'infoUrl' => $self->infoUrl,
			'post'    => $post,
			'create'  => $args->{'create'},
			'client'  => $args->{'client'},
		});
	}

	main::INFOLOG && $log->info("Opened stream!");

	return $self;
}

# small wrapper to grab the content and give time to the players.
# This should really use the async http code.
sub content {
	my $self   = shift;
	my $length = shift || $self->contentLength() || MAXCHUNKSIZE();

	my $content = '';
	my $bytesread = $self->sysread($content, $length);

	while ((defined($bytesread) && ($bytesread != 0)) || (!defined($bytesread) && $! == EWOULDBLOCK )) {

		main::idleStreams(0.1);

		$bytesread = $self->sysread(my $buf, $length);

		if ($bytesread) {
			$content .= $buf;
		}
	}

	return $content;
}

sub syswrite {
	my $self = $_[0];
	my $data = $_[1];

	my $length = length $data;

	while (length $data > 0) {

		return unless ${*$self}{'_sel'}->can_write(0.05);

		local $SIG{'PIPE'} = 'IGNORE';

		my $wc = CORE::syswrite($self, $data, length($data));

		if (defined $wc) {

			substr($data, 0, $wc) = '';

		} elsif ($! == EWOULDBLOCK) {

			return;
		}
	}

	return $length;
}

sub url {
	my $self = shift;

	return ${*$self}{'url'};
}

sub infoUrl {
	my $self = shift;

	return ${*$self}{'infoUrl'} || ${*$self}{'url'};
}

sub title {
	my $self = shift;

	return ${*$self}{'title'};
}

sub bitrate {
	my $self = shift;

	return ${*$self}{'bitrate'};
}

sub client {
	my $self = shift;

	return ${*$self}{'client'};
}

sub contentLength {
	my $self = shift;

	return ${*$self}{'contentLength'};
}

sub contentType {
	my $self = shift;

	return ${*$self}{'contentType'};
}

sub duration {
	my $self = shift;

	return ${*$self}{'duration'};
}

sub redirect {
	my $self = shift;

	return ${*$self}{'redirect'};
}

sub DESTROY {
	my $self = shift;
 
	if ($log->is_debug && defined ${*$self}{'url'}) {

		my $class = ref($self);

		main::DEBUGLOG && $log->debug(sprintf("%s - in DESTROY", $class));
		main::DEBUGLOG && $log->debug(sprintf("%s About to close socket to: [%s]", $class, ${*$self}{'url'}));
	}

	$self->close;
}

sub close {
	my $self = shift;

	# Remove the reference to ourselves that is the IO::Select handle.
	if (defined $self && defined ${*$self}{'_sel'}) {
		${*$self}{'_sel'}->remove($self);
		${*$self}{'_sel'} = undef;
	}

	$self->SUPER::close;
}

1;

__END__
