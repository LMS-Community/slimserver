package Slim::Player::Protocols::HTTP;
		  
# $Id$

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

use strict;

use File::Spec::Functions qw(:ALL);
use FileHandle;
use IO::Socket qw(:DEFAULT :crlf);

use base qw(IO::Socket::INET);

BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };

		*IO::Socket::blocking = sub {
			my ($self, $blocking) = @_;

			my $nonblocking = $blocking ? "0" : "1";

			ioctl($self, 0x8004667e, $nonblocking);
		};

	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}
}

use Slim::Display::Display;
use Slim::Music::Info;
use Slim::Utils::Misc;

sub new {
	my $class = shift;
	my $args  = shift;

	unless ($args->{'url'}) {
		Slim::Utils::Misc::msg("No url passed to Slim::Player::Protocols->new() !\n");
		return undef;
	}

	$args->{'infoUrl'} ||= $args->{'url'};
	
	my $self = $class->open($args);

	if (defined($self)) {
		${*$self}{'url'}     = $args->{'url'};
		${*$self}{'infoUrl'} = $args->{'infoUrl'};
		${*$self}{'client'}  = $args->{'client'};
	}

	return $self;
}

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
	);

	# store a IO::Select object in ourself.
	# used for non blocking I/O
	${*$sock}{'_sel'} = IO::Select->new($sock);

	# Manually connect, so we can set blocking.
	# I hate Windows.
	Slim::Utils::Misc::blocking($sock, 0) || do {
		$::d_remotestream && msg("Couldn't set non-blocking on socket!\n");
	};

	my $in_addr = inet_aton($server) || do {

		Slim::Utils::Misc::msg("Couldn't resolve IP address for: $server\n");
		return undef;
	};

	$sock->connect(pack_sockaddr_in($port, $in_addr)) || do {

		my $errnum = 0 + $!;

		if ($errnum != EWOULDBLOCK && $errnum != EINPROGRESS) {
			$::d_remotestream && msg("Can't open socket to [$server:$port]: $errnum: $!\n");
			return undef;
		}

		() = ${*$sock}{'_sel'}->can_write($timeout) or do {

			$::d_remotestream && msgf("Timeout on connect to [$server:$port]: $errnum: $!\n");
			return undef;
		};
	};

	return $sock->request($args);
}

