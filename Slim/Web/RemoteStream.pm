package Slim::Web::RemoteStream;

# $Id: RemoteStream.pm,v 1.26 2004/08/03 17:29:22 vidur Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use FileHandle;
use IO::Socket qw(:DEFAULT :crlf);

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

# Big TODO: don't block! - Working on it

#$::d_remotestream = 1;

# make a request to a remote shout/icecast server
# 2001-10-25 ERL Added (recursive) redirection
sub openRemoteStream {
	my $url = shift;
	my $client = shift;
	
	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);

 	my $timeout = Slim::Utils::Prefs::get('remotestreamtimeout');
	my $proxy = Slim::Utils::Prefs::get('webproxy');

	my $peeraddr = "$server:$port";
	if ($proxy) {
	    $peeraddr = $proxy;
	    $path = "http://$server:$port$path";
	}
	
	$::d_remotestream && msg("Opening connection to $url: [$server on port $port with path $path with timeout $timeout]\n");
	
   	my $sock = IO::Socket::INET->new(

		PeerAddr  => $peeraddr,
 		LocalAddr => $main::localStreamAddr,
 		Timeout   => $timeout,

	) || do {

		my $errnum = 0 + $!;
 		$::d_remotestream && msg("Can't open socket to [$server:$port]: $errnum: $!\n");

		return undef;
	};

	$sock->autoflush(1);

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

	syswrite($sock, $request);

	my $response = Slim::Utils::Misc::sysreadline($sock, $timeout);

	$::d_remotestream && msg("Response: $response");
	
	if (!$response || $response !~ / (\d\d\d)/) {
		$sock->close();
		$::d_remotestream && msg("Invalid response code ($response) from remote stream $url\n");
		return undef; 	
	} 
	
	$response = $1;
	
	if ($response < 200) {
		$::d_remotestream && msg("Invalid response code ($response) from remote stream $url\n");
		$sock->close();
		return undef;
	}

	if ($response > 399) {
		$::d_remotestream && msg("Invalid response code ($response) from remote stream $url\n");
		$sock->close();
		return undef;
	}

	my $redir = '';
	Slim::Music::Info::setContentType($url,Slim::Music::Info::typeFromPath($url, 'mp3'));
	while(my $header = Slim::Utils::Misc::sysreadline($sock, $timeout)) {

		$::d_remotestream && msg("header: " . $header);
		if ($header =~ /^ic[ey]-name:\s*(.+)$CRLF$/i) {
			Slim::Music::Info::setTitle($url, $1);
		}

		if ($header =~ /^icy-br:\s*(.+)\015\012$/i) {
			Slim::Music::Info::setBitrate($url, $1 * 1000);
		}
		
		if ($header =~ /^icy-metaint:\s*(.+)$CRLF$/) {
			if ($client) {
				$client->shoutMetaInterval($1);
			}
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
			
			Slim::Music::Info::setContentType($url,$contenttype);
		}
		
		if ($header eq $CRLF) { 
			$::d_remotestream && msg("Recieved final blank line...\n");
			last; 
		}
	}

	if ($redir) {
		# Redirect -- maybe recursively?
		$sock->close();

		$::d_remotestream && msg("Redirect to: $redir\n");
		
		my $oldtitle = Slim::Music::Info::title($url);
		
		$sock = openRemoteStream($redir, $client);
		
		# if we've opened the redirect, re-use the old title and new content type.
		
		if (defined($sock)) {
			
			if (defined($oldtitle) && (Slim::Music::Info::plainTitle($redir) eq Slim::Music::Info::title($redir))) {
				$::d_remotestream && msg("Saving old title: $oldtitle for $redir\n");
				Slim::Music::Info::setTitle($redir, $oldtitle);
			}

			my $redirectedcontenttype = Slim::Music::Info::contentType($redir);
			$::d_remotestream && msg("Content type ($redirectedcontenttype) of $url is being set to the content type of the redir: $redir\n");
			Slim::Music::Info::setContentType($url,$redirectedcontenttype);
		}
		
		return $sock;
	}

	$::d_remotestream && msg("opened stream!\n");

	return $sock;
}

#
# read instream metadata for shoutcast/icecast
#
sub readMetaData {
	my $client = shift;

	my $metadataSize = 0;
	my $handle = $client->audioFilehandle();

	my $byteRead = 0;
		
	while ($byteRead == 0)
	{
		$byteRead = $handle->sysread($metadataSize, 1);
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
			$byteRead = $handle->sysread($metadatapart, $metadataSize);
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
			my $url = Slim::Player::Playlist::song($client);
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

1;
__END__
