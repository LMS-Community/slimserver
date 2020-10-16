package Slim::Player::ProtocolHandlers;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Scalar::Util qw(blessed);
use Tie::RegexpHash;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Music::Info;
use Slim::Networking::Async::HTTP;

# the protocolHandlers hash contains the modules that handle specific URLs,
# indexed by the URL protocol.  built-in protocols are exist in the hash, but
# have a zero value
my %protocolHandlers = ( 
	file     => main::LOCALFILE ? qw(Slim::Player::Protocols::LocalFile) : qw(Slim::Player::Protocols::File),
	tmp      => qw(Slim::Player::Protocols::Volatile),
	http     => qw(Slim::Player::Protocols::HTTP),
	https    => Slim::Networking::Async::HTTP->hasSSL() ? qw(Slim::Player::Protocols::HTTPS) : qw(Slim::Player::Protocols::HTTP),
	icy      => qw(Slim::Player::Protocols::HTTP),
	mms      => qw(Slim::Player::Protocols::MMS),
	spdr     => qw(Slim::Player::Protocols::SqueezePlayDirect),
	playlist => 0,
	db       => 1,
);

tie my %URLHandlers, 'Tie::RegexpHash';

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

sub registerURLHandler {
	my ($class, $regexp, $classToRegister) = @_;

	$URLHandlers{$regexp} = $classToRegister;
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
	my $handler = $class->loadURLHandler($url)
	    // $class->loadHandler($protocol);

	# Handler should be a class, not '1' for rtsp
	return $handler && $handler =~ /::/ ? $handler : undef;
}

sub iconHandlerForURL {
	my ($class, $url) = @_;

	return undef unless $url;
	
	my $handler;
	foreach (keys %iconHandlers) {
		if ($url =~ /$_/i) {
			$handler = $iconHandlers{$_};
			last;
		}
	}

	return $handler;
}


sub iconForURL {
	my ($class, $url, $client) = @_;
	
	$url ||= '';

	if (my $handler = $class->handlerForURL($url)) {
		if ($client && $handler->can('getMetadataFor')) {
			if ( my $meta = $handler->getMetadataFor($client, $url) ) {
				return $meta->{cover} if $meta->{cover};
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

sub loadHandler {
	my ($class, $protocol) = @_;

	return $class->loadHandlerClass($protocolHandlers{lc $protocol});
}

sub loadURLHandler {
	my ($class, $url) = @_;

	return $class->loadHandlerClass($URLHandlers{$url});
}

# Dynamically load in the protocol handler classes to save memory.
sub loadHandlerClass {
	my ($class, $handlerClass) = @_;

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
