package Slim::Player::Playlist;

# SlimServer Copyright (C) 2001,2002,2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use FileHandle;
use IO::Socket qw(:DEFAULT :crlf);
use Time::HiRes;
use Slim::Control::Command;
use Slim::Display::Display;
use Slim::Utils::Misc;
use Slim::Utils::Scan;
use Slim::Utils::Strings qw(string);

#
# accessors for playlist information
#
sub count {
	my $client = shift;
	return scalar(@{playList($client)});
}

sub song {
	my $client = shift;
	my $index = shift;
	
	if (count($client) == 0) {
		return;
	}

	if (!defined($index)) {
		$index = Slim::Player::Source::currentSongIndex($client);
	}
	return ${playList($client)}[${shuffleList($client)}[$index]];
}

sub shuffleList {
	my ($client) = shift;
	
	$client = Slim::Player::Sync::masterOrSelf($client);
	
	return $client->shufflelist;
}

sub playList {
	my ($client) = shift;

	$client = Slim::Player::Sync::masterOrSelf($client);
	
	return $client->playlist;
}

sub shuffle {
	my $client = shift;
	my $shuffle = shift;
	
	$client = Slim::Player::Sync::masterOrSelf($client);

	if (defined($shuffle)) {
		Slim::Utils::Prefs::clientSet($client, "shuffle", $shuffle);
	}
	
	return Slim::Utils::Prefs::clientGet($client, "shuffle");
}

sub repeat {
	my $client = shift;
	my $repeat = shift;
	
	$client = Slim::Player::Sync::masterOrSelf($client);

	if (defined($repeat)) {
		Slim::Utils::Prefs::clientSet($client, "repeat", $repeat);
	}
	
	return Slim::Utils::Prefs::clientGet($client, "repeat");
}

# NOTE:
#
# If you are trying to control playback, try to use Slim::Control::Command::execute() instead of 
# calling the functions below.
#

sub copyPlaylist {
	my $toclient = shift;
	my $fromclient = shift;

	@{$toclient->playlist} = @{$fromclient->playlist};
	@{$toclient->shufflelist} = @{$fromclient->shufflelist};
	$toclient->currentsong(	$fromclient->currentsong);	
	Slim::Utils::Prefs::clientSet($toclient, "shuffle", Slim::Utils::Prefs::clientGet($fromclient, "shuffle"));
	Slim::Utils::Prefs::clientSet($toclient, "repeat", Slim::Utils::Prefs::clientGet($fromclient, "repeat"));
}

sub removeTrack {
	my $client = shift;
	my $tracknum = shift;
	
	my $playlistIndex = ${shuffleList($client)}[$tracknum];

	my $stopped = 0;
	my $oldmode = Slim::Player::Source::playmode($client);
	
	if ($tracknum == Slim::Player::Source::currentSongIndex($client)) {
		Slim::Player::Source::playmode($client, "stop");
		$stopped = 1;
	} elsif ($tracknum < Slim::Player::Source::currentSongIndex($client)) {
		Slim::Player::Source::currentSongIndex($client,Slim::Player::Source::currentSongIndex($client) - 1);
	}
	
	splice(@{playList($client)}, $playlistIndex, 1);

	my @reshuffled;
	my $counter = 0;
	foreach my $i (@{shuffleList($client)}) {
		if ($i < $playlistIndex) {
			push @reshuffled, $i;
		} elsif ($i > $playlistIndex) {
			push @reshuffled, ($i - 1);
		} else {
		}
	}
	
	$client = Slim::Player::Sync::masterOrSelf($client);
	
	@{$client->shufflelist} = @reshuffled;

	if ($stopped && ($oldmode eq "play")) {
		Slim::Player::Source::jumpto($client, $tracknum);
	}
	
	refreshPlaylist($client);

}

