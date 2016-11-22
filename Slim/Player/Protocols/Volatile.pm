package Slim::Player::Protocols::Volatile;

# Logitech Media Server Copyright 2001-2011 Logitech, Vidur Apparao.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

# Subclass of file:// protocol handler to allow files to be played without being stored in the database.
# This can be used to eg. browse music folder while a scan is running, or play files from removable media.

use strict;

use Slim::Music::Artwork;
use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);
use base qw(Slim::Player::Protocols::File);

sub isRemote { 1 }

sub pathFromFileURL {
	my ($class, $url) = @_;
	
	$url =~ s/^tmp\b/file/;
	return Slim::Utils::Misc::pathFromFileURL($url);
}

sub getMetadataFor {
	my ( $class, $client, $url ) = @_;

	my $track = Slim::Schema::RemoteTrack->fetch($url);
	
	$url =~ s/^tmp/file/;
	my $path = $class->pathFromFileURL($url);
	
	if ( ! ($track->title && $track->artistName && $track->duration) ) {
		my $attributes = Slim::Formats->readTags( $path );
		
		# make sure we have a value for artist, or we'll end up scanning the file over and over again
		$attributes->{ARTIST} = cstring($client, 'NO_ARTIST') unless defined $attributes->{ARTIST};
		
		$track->setAttributes($attributes) if $attributes && keys %$attributes;
		
		$class->getArtwork($track, $path)
	}
	
	# artwork might have been purged from cache - re-read it
	if ( $track->cover && !$track->coverArt ) {
		$class->getArtwork($track, $path);
	}
	
	return {
		title     => $track->title,
		artist    => $track->artistName,
		album     => $track->albumname,
		tracknum  => $track->tracknum,
		disc      => $track->disc,
		duration  => $track->secs,
		coverid   => $track->coverid,
		icon      => $track->cover && '/music/' . $track->coverid . '/cover.png',
		samplerate=> $track->samplerate,
		bitrate   => $track->prettyBitRate,
		genre     => $track->genre,
		replay_gain=> $track->replay_gain,
		type      => $track->content_type,
		year      => $track->year,
	};
}

sub getArtwork {
	my ($class, $track, $path) = @_;

	return if $path && -d $path;
	
	# Try to read a cover image from the tags first.
	my ($body, $contentType, $file);
	
	eval {
		($body, $contentType, $file) = Slim::Music::Artwork->_readCoverArtTags($track, $path);
	
		# Nothing there? Look on the file system.
		if (!defined $body) {
			($body, $contentType, $file) = Slim::Music::Artwork->_readCoverArtFiles($track, $path);
		}
	};
	
	if ($body && defined $file) {
		Slim::Utils::Cache->new->set( 'cover_' . $track->url, {
			image => $body,
			type  => $contentType || 'image/jpeg',
		}, 86400 * 7 );
		
		$track->cover($file);
	}
	elsif ($track->cover) {
		$track->cover(0)
	}
}

1;
