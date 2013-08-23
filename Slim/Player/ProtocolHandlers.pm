package Slim::Player::ProtocolHandlers;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Music::Info;

# the protocolHandlers hash contains the modules that handle specific URLs,
# indexed by the URL protocol.  built-in protocols are exist in the hash, but
# have a zero value
my %protocolHandlers = ( 
	file     => main::LOCALFILE ? qw(Slim::Player::Protocols::LocalFile) : qw(Slim::Player::Protocols::File),
	http     => qw(Slim::Player::Protocols::HTTP),
	icy      => qw(Slim::Player::Protocols::HTTP),
	mms      => qw(Slim::Player::Protocols::MMS),
	spdr     => qw(Slim::Player::Protocols::SqueezePlayDirect),
	playlist => 0,
	db       => 1,
);

my %localHandlers = (
	file     => 1,
	db       => 1,
);

my %loadedHandlers = ();

my %iconHandlers = ();

sub isValidHandler {
	my ($class, $protocol) = @_;

	if (defined $protocol) {
		if ($protocolHandlers{$protocol}) {
			return 1;
		}
	
		if (exists $protocolHandlers{$protocol}) {
			return 0;
		}
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

sub registerIconHandler {
        my ($class, $regex, $ref) = @_;

        $iconHandlers{$regex} = $ref;
}


sub handlerForProtocol {
	my ($class, $protocol) = @_;
	
	return $protocolHandlers{$protocol};
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
			if ( my $meta = $handler->getMetadataFor($client, $url) ) {
				return $meta->{cover};
			}
		}
		
		if ($handler->can('getIcon')) {
			return $handler->getIcon($url);
		}
	}

	elsif ($url =~ /^[a-z0-9\-]*playlist:/) {
		return 'html/images/playlists.png';
	}

	elsif ($url =~ /^db:album\.(\w+)=(.+)/) {
		my $value = Slim::Utils::Misc::unescape($2);
		
		if (utf8::is_utf8($value)) {
			utf8::decode($value);
			utf8::encode($value);
		}
		
		my $album = Slim::Schema->search('Album', { $1 => $value })->first;

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
