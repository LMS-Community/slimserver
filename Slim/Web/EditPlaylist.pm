package Slim::Web::EditPlaylist;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use File::Spec::Functions;
use Slim::Formats::Parse;
use Slim::Music::Info;
use Slim::Player::Playlist;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Text;
use Slim::Web::HTTP;

# Subversion Change 134 says that I can blame Felix for adding this
# "functionality" to SlimServer :)
#
# http://svn.slimdevices.com/trunk/server/Slim/Web/EditPlaylist.pm?rev=134&view=rev

sub editplaylist {
	my ($client, $params) = @_;

	# This is a dispatcher to parts of the playlist editing that at one
	# time was contained in the mess of Slim::Web::Pages::browser()
	#
	# Now that playlists reside in the db - these functions are much
	# smaller and easier to work with.
	if ($params->{'saveCurrentPlaylist'}) {

		return saveCurrentPlaylist($client, $params);

	} elsif ($params->{'renamePlaylist'}) {

		return renamePlaylist($client, $params);

	} elsif ($params->{'deletePlaylist'}) {

		return deletePlaylist($client, $params);
	}

	my $ds       = Slim::Music::Info::getCurrentDataStore();

	my $playlist = $ds->objectForId('playlist', $params->{'id'}) || return [];
	my @items    = $playlist->tracks;

	# 0 base
	my $itemPos = ($params->{'item'} || 1) - 1;

	my $changed = 0;

	# Edit function - fill the to fields in the form
	if ($params->{'delete'}) {

		# Delete function - Remove entry from list
		splice(@items, $itemPos, 1);

		$changed = 1;

	} elsif (defined($params->{'form_title'})) {

		# Add function - Add entry it not already in list
		my $found = 0;
		my $title = $params->{'form_title'};
		my $url   = $params->{'form_url'};

		if ($title && $url) {

			my $playlistTrack = $ds->updateOrCreate({
				'url'      => $url,
				'readTags' => 1,
				'commit'   => 1,
			});

			for my $item (@items) {

				if ($item eq $playlistTrack) {
					# The assignment below ensures that the object
					# in the list is the one that we're going to 
					# change. It may be different of a different class
					# (Track vs LightWeightTrack) than the one just
					# returned from updateOrCreate.
					$playlistTrack = $item;
					$found = 1;
					last;
				}
			}

			if ($found == 0) {
				push @items, $playlistTrack;
			}

			$playlistTrack->title($title);
			$playlistTrack->titlesort(Slim::Utils::Text::ignoreCaseArticles($title));
			$playlistTrack->titlesearch(Slim::Utils::Text::ignoreCaseArticles($title));
			$playlistTrack->update;

			$changed = 1;
		}

	} elsif ($params->{'up'}) {

		# Up function - Move entry up in list
		if ($itemPos != 0) {

			my $item = $items[$itemPos];
			$items[$itemPos] = $items[$itemPos - 1];
			$items[$itemPos - 1] = $item;

			$changed = 1;
		}

	} elsif ($params->{'down'}) {

		# Down function - Move entry down in list
		if ($itemPos != scalar(@items) - 1) {

			my $item = $items[$itemPos];
			$items[$itemPos] = $items[$itemPos + 1];
			$items[$itemPos + 1] = $item;

			$changed = 1;
		}
	}

	if ($changed) {
		$::d_playlist && msg("Playlist has changed via editing - saving new list of tracks.\n");

		$playlist->setTracks(\@items);
		$playlist->update;

		if ($playlist->content_type eq 'ssp') {

			$::d_playlist && msg("Writing out playlist to disk..\n");

			Slim::Formats::Parse::writeList(\@items, undef, $playlist->url);
		}

		$ds->forceCommit;
		$ds->wipeCaches;

		# If we've changed the files - make sure that we clear the
		# format display cache - otherwise we'll show bogus data.
		Slim::Music::Info::clearFormatDisplayCache();
	}

	# This is our display - dispatch to browsedb ?
	$params->{'listTemplate'} = 'edit_playlist_list.html';
	$params->{'items'}        = \@items;
	$params->{'playlist'}     = $playlist;

	if ($items[$itemPos] && ref($items[$itemPos])) {

		$params->{'form_title'} = $items[$itemPos]->title;
		$params->{'form_url'}   = $items[$itemPos]->url;
	}

	return Slim::Web::HTTP::filltemplatefile("edit_playlist.html", $params);
}

