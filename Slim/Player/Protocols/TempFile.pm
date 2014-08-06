package Slim::Player::Protocols::TempFile;

# Logitech Media Server Copyright 2001-2011 Logitech, Vidur Apparao.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

# Subclass of file: protocol handler to allow files to be played without being stored in the database.
# This can be used to eg. browse music folder while a scan is running, or play files from removable media.

use strict;

use Slim::Utils::Log;
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
	
	if ( ! ($track->title && $track->artistName && $track->duration) ) {
		my $path = $class->pathFromFileURL($url);
		my $attributes = Slim::Formats->readTags( $path );
		$track->setAttributes($attributes) if $attributes && keys %$attributes;
		
		# Try to read a cover image from the tags first.
		my ($body, $contentType);
	
		eval {
			($body, $contentType) = $class->_readCoverArtTags($track, $path);
		
			# Nothing there? Look on the file system.
			if (!defined $body) {
				($body, $contentType) = $class->_readCoverArtFiles($track, $path);
			}
		};
		
		if ($body) {
			my $cache = Slim::Utils::Cache->new();
			$cache->set( 'cover_' . $track->url, {
				image => $body,
				type  => $contentType || 'image/jpeg',
			}, 86400 * 7 );
		}
	}
	
#	warn Data::Dump::dump($track);
	
	return {
		title     => $track->title,
		artist    => $track->artistName,
		album     => $track->albumname,
		duration  => $track->duration,
		cover     => $track->coverArt,
		coverid   => $track->coverid,
		'icon-id' => $track->coverid,
		icon      => $class->getIcon($url),
		bitrate   => $track->prettyBitRate,
		genre     => $track->genre,
#		info_link => 'plugins/spotifylogi/trackinfo.html',
#		type      => 'Ogg Vorbis (Spotify)',
	};
}

1;