sub removeMultipleTracks {
	my $client = shift;
	my $songlist = shift;

	my %songlistentries;
	if (defined($songlist) && ref($songlist) eq 'ARRAY') {
		foreach my $item (@$songlist) {
			$songlistentries{$item}=1;
		}
	}

	my $stopped = 0;
	my $oldmode = Slim::Player::Source::playmode($client);
	
	my $curtrack = ${shuffleList($client)}[Slim::Player::Source::currentSongIndex($client)];

	my $i=0;
	my $oldcount=0;
	# going to need to renumber the entries in the shuffled list
	# will need to map the old position numbers to where the track ends
	# up after all the deletes occur
	my %oldToNew;
	while ($i <= $#{playList($client)}) {
		#check if this file meets all criteria specified
		my $thistrack=${playList($client)}[$i];
		if (exists($songlistentries{$thistrack})) {
			splice(@{playList($client)}, $i, 1);
			if ($curtrack == $oldcount) {
				Slim::Player::Source::playmode($client, "stop");
				$stopped = 1;
			}
		} else {
			$oldToNew{$oldcount}=$i;
			$i++;
		}
		$oldcount++;
	}
	
	my @reshuffled;
	my $newtrack;
	my $getnext=0;
	# renumber all of the entries in the shuffle list with their 
	# new positions, also get an update for the current track, if the 
	# currently playing track was deleted, try to play the next track 
	# in the new list
	foreach my $oldnum (@{shuffleList($client)}) {
		if ($oldnum == $curtrack) { $getnext=1; }
		if (exists($oldToNew{$oldnum})) { 
			push(@reshuffled,$oldToNew{$oldnum});
			if ($getnext) {
				$newtrack=$#reshuffled;
				$getnext=0;
			}
		}
	}

	# if we never found a next, we deleted eveything after the current
	# track, wrap back to the beginning
	if ($getnext) {	$newtrack=0; }

	$client = Slim::Player::Sync::masterOrSelf($client);
	
	@{$client->shufflelist} = @reshuffled;

	if ($stopped && ($oldmode eq "play")) {
		Slim::Player::Source::jumpto($client,$newtrack);
	} else {
		Slim::Player::Source::currentSongIndex($client,$newtrack);
	}

	refreshPlaylist($client);
}


sub forgetClient {
	my $client = shift;
	# clear out the playlist
	Slim::Control::Command::execute($client, ["playlist", "clear"]);
	
	# trying to play will close out any open files.
	Slim::Control::Command::execute($client, ["play"]);
}

sub refreshPlaylist {
	my $client = shift;
	# make sure we're displaying the new current song in the playlist view.
	foreach my $everybuddy ($client, Slim::Player::Sync::syncedWith($client)) {
		if ($everybuddy->isPlayer()) {
			Slim::Buttons::Playlist::jump($everybuddy);
		}
	}
	
}

sub moveSong {
	my $client = shift;
	my $src = shift;
	my $dest = shift;
	my $size = shift;
	my $listref;
	
	if (!defined($size)) { $size = 1;};
	if (defined $dest && $dest =~ /^[\+-]/) {
		$dest = $src + $dest;
	}
	if (defined $src && defined $dest && $src < Slim::Player::Playlist::count($client) && $dest < Slim::Player::Playlist::count($client) && $src >= 0 && $dest >=0) {
		if (Slim::Player::Playlist::shuffle($client)) {
			$listref = Slim::Player::Playlist::shuffleList($client);
		} else {
			$listref = Slim::Player::Playlist::playList($client);
		}
		if (defined $listref) {
			my @item = splice @{$listref},$src, $size;
			splice @{$listref},$dest, 0, @item;
			my $currentSong = Slim::Player::Source::currentSongIndex($client);
			if ($src == $currentSong) {
				Slim::Player::Source::currentSongIndex($client,$dest);
			} elsif ($dest == $currentSong) {
				Slim::Player::Source::currentSongIndex($client,($dest>$src)? $currentSong - 1 : $currentSong + 1);
			}
			Slim::Player::Playlist::refreshPlaylist($client);
		}
	}
}

sub clear {
	my $client = shift;
	@{Slim::Player::Playlist::playList($client)} = ();
	Slim::Player::Playlist::reshuffle($client);
}

