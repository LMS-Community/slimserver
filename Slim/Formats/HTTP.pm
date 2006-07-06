package Slim::Formats::HTTP;

# $Id$

# SlimServer Copyright (c) 2001-2005 Slim Devices Inc.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License, version 2.  

# This is a base class for remote stream formats to pull their metadata.

use strict;
use base qw(Slim::Formats::RemoteStream);

use IO::Socket qw(:crlf);
use MIME::Base64;

use Slim::Utils::Misc;
use Slim::Utils::Unicode;

use constant DEFAULT_TYPE => 'mp3';

# Class constructor for just reading metadata from the stream / remote playlist
sub getTag {
	my $class = shift;
	my $url   = shift || return {};

	my $args  = {
		'url'      => $url,
		'readTags' => 1,
	};

	my $self = $class->SUPER::open($args);

	# We might have redirected - be sure to return that object.
	return $self->request($args);
}

sub getFormatForURL {
	my $class = shift;

	return DEFAULT_TYPE;
}

sub requestString {
	my $self   = shift;
	my $client = shift;
	my $url    = shift;
	my $post   = shift;

	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);
 
	my $proxy = Slim::Utils::Prefs::get('webproxy');

	# Proxy not supported for direct streaming
	if ( !$client->canDirectStream($url) ) {
		if ($proxy && $server ne 'localhost' && $server ne '127.0.0.1') {
			$path = "http://$server:$port$path";
		}
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
		"Accept: */*",
		"Cache-Control: no-cache",
		"User-Agent: " . Slim::Utils::Misc::userAgentString(),
		"Icy-MetaData: 1",
		"Connection: close",
		"Host: $host" . $CRLF
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

	return $request;
}

sub parseHeaders {
	my $self    = shift;
	my @headers = @_;

	for my $header (@headers) {

		$::d_remotestream && msg("header-rs: " . $header);

		if ($header =~ /^ic[ey]-name:\s*(.+)$CRLF$/i) {

			${*$self}{'title'} = Slim::Utils::Unicode::utf8decode_guess($1, 'iso-8859-1');
		}

		if ($header =~ /^icy-br:\s*(.+)$CRLF$/i) {

			${*$self}{'bitrate'} = $1 * 1000;
			Slim::Music::Info::setBitrate( $self->url, ${*$self}{'bitrate'} );
		}
		
		if ($header =~ /^icy-metaint:\s*(.+)$CRLF$/) {

			${*$self}{'metaInterval'} = $1;
			${*$self}{'metaPointer'}  = 0;
		}
		
		if ($header =~ /^Location:\s*(.*)$CRLF$/i) {

			${*$self}{'redirect'} = $1;
		}

		if ($header =~ /^Content-Type:\s*(.*)$CRLF$/i) {

			my $contentType = $1;

			if (($contentType =~ /text/i) && !($contentType =~ /text\/xml/i)) {
				# webservers often lie about playlists.  This will
				# make it guess from the suffix.  (unless text/xml)
				$contentType = '';
			}
			
			${*$self}{'contentType'} = $contentType;
		}
		
		if ($header =~ /^Content-Length:\s*(.*)$CRLF$/i) {

			${*$self}{'contentLength'} = $1;
		}

		if ($header eq $CRLF) { 

			$::d_remotestream && msg("Recieved final blank line...\n");
			last; 
		}
	}
}

1;

__END__
