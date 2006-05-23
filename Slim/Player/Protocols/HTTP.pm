package Slim::Player::Protocols::HTTP;

# $Id$

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

use strict;
use base qw(Slim::Formats::HTTP);

use File::Spec::Functions qw(:ALL);

BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };

	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}
}

use Slim::Music::Info;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

use constant MAXCHUNKSIZE => 32768;

sub new {
	my $class = shift;
	my $args  = shift;

	if (!$args->{'url'}) {
		msg("No url passed to Slim::Player::Protocols::HTTP->new() !\n");
		return undef;
	}

	my $self = $class->open($args);

	if (defined($self)) {
		${*$self}{'url'}     = $args->{'url'};
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

	) or do {

		msg("Couldn't create socket binding to $main::localStreamAddr with timeout: $timeout - $!\n");
		return undef;
	};

	# store a IO::Select object in ourself.
	# used for non blocking I/O
	${*$sock}{'_sel'} = IO::Select->new($sock);

	# Manually connect, so we can set blocking.
	# I hate Windows.
	Slim::Utils::Misc::blocking($sock, 0) || do {
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

	return $sock->request($args);
}

sub request {
	my $self = shift;
	my $args = shift;

	my $url     = $args->{'url'};
	my $infoUrl = $args->{'infoUrl'};
	my $post    = $args->{'post'};
	my $create  = $args->{'create'};

	# Try and use a track object if we have one - otherwise fall back to the URL.
	my $track = $args->{'track'} || $infoUrl;

	# Most callers will want create on. Some want it off. So check for the explict 0 value.
	unless (defined $create) {
		$create = 1;
	}

	my $class = ref $self;

	my $request = $self->requestString($url, $post);
	
	$::d_remotestream && msg("Request: $request");

	$self->syswrite($request);

	my $timeout  = $self->timeout();
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
	my $ct    = Slim::Music::Info::typeFromPath($track, 'mp3');

	${*$self}{'contentType'} = $ct;
	Slim::Music::Info::setContentType($track, $ct) if $create;

	while(my $header = Slim::Utils::Misc::sysreadline($self, $timeout)) {

		$::d_remotestream && msg("header: " . $header);

		if ($header =~ /^ic[ey]-name:\s*(.+)$CRLF$/i) {

			my $title = Slim::Utils::Unicode::utf8decode_guess($1, 'iso-8859-1');

			Slim::Music::Info::setCurrentTitle($infoUrl, $title) if $create;

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
			
			if (($contentType =~ /text/i) &&
				!($contentType =~ /text\/xml/i)) {
				# webservers often lie about playlists.  This will
				# make it guess from the suffix.  (unless text/xml)
				$contentType = '';
			}
			
			${*$self}{'contentType'} = $contentType;

			Slim::Music::Info::setContentType($track, $contentType) if $create;
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

		# Close the existing handle and refcnt-- to avoid keeping the
		# socket in a CLOSE_WAIT state and leaking.
		$self->close();
		undef $self;

		$::d_remotestream && msg("Redirect to: $redir\n");

		my $ds       = Slim::Music::Info::getCurrentDataStore();
		my $oldTrack = $ds->objectForUrl($infoUrl);

		if (!blessed($oldTrack) || !$oldTrack->can('title')) {

			errorMsg("Slim::Player::Protocols::HTTP::request: Couldn't retrieve track object for: [$infoUrl]\n");

			return $self;
		}	

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
	my $length = shift || $self->contentLength() || MAXCHUNKSIZE;

	my $content = '';
	my $bytesread = $self->sysread($content, $length);

	while ((defined($bytesread) && ($bytesread != 0)) || (!defined($bytesread) && $! == EWOULDBLOCK )) {

		eval { ::idleStreams(0.1) };

		$bytesread = $self->sysread($content, $length);
	}

	return $content;
}

sub sysread {
	my $self = $_[0];
	my $chunkSize = $_[2];

	my $metaInterval = ${*$self}{'metaInterval'};
	my $metaPointer  = ${*$self}{'metaPointer'};

	if ($metaInterval && ($metaPointer + $chunkSize) > $metaInterval) {

		$chunkSize = $metaInterval - $metaPointer;
		$::d_source && msg("reduced chunksize to $chunkSize for metadata\n");
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

		${*$self}{'title'} = parseMetadata($client, $self->url, $metadata);

		# new song, so reset counters
		$client->songBytes(0);
	}
}

sub parseMetadata {
	my $client   = shift;
	my $url      = shift;
	my $metadata = shift;

	# XXXX - find out how we're being called - $self->url should be set.
	if (!$url) {

		$url = Slim::Player::Playlist::song(
			$client, Slim::Player::Source::streamingSongIndex($client)
		);
	}

	if ($metadata =~ (/StreamTitle=\'(.*?)\'(;|$)/)) {

		my $newTitle = Slim::Utils::Unicode::utf8decode_guess($1, 'iso-8859-1');

		my $oldTitle = Slim::Music::Info::getCurrentTitle($client, $url) || '';

		# capitalize titles that are all lowercase
		if (lc($newTitle) eq $newTitle) {
			$newTitle =~ s/ (
					  (^\w)    #at the beginning of the line
					  |        # or
					  (\s\w)   #preceded by whitespace
					  |        # or
					  (-\w)   #preceded by dash
					  )
				/\U$1/xg;
		}

		if ($newTitle && ($oldTitle ne $newTitle)) {

			Slim::Music::Info::setCurrentTitle($url, $newTitle);

			for my $everybuddy ( $client, Slim::Player::Sync::syncedWith($client)) {
				$everybuddy->update();
			}
			
			# For some purposes, a change of title is a newsong...
			Slim::Control::Request::notifyFromArray($client, ['playlist', 'newsong', $newTitle]);
		}

		$::d_remotestream && msg("shoutcast title = $newTitle\n");

		return $newTitle;
	}

	return undef;
}

sub canDirectStream {
	my ($classOrSelf, $client, $url) = @_;

	# Check the available types - direct stream MP3, but not Ogg.
	my ($command, $type, $format) = Slim::Player::TranscodingHelper::getConvertCommand($client, $url);

	if (defined $command && $command eq '-' || $format eq 'mp3') {
		return $url;
	}

	return 0;
}

sub sysread {
	my $self = $_[0];
	my $chunkSize = $_[2];

	my $metaInterval = ${*$self}{'metaInterval'};
	my $metaPointer  = ${*$self}{'metaPointer'};

	if ($metaInterval && ($metaPointer + $chunkSize) > $metaInterval) {

		$chunkSize = $metaInterval - $metaPointer;
		$::d_source && msg("reduced chunksize to $chunkSize for metadata\n");
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

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
