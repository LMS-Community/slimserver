package Slim::Buttons::Browse;

# $Id: Browse.pm,v 1.5 2003/09/15 18:50:18 dean Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Block;
use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Buttons::TrackInfo;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw (string);
use Slim::Utils::Scan;

# Each button on the remote has a function:

my %functions = (
	'up' => sub  {
		my $client = shift;
		my $button = shift;
		my $inc = shift || 1;
		my $count = $client->numberOfDirItems();
		if ($count < 2) {
			Slim::Display::Animation::bumpUp($client);
		} else {
			$inc = ($inc =~ /\D/) ? -1 : -$inc;
			my $newposition = Slim::Buttons::Common::scroll($client, $inc, $count, $client->currentDirItem());
			$client->currentDirItem($newposition);
			$client->update();
		}
	},
	'down' => sub  {
		my $client = shift;
		my $button = shift;
		my $inc = shift || 1;
		my $count = $client->numberOfDirItems();
		if ($count < 2) {
			Slim::Display::Animation::bumpDown($client);
		} else {
			if ($inc =~ /\D/) {$inc = 1}
			my $newposition = Slim::Buttons::Common::scroll($client, $inc, $client->numberOfDirItems(), $client->currentDirItem());
			$client->currentDirItem($newposition);
			$client->update();
		}
	},
	'left' => sub  {
		my $client = shift;
		if ($client->pwd() =~ m|^[/\\]?$| || $client->pwd() eq "__playlists") {
			# go to the home directory
			Slim::Buttons::Common::popModeRight($client);
			$client->lastSelection('', $client->currentDirItem());
		} else {
			# move up one level
			my @oldlines = Slim::Display::Display::curLines($client);
			loadDir($client, updir(), "left", \@oldlines);
		}
	},
	'right' => sub  {
		my $client = shift;
		if (!$client->numberOfDirItems()) {
			# don't do anything if the list is empty
			Slim::Display::Animation::bumpRight($client);
		} else {
			my $currentItem = $client->dirItems($client->currentDirItem());
			$::d_files && msg("currentItem == $currentItem\n");
			my @oldlines = Slim::Display::Display::curLines($client);
			if (Slim::Music::Info::isList($currentItem)) {
				# load the current item if it's a list (i.e. directory or playlist)
				# treat playlist files as directories.
				# ie - list the contents
				loadDir($client, $currentItem, "right", \@oldlines);
			} elsif (Slim::Music::Info::isSong($currentItem) || Slim::Music::Info::isHTTPURL($currentItem)) {
				# enter the trackinfo mode for the track in $currentitem
				Slim::Buttons::Common::pushMode($client, 'trackinfo', {'track' => $currentItem});
				Slim::Display::Animation::pushLeft($client, @oldlines, Slim::Display::Display::curLines($client));
			} else {
				warn "Error attempting to descend directory or open file: $currentItem\n";
			}
		}
	},
	'numberScroll' => sub  {
		my $client = shift;
		my $button = shift;
		my $digit = shift;
		
		my $i = SliMP3::Buttons::Common::numberScroll($client, $digit, $client->dirItems, SliMP3::Info::isDir(SliMP3::Misc::virtualToAbsolute($client->pwd())),
			sub {
				my $j = $client->dirItems(shift);
				if (Slim::Utils::Prefs::get('filesort')) {
 			       return Slim::Music::Info::plainTitle($j);
				} elsif (Slim::Music::Info::trackNumber($j)) {
					return Slim::Music::Info::trackNumber($j);
				} else {
					return Slim::Music::Info::title($j);
				}
			}
			);

		$client->currentDirItem($i);
		$client->update();
	},
	'add' => sub  {
		my $client = shift;
		my $currentItem = $client->dirItems($client->currentDirItem());
		my $line1 = string('ADDING_TO_PLAYLIST');
		my $line2 = Slim::Music::Info::standardTitle($client, $currentItem);
		$::d_files && msg("currentItem == $currentItem\n");
		if (Slim::Music::Info::isList($currentItem)) {
			# we are looking at an playlist file or directory
			Slim::Buttons::Block::block($client, $line1, $line2);
			Slim::Control::Command::execute($client, ["playlist", "add", $currentItem], \&playDone, [$client]);
		} elsif (Slim::Music::Info::isSong($currentItem) || Slim::Music::Info::isHTTPURL($currentItem)) {
			Slim::Display::Animation::showBriefly($client, $line1, $line2, undef, 1);
			# we are looking at a song file, play it and all the other songs in the directory after
			Slim::Control::Command::execute($client, ["playlist", "append", $currentItem]);
		} else {
			warn "Error attempting to add directory or file to playlist.\n";
			return;
		}
	},
	'insert' => sub  {
		my $client = shift;
		my $currentItem = $client->dirItems($client->currentDirItem());
		my $line1 = string('INSERT_TO_PLAYLIST');
		my $line2 = Slim::Music::Info::standardTitle($client, $currentItem);
		$::d_files && msg("currentItem == $currentItem\n");
		if (Slim::Music::Info::isList($currentItem)) {
			# we are looking at an playlist file or directory
			Slim::Buttons::Block::block($client, $line1, $line2);
			Slim::Control::Command::execute($client, ["playlist", "insertlist", $currentItem], \&playDone, [$client]);
		} elsif (Slim::Music::Info::isSong($currentItem) || Slim::Music::Info::isHTTPURL($currentItem)) {
			Slim::Display::Animation::showBriefly($client, $line1, $line2, undef, 1);
			# we are looking at a song file, play it and all the other songs in the directory after
			Slim::Control::Command::execute($client, ["playlist", "insert", $currentItem]);
		} else {
			warn "Error attempting to add directory or file to playlist.\n";
			return;
		}
	},
	'play' => sub  {
		my $client = shift;
		my $currentItem = $client->dirItems($client->currentDirItem());
		my $line1;
		my $line2 = Slim::Music::Info::standardTitle($client, $currentItem);
		my $shuffled = 0;
		if (Slim::Player::Playlist::shuffle($client)) {
			$line1 = string('PLAYING_RANDOMLY_FROM');
			$shuffled = 1;
		} else {
			$line1 = string('NOW_PLAYING_FROM');
		
		}
		if (Slim::Music::Info::isList($currentItem)) {
			# we are looking at an playlist file or directory
			Slim::Buttons::Block::block($client,$line1, $line2);
			Slim::Control::Command::execute($client, ["playlist", "load", $currentItem], \&playDone, [$client]);
		} elsif (Slim::Music::Info::isSong($currentItem) || Slim::Music::Info::isHTTPURL($currentItem)) {
			# put all the songs at this level on the playlist and start playing the selected one.
			Slim::Display::Animation::showBriefly($client, $line1, $line2, undef, 1);
			if (Slim::Utils::Prefs::get('playtrackalbum') && !Slim::Music::Info::isHTTPURL($currentItem)) {
				Slim::Control::Command::execute($client, ["playlist", "clear"]);
				Slim::Control::Command::execute($client, ["playlist", "shuffle" , 0]);
				my $startindex = 0;
				my $startindexcounter = 0;
				my $dirref = $client->dirItems;
				if (Slim::Music::Info::isPlaylist(Slim::Utils::Misc::virtualToAbsolute($client->pwd()))) {
					$startindex = $client->currentDirItem();
					Slim::Control::Command::execute($client, ["playlist", "load", $client->pwd()], \&playDone, [$client, $startindex, $shuffled]);
				} else {
					foreach my $song (@$dirref) {
						if (Slim::Music::Info::isSong($song)) {
							if ($song eq $currentItem) { $startindex = $startindexcounter; }
							Slim::Control::Command::execute($client, ["playlist", "append", $song]);
							$startindexcounter++;
						}
					}
					playDone($client, $startindex, $shuffled);
				}
			} else {
				Slim::Control::Command::execute($client, ["playlist", "play", $currentItem]);
			}
		} else {
			warn "Error attempting to play directory or open file.\n";
		}
	}
);

