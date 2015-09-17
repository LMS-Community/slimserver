package Slim::Web::Pages::EditPlaylist;

# Logitech Media Server Copyright 2001-2011 Logitech.
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
use Slim::Web::Pages;

sub init {
	Slim::Web::Pages->addPageFunction(qr/^edit_playlist\.(?:htm|xml)/, \&editplaylist);
}

sub editplaylist {
	my ($client, $params) = @_;

	my $playlist_id = $params->{'playlist_id'};
	$params->{'playlist.id'} = $playlist_id if (defined $playlist_id);

	# This is a dispatcher to parts of the playlist editing
	if ($params->{'saveCurrentPlaylist'}) {

		return saveCurrentPlaylist(@_);

	} elsif ($params->{'renamePlaylist'}) {

		return renamePlaylist(@_);

	} elsif ($params->{'deletePlaylist'}) {

		return deletePlaylist(@_);
	}

	# 0 base
	my $itemPos = ($params->{'itempos'} || 0);

	my $changed = 0;

	if ($params->{'delete'}) {

		Slim::Control::Request::executeRequest(undef, 
			['playlists', 'edit', 'cmd:delete', 
			'playlist_id:' . $playlist_id,
			'index:' . $itemPos]);

	} elsif (defined($params->{'form_url'})) {

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

	return browsePlaylist(@_);
}

sub saveCurrentPlaylist {
	my ($client, $params) = @_;

	if (defined $client && Slim::Player::Playlist::count($client)) {

		my $title = $client->currentPlaylist ? 
				Slim::Music::Info::standardTitle($client, $client->currentPlaylist) : 
					$client->string('UNTITLED');

		if ($title ne Slim::Utils::Misc::cleanupFilename($title)) {

			$params->{'warning'} = 'FILENAME_WARNING';

		} else {
			
			# Changed by Fred to fix the issue of getting the playlist object
			# by setting $p1 to it, which was messing up callback and the CLI.
	
			my $request = Slim::Control::Request::executeRequest($client, ['playlist', 'save', $title]);
	
			if (defined $request) {
			
				$params->{'playlist.id'} = $request->getResult('__playlist_id');
				
				if ($request->getResult('writeError')) {
					
					$params->{'warning'} = $client->string('PLAYLIST_CANT_WRITE');
				
				}
			}
	
		}

		# Don't add this back to the breadcrumbs
		delete $params->{'saveCurrentPlaylist'};
	
		return browsePlaylist(@_);
		
	} else {

		return browsePlaylists(@_);
	}

}

sub renamePlaylist {
	my ($client, $params) = @_;

	my $newName = $params->{'newname'};
	if ($newName ne Slim::Utils::Misc::cleanupFilename($newName)) {
			
		$params->{'warning'} = 'FILENAME_WARNING';

	} else {
			
		my $playlist_id = $params->{'playlist_id'};
		my $dry_run     = !$params->{'overwrite'};
	
		my $request = Slim::Control::Request::executeRequest(undef, [
						'playlists', 
						'rename', 
						'playlist_id:' . $playlist_id,
						'newname:' . $newName,
						'dry_run:' . $dry_run]);
	
		if (blessed($request) && $request->getResult('overwritten_playlist_id') && !$params->{'overwrite'}) {
	
			$params->{'warning'} = 'RENAME_WARNING';
	
		}
		
		else {
	
			my $request = Slim::Control::Request::executeRequest(undef, [
							'playlists', 
							'rename', 
							'playlist_id:' . $playlist_id,
							'newname:' . $newName]);
							
			if ($request && $request->getResult('writeError')) {
				
				$params->{'warning'} = $client->string('PLAYLIST_CANT_WRITE');
			
			}

		}
	}

	return browsePlaylist(@_);
}

sub deletePlaylist {
	my ($client, $params) = @_;
	
	my $playlist_id = $params->{'playlist_id'};
	my $playlistObj = Slim::Schema->find('Playlist', $playlist_id);

	# Warn the user if the playlist already exists.
	if (blessed($playlistObj) && !$params->{'confirm'}) {

		$params->{'warning'}     = 'DELETE_WARNING';
		$params->{'playlist.id'} = $playlist_id;

	} elsif (blessed($playlistObj)) {
	
		my $request = Slim::Control::Request::executeRequest(undef, 
			['playlists', 'delete', 'playlist_id:' . $playlist_id]);

		if ($request && $request->getResult('writeError')) {
			
			$params->{'warning'} = $client->string('PLAYLIST_CANT_WRITE');
			
		} else {
			# don't show the playlist name field any more
			delete $params->{'playlist_id'};

			# Send the user off to the top level browse playlists
			return browsePlaylists(@_);
		}

		$playlistObj = undef;
	}

	return browsePlaylist(@_);
}

sub browsePlaylists {
	my ($client, $params) = @_;
	my $allArgs = \@_;

	my @verbs = ('browselibrary', 'items', 'feedMode:1', 'mode:playlists');
	
	my $callback = sub {
		my ($client, $feed) = @_;
		Slim::Web::XMLBrowser->handleWebIndex( {
			client  => $client,
			feed    => $feed,
			timeout => 35,
			args    => $allArgs,
			title   => 'SAVED_PLAYLISTS',
			path    => 'clixmlbrowser/clicmd=browselibrary+items&linktitle=SAVED_PLAYLISTS&mode=playlists/',
		} );
	};

	# execute CLI command
	my $proxiedRequest = Slim::Control::Request::executeRequest( $client, ['browselibrary', 'items', 'feedMode:1', 'mode:playlists'] );
		
	# wrap async requests
	if ( $proxiedRequest->isStatusProcessing ) {			
		$proxiedRequest->callbackFunction( sub { $callback->($client, $_[0]->getResults); } );
	} else {
		$callback->($client, $proxiedRequest->getResults);
	}
}

sub browsePlaylist {
	my ($client, $params) = @_;
	my $allArgs = \@_;

	my $playlist_id = $params->{'playlist.id'};
	
	my $title;
	my $obj = Slim::Schema->find('Playlist', $playlist_id);
	$title = string('PLAYLIST') . ' (' . $obj->name . ')' if $obj;
	
	my @verbs = ('browselibrary', 'items', 'feedMode:1', 'mode:playlistTracks', 'playlist_id:' . $playlist_id);
	
	my $callback = sub {
		my ($client, $feed) = @_;
		Slim::Web::XMLBrowser->handleWebIndex( {
			client  => $client,
			feed    => $feed,
			timeout => 35,
			args    => $allArgs,
			title   => $title,
			path    => sprintf('clixmlbrowser/clicmd=browselibrary+items&linktitle=%s&mode=playlistTracks&playlist_id=%s/', 
							Slim::Utils::Misc::escape($title),
							$playlist_id),
		} );
	};

	# execute CLI command
	my $proxiedRequest = Slim::Control::Request::executeRequest( $client, \@verbs );
		
	# wrap async requests
	if ( $proxiedRequest->isStatusProcessing ) {			
		$proxiedRequest->callbackFunction( sub { $callback->($client, $_[0]->getResults); } );
	} else {
		$callback->($client, $proxiedRequest->getResults);
	}
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
