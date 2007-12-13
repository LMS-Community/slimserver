package Slim::Player::ProtocolHandlers;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Misc;

# the protocolHandlers hash contains the modules that handle specific URLs,
# indexed by the URL protocol.  built-in protocols are exist in the hash, but
# have a zero value
my %protocolHandlers = ( 
	http     => qw(Slim::Player::Protocols::HTTP),
	icy      => qw(Slim::Player::Protocols::HTTP),
	mms      => qw(Slim::Player::Protocols::MMS),
	rtsp     => 1,
	file     => 0,
	playlist => 0,
);

my %loadedHandlers = ();

sub isValidHandler {
	my ($class, $protocol) = @_;

	if ($protocolHandlers{$protocol}) {
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
	my $url    = shift;
	my $client = shift;

	my $protoClass = $class->handlerForURL($url);
	my $log        = logger('player.source');

	$log->info("Trying to open protocol stream for $url");

	if ($protoClass) {

		$log->info("Found handler for $url - using $protoClass");

		return $protoClass->new({
			'url'    => $url,
			'client' => $client,
		});
	}

	$log->warn("Couldn't find protocol handler for $url");

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
	my $handler = $class->loadHandler($protocol);
	
	# Handler should be a class, not '1' for rtsp
	return $handler =~ /::/ ? $handler : undef;
}

# Dynamically load in the protocol handler classes to save memory.
sub loadHandler {
	my ($class, $protocol) = @_;

	my $handlerClass = $protocolHandlers{lc $protocol};

	if ($handlerClass && !$loadedHandlers{$handlerClass}) {

		Slim::bootstrap::tryModuleLoad($handlerClass);

		if ($@) {

			logWarning("Couldn't load class: [$handlerClass] - [$@]");

			return undef;
		}

		$loadedHandlers{$handlerClass} = 1;
	}

	return $handlerClass;
}

1;

__END__