sub playDone {
	my $client = shift;
	my $startindex = shift;
	my $shuffled = shift;
	
	Slim::Buttons::Block::unblock($client);
	
	#The following commented out to allow showBriefly to finish
	#$client->update();
	if (defined($startindex)) { Slim::Control::Command::execute($client, ["playlist", "jump", $startindex]); }
	if (defined($shuffled)) { Slim::Control::Command::execute($client, ["playlist", "shuffle" , $shuffled]); }

}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	$client->lines(\&lines);
}

# create a directory listing, and append it to dirItems
sub loadDir {
	my ($client,$dir, $direction, $oldlinesref) = @_;

	my $pwd;
	my $oldpwd = $client->pwd();
	my $abspwd;

	if (defined($oldpwd)) {
		$client->lastSelection($oldpwd, $client->currentDirItem());
		$::d_files && msg("saving lastSelection for: $oldpwd as " . $client->currentDirItem() . "\n");
	}

	if ($dir eq "__playlists") {
		$::d_files && msg("loaddir: dir eq __playlists\n");
		$pwd = $dir;
	} elsif (!defined($dir) || $dir eq "") {
		$::d_files && msg("loaddir: !defined(dir) || dir eq ''\n");
		$pwd = '';
	} elsif ($dir eq updir()) {
		$::d_files && msg("loaddir: dir eq updir()\n");
		$pwd = Slim::Utils::Misc::ascendVirtual($oldpwd);
	} else {
		$::d_files && msg("loaddir: normal descend()\n");
		$pwd = Slim::Utils::Misc::descendVirtual($oldpwd
			,$client->dirItems($client->currentDirItem()),$client->currentDirItem());
	}

	@{$client->dirItems}=();

	$abspwd = Slim::Utils::Misc::virtualToAbsolute($pwd);
	$::d_files && msg("virtual directory: $pwd\nabsolute directory: $abspwd\n");

	unless (defined($abspwd) && 
			(Slim::Music::Info::isHTTPURL($abspwd) || 
			 Slim::Music::Info::isITunesPlaylistURL($abspwd) || 
			 (-e $abspwd)
			)
		   ) {
		opendir_done($client, $pwd, $direction, $oldlinesref, 0);
		$::d_files && msg("No such file or dir: [$pwd] removed out from under?\n");
		return;
	}

	$::d_files && msg("debug: Opening dir: [$pwd]\n");

	if (Slim::Music::Info::isList($abspwd)) {
		my $itemCount = 0;
		$::d_files && msg("getting playlist " . $pwd . " as directory\n");
		Slim::Buttons::Block::block($client,@$oldlinesref);

		Slim::Utils::Scan::addToList($client->dirItems, $abspwd, 0, undef, \&opendir_done, $client, $pwd, $direction, $oldlinesref);
		# addToList will call &opendir_done when it finishes.

	} else {
		warn "Trying to loadDir on a non directory or playlist: $pwd";
	}
}