sub request {
	my $self = shift;
	my $args = shift;

	my $url     = $args->{'url'};
	my $infoUrl = $args->{'infoUrl'};
	my $post    = $args->{'post'};
	my $create  = $args->{'create'};

	# Most callers will want create on. Some want it off. So check for the explict 0 value.
	unless (defined $create) {
		$create = 1;
	}

	my $class = ref $self;

	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);
 	my $timeout = $self->timeout();

	my $proxy = Slim::Utils::Prefs::get('webproxy');
	if ($proxy) {
		$path = "http://$server:$port$path";
	}

	my $type = $post ? 'POST' : 'GET';

	# Although the port can be part of the Host: header, some hosts (such
	# as online.wsj.com don't like it, and will infinitely redirect.
	# According to the spec, http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html
	# The port is optional if it's 80, so follow that rule.
	my $host = $port == 80 ? $server : "$server:$port";

	# make the request
	my $request = join($CRLF, (
		"$type $path HTTP/1.0",
		"Host: $host",
		"User-Agent: iTunes/3.0 ($^O; SlimServer $::VERSION)",
		"Accept: */*",
		"Cache-Control: no-cache",
		"Connection: close",
		"Icy-MetaData:1" . $CRLF,
	));
	
	if (defined($user) && defined($password)) {
		$request .= "Authorization: Basic " . MIME::Base64::encode_base64($user . ":" . $password,'') . $CRLF;
	}

	# Send additional information if we're POSTing
	if ($post) {

		$request .= "Content-Type: application/x-www-form-urlencoded$CRLF";
		$request .= sprintf("Content-Length: %d$CRLF", length($post));
		$request .= $CRLF . $post . $CRLF;

	} else {

		$request .= $CRLF;
	}

	$::d_remotestream && msg("Request: $request");

	$self->syswrite($request);

	my $response = Slim::Utils::Misc::sysreadline($self, $timeout);

	$::d_remotestream && msg("Response: $response");
	
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
	my $ct    = Slim::Music::Info::typeFromPath($infoUrl, 'mp3');

	${*$self}{'contentType'} = $ct;
	Slim::Music::Info::setContentType($infoUrl, $ct) if $create;

	while(my $header = Slim::Utils::Misc::sysreadline($self, $timeout)) {

		$::d_remotestream && msg("header: " . $header);

		if ($header =~ /^ic[ey]-name:\s*(.+)$CRLF$/i) {

			my $title = $1;

			if ($title && $] > 5.007) {
				$title = Encode::decode('iso-8859-1', $title, Encode::FB_QUIET);
			}

			Slim::Music::Info::setTitle($infoUrl, $title) if $create;

			${*$self}{'title'} = $title;
		}

		if ($header =~ /^icy-br:\s*(.+)\015\012$/i) {
			Slim::Music::Info::setBitrate($infoUrl, $1 * 1000) if $create;
		}
		
		if ($header =~ /^icy-metaint:\s*(.+)$CRLF$/) {
			${*$self}{'metaInterval'} = $1;
			${*$self}{'metaPointer'} = 0;
		}
		
		if ($header =~ /^Location:\s*(.*)$CRLF$/i) {
			$redir = $1;
		}

		if ($header =~ /^Content-Type:\s*(.*)$CRLF$/i) {
			my $contentType = $1;
			
			if ($contentType =~ /text/i) {
				# webservers often lie about playlists.  This will make it guess from the suffix. 
				$contentType = '';
			}
			
			${*$self}{'contentType'} = $contentType;

			Slim::Music::Info::setContentType($infoUrl, $contentType) if $create;
		}
		
		if ($header =~ /^Content-Length:\s*(.*)$CRLF$/i) {

			${*$self}{'contentLength'} = $1;
		}

		if ($header eq $CRLF) { 
			$::d_remotestream && msg("Recieved final blank line...\n");
			last; 
		}
	}

	if ($redir) {
		# Redirect -- maybe recursively?
		$self->close();

		$::d_remotestream && msg("Redirect to: $redir\n");

		my $ds       = Slim::Music::Info::getCurrentDataStore();
		my $oldTrack = $ds->objectForUrl($infoUrl);
		my $oldTitle = $oldTrack->title() if $create;
		
		$self = $class->open({
			'url'     => $redir,
			'infoUrl' => $redir,
			'create'  => $create,
			'post'    => $post,
		});
		
		# if we've opened the redirect, re-use the old title and new content type.
		
		if (defined($self)) {

			if (defined($oldTitle)) { 

				my $newTrack = $ds->objectForUrl($redir);
				my $newTitle = $newTrack->title();

				if (Slim::Music::Info::plainTitle($redir) eq $newTitle) {

					$::d_remotestream && msg("Saving old title: $oldTitle for $redir\n");

					Slim::Music::Info::setTitle($redir, $oldTitle);

				} elsif (Slim::Music::Info::plainTitle($infoUrl) eq Slim::Music::Info::title($infoUrl)) {

					$::d_remotestream && msg("Saving using redirected title for original URL: $oldTitle for $redir\n");
					Slim::Music::Info::setTitle($infoUrl, $newTitle);
				}
			}

			my $redirectedContentType = Slim::Music::Info::contentType($redir);

			$::d_remotestream && msg("Content type ($redirectedContentType) of $infoUrl is being set to the contentType of: $redir\n");

			${*$self}{'contentType'} = $redirectedContentType;
			Slim::Music::Info::setContentType($infoUrl, $redirectedContentType) if $create;
		}
		
		return $self;
	}

	$::d_remotestream && msg("opened stream!\n");

	return $self;
}

# small wrapper to grab the content in a non-blocking fashion.
sub content {
	my $self   = shift;
	my $length = shift || $self->contentLength() || Slim::Web::HTTP::MAXCHUNKSIZE();

        my $content = '';

	while (($self->sysread($content, $length) != 0)) {

		::idleStreams();
	}

	return $content;
}

