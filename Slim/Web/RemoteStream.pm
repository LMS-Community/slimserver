package Slim::Web::RemoteStream;

# $Id: RemoteStream.pm,v 1.2 2003/07/24 23:14:04 dean Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use FileHandle;
use IO::Socket qw(:DEFAULT :crlf);
use IO::Select;

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
	
	$::d_remotestream && msg("Opening connection to $url: [$server on port $port with path $path]\n");
	
   	my $sock = IO::Socket::INET->new(PeerAddr => "$server:$port",
 					LocalAddr => $main::localStreamAddr,
 					 Timeout  => 10);

	if (!$sock)	{
		my $errnum = 0 + $!;
 		$::d_remotestream && msg("Can't open socket to [$server:$port]: $errnum: $!\n");
		return undef;
	}

	$sock->autoflush(1);

	# make the request
	my $request =   "GET $path HTTP/1.0" . $CRLF . 
					"Host: " . $server . ":" . $port . $CRLF .
#					"User-Agent: Slim Server/" . $::VERSION . " (" . $^O . ")" . $CRLF .
					"User-Agent: iTunes/3.0 (" . $^O . "; SlimServer " . $::VERSION . ")" . $CRLF .
					"Accept: */*" . $CRLF .
					"Cache-Control: no-cache" . $CRLF .
					"Connection: close" . $CRLF .
					"Icy-MetaData:1" . $CRLF;
	
	if (defined($user) && defined($password)) {
		$request .= "Authorization: Basic " . MIME::Base64::encode_base64($user . ":" . $password,'') . $CRLF;
	}

	$request .=  $CRLF;

	$::d_remotestream && msg("Request: $request");

	print $sock $request;

	my $response = <$sock>;

	$::d_remotestream && msg("Response: $response");
	
	if (!$response || $response !~ / (\d\d\d)/) {
		close $sock;
		$::d_remotestream && msg("Invalid response code ($response) from remote stream $url\n");
		return undef; 	
	} 
	
	$response = $1;
	
	if ($response < 200) {
		$::d_remotestream && msg("Invalid response code ($response) from remote stream $url\n");
		close $sock;
		return undef;
	}

	if ($response > 399) {
		$::d_remotestream && msg("Invalid response code ($response) from remote stream $url\n");
		close $sock;
		return undef;
	}

	my $redir = '';
	Slim::Music::Info::setContentType($url,Slim::Music::Info::typeFromPath($url, 'mp3'));
	while(<$sock>) {
		$::d_remotestream && msg("header: " . $_);
		if (/^icy-name:\s*(.+)\015\012$/i) {
			Slim::Music::Info::setTitle($url, $1);
		}
		
		if (/^icy-metaint:\s*(.+)\015\012$/) {
			if ($client) {
				$client->shoutMetaInterval($1);
			}
		}
		
		if (/^Location:\s*(.*)\015\012$/i) {
			$redir = $1;
		}

		if (/^Content-Type:\s*(.*)\015\012$/i) {
			my $contenttype = $1;
			
			if ($contenttype =~ /text/i) {
				# webservers often lie about playlists.  This will make it guess from the suffix. 
				$contenttype = '';
			}
			
			Slim::Music::Info::setContentType($url,$contenttype);
		}
		
		if ($_ eq $CRLF) { 
			$::d_remotestream && msg("Recieved final blank line...\n");
			last; 
		}
	}

	if ($redir) {
		# Redirect -- maybe recursively?
		$sock->close;

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
	$client->mp3filehandle()->read($metadataSize, 1);
	$metadataSize = ord($metadataSize) * 16;
		
	if ($metadataSize > 0) {
		my $metadata;
		
		$client->mp3filehandle()->read($metadata, $metadataSize);

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
				foreach my $everybuddy ( $client, Slim::Player::Playlist::syncedWith($client)) {
					Slim::Display::Animation::killAnimation($everybuddy);
				}
			}
			
			$::d_remotestream && msg("shoutcast title = $1\n");
		}

		# new song, so reset counters
		$client->songpos(0);
		$client->htmlstatusvalid(0);
		
	}
}

1;
__END__
