package Slim::Player::Playlist;

# Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

#
# accessors for playlist information
#

# $client
sub count {return $_[0]->getPlaylist()->count();}

# $client
sub shuffleType {return $_[0]->getPlaylist()->shuffleType(@_);}

# $client, $index, $refresh, $useShuffled
sub song {return $_[0]->getPlaylist()->song(@_);}

# $client, $start, $end
sub songs {return $_[0]->getPlaylist()->songs(@_);}

# Refresh track(s) in a client playlist from the database
# $client, $url
sub refreshTrack {return $_[0]->getPlaylist()->refreshTrack(@_);}

# $client
sub url {return $_[0]->getPlaylist()->url(@_);}

# $client
sub shuffleList {return $_[0]->getPlaylist()->shuffleList(@_);}

# $client
sub playList {return $_[0]->getPlaylist()->playList(@_);}

# $client, $tracksRef, $position, $jumpIndex, $request
# $position:i=0..n => before current-playlist track i
#           -1     => after current track (insert)
#			-2     => replace all
# 			-3     => at end (append), default
sub addTracks {return $_[0]->getPlaylist()->addTracks(@_);}

# $client, $shuffle
sub shuffle {return $_[0]->getPlaylist()->shuffle(@_);}

# $client, $dontpreservecurrsong
sub reshuffle {return $_[0]->getPlaylist()->reshuffle(@_);}

# $client, $repeat
sub repeat {return $_[0]->getPlaylist()->repeat(@_);}

# $toClient, $fromClient, $noQueueReset
sub copyPlaylist {return $_[0]->getPlaylist()->copyPlaylist(@_);}

# $client, $tracknum, $nTracks
sub removeTrack {return $_[0]->getPlaylist()->removeTrack(@_);}

# $client, $tracks
sub removeMultipleTracks {return $_[0]->getPlaylist()->removeMultipleTracks(@_);}

# $client, $index
sub refreshPlaylist {return $_[0]->getPlaylist()->refreshPlaylist(@_);}

# $client, $src, $dest, $size
sub moveSong {return $_[0]->getPlaylist()->moveSong(@_);}

# $client
sub stopAndClear {return $_[0]->getPlaylist()->stopAndClear(@_);}


# restore the old playlist if we aren't already synced with somebody (that has a playlist)
# $client, $callback
sub loadClientPlaylist {return $_[0]->getPlaylist()->loadClientPlaylist(@_);}

sub fischer_yates_shuffle {
	my ($listRef) = @_;

	if ($#$listRef == -1 || $#$listRef == 0) {
		return;
	}

	for (my $i = ($#$listRef + 1); --$i;) {
		# swap each item with a random item;
		my $a = int(rand($i + 1));
		@$listRef[$i,$a] = @$listRef[$a,$i];
	}
}

# $request
sub newSongPlaylistCallback {
	my $request = shift;

	my $client = $request->client() || return;
	
	$client->getPlaylist()->newSongPlaylist($client)
}


# $playlistObj
sub removePlaylistFromDisk {
	my $playlistObj = shift;

	if (!$playlistObj->can('path')) {
		return;
	}

	my $path = $playlistObj->path;

	if (-e $path) {
		unlink $path;
	} else {
		unlink catfile(Slim::Utils::Misc::getPlaylistDir(), $playlistObj->title . '.m3u');
	}
}


# $request
sub modifyPlaylistCallback {
	my $request = shift;
	my $client  = $request->client() or return;
	return $client->getPlaylist()->modifyPlaylistCallback($client, $request);
}

sub scheduleWriteOfPlaylist {
	my ($self, $client, $playlistObj) = @_;

	# This should proably be more configurable / have writeM3U or a
	# wrapper know about the scheduler, so we can write out a file at a time.
	#
	# Need to fork!
	#
	# This can happen if the user removes the
	# playlist - because this is a closure, we get
	# a bogus object back)
	if (!blessed($playlistObj) || !$playlistObj->can('tracks') || !Slim::Utils::Misc::getPlaylistDir()) {

		return 0;
	}

	if ($playlistObj->title eq Slim::Utils::Strings::string('UNTITLED')) {

		logger('player.playlist')->warn("Not writing out untitled playlist.");

		return 0;
	}

	Slim::Formats::Playlists::M3U->write( 
		[ $playlistObj->tracks ],
		undef,
		$playlistObj->path,
		1,
		main::LOCAL_PLAYERS && defined($client) ? Slim::Player::Source::playingSongIndex($client) : 0,
	);
}




1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
