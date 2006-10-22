package Slim::Player::Protocols::MMS;

# $Id$

# SlimServer Copyright (c) 2001-2006 Vidur Apparao, Slim Devices Inc.
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
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;

use constant DEFAULT_TYPE => 'wma';

=head2 new ( $class, $args )

Create a new instance of the MMS protocol handler, only for transcoding using wmadec or
another command-line tool.

=cut

sub new {
	my $class = shift;
	my $args  = shift;

	my $url    = $args->{'url'};
	my $client = $args->{'client'};

	# Set the content type to 'wma' to get the convert command
	my ($command, $type, $format) = Slim::Player::TranscodingHelper::getConvertCommand($client, $url, DEFAULT_TYPE);

	unless (defined($command) && $command ne '-') {

		logger('player.streaming.remote')->error("Error: Couldn't find conversion command for wma!");

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
	my $classOrSelf = shift;
	my $client      = shift;
	my $url         = shift;

	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);

	# Use full path for proxy servers
	my $proxy = Slim::Utils::Prefs::get('webproxy');
	if ( $proxy && $server !~ /(?:localhost|127.0.0.1)/ ) {
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

	# Cache always uses mms URLs
	my $mmsURL = $url;
	$mmsURL    =~ s/^http/mms/;
	
	my $cache     = Slim::Utils::Cache->instance;
	my $streamNum = $cache->get( 'wma_streamNum_' . $mmsURL );
	my $wma       = $cache->get( 'wma_metadata_'  . $mmsURL );
	
	# Just in case, use stream #1
	$streamNum ||= 1;
	
	# Handle our metadata
	if ( $wma ) {
		setMetadata( $client, $url, $wma, $streamNum );
	}

	push @headers, (
		"Pragma: no-cache,rate=1.0000000,stream-time=0,stream-offset=0:0,request-context=2,max-duration=0",
		"Pragma: xPlayStrm=1",
		"Pragma: stream-switch-count=1",
		"Pragma: stream-switch-entry=ffff:" . $streamNum . ":0 ",
	);

	# make the request
	return join($CRLF, @headers, $CRLF);
}

sub getFormatForURL {
	my ($classOrSelf, $url) = @_;

	return DEFAULT_TYPE;
}

sub parseMetadata {
	my ( $client, $url, $metadata ) = @_;
	
	my $wma = Audio::WMA->parseObject( $metadata );
	
	# Cache always uses mms URLs
	my $mmsURL = $url;
	$mmsURL    =~ s/^http/mms/;
	
	my $cache     = Slim::Utils::Cache->instance;
	my $streamNum = $cache->get( 'wma_streamNum_' . $mmsURL );

	setMetadata( $client, $url, $wma, $streamNum || 1 );
	
	return;
}

sub setMetadata {
	my ( $client, $url, $wma, $streamNumber ) = @_;

	my $log = logger('player.streaming.direct');
	
	# Bitrate method 1: from parseDirectBody, we have the whole WMA object
	if ( $streamNumber && ref $wma->stream ) {

		for my $stream ( @{ $wma->stream } ) {

			if ( $stream->{'streamNumber'} == $streamNumber ) {

				if ( my $bitrate = $stream->{'bitrate'} ) {

					my $kbps = int( $bitrate / 1000 );
					my $vbr  = $wma->tags('vbr') || undef;

					Slim::Music::Info::setBitrate( $url, $kbps * 1000, $vbr );

					$log->info("Setting bitrate to $kbps from WMA metadata");
				}

				last;
			}
		}
	}
	elsif ( ref $wma->{'BITRATES'} ) {

		# method 2: from parseMetadata
		my $bitrates = $wma->{'BITRATES'};
		my $bitrate  = 0;

		for my $stream ( keys %{ $bitrates } ) {

			if ( $stream == $streamNumber ) {

				$bitrate = $bitrates->{$stream};
			}
		}

		my $kbps = int( $bitrate / 1000 );
		my $vbr  = $wma->tags('vbr') || undef;

		Slim::Music::Info::setBitrate( $url, $kbps * 1000, $vbr );

		$log->info("Setting bitrate to $kbps from WMA bitrate properties object");
	}
	
	# Set duration and progress bar if available and this is not a broadcast stream
	if ( $wma->info('playtime_seconds') ) {

		if ( my $secs = int( $wma->info('playtime_seconds') ) ) {

			if ( $wma->info('flags') && $wma->info('flags')->{'broadcast'} != 1 ) {

				if ( $secs > 0 ) {
					
					$client->streamingProgressBar( {
						'url'      => $url,
						'duration' => $secs,
					} );
				}
			}
		}
	}
	
	# Set title if available
	if ( my $title = $wma->tags('title') ) {
		
		# Ignore title metadata for Rhapsody tracks
		if ( $url !~ /^rhap/ ) {

			Slim::Music::Info::setCurrentTitle($url, $title);

			for my $everybuddy ( $client, Slim::Player::Sync::syncedWith($client)) {
				$everybuddy->update();
			}
		
			$log->info("Setting title to '$title' from WMA metadata");
		}
	}
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
