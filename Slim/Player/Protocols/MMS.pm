package Slim::Player::Protocols::MMS;
		  
# $Id$

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

use strict;

use File::Spec::Functions qw(:ALL);
use IO::Socket qw(:DEFAULT :crlf);

use Slim::Player::Pipeline;

use base qw(Slim::Player::Pipeline);

use Slim::Display::Display;
use Slim::Utils::Misc;

sub new {
	my $class = shift;
	my $args  = shift;

	my $url    = $args->{'url'};
	my $client = $args->{'client'};

	# Set the content type to 'wma' to get the convert command
	Slim::Music::Info::setContentType($url, 'wma');

	my ($command, $type, $format) = Slim::Player::Source::getConvertCommand($client, $url);

	unless (defined($command) && $command ne '-') {
		$::d_remotestream && msg "Couldn't find conversion command for wma\n";
		Slim::Player::Source::errorOpening($client,Slim::Utils::Strings::string('WMA_NO_CONVERT_CMD'));
		return undef;
	}

	Slim::Music::Info::setContentType($url, $format);

	my $maxRate = 0;
	my $quality = 1;

	if (defined($client)) {
		$maxRate = Slim::Utils::Prefs::maxRate($client);
		$quality = $client->prefGet('lameQuality');
	}

	$command = Slim::Player::Source::tokenizeConvertCommand($command, $type, $url, $url, 0, $maxRate, 1, $quality);

	return $class->SUPER::new(undef, $command);
}

sub randomGUID {
	my $guid = '{';

	for my $digit (0...31) {
        if ($digit==8 || 
			$digit == 12 || 
			$digit == 16 || 
			$digit == 20) {
			$guid .= '-';
		}
		
		$guid .= sprintf('%x', int(rand(16)));
	}

	$guid .= '}';
}

sub requestString {
	my $classOrSelf = shift;
	my $url = shift;

	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);

	my $proxy = Slim::Utils::Prefs::get('webproxy');
	if ($proxy && $server ne 'localhost' && $server ne '127.0.0.1') {
		$path = "http://$server:$port$path";
	}

	my $host = $port == 80 ? $server : "$server:$port";

	# make the request
	return join($CRLF, (
		"GET $path HTTP/1.0",
		"Accept: */*",
		"User-Agent: NSPlayer/4.1.0.3856",
		"Host: $host",
		"Pragma: no-cache,rate=1.0000000,stream-time=0,stream-offset=0:0,request-context=2,max-duration=0",
		"Pragma: xPlayStrm=1",
		"Pragma: xClientGUID=" . randomGUID(),
		"Pragma: stream-switch-count=1",
		"Pragma: stream-switch-entry=ffff:1:0",
		$CRLF
	));
}

sub getFormatForURL {
	my $classOrSelf = shift;
	my $url = shift;

	return 'wma';
}

sub translateContentType {
	my $classOrSelf = shift;
	my $contentType = shift;

	# application/octet-stream means we're getting audio data
	if (($contentType eq "application/octet-stream") ||
		($contentType eq "application/x-mms-framed")) {
		return 'wma';
	}

	# Assume (and this may not be correct) that anything else
	# is an asx redirector.
	return 'asx';
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
