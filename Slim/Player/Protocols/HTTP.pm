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

use vars qw(@ISA);

@ISA = qw(IO::Socket::INET);

BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };
	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}
}

use Slim::Display::Display;
use Slim::Utils::Misc;

sub new {
	my $class = shift;
	my $url = shift;
	my $client = shift;
	my $infoUrl = shift || $url;

	my $self = $class->open($url, $infoUrl);

	if (defined($self)) {
		${*$self}{'url'} = $url;
		${*$self}{'infoUrl'} = $infoUrl;
		${*$self}{'client'} = $client;
	}

	return $self;
}

sub open {
	my $class = shift;
	my $url = shift;
	my $infoUrl = shift;

	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);

	my $timeout = Slim::Utils::Prefs::get('remotestreamtimeout');
	my $proxy = Slim::Utils::Prefs::get('webproxy');

	my $peeraddr = "$server:$port";
	if ($proxy) {
		$peeraddr = $proxy;
		$::d_remotestream && msg("Opening connection using proxy $proxy\n");
	}

	$::d_remotestream && msg("Opening connection to $url: [$server on port $port with path $path with timeout $timeout]\n");

	my $sock = $class->SUPER::new(

		PeerAddr  => $peeraddr,
		LocalAddr => $main::localStreamAddr,
		Timeout	  => $timeout,

	) || do {

		my $errnum = 0 + $!;
		$::d_remotestream && msg("Can't open socket to [$server:$port]: $errnum: $!\n");

		return undef;
	};

	$sock->autoflush(1);

	return $sock->request($url, $infoUrl);
}

sub request {
	my $self = shift;
	my $url = shift;
	my $infoUrl = shift;
	my $class = ref $self;

	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);
 	my $timeout = Slim::Utils::Prefs::get('remotestreamtimeout');

	my $proxy = Slim::Utils::Prefs::get('webproxy');
	if ($proxy) {
		$path = "http://$server:$port$path";
	}

	# make the request
	my $request = join($CRLF, (
		"GET $path HTTP/1.0",
		"Host: $server:$port",
#		"User-Agent: SlimServer/$::VERSION ($^O)",
		"User-Agent: iTunes/3.0 ($^O; SlimServer $::VERSION)",
		"Accept: */*",
		"Cache-Control: no-cache",
		"Connection: close",
		"Icy-MetaData:1" . $CRLF,
	));
	
	if (defined($user) && defined($password)) {
		$request .= "Authorization: Basic " . MIME::Base64::encode_base64($user . ":" . $password,'') . $CRLF;
	}

	$request .= $CRLF;

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
	my $ct = Slim::Music::Info::typeFromPath($infoUrl, 'mp3');
	Slim::Music::Info::setContentType($infoUrl, $ct);
	while(my $header = Slim::Utils::Misc::sysreadline($self, $timeout)) {

		$::d_remotestream && msg("header: " . $header);
		if ($header =~ /^ic[ey]-name:\s*(.+)$CRLF$/i) {
			Slim::Music::Info::setTitle($infoUrl, $1);
			${*$self}{'title'} = $1;
		}

		if ($header =~ /^icy-br:\s*(.+)\015\012$/i) {
			Slim::Music::Info::setBitrate($infoUrl, $1 * 1000);
		}
		
		if ($header =~ /^icy-metaint:\s*(.+)$CRLF$/) {
			${*$self}{'metaInterval'} = $1;
			${*$self}{'metaPointer'} = 0;
		}
		
		if ($header =~ /^Location:\s*(.*)$CRLF$/i) {
			$redir = $1;
		}

		if ($header =~ /^Content-Type:\s*(.*)$CRLF$/i) {
			my $contenttype = $1;
			
			if ($contenttype =~ /text/i) {
				# webservers often lie about playlists.  This will make it guess from the suffix. 
				$contenttype = '';
			}
			
			Slim::Music::Info::setContentType($infoUrl,$contenttype);
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
		
		my $oldtitle = Slim::Music::Info::title($infoUrl);
		
		$self = $class->open($redir, $redir);
		
		# if we've opened the redirect, re-use the old title and new content type.
		
		if (defined($self)) {
			if (defined($oldtitle)) { 
				my $newtitle = Slim::Music::Info::title($redir);
				if (Slim::Music::Info::plainTitle($redir) eq $newtitle) {
					$::d_remotestream && msg("Saving old title: $oldtitle for $redir\n");
					Slim::Music::Info::setTitle($redir, $oldtitle);
				} elsif (Slim::Music::Info::plainTitle($infoUrl) eq Slim::Music::Info::title($infoUrl)) {
					$::d_remotestream && msg("Saving using redirected title for original URL: $oldtitle for $redir\n");
					Slim::Music::Info::setTitle($infoUrl, $newtitle);
				}
			}

			my $redirectedcontenttype = Slim::Music::Info::contentType($redir);
			$::d_remotestream && msg("Content type ($redirectedcontenttype) of $infoUrl is being set to the content type of the redir: $redir\n");
			Slim::Music::Info::setContentType($infoUrl,$redirectedcontenttype);
		}
		
		return $self;
	}

	$::d_remotestream && msg("opened stream!\n");

	return $self;
}

sub sysread {
	my $self = $_[0];
	my $chunksize = $_[2];
	my $metaInterval = ${*$self}{'metaInterval'};
	my $metaPointer = ${*$self}{'metaPointer'};

	if ($metaInterval &&
		($metaPointer + $chunksize) > $metaInterval) {
		$chunksize = $metaInterval - $metaPointer;
		$::d_source && msg("reduced chunksize to $chunksize for metadata\n");
	}

	my $readlen = $self->SUPER::sysread($_[1], $chunksize);

	if ($metaInterval && $readlen) {
		$metaPointer += $readlen;
		${*$self}{'metaPointer'} = $metaPointer;

		# handle instream metadata for shoutcast/icecast
		if ($metaPointer == $metaInterval) {
			$self->readMetaData();
			${*$self}{'metaPointer'} = 0;
		}
		elsif ($metaPointer > $metaInterval) {
			msg("Problem: the shoutcast metadata overshot the interval.\n");
		}	
	}

	return $readlen;
}

sub readMetaData {
	my $self = shift;
	my $client = ${*$self}{'client'};

	my $metadataSize = 0;
	my $byteRead = 0;


	while ($byteRead == 0)
	{
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
			my $url = ${*$self}{'infoUrl'};
			my $oldtitle = Slim::Music::Info::title($url);
			my $title = $1;
			
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
			
			if (defined($title) && $title ne '' && $oldtitle ne $title) {
				Slim::Music::Info::setTitle($url, $title);
				${*$self}{'title'} = $title;
				foreach my $everybuddy ( $client, Slim::Player::Sync::syncedWith($client)) {
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
