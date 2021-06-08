package Slim::Player::SongStreamController;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use bytes;
use strict;

use base qw(Slim::Utils::Accessor);

use Slim::Utils::Log;

my $log = logger('player.source');

my $_liveCount = 0;

{
	__PACKAGE__->mk_accessor('ro', qw(song streamHandler protocolHandler));
	__PACKAGE__->mk_accessor('rw', qw(playerProxyStreaming));
}	

sub new {
	my ($class, $song, $streamHandler) = @_;
	
	my $self = $class->SUPER::new;

	$self->init_accessor(
		song => $song,
		streamHandler => $streamHandler,
		protocolHandler => Slim::Player::ProtocolHandlers->handlerForURL($song->streamUrl()),
	);	

	$_liveCount++;
	if (main::DEBUGLOG && $log->is_debug) {
		$log->debug("live=$_liveCount");	
	}
	
	return $self;
}

sub DESTROY {
	my $self = shift;
	
	$self->close();
	
	$_liveCount--;
	if (main::DEBUGLOG && $log->is_debug)	{
		$log->debug("DESTROY($self) live=$_liveCount");
	}
}

sub close {
	my $self = shift;
	
	my $fd = $self->streamHandler;
	
	if (defined $fd) {
		Slim::Networking::Select::removeError($fd);
		Slim::Networking::Select::removeRead($fd);
		$fd->close;
	}
}

sub songProtocolHandler {
	return shift->song->handler();
}

sub isDirect {
	return shift->song->directstream() || 0;
}

sub streamUrl {
	return shift->song->streamUrl();
}

sub track {
	return shift->song->currentTrack();
}

1;
