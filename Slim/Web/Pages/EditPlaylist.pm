package Slim::Web::Pages::EditPlaylist;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use File::Spec::Functions;
use Scalar::Util qw(blessed);

use Slim::Control::Request;
use Slim::Formats::Playlists;
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

sub init {
	Slim::Web::HTTP::addPageFunction(qr/^edit_playlist\.(?:htm|xml)/, \&editplaylist);
}

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

	my $playlist_id = $params->{'playlist.id'};
	# 0 base
	my $itemPos = ($params->{'item'} || 1) - 1;


	my $changed = 0;

	if ($params->{'delete'}) {

		Slim::Control::Request::executeRequest(undef, 
			['playlists', 'edit', 'cmd:delete', 
			'playlist_id:' . $playlist_id,
			'index:' . $itemPos]);

	} elsif (defined($params->{'form_title'})) {

		Slim::Control::Request::executeRequest(undef, 
			['playlists', 'edit', 'cmd:add', 
			'playlist_id:' . $playlist_id,
			'title:' . $params->{'form_title'},
			'url:' . $params->{'form_url'}]);

	} elsif ($params->{'up'}) {

		Slim::Control::Request::executeRequest(undef, 
			['playlists', 'edit', 'cmd:up', 
			'playlist_id:' . $playlist_id,
			'index:' . $itemPos]);

	} elsif ($params->{'down'}) {

		Slim::Control::Request::executeRequest(undef, 
			['playlists', 'edit', 'cmd:down', 
			'playlist_id:' . $playlist_id,
			'index:' . $itemPos]);

	}


	my $playlist = Slim::Schema->find('Playlist', $playlist_id);

	if (!blessed($playlist) || !$playlist->tracks) {

		return [];
	}

	my @items   = $playlist->tracks;

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

	if (defined $client && Slim::Player::Playlist::count($client)) {

		my $title = $client->currentPlaylist ? 
				Slim::Music::Info::standardTitle($client, $client->currentPlaylist) : 
					$client->string('UNTITLED');

		# Changed by Fred to fix the issue of getting the playlist object
		# by setting $p1 to it, which was messing up callback and the CLI.

		my $request = Slim::Control::Request::executeRequest($client, ['playlist', 'save', $title]);

		if (defined $request) {
		
			$params->{'playlist.id'} = $request->getResult('__playlist_id');
		}

		# setup browsedb params to view the current playlist
		$params->{'level'} = 1;
		$params->{'untitledString'} = $title;

	} else {

		$params->{'level'} = 0;
	}

	$params->{'hierarchy'} = 'playlist,playlistTrack';

	# Don't add this back to the breadcrumbs
	delete $params->{'saveCurrentPlaylist'};

	return Slim::Web::Pages::BrowseDB::browsedb($client, $params);
}

sub renamePlaylist {
	my ($client, $params) = @_;

	$params->{'hierarchy'} = 'playlist,playlistTrack';
	$params->{'level'}     = 0;
	
	my $playlist_id = $params->{'playlist.id'};
	my $newName     = $params->{'newname'};
	my $dry_run     = $params->{'overwrite'};
	
	my $request = Slim::Control::Request::executeRequest(undef, [
					'playlists', 
					'rename', 
					'playlist_id:' . $playlist_id,
					'newname:' . $newName,
					'dry_run:' . $dry_run]);

	if (blessed($request)) {
	
		if ($request->getResult('overwritten_playlist_id') && !$params->{'overwrite'}) {

			$params->{'RENAME_WARNING'} = 1;

		} elsif (!$params->{'overwrite'}) {

			my $request = Slim::Control::Request::executeRequest(undef, [
							'playlists', 
							'rename', 
							'playlist_id:' . $playlist_id,
							'newname:' . $newName]);
		}
		
		$params->{'level'}       = 1;
		$params->{'playlist.id'} = $playlist_id;
	}

	return Slim::Web::Pages::BrowseDB::browsedb($client, $params);
}

sub deletePlaylist {
	my ($client, $params) = @_;
	
	my $playlist_id = $params->{'playlist.id'};
	my $playlistObj = Slim::Schema->find('Playlist', $playlist_id);

	$params->{'level'} = 0;

	# Warn the user if the playlist already exists.
	if (blessed($playlistObj) && !$params->{'confirm'}) {

		$params->{'DELETE_WARNING'} = 1;
		$params->{'level'}          = 1;
		$params->{'playlist.id'}    = $playlist_id;

	} elsif (blessed($playlistObj)) {
	
		Slim::Control::Request::executeRequest(undef, 
			['playlists', 'delete', 'playlist_id:' . $playlist_id]);

		$playlistObj = undef;
	}

	# Send the user off to the top level browse playlists
	$params->{'hierarchy'} = 'playlist,playlistTrack';

	return Slim::Web::Pages::BrowseDB::browsedb($client, $params);
}


1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