sub fischer_yates_shuffle {
	my ($listRef)=@_;
	if ($#$listRef == -1 || $#$listRef == 0) {
		return;
	}
	for (my $i = ($#$listRef + 1); --$i;) {
		# swap each item with a random item;
		my $a = int(rand($i + 1));
		@$listRef[$i,$a] = @$listRef[$a,$i];
	}
}


#reshuffle - every time the playlist is modified, the shufflelist should be updated
#		We also invalidate the htmlplaylist at this point
sub reshuffle {
	my($client) = shift;
	my($dontpreservecurrsong) = shift;
	my($realsong);
	my($i);
	my($temp);
	my($songcount) = count($client);
	my $listRef = shuffleList($client);

	if ($songcount) {
		$realsong = ${$listRef}[Slim::Player::Source::currentSongIndex($client)];

		if (!defined($realsong) || $dontpreservecurrsong) {
			$realsong = -1;
		} elsif ($realsong > $songcount) {
			$realsong = $songcount;
		}

		@{$listRef} = (0 .. ($songcount - 1));

		if (shuffle($client) == 1) {
			fischer_yates_shuffle($listRef);
			for ($i = 0; $i < $songcount; $i++) {
				if (${$listRef}[$i] == $realsong) {
					if (shuffle($client)) {
						$temp = ${$listRef}[$i];
						${$listRef}[$i] = ${$listRef}[0];
						${$listRef}[0] = $temp;
						$i = 0;
					}
					last;
				}
			}
		} elsif (shuffle($client) == 2) {
			my %albtracks;
			my %trackToNum;
			my $i = 0;			
			foreach my $track (@{playList($client)}) {
				my $album=Slim::Music::Info::matchCase(Slim::Music::Info::album($track));
				if (!defined($album)) {
					$album=string('NO_ALBUM');
				}
				push @{$albtracks{$album}},$i;
				$trackToNum{$track}=$i;
				$i++;
			}
			if ($realsong == -1) {
				$realsong=${$listRef}[Slim::Utils::Prefs::clientGet($client,'currentSong')];
			}
			my $curalbum=Slim::Music::Info::matchCase(Slim::Music::Info::album(${playList($client)}[$realsong]));
			if (!defined($curalbum)) {
				$curalbum = string('NO_ALBUM');
			}
			my @albums = keys(%albtracks);

			fischer_yates_shuffle(\@albums);

			for ($i = 0; $i <= $#albums && $realsong != -1; $i++) {
				my $album=shift(@albums);
				if ($album ne $curalbum) {
					push(@albums,$album);
				} else {
					unshift(@albums,$album);
					last;
				}
			}
			my @shufflelist;
			$i=0;
			my $album=shift(@albums);
			my @albumorder=map {${playList($client)}[$_]} @{$albtracks{$album}};
			@albumorder=Slim::Music::Info::sortByAlbum(@albumorder);
			foreach my $trackname (@albumorder) {
				my $track=$trackToNum{$trackname};
				push @shufflelist,$track;
				$i++
			}
			foreach my $album (@albums) {
				my @albumorder=map {${playList($client)}[$_]} @{$albtracks{$album}};
				@albumorder=Slim::Music::Info::sortByAlbum(@albumorder);
				foreach my $trackname (@albumorder) {
					push @shufflelist,$trackToNum{$trackname};
				}
			}
			@{$listRef}=@shufflelist;
		} 
		
		for ($i = 0; $i < $songcount; $i++) {
			if (${$listRef}[$i] == $realsong) {
				Slim::Player::Source::currentSongIndex($client,$i);
				last;
			}
		}
	
		if (Slim::Player::Source::currentSongIndex($client) >= $songcount) { 
			Slim::Player::Source::currentSongIndex($client, 0);
		};
		
	} else {
		@{$listRef} = ();
		Slim::Player::Source::currentSongIndex($client, 0);
	}
	refreshPlaylist($client);
}

# DEPRICATED
# for backwards compatibility with plugins and the like, this stuff was moved to Slim::Control::Command
sub executecommand {
	Slim::Control::Command::execute(@_);
}

sub setExecuteCommandCallback {
	Slim::Control::Command::setExecuteCallback(@_);
}

sub clearExecuteCommandCallback {
	Slim::Control::Command::clearExecuteCallback(@_);
}

sub modifyPlaylistCallback {
	my $client = shift;
	my $paramsRef = shift;
	if (Slim::Utils::Prefs::get('playlistdir') && Slim::Utils::Prefs::get('persistPlaylists')) {
		#Did the playlist change?
		my $saveplaylist = $paramsRef->[0] eq 'playlist' && ($paramsRef->[1] eq 'play' 
					|| $paramsRef->[1] eq 'append' || $paramsRef->[1] eq 'load_done'
					|| $paramsRef->[1] eq 'loadalbum'
					|| $paramsRef->[1] eq 'addalbum' || $paramsRef->[1] eq 'clear'
					|| $paramsRef->[1] eq 'delete' || $paramsRef->[1] eq 'move'
					|| $paramsRef->[1] eq 'sync');
		#Did the playlist or the current song change?
		my$savecurrsong = $saveplaylist || $paramsRef->[0] eq 'open' 
					|| ($paramsRef->[0] eq 'playlist' 
						&& ($paramsRef->[1] eq 'jump' || $paramsRef->[1] eq 'index' || $paramsRef->[1] eq 'shuffle'));
		return if !$savecurrsong;
		my @syncedclients = Slim::Player::Sync::syncedWith($client);
		push @syncedclients,$client;
		my $playlistref = Slim::Player::Playlist::playList($client);
		my $currsong = (Slim::Player::Playlist::shuffleList($client))->[Slim::Player::Source::currentSongIndex($client)];
		foreach my $eachclient (@syncedclients) {
			if ($saveplaylist) {
				my $playlistname = "__" . $eachclient->id() . ".m3u";
				$playlistname =~ s/\:/_/g;
				$playlistname = catfile(Slim::Utils::Prefs::get('playlistdir'),$playlistname);
				Slim::Formats::Parse::writeM3U($playlistref,$playlistname);
			}
			if ($savecurrsong) {
				Slim::Utils::Prefs::clientSet($eachclient,'currentSong',$currsong);
			}
		}
	}
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
