package Slim::Player::ProtocolHandlers;

# $Id$

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Utils::Misc;

# the protocolHandlers hash contains the modules that handle specific URLs,
# indexed by the URL protocol.  built-in protocols are exist in the hash, but
# have a zero value
my %protocolHandlers = ( 
	http     => qw(Slim::Player::Protocols::HTTP),
	icy      => qw(Slim::Player::Protocols::HTTP),
	mms      => qw(Slim::Player::Protocols::MMS),
	file     => 0,
	playlist => 0,
);

my %loadedHandlers = ();

sub isValidHandler {
	my ($class, $protocol) = @_;

	if (defined $protocolHandlers{$protocol}) {
		return 1;
	}

	if (exists $protocolHandlers{$protocol}) {
		return 0;
	}

	return undef;
}

sub registeredHandlers {
	my $class = shift;

	return keys %protocolHandlers;
}

sub registerHandler {
	my ($class, $protocol, $classToRegister) = @_;
	
	$protocolHandlers{$protocol} = $classToRegister;
}

sub openRemoteStream {
	my $class  = shift;
	my $track  = shift;
	my $client = shift;

	my $ds = Slim::Music::Info::getCurrentDataStore();

	# Make sure we're dealing with a track object.
	if (!blessed($track) || !$track->can('url')) {

		$track = $ds->objectForUrl($track, 1);
	}

	my $url        = $track->url;
	my $protoClass = $class->handlerForURL($url);

	$::d_source && msg("Trying to open protocol stream for $url\n");

	if ($protoClass) {

		$::d_source && msg("Found handler for $url - using $protoClass\n");

		return $protoClass->new({
			'track'  => $track,
			'url'    => $url,
			'client' => $client,
			'create' => 1,
		});
	}

	$::d_source && msg("Couldn't find protocol handler for $url\n");

	return undef;
}

sub handlerForURL {
	my ($class, $url) = @_;

	if (!$url) {
		return undef;
	}

	my ($protocol) = $url =~ /^([a-zA-Z0-9\-]+):/;

	if (!$protocol) {
		return undef;
	}

	# Load the handler when requested..
	return $class->loadHandler($protocol);
}

# Dynamically load in the protocol handler classes to save memory.
sub loadHandler {
	my ($class, $protocol) = @_;

	my $handlerClass = $protocolHandlers{lc $protocol};

	if ($handlerClass && !$loadedHandlers{$handlerClass}) {

		eval "use $handlerClass";

		$loadedHandlers{$handlerClass} = 1;
	}

	return $handlerClass;
}

1;

__END__
