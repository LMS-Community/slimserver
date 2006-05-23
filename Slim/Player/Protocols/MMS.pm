package Slim::Player::Protocols::MMS;

# $Id$

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

use strict;
use base qw(Slim::Player::Pipeline);

use Audio::WMA;
use File::Spec::Functions qw(:ALL);
use IO::Socket qw(:DEFAULT :crlf);

use Slim::Formats::Playlists;
use Slim::Player::Source;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Misc;

# The following are class variables, since they hold state used during
# the direct streaming process. Currently protocol handlers can serve
# a dual role. An instance of a protocol handler (a socket suclass)
# can be used for server side streaming. Class methods are used to
# help with client side direct streaming. In the future, we may want
# to split the two into different classes - the socket version and the
# protocol parsing version. For now we live with the ugliness of both
# roles in the same package.
our %stream_nums  = ();
our %parser_state = ();

use constant DEFAULT_TYPE => 'wma';

sub new {
	my $class = shift;
	my $args  = shift;

	my $url    = $args->{'url'};
	my $client = $args->{'client'};

	# Set the content type to 'wma' to get the convert command
	my ($command, $type, $format) = Slim::Player::TranscodingHelper::getConvertCommand($client, $url, DEFAULT_TYPE);

	unless (defined($command) && $command ne '-') {

		$::d_remotestream && msg "Couldn't find conversion command for wma\n";

		# XXX - errorOpening should not be in Source!
		Slim::Player::Source::errorOpening($client, $client->string('WMA_NO_CONVERT_CMD'));

		return undef;
	}

	my $maxRate = 0;
	my $quality = 1;

	if (defined($client)) {
		$maxRate = Slim::Utils::Prefs::maxRate($client);
		$quality = $client->prefGet('lameQuality');
	}

	$command = Slim::Player::TranscodingHelper::tokenizeConvertCommand($command, $type, $url, $url, 0, $maxRate, 1, $quality);

	my $self = $class->SUPER::new(undef, $command);

	${*$self}{'contentType'} = $format;

	return $self;
}

sub contentType {
	my $self = shift;

	return ${*$self}{'contentType'};
}

sub randomGUID {
	my $guid = '';

	for my $digit (0...31) {

        	if ($digit==8 || $digit == 12 || $digit == 16 || $digit == 20) {

			$guid .= '-';
		}
		
		$guid .= sprintf('%x', int(rand(16)));
	}

	return $guid;
}

sub canDirectStream {
	my ($classOrSelf, $client, $url) = @_;

	# Bug 3181 & Others. Check the available types - if the user has
	# disabled built-in WMA, return false. This is required for streams
	# that are MMS only, or for WMA codecs we don't support in firmware.
	my ($command, $type, $format) = Slim::Player::TranscodingHelper::getConvertCommand($client, $url, DEFAULT_TYPE);

	if (defined $command && $command eq '-') {
		return $url;
	}

	return 0;
}

