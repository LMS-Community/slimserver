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
use Slim::Music::Info;

# Tell PerlSvc to bundle these modules
if (0) {
	require Slim::Player::Protocols::File;
	require Slim::Player::Protocols::HTTP;
	require Slim::Player::Protocols::MMS;
}

# the protocolHandlers hash contains the modules that handle specific URLs,
# indexed by the URL protocol.  built-in protocols are exist in the hash, but
# have a zero value
my %protocolHandlers = ( 
	file     => qw(Slim::Player::Protocols::File),
	http     => qw(Slim::Player::Protocols::HTTP),
	icy      => qw(Slim::Player::Protocols::HTTP),
	mms      => qw(Slim::Player::Protocols::MMS),
	rtsp     => 1,
	playlist => 0,
	db       => 1,
);

my %localHandlers = (
	file     => 1,
);

my %loadedHandlers = ();

my %iconHandlers = ();

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

sub isValidRemoteHandler {
	my ($class, $protocol) = @_;
	
	return isValidHandler(@_) && !$localHandlers{$protocol};
	
}

sub registeredHandlers {
	my $class = shift;

	return keys %protocolHandlers;
}

sub registerHandler {
	my ($class, $protocol, $classToRegister) = @_;
	
	$protocolHandlers{$protocol} = $classToRegister;
}

sub openStream {
	my $class    = shift;
	my $song     = shift;
	my $client   = shift;
	
	my $url        = $song->currentTrack()->url;
	my $protoClass = $song->currentTrackHandler();
	my $log        = logger('player.source');

	$log->info("Trying to open protocol stream for $url");

	if ($protoClass) {

		$log->info("Found handler for $url - using $protoClass");

		return $protoClass->new({
			url      => $url, # it is just easier if we always include the URL here
			client   => $client,
			song     => $song,
		});
	}

	$log->warn("Couldn't find protocol handler for $url");

	return undef;
}

sub registerIconHandler {
        my ($class, $regex, $ref) = @_;

        $iconHandlers{$regex} = $ref;
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
	return $handler && $handler =~ /::/ ? $handler : undef;
}

sub iconHandlerForURL {
	my ($class, $url) = @_;

	return undef unless $url;
	
	my $handler;
	foreach (keys %iconHandlers) {
		if ($url =~ /$_/) {
			$handler = $iconHandlers{$_};
			last;
		}
	}

	return $handler;
}


sub iconForURL {
	my ($class, $url, $client) = @_;

	if (my $handler = $class->handlerForURL($url)) {
		if ($client && $handler->can('getMetadataFor')) {
			return $handler->getMetadataFor($client, $url)->{cover};
		}
		elsif ($handler->can('getIcon')) {
			return $handler->getIcon($url);
		}
	}

	elsif ( ($url =~ /^file:/ && Slim::Music::Info::isPlaylist($url)) || $url =~ /^[a-z0-9\-]*playlist:/) {
		return 'html/images/playlists.png';
	}

	elsif ( ($url =~ /^file:/ && Slim::Music::Info::isSong($url))) {
		my $track = Slim::Schema->rs('Track')->objectForUrl({
			'url' => $url,
		});

		if ($track && $track->coverArt) {
			return 'music/' . $track->id . '/cover.png';
		}

		return 'html/images/cover.png';
	}

	elsif ($url =~ /^db:album\.(\w+)=(.+)/) {
		my $album = Slim::Schema->single('Album', { $1 => Slim::Utils::Misc::unescape($2) });

		if ($album && $album->artwork) {
			return 'music/' . $album->artwork . '/cover.png';
		}

		return 'html/images/albums.png'
	}

	elsif ($url =~ /^db:contributor/) {
		return 'html/images/artists.png'
	}

	elsif ($url =~ /^db:year/) {
		return 'html/images/years.png'
	}

	elsif ($url =~ /^db:genre/) {
		return 'html/images/genres.png'
	}

	return;
}

# Dynamically load in the protocol handler classes to save memory.
sub loadHandler {
	my ($class, $protocol) = @_;

	my $handlerClass = $protocolHandlers{lc $protocol};

	if ($handlerClass && $handlerClass ne '1' && !$loadedHandlers{$handlerClass}) {

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
