package Slim::Formats::RemoteStream;
		  
# $Id$

# SlimServer Copyright (c) 2001-2005 Slim Devices Inc.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License, version 2.  

# This is a base class for remote stream formats to pull their metadata.

use strict;
use base qw(IO::Socket::INET);

use IO::Socket qw(:DEFAULT :crlf);
use IO::Select;

use Slim::Music::Info;
use Slim::Utils::Errno;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Prefs;
use Slim::Utils::Unicode;

use constant MAXCHUNKSIZE => 32768;

sub open {
	my $class = shift;
	my $args  = shift;

	my $url   = $args->{'url'};

	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);

	if (!$server || !$port) {

		$::d_remotestream && msg("Couldn't find server or port in url: [$url]\n");
		return;
	}

	my $timeout = $args->{'timeout'} || Slim::Utils::Prefs::get('remotestreamtimeout');
	my $proxy   = Slim::Utils::Prefs::get('webproxy');

	my $peeraddr = "$server:$port";

	# Don't proxy for localhost requests.
	if ($proxy && $server ne 'localhost' && $server ne '127.0.0.1') {

		$peeraddr = $proxy;
		($server, $port) = split /:/, $proxy;
		$::d_remotestream && msg("Opening connection using proxy $proxy\n");
	}

	$::d_remotestream && msg("Opening connection to $url: [$server on port $port with path $path with timeout $timeout]\n");
		
	my $sock = $class->SUPER::new(
		LocalAddr => $main::localStreamAddr,
		Timeout	  => $timeout,

	) or do {

		msg("Couldn't create socket binding to $main::localStreamAddr with timeout: $timeout - $!\n");
		return undef;
	};

	# store a IO::Select object in ourself.
	# used for non blocking I/O
	${*$sock}{'_sel'} = IO::Select->new($sock);

	# Manually connect, so we can set blocking.
	# I hate Windows.
	Slim::Utils::Network::blocking($sock, 0) || do {
		$::d_remotestream && msg("Couldn't set non-blocking on socket!\n");
	};

	my $in_addr = inet_aton($server) || do {

		msg("Couldn't resolve IP address for: $server\n");
		close $sock;
		return undef;
	};

	$sock->connect(pack_sockaddr_in($port, $in_addr)) || do {

		my $errnum = 0 + $!;

		if ($errnum != EWOULDBLOCK && $errnum != EINPROGRESS) {
			$::d_remotestream && msg("Can't open socket to [$server:$port]: $errnum: $!\n");
			close $sock;
			return undef;
		}

		() = ${*$sock}{'_sel'}->can_write($timeout) or do {

			$::d_remotestream && msgf("Timeout on connect to [$server:$port]: $errnum: $!\n");
			close $sock;
			return undef;
		};
	};

	# When reading metadata, the caller doesn't want to immediately request data.
	if (!$args->{'readTags'}) {

		return $sock->request($args);

	} else {

		return $sock;
	}
}

sub request {
	my $self = shift;
	my $args = shift;

	my $url     = ${*$self}{'url'} = $args->{'url'};
	my $post    = $args->{'post'};

	my $class   = ref $self;
	my $request = $self->requestString($args->{'client'}, $url, $post);
	
	${*$self}{'client'} = $args->{'client'};
	${*$self}{'create'} = $args->{'create'};
	
	$::d_remotestream && msg("Request: \n$request\n");

	$self->syswrite($request);

	my $timeout  = $self->timeout();
	my $response = Slim::Utils::Network::sysreadline($self, $timeout);

	$::d_remotestream && msg("Response: $response\n");

	if (!$response || $response !~ / (\d\d\d)/) {
		$self->close();
		$::d_remotestream && msg("Invalid response code ($response) from remote stream $url\n");
		return undef; 	
	} 

	$response = $1;
	
	if ($response < 200) {
		$::d_remotestream && msg("Invalid response code ($response) from remote stream $url\n");
		$self->close();
		return undef;
	}

	if ($response > 399) {
		$::d_remotestream && msg("Invalid response code ($response) from remote stream $url\n");
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

		$::d_remotestream && msg("Redirect to: $redir\n");

		return $class->open({
			'url'     => $redir,
			'infoUrl' => $self->infoUrl,
			'post'    => $post,
			'create'  => $args->{'create'},
		});
	}

	$::d_remotestream && msg("opened stream!\n");

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
 
	if ($::d_remotestream && defined ${*$self}{'url'}) {

		my $class = ref($self);

		msgf("%s - in DESTROY\n", $class);
		msgf("%s About to close socket to: [%s]\n", $class, ${*$self}{'url'});
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