sub sysread {
	my $self = $_[0];
	my $chunkSize = $_[2];

	my $metaInterval = ${*$self}{'metaInterval'};
	my $metaPointer  = ${*$self}{'metaPointer'};
 	my $timeout      = $self->timeout();

	if ($metaInterval && ($metaPointer + $chunkSize) > $metaInterval) {

		$chunkSize = $metaInterval - $metaPointer;
		$::d_source && msg("reduced chunksize to $chunkSize for metadata\n");
	}

	unless (${*$self}{'_sel'}->can_read($timeout)) {
		Slim::Utils::Misc::bt("Couldn't read - hit timeout: $timeout!\n");
		return;
	}

	my $readLength = CORE::sysread($self, $_[1], $chunkSize, length($_[1]));

	if ($metaInterval && $readLength) {

		$metaPointer += $readLength;
		${*$self}{'metaPointer'} = $metaPointer;

		# handle instream metadata for shoutcast/icecast
		if ($metaPointer == $metaInterval) {

			$self->readMetaData();
			${*$self}{'metaPointer'} = 0;

		} elsif ($metaPointer > $metaInterval) {

			msg("Problem: the shoutcast metadata overshot the interval.\n");
		}	
	}

	return $readLength;
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

sub readMetaData {
	my $self = shift;
	my $client = ${*$self}{'client'};

	my $metadataSize = 0;
	my $byteRead = 0;

	while ($byteRead == 0) {

		$byteRead = $self->SUPER::sysread($metadataSize, 1);

		if ($!) {
			if ($! ne "Unknown error" && $! != EWOULDBLOCK) {
			 	$::d_remotestream && msg("Metadata byte not read! $!\n");  
			 	return;
			 } else {
			 	$::d_remotestream && msg("Metadata byte not read, trying again: $!\n");  
			 }			 
		}

		$byteRead = defined $byteRead ? $byteRead : 0;
	}
	
	$metadataSize = ord($metadataSize) * 16;
	
	$::d_remotestream && msg("metadata size: $metadataSize\n");

	if ($metadataSize > 0) {
		my $metadata;
		my $metadatapart;
		
		do {
			$metadatapart = '';
			$byteRead = $self->SUPER::sysread($metadatapart, $metadataSize);
			if ($!) {
				if ($! ne "Unknown error" && $! != EWOULDBLOCK) {
					$::d_remotestream && msg("Metadata bytes not read! $!\n");  
					return;
				} else {
					$::d_remotestream && msg("Metadata bytes not read, trying again: $!\n");  
				}			 
			}
			$byteRead = 0 if (!defined($byteRead));
			$metadataSize -= $byteRead;	
			$metadata .= $metadatapart;	
		} while ($metadataSize > 0);			
		
		$::d_remotestream && msg("metadata: $metadata\n");
		
		if ($metadata =~ (/StreamTitle=\'(.*?)\'(;|$)/)) {

			my $url      = ${*$self}{'infoUrl'};

			my $ds       = Slim::Music::Info::getCurrentDataStore();
			my $track    = $ds->objectForUrl($url);

			my $oldTitle = $track->title();
			my $title    = $1;

			if ($title && $] > 5.007) {
				$title = Encode::decode('iso-8859-1', $title, Encode::FB_QUIET);
			}
			
			# capitalize titles that are all lowercase
			if (lc($title) eq $title) {
				$title =~ s/ (
                        (^\w)    #at the beginning of the line
						|        # or
						(\s\w)   #preceded by whitespace
						|        # or
						(-\w)   #preceded by dash
						)
					/\U$1/xg;
			}
			
			if (defined($title) && $title ne '' && $oldTitle ne $title) {

				Slim::Music::Info::setTitle($track, $title);

				${*$self}{'title'} = $title;

				for my $everybuddy ( $client, Slim::Player::Sync::syncedWith($client)) {
					$everybuddy->update();
				}
			}
			
			$::d_remotestream && msg("shoutcast title = $1\n");
		}

		# new song, so reset counters
		$client->songBytes(0);
	}
}

sub title {
	my $self = shift;

	return ${*$self}{'title'};
}

sub contentLength {
	my $self = shift;

	return ${*$self}{'contentLength'};
}

sub contentType {

	my $self = shift;



	return ${*$self}{'contentType'};

}

sub skipForward {
	return 0;
}

sub skipBack {
	return 0;
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
