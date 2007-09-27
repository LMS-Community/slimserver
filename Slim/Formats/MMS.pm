package Slim::Formats::MMS;

# $Id$

# SqueezeCenter Copyright (c) 2001-2006 Vidur Apparao, Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Formats::MMS

=head1 DESCRIPTION

Extract metadata from MMS/WMA streams.

=head1 METHODS

=cut

use strict;
use base qw(Slim::Formats::RemoteStream);

use Audio::WMA;
use File::Spec::Functions qw(:ALL);
use IO::Socket qw(:DEFAULT :crlf);

use Slim::Formats::Playlists;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

# 
use constant DEFAULT_TYPE => 'wma';

=head2 getTag( $url )

Class constructor for reading metadata from the stream / remote playlist

=cut

sub getTag {
	my $class = shift;
	my $url   = shift || return {};

	my $args  = {
		'url'      => $url,
		'readTags' => 1,
	};

	my $self = $class->SUPER::open($args);

	$self->request($args);

	if ($self->contentType && $self->contentType eq DEFAULT_TYPE) {

		while (sysread($self, my $frame, 1024)) {

			$self->handleBodyFrame($frame);

			if (!${*$self}{"chunk_remaining"}) {
				last;
			}
		}
	}

	$self->parseBody($url);

	return $self;
}

=head2 getFormatForURL()

Returns the type of of stream we are checking (wma)

=cut

sub getFormatForURL {
	my ($classOrSelf, $url) = @_;

	return DEFAULT_TYPE;
}

=head2 randomGUID()

Generate a random GUID.

=cut

sub randomGUID {
	my $self = shift;

	my $guid = '';

	for my $digit (0...31) {

        	if ($digit == 8 || $digit == 12 || $digit == 16 || $digit == 20) {

			$guid .= '-';
		}
		
		$guid .= sprintf('%x', int(rand(16)));
	}

	return $guid;
}

=head2 requestString( $client, $url, )

Generate a MMS request string suitable for sending to a MMS server.

Most WM streaming stations also stream via HTTP. The requestString class
method is invoked by the direct streaming code to obtain a request string to
send to a WM streaming server. We construct a HTTP request string and cross
our fingers. 

=cut

sub requestString {
	my $self = shift;
	my $url  = shift;

	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);

	# Use full path for proxy servers
	my $proxy = preferences('server')->get('webproxy');
	if ( $proxy && $server !~ /(?:localhost|127.0.0.1)/ ) {
		$path = "http://$server:$port$path";
	}

	my $host = $port == 80 ? $server : "$server:$port";

	my @headers = (
		"GET $path HTTP/1.0",
		"Accept: */*",
		"User-Agent: NSPlayer/4.1.0.3856",
		"Host: $host",
		"Pragma: xClientGUID={" . $self->randomGUID() . "}",
	);

	# HTTP interaction with WM radio servers actually involves two separate
	# connections. The first is a request for the ASF header. We use it
	# to determine which stream number to request. Once we have the stream
	# number we can request the stream itself.
	if (defined ${*$self}{'stream_num'}) {

		push @headers, (
			"Pragma: no-cache,rate=1.0000000,stream-time=0,stream-offset=0:0,request-context=2,max-duration=0",
			"Pragma: xPlayStrm=1",
			"Pragma: stream-switch-count=1",
			"Pragma: stream-switch-entry=ffff:" .  ${*$self}{'stream_num'} . ":0",
		);

	} else {

		push @headers, (
			 "Pragma: no-cache,rate=1.0000000,stream-time=0,stream-offset=0:0,request-context=1,max-duration=0", 
			 "Connection: Close",
		);
	}

	# make the request
	return join($CRLF, @headers, $CRLF);
}

sub parseHeaders {
	my $self    = shift;
	my @headers = @_;

	my ($contentType, $mimeType, $length, $body);

	my $log = logger('player.streaming.remote');

	foreach my $header (@headers) {

		$header =~ s/[\r\n]+$//;

		$log->info("Header: $header");

		if ($header =~ /^Content-Type:\s*(.*)/i) {
			$mimeType = $1;
		}

		if ($header =~ /^Content-Length:\s*(.*)/i) {
			$length = $1;
		}
	}

	if (($mimeType eq "application/octet-stream") ||
		($mimeType eq "application/x-mms-framed") ||
		($mimeType eq "application/vnd.ms.wms-hdr.asfv1")) {

		$log->info("It looks like a WMA file");

		$contentType = 'wma';

	} else {

		# Assume (and this may not be correct) that anything else
		# is an asx redirector.

		$log->info("It looks like an ASX redirector");

		$contentType = 'asx';
	}

	# If we don't yet have the stream number for this URL, ask
	# for the header first.
	if (!defined ${*$self}{'stream_num'}) {

		$body = 1;
		
		# If the length of the ASF header isn't specified, then
		# ask for say 30K...most headers will be signficantly smaller.
		if (!$length) {
			$length = 30 * 1024;
		}

		# XXX - why is this a global?
		${*$self}{"chunk_remaining"} = 0;
		${*$self}{"header_length"}   = 0;
		${*$self}{"bytes_received"}  = 0;
	}

	#
	${*$self}{'contentType'} = $contentType;

	return (undef, undef, 0, '', $contentType, $length, $body);
}

sub handleBodyFrame {
	my $self  = shift;
	my $frame = shift;

	#
	my $remaining = length($frame);
	my $position  = 0;

	while ($remaining) {

		if (!${*$self}{"chunk_remaining"}) {

			my $chunkType = unpack('v', substr($frame, $position, 2));

			if ($chunkType != 0x4824) {
				return 1;
			}

			my $chunkLength = unpack('v', substr($frame, $position+2, 2));

			$position  += 12;
			$remaining -= 12;

			${*$self}{"chunk_remaining"} = $chunkLength - 8;
		}

		my $size = ${*$self}{"chunk_remaining"} || 0;

		if ($size >= $remaining) {
			$size = $remaining;
		}

		#
		${*$self}{"directBody"} .= substr($frame, $position, $size);

		$position  += $size;
		$remaining -= $size;

		${*$self}{"chunk_remaining"} -= $size;
		${*$self}{"bytes_received"}  += $size;
	}

	if (!${*$self}{"header_length"} && ${*$self}{"bytes_received"} > 24) {

		# The extra 50 bytes is the header of the data atom
		${*$self}{"header_length"} = unpack('V', substr(${*$self}{"directBody"}, 16, 8) ) + 50;
	}

	#
	if (${*$self}{"header_length"} && ${*$self}{"bytes_received"} >= ${*$self}{"header_length"}) {

		return 1;
	}

	return 0;
}

sub directBody {
	my $self = shift;

	return ${*$self}{"directBody"};
}

sub parseBody {
	my ($self, $url) = @_;

	my $io = IO::String->new($self->directBody);

	if ($self->contentType eq 'wma') {

		my $wma = eval {

			local $^W = 0;

			Audio::WMA->new($io)
		};

		if (!$wma || $@) {

			logError("Couldn't create an Audio::WMA object from stream: [$@]");

			return;
		}

		my $tags  = $wma->tags;

		my $title = $tags->{'TITLE'} || $tags->{'DESCRIPTION'} || $tags->{'AUTHOR'};

		${*$self}{'title'}   = $title;
		${*$self}{'bitrate'} = $wma->info('bitrate');

	} else {

		return Slim::Formats::Playlists->parseList($url, $io, undef, $self->contentType);
	}
}

1;

__END__