#
# this is the callback from addToList when we open a directory:
#
sub opendir_done {
	my ($client, $pwd, $direction, $oldlinesref, $itemCount) = @_;
	$::d_files && msg("opendir_done($client, $pwd, $itemCount)\n");

	if ($pwd eq '__playlists' && Slim::Music::iTunes::useiTunesLibrary()) {
		$::d_files && msg("adding itunes playlists\n");
		push @{$client->dirItems}, @{Slim::Music::iTunes::playlists()};
	} 

	# in case we were blocked...
	Slim::Buttons::Block::unblock($client);

	$client->numberOfDirItems(scalar @{$client->dirItems});

	##############
	# check for the user's last selection
	if ($::d_files and defined $client->lastSelection($pwd)) {
		msg("\$lastselection{$pwd} == ".$client->lastSelection($pwd)."\n");
	}

	if (defined($pwd)) {
		if (defined $client->lastSelection($pwd) && ($client->lastSelection($pwd) < $client->numberOfDirItems())) {
			$client->currentDirItem($client->lastSelection($pwd));
		} else {
			$client->currentDirItem(0);
		}

		$client->pwd($pwd);
	}

	if (defined $direction) {
		if ($direction eq 'left') {
			Slim::Display::Animation::pushRight($client, @$oldlinesref, Slim::Display::Display::curLines($client));
		} else {
			Slim::Display::Animation::pushLeft($client, @$oldlinesref, Slim::Display::Display::curLines($client));
		}
	}

	return 1;
}

#
# figure out the lines to be put up to display the directory
#
sub lines {
	my $client = shift;
	my ($line1, $line2, $overlay);
	my $showArrow = 0;
	my $showSong = 0;

	$line1 = line1($client);
	$line2 = line2($client);
	$overlay = overlay($client);

	return ($line1, $line2, undef, $overlay);
}

sub line1 {
	my $client = shift;
	my $line1;

	if ($client->pwd() eq "__playlists") {
		$line1 = string('SAVED_PLAYLISTS');
	} elsif ((defined $client->pwd() and $client->pwd() =~ m|^[/\\]?$|) || !Slim::Utils::Prefs::get("mp3dir")) {
		$line1 = string('MUSIC');
	} else {
		my $dir;
		# show only deepest two levels past the root dir
		$dir = $client->pwd();
		my @components = splitdir($dir);
		if ($components[0] eq "__playlists") { shift @components; };
		my $shortpwd;

		foreach my $path (@components) {
			if (Slim::Music::Info::isURL($path)) { $path = Slim::Music::Info::standardTitle($client, $path); }
		}

		if (@components > 1) {
			$shortpwd = join('/', grep {!/^\s*$/} splice(@components, -2));
		} else {
			$shortpwd = $components[0];
		}

		$line1 = $shortpwd;
	}

	if ($client->numberOfDirItems()) {
		$line1 .= sprintf(" (%d ".string('OUT_OF')." %s)", $client->currentDirItem + 1, $client->numberOfDirItems());
	}

	return $line1;
}

sub line2 {
	my $client = shift;
	my $line2;

	if (!$client->numberOfDirItems()) {
		$line2 = string('EMPTY');
	} else {
		my $fullpath;
		$fullpath = $client->dirItems($client->currentDirItem());

		# try and use the id3 tag
		$line2 = Slim::Music::Info::standardTitle($client, $fullpath);
	}

	return $line2;
}

sub overlay {
	my $client = shift;
	my $fullpath;
	$fullpath = $client->dirItems($client->currentDirItem());

	if ($fullpath && Slim::Music::Info::isSong($fullpath) || Slim::Music::Info::isHTTPURL($fullpath)) {
		return Slim::Hardware::VFD::symbol('notesymbol');
	}

	if ($fullpath && Slim::Music::Info::isList($fullpath)) {
		return Slim::Hardware::VFD::symbol('rightarrow');
	}

	return undef;
}

1;

__END__