sub saveCurrentPlaylist {
	my ($client, $params) = @_;

	my $ds = Slim::Music::Info::getCurrentDataStore();

	if (defined $client && Slim::Player::Playlist::count($client)) {

		my $title = $client->string('UNTITLED');

		my ($playlistObj) = $client->execute(['playlist', 'save', $title]);

		if ($playlistObj) {

			$params->{'playlist'} = $playlistObj->id;
		}

		# setup browsedb params to view the current playlist
		$params->{'level'} = 1;
		$params->{'untitledString'} = $title;

	} else {

		$params->{'level'} = 0;
	}

	$params->{'hierarchy'} = 'playlist,playlistTrack';

	return Slim::Web::Pages::browsedb($client, $params);
}

sub renamePlaylist {
	my ($client, $params) = @_;

	# 
	$params->{'hierarchy'} = 'playlist,playlistTrack';
	$params->{'level'}     = 0;

	my $ds          = Slim::Music::Info::getCurrentDataStore();
	my $playlistObj = $ds->objectForId('track', $params->{'id'});

	if ($playlistObj && $params->{'newname'}) {

		my $newName  = $params->{'newname'};

		# don't allow periods, colons, control characters, slashes, backslashes, just to be safe.
		$newName     =~ tr|.:\x00-\x1f\/\\| |s;

		my $newUrl   = Slim::Utils::Misc::fileURLFromPath(
			catfile(Slim::Utils::Prefs::get('playlistdir'), $newName . '.m3u')
		);

		my $existingPlaylist = $ds->objectForUrl($newUrl);

		# Warn the user if the playlist already exists.
		if (defined $existingPlaylist && !$params->{'overwrite'}) {

			$params->{'RENAME_WARNING'} = 1;

		} elsif (!defined $existingPlaylist || $params->{'overwrite'}) {

			if ($existingPlaylist && $existingPlaylist ne $playlistObj) {

				removePlaylistFromDisk($existingPlaylist);

				# Quickly remove a playlist from the database.
				$existingPlaylist->setTracks([]);

				$ds->delete($existingPlaylist, 1);

				$existingPlaylist = undef;
			}

			$ds->updateOrCreate({
				'url'        => $playlistObj,
				'attributes' => {
					'url'   => $newUrl,
					'title' => $newName,
				},
				'commit'     => 1,
			});

			Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj);
		}

		$params->{'level'}     = 1;
		$params->{'playlist'}  = $playlistObj->id;
	}

	return Slim::Web::Pages::browsedb($client, $params);
}

sub deletePlaylist {
	my ($client, $params) = @_;

	my $ds          = Slim::Music::Info::getCurrentDataStore();
	my $playlistObj = $ds->objectForId('track', $params->{'id'});

	$params->{'level'}     = 0;
	
	# Warn the user if the playlist already exists.
	if ($playlistObj && !$params->{'confirm'}) {

		$params->{'DELETE_WARNING'} = 1;
		$params->{'level'}     = 1;
		$params->{'playlist'}  = $playlistObj->id;

	} elsif ($playlistObj) {

		removePlaylistFromDisk($playlistObj);

		# Do a fast delete, and then commit it.
		$playlistObj->setTracks([]);

		$ds->delete($playlistObj, 1);
	}

	# Send the user off to the top level browse playlists
	$params->{'hierarchy'} = 'playlist,playlistTrack';

	return Slim::Web::Pages::browsedb($client, $params);
}

sub removePlaylistFromDisk {
	my $playlistObj = shift;

	if (!$playlistObj->can('path')) {
		return;
	}

	my $path = $playlistObj->path;

	if (-e $path) {

		unlink $path;

	} else {

		unlink catfile(Slim::Utils::Prefs::get('playlistdir'), $playlistObj->title . '.m3u');
	}
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