# Most WM streaming stations also stream via HTTP. The requestString class
# method is invoked by the direct streaming code to obtain a request string
# to send to a WM streaming server. We construct a HTTP request string and
# cross our fingers. 
sub requestString {
	my $self = shift;
	my $url  = shift;

	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);

	my $proxy = Slim::Utils::Prefs::get('webproxy');
	if ($proxy && $server ne 'localhost' && $server ne '127.0.0.1') {
		$path = "http://$server:$port$path";
	}

	my $host = $port == 80 ? $server : "$server:$port";

	my @headers = (
		"GET $path HTTP/1.0",
		"Accept: */*",
		"User-Agent: NSPlayer/4.1.0.3856",
		"Host: $host",
		"Pragma: xClientGUID={" . randomGUID() . "}",
	);

	# HTTP interaction with WM radio servers actually involves two separate
	# connections. The first is a request for the ASF header. We use it
	# to determine which stream number to request. Once we have the stream
	# number we can request the stream itself.
	if (defined($stream_nums{$url})) {

		push @headers, (
			"Pragma: no-cache,rate=1.0000000,stream-time=0,stream-offset=0:0,request-context=2,max-duration=0",
			"Pragma: xPlayStrm=1",
			"Pragma: stream-switch-count=1",
			"Pragma: stream-switch-entry=ffff:" . $stream_nums{$url} . ":0",
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

sub getFormatForURL {
	my ($classOrSelf, $url) = @_;

	return DEFAULT_TYPE;
}

sub parseHeaders {
	my $self = shift;
	my $url  = shift;

	return $self->parseDirectHeaders('noclient', $url, @_);
}

sub parseDirectHeaders {
	my $self    = shift;
	my $client  = shift;
	my $url     = shift;
	my @headers = @_;

	my ($contentType, $mimeType, $length, $body);

	foreach my $header (@headers) {

		$header =~ s/[\r\n]+$//;

		$::d_directstream && msg("header: " . $header . "\n");

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

		$::d_directstream && msg("it looks like a WMA file\n");

		$contentType = 'wma';

	} else {

		# Assume (and this may not be correct) that anything else
		# is an asx redirector.

		$::d_directstream && msg("it looks like an ASX redirector\n");

		$contentType = 'asx';
	}

	# If we don't yet have the stream number for this URL, ask
	# for the header first.
	if (!defined $stream_nums{$url}) {

		$body = 1;
		
		# If the length of the ASF header isn't specified, then
		# ask for say 30K...most headers will be signficantly smaller.
		if (!$length) {
			$length = 30 * 1024;
		}

		# XXX - why is this a global?
		$parser_state{$client}{"chunk_remaining"} = 0;
		$parser_state{$client}{"header_length"}   = 0;
		$parser_state{$client}{"bytes_received"}  = 0;
	}

	return (undef, undef, 0, '', $contentType, $length, $body);
}

sub handleBodyFrame {
	my $classOrSelf = shift;
	my $client      = shift || 'noclient';
	my $frame       = shift;

	#
	my $remaining   = length($frame);
	my $position    = 0;

	while ($remaining) {

		if (!$parser_state{$client}{"chunk_remaining"}) {

			my $chunkType = unpack('v', substr($frame, $position, 2));

			if ($chunkType != 0x4824) {
				return 1;
			}

			my $chunkLength = unpack('v', substr($frame, $position+2, 2));

			$position  += 12;
			$remaining -= 12;

			$parser_state{$client}{"chunk_remaining"} = $chunkLength - 8;
		}

		my $size = $parser_state{$client}{"chunk_remaining"} || 0;

		if ($size >= $remaining) {
			$size = $remaining;
		}

		$client->directBody($client->directBody() . substr($frame, $position, $size));

		$position  += $size;
		$remaining -= $size;

		$parser_state{$client}{"chunk_remaining"} -= $size;
		$parser_state{$client}{"bytes_received"}  += $size;
	}

	if (!$parser_state{$client}{"header_length"} &&
		$parser_state{$client}{"bytes_received"} > 24) {

		# The extra 50 bytes is the header of the data atom
		$parser_state{$client}{"header_length"} = unpack('V', substr($client->directBody(), 16, 8) ) + 50;
	}

	if ($parser_state{$client}{"header_length"} &&

		$parser_state{$client}{"bytes_received"} >= $parser_state{$client}{"header_length"}) {

		return 1;
	}

	return 0;
}

sub parseDirectBody {
	my $classOrSelf = shift;
	my $url = shift;
	my $body = shift;

	my $io = IO::String->new($body);

	$::d_directstream && msg("parseDirectBody: MMS protocol handler received response body\n");
	
	# If it's a WMA header, then parse to get the stream number.
	# We return the URL again, but this time we will connect to
	# play back.
	if ($body =~ /ASX/ || $body =~ /References/ || $body =~ m|://|) {

		$::d_directstream && msg("parseDirectBody: Treating [$url] as playlist.\n");

		return Slim::Formats::Playlists->parseList($url, $io);

	} else {

		$::d_directstream && msg("parseDirectBody: Parsing WMA Header info from: [$url]\n");
		
		my $wma  = Audio::WMA->new($io) || return ();
		
		my $stream = $wma->stream(0) || return ();

		return unless defined($stream->{'flags_raw'});

		$stream_nums{$url} = $stream->{'flags_raw'} & 0x007F;

		$::d_directstream && msg("Parsed body as WMA header.\n");

		return $url;
	}
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
