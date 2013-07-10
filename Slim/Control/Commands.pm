package Slim::Control::Commands;

# $Id: Commands.pm 5121 2005-11-09 17:07:36Z dsully $
#
# Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

################################################################################

=head1 NAME

Slim::Control::Commands

=head1 DESCRIPTION

Implements most server commands and is designed to be exclusively called
through Request.pm and the mechanisms it defines.

=cut

use strict;

use Scalar::Util qw(blessed);
use File::Spec::Functions qw(catfile);
use File::Basename qw(basename);
use Digest::MD5 qw(md5_hex);
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Scanner;
use Slim::Utils::Prefs;
use Slim::Utils::OSDetect;

if ( !main::SLIM_SERVICE ) {
	require Slim::Utils::Scanner::Local;
	
	if (main::IMAGE || main::VIDEO) {
		require Slim::Utils::Scanner::LMS;
	}
}

{
	if (main::LOCAL_PLAYERS) {
		require Slim::Control::LocalPlayers::Commands;
	}
}

my $log = logger('control.command');

my $prefs = preferences('server');


sub abortScanCommand {
	my $request = shift;

	Slim::Music::Import->abortScan();
	
	$request->setStatusDone();
}


sub clientForgetCommand {
	my $request = shift;

	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotCommand([['client'], ['forget']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();
	
	# Bug 6508
	# Can have a timing race with client reconnecting before this command get executed
	if ($client->connected()) {
		main::INFOLOG && $log->info($client->id . ': not forgetting as connected again');
		return;
	}
	
	$client->controller()->playerInactive($client);

	$client->forgetClient();
	
	$request->setStatusDone();
}


sub debugCommand {
	my $request = shift;

	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotCommand([['debug']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $category = $request->getParam('_debugflag');
	my $newValue = $request->getParam('_newvalue');

	if ( !defined $category || !Slim::Utils::Log->isValidCategory($category) ) {

		$request->setStatusBadParams();
		return;
	}
	
	my $ret = Slim::Utils::Log->setLogLevelForCategory($category, $newValue);

	if ($ret == 0) {

		$request->setStatusBadParams();
		return;
	}

	# If the above setLogLevelForCategory has returned true, we need to reinitialize.
	if ($ret == 1) {

		Slim::Utils::Log->reInit;
	}

	$request->setStatusDone();
}

sub loggingCommand {
	my $request = shift;
	
	# check this is the correct command.
	if ($request->isNotCommand([['logging']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $group = uc( $request->getParam('group') );
	
	if ($group && Slim::Utils::Log->logLevels($group)) {
		Slim::Utils::Log->setLogGroup($group, $request->getParam('persist'));
	}
	else {
		$request->setStatusBadParams();
		return;
	}
	
	$request->setStatusDone();
}

sub playlistXalbumCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['playalbum', 'loadalbum', 'addalbum', 'insertalbum', 'deletealbum']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $cmd      = $request->getRequest(1);
	my $genre    = $request->getParam('_genre'); #p2
	my $artist   = $request->getParam('_artist');#p3
	my $album    = $request->getParam('_album'); #p4
	my $title    = $request->getParam('_title'); #p5

	# Pass to parseSearchTerms
	my $find     = {};

	if (specified($genre)) {

		$find->{'genre.name'} = _playlistXalbum_singletonRef($genre);
	}

	if (specified($artist)) {

		$find->{'contributor.name'} = _playlistXalbum_singletonRef($artist);
	}

	if (specified($album)) {

		$find->{'album.title'} = _playlistXalbum_singletonRef($album);
	}

	if (specified($title)) {

		$find->{'me.title'} = _playlistXalbum_singletonRef($title);
	}

	my @results = _playlistXtracksCommand_parseSearchTerms($client, $find);

	$cmd =~ s/album/tracks/;

	Slim::Control::Request::executeRequest($client, ['playlist', $cmd, 'listRef', \@results],
		sub {
			$request->setRawResults($_[0]->getResults());
			$request->addResult('count', scalar(@results));
			$request->setStatusDone();
		}
	);
	
	$request->setStatusProcessing() unless $request->isStatusDone();
}


sub playlistXitemCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['add', 'append', 'insert', 'insertlist', 'load', 'play', 'resume']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $cmd      = $request->getRequest(1); #p1
	my $item     = $request->getParam('_item'); #p2
	my $title    = $request->getParam('_title') || ''; #p3
	my $fadeIn   = $cmd eq 'play' ? $request->getParam('_fadein') : undef;
	my $noplay       = $request->getParam('noplay') || 0; # optional tagged param, used for resuming playlist after preview
	my $wipePlaylist = $request->getParam('wipePlaylist') || 0; #optional tagged param, used for removing playlist after resume
	my $icon     = $request->getParam('icon');	# optional tagged param, used for popups

	if (!defined $item) {
		$request->setStatusBadParams();
		return;
	}

	main::INFOLOG && $log->info("cmd: $cmd, item: $item, title: $title, fadeIn: ", ($fadeIn ? $fadeIn : 'undef'));

	my $jumpToIndex = $request->getParam('play_index'); # This should be undef (by default) - see bug 2085
	my $results;
	
	if ( main::SLIM_SERVICE ) {
		# If the item is a base64+storable string, decode it.
		# This is used for sending multiple URLs from the web
		# XXX: JSON::XS is faster than Storable
		use MIME::Base64 qw(decode_base64);
		use Storable qw(thaw);
		
		if ( !ref $item && $item =~ /^base64:/ ) {
			$item =~ s/^base64://;
			$item = thaw( decode_base64( $item ) );
		}
	}
	
	# If we're playing a list of URLs (from XMLBrowser), only work on the first item
	my $list;
	if ( ref $item eq 'ARRAY' ) {
		
		# If in shuffle mode, we need to shuffle the list of items as
		# soon as we get it
		if ( Slim::Player::Playlist::shuffle($client) == 1 ) {
			Slim::Player::Playlist::fischer_yates_shuffle($item);
		}
		
		$list = $item;
		$item = shift @{$item};
	}

	my $url  = blessed($item) ? $item->url : $item;

	# Strip off leading and trailing whitespace. PEBKAC
	$url =~ s/^\s*//;
	$url =~ s/\s*$//;

	main::INFOLOG && $log->info("url: $url");

	my $path = $url;
	
	# Set title if supplied
	if ( main::SERVICES && $title ) {
		Slim::Music::Info::setTitle( $url, $title );
		Slim::Music::Info::setCurrentTitle( $url, $title );
	}

	# check whether url is potentially for some sort of db entry, if so pass to playlistXtracksCommand
	# But not for or local file:// URLs,  and this may mean 
	# rescanning items already in the database but still allows playlist and other favorites to be played
	
	# XXX: hardcoding these protocols isn't the best way to do this. We should have a flag in ProtocolHandler to get this list
	if ($path =~ /^db:|^itunesplaylist:|^musicipplaylist:/) {

		if (my @tracks = _playlistXtracksCommand_parseDbItem($client, $path)) {
			$client->execute(['playlist', $cmd . 'tracks' , 'listRef', \@tracks, $fadeIn],
				sub {
					$request->setRawResults($_[0]->getResults());
					$request->addResult('count', scalar(@tracks));
					$request->setStatusDone();
				}
			);
			
			$request->setStatusProcessing() unless $request->isStatusDone();
			return;
		}
	}

	# correct the path
	# this only seems to be useful for playlists?
	if (!Slim::Music::Info::isRemoteURL($path) && !-e $path && !(Slim::Music::Info::isPlaylistURL($path))) {

		my $easypath = catfile(Slim::Utils::Misc::getPlaylistDir(), basename($url) . ".m3u");

		if (-e $easypath) {

			$path = $easypath;

		} else {

			$easypath = catfile(Slim::Utils::Misc::getPlaylistDir(), basename($url) . ".pls");

			if (-e $easypath) {
				$path = $easypath;
			}
		}
	}

	# Un-escape URI that have been escaped again.
	if (Slim::Music::Info::isRemoteURL($path) && $path =~ /%3A%2F%2F/) {

		$path = Slim::Utils::Misc::unescape($path);
	}

	main::INFOLOG && $log->info("path: $path");
	
	# bug 14760 - just continue where we were if what we are about to play is the
	# same as the single thing we are already playing
	if ( main::LOCAL_PLAYERS
		&& $cmd =~ /^(play|load)$/
		&& Slim::Player::Playlist::count($client) == 1
		&& $client->playingSong()	
		&& $path eq $client->playingSong()->track()->url()
		&& !$noplay
		&& $client->isLocalPlayer )
	{
		# Bug 16154: use more-precise control measures
		# so that we only leave it playing if fully in Playing state already.
		if ( $client->isPaused() ) {
			Slim::Player::Source::playmode($client, 'resume', undef, undef, $fadeIn);
		} elsif ( !$client->isPlaying('really') ) {
			Slim::Player::Source::playmode($client, 'play', undef, undef, $fadeIn);
		}
		
		playlistXitemCommand_done($client, $request, $path);
		
		main::DEBUGLOG && $log->debug("done.");
		
		return;
	}

	my $fixedPath = Slim::Utils::Misc::fixPath($path);

	if (main::LOCAL_PLAYERS) {
		if ($cmd =~ /^(play|load|resume)$/) {
	
			Slim::Player::Playlist::stopAndClear($client);
	
			$client->currentPlaylist( $fixedPath );
	
			if ( main::INFOLOG && $log->is_info ) {
				$log->info("currentPlaylist:" .  $fixedPath );
			}
	
			$client->currentPlaylistModified(0);
	
		} elsif ($cmd =~ /^(add|append)$/) {
	
			$client->currentPlaylist( $fixedPath );
			$client->currentPlaylistModified(1);
	
			if ( main::INFOLOG && $log->is_info ) {
				$log->info("currentPlaylist:" .  $fixedPath );
			}
	
		} else {
	
			$client->currentPlaylistModified(1);
		}
	}
	
	if (!Slim::Music::Info::isRemoteURL( $fixedPath ) && Slim::Music::Info::isFileURL( $fixedPath ) ) {

		$path = Slim::Utils::Misc::pathFromFileURL($fixedPath);

		main::INFOLOG && $log->info("path: $path");
	}

	if ($cmd =~ /^(play|load)$/) { 

		$jumpToIndex = 0 if !defined $jumpToIndex;

	} elsif ($cmd eq "resume" && Slim::Music::Info::isM3U($path)) {

		$jumpToIndex = Slim::Formats::Playlists::M3U->readCurTrackForM3U($path);

	} else {
		
		$jumpToIndex = undef;
		
	}

	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("jumpToIndex: %s", (defined $jumpToIndex ? $jumpToIndex : 'undef')));
	}

	my @infoTags = (Slim::Music::Info::title($path) || $path);
	push @infoTags, $icon;

	if ($cmd =~ /^(insert|insertlist)$/) {

		my @dirItems     = ();

		Slim::Utils::Scanner->scanPathOrURL({
			'url'      => $path,
			'listRef'  => \@dirItems,
			'client'   => $client,
			'callback' => sub {
				my $foundItems = shift;

				Slim::Player::Playlist::addTracks($client, $foundItems, -1, undef, $request, @infoTags,
					sub {
						if (my $error = shift) {
							$request->addResult(error => $error);
						}
						
						_insert_done($client);

						playlistXitemCommand_done( $client, $request, $path );
					}
				);
			},
		});

	} else {
		
		Slim::Utils::Scanner->scanPathOrURL({
			'url'      => $path,
			'listRef'  => $client->isLocalPlayer ? Slim::Player::Playlist::playList($client) : undef,		# where is listRef being used anyway?
			'client'   => $client,
			'cmd'      => $cmd,
			'callback' => sub {
				my ( $foundItems, $error ) = @_;
				
				# If we are playing a list of URLs, add the other items now
				my $noShuffle = 0;
				if ( ref $list eq 'ARRAY' ) {
					push @{$foundItems}, @{$list};
					
					# If we had a list of tracks, we already shuffled above
					$noShuffle = 1;
				}

				Slim::Player::Playlist::addTracks($client, $foundItems, $cmd eq 'add' ? -3 : -2,
					$jumpToIndex, $request, @infoTags,
					sub {
						if (my $error = shift) {
							$request->addResult(error => $error);
						}
						
						_playlistXitem_load_done(
							$client,
							$jumpToIndex,
							$request,
							Slim::Utils::Misc::fixPath($path),
							$error,
							$noShuffle,
							$fadeIn,
							$noplay,
							$wipePlaylist,
						);

						playlistXitemCommand_done( $client, $request, $path );
					}
				);
			},
		});

	}

	if (!$request->isStatusDone()) {
		$request->setStatusProcessing();
	}

	main::DEBUGLOG && $log->debug("done.");
}

# Called after insert/load async callbacks are finished
sub playlistXitemCommand_done {
	my ( $client, $request, $path ) = @_;

	# Update the parameter item with the correct path
	# Not sure anyone depends on this behaviour...
	$request->addParam('_item', $path);

	$client->isLocalPlayer && $client->currentPlaylistUpdateTime(Time::HiRes::time());

	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();

	$request->setStatusDone();
}

sub playlistXtracksCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['playtracks', 'loadtracks', 'addtracks', 'inserttracks', 'deletetracks']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client      = $request->client();
	my $cmd         = $request->getRequest(1); #p1
	my $what        = $request->getParam('_what'); #p2
	my $listref     = $request->getParam('_listref');#p3
	my $fadeIn      = $request->getParam('_fadein');#p4
	my $jumpToIndex = $request->getParam('_index');#p5, by default undef - see bug 2085

	if (!defined $what) {
		$request->setStatusBadParams();
		return;
	}

	my $load   = ($cmd eq 'loadtracks' || $cmd eq 'playtracks');
	my $insert = ($cmd eq 'inserttracks');
	my $add    = ($cmd eq 'addtracks');
	my $delete = ($cmd eq 'deletetracks');

	# if loading, start by clearing it all...
	if ($load) {
		Slim::Player::Playlist::stopAndClear($client);
	}

	# parse the param
	my @tracks = ();

	if ($what =~ /urllist/i) {
		@tracks = _playlistXtracksCommand_constructTrackList($client, $what, $listref);
		
	} elsif ($what =~ /listRef/i) {
		@tracks = _playlistXtracksCommand_parseListRef($client, $what, $listref);

	} elsif ($what =~ /searchRef/i) {

		@tracks = _playlistXtracksCommand_parseSearchRef($client, $what, $listref);

	} elsif ($what =~ /dataRef/i) {

		@tracks = _playlistXtracksCommand_parseDataRef($client, $what, $listref);

	} else {

		@tracks = _playlistXtracksCommand_parseSearchTerms($client, $what);
	}

	my $size;

	my $callback = sub {
		if (my $error = shift) {
			$request->addResult(error => $error);
		}
		
		if ($insert) {
			_insert_done($client);
			$request->addResult(index => (Slim::Player::Source::streamingSongIndex($client)+1));
		}
	
		if ($delete) {
			Slim::Player::Playlist::removeMultipleTracks($client, \@tracks);
		}
	
		if (main::LOCAL_PLAYERS && ($load || $add) && $client->isLocalPlayer) {
			Slim::Player::Playlist::reshuffle($client, $load ? 1 : undef);
			$request->addResult(index => (Slim::Player::Playlist::count($client) - $size));	# does not mean much if shuffled
		}
		
		$request->addResult(count => scalar @tracks);
	
		if (main::LOCAL_PLAYERS && $load && $client->isLocalPlayer) {
			# The user may have stopped in the middle of a
			# saved playlist - resume if we can. Bug 1582
			my $playlistObj = $client->currentPlaylist();
	
			if ($playlistObj && ref($playlistObj) && $playlistObj->content_type =~ /^(?:ssp|m3u)$/) {
	
				if (!defined $jumpToIndex && !Slim::Player::Playlist::shuffle($client)) {
					$jumpToIndex = Slim::Formats::Playlists::M3U->readCurTrackForM3U( $client->currentPlaylist->path );
				}
	
				# And set a callback so that we can
				# update CURTRACK when the song changes.
				Slim::Control::Request::subscribe(\&Slim::Player::Playlist::newSongPlaylistCallback, [['playlist'], ['newsong']]);
			}
			# bug 14662: Playing a specific track while track shuffle is enabled will play another track
			elsif (defined $jumpToIndex && Slim::Player::Playlist::shuffle($client)) {
				my $shuffleList = Slim::Player::Playlist::shuffleList($client);
				for (my $i = 0; $i < scalar @$shuffleList; $i++) {
					if ($shuffleList->[$i] == $jumpToIndex) {
						$jumpToIndex = $i;
						last;
					}
				}
			}
			
			$client->execute(['playlist', 'jump', $jumpToIndex, $fadeIn]);
			
			# Reshuffle (again) to get playing song or album at start of list
			Slim::Player::Playlist::reshuffle($client) if $load && defined $jumpToIndex && Slim::Player::Playlist::shuffle($client);
			
			$client->currentPlaylistModified(0);
		}
		
		if (main::LOCAL_PLAYERS) {
			if ($add || $insert || $delete) {
				$client->currentPlaylistModified(1);
			}
		
			if ($load || $add || $insert || $delete) {
				$client->currentPlaylistUpdateTime(Time::HiRes::time());
			}
		}
	
		$request->setStatusDone();
	};
	
	# add or remove the found songs
	if ($load || $add || $insert) {
		$size = Slim::Player::Playlist::addTracks($client, \@tracks, $insert ? -1 : $add ? -3 : -2,
			$load ? ($jumpToIndex || 0) : undef, $request,
			$request->getParam('infoText'), $request->getParam('infoIcon'),
			$callback);
	} else {
		$callback->();
	}
}

sub playlistcontrolCommand {
	my $request = shift;
	
	main::INFOLOG && $log->info("Begin Function");

	# check this is the correct command.
	if ($request->isNotCommand([['playlistcontrol']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client              = $request->client();
	my $cmd                 = $request->getParam('cmd');
	my $jumpIndex           = $request->getParam('play_index');

	if (Slim::Music::Import->stillScanning()) {
		$request->addResult('rescan', "1");
	}

	if ($request->paramUndefinedOrNotOneOf($cmd, ['load', 'insert', 'add', 'delete'])) {
		$request->setStatusBadParams();
		return;
	}

	my $load   = ($cmd eq 'load');
	my $insert = ($cmd eq 'insert');
	my $add    = ($cmd eq 'add');
	my $delete = ($cmd eq 'delete');
	

	# shortcut to playlist $cmd url if given a folder_id...
	# the acrobatics it does are too risky to replicate
	if (defined(my $folderId = $request->getParam('folder_id'))) {
		
		# unfortunately playlist delete is not supported
		if ($delete) {
			$request->setStatusBadParams();
			return;
		}
		
		my $folder = Slim::Schema->find('Track', $folderId);
		
		# make sure it's a folder
		if (!blessed($folder) || !$folder->can('url') || !$folder->can('content_type') || $folder->content_type() ne 'dir') {
			$request->setStatusBadParams();
			return;
		}

		Slim::Control::Request::executeRequest(
			$client,
			['playlist', $cmd, $folder->url(), ($load && $jumpIndex ? 'play_index:' . $jumpIndex : undef) ],
			sub {
				$request->setRawResults($_[0]->getResults());
				$request->addResult('count', 1);
				$request->setStatusDone();
			}
		);
		
		$request->setStatusProcessing() unless $request->isStatusDone();
		return;
	}

	# if loading, first stop & clear everything
	if ($load) {
		Slim::Player::Playlist::stopAndClear($client);
	}

	# find the songs
	my @tracks = ();

	# info line and artwork to display if sucessful
	my $info;
	my $artwork;

	# Bug: 2373 - allow the user to specify a playlist name
	my $playlist_id = 0;

	if (defined(my $playlist_name = $request->getParam('playlist_name'))) {

		my $playlistObj = Slim::Schema->single('Playlist', { 'title' => $playlist_name });

		if (blessed($playlistObj)) {

			$playlist_id = $playlistObj->id;
		}
	}

	$playlist_id ||= $request->getParam('playlist_id');

	if ($playlist_id) {

		# Special case...
		my $playlist = Slim::Schema->find('Playlist', $playlist_id);

		if (blessed($playlist) && $playlist->can('tracks')) {

			$cmd .= "tracks";

			Slim::Control::Request::executeRequest(
				$client,
				['playlist', $cmd, 'playlist.id=' . $playlist_id, undef, undef, $jumpIndex, 'infoText:' . $playlist->title],
				sub {
					$request->setRawResults($_[0]->getResults());
					$request->addResult('count', $playlist->tracks->count());
					$request->setStatusDone();
				}
			);

			$request->setStatusProcessing() unless $request->isStatusDone();
			return;
		}

	} elsif (defined(my $track_id_list = $request->getParam('track_id'))) {

		# split on commas
		my @track_ids = split(/,/, $track_id_list);
		
		# keep the order
		my %track_ids_order;
		my $i = 0;
		for my $id (@track_ids) {
			$track_ids_order{$id} = $i++;
		}

		# find the tracks
		my @rawtracks = Slim::Schema->search('Track', { 'id' => { 'in' => \@track_ids } })->all;
		
		# sort them back!
		@tracks = sort { $track_ids_order{$a->id()} <=> $track_ids_order{$b->id()} } @rawtracks;

		$artwork = $tracks[0]->album->artwork || 0 if scalar @tracks == 1;

	} else {

		# rather than re-invent the wheel, use _playlistXtracksCommand_parseSearchTerms
		
		my $what = {};
		
		if (defined(my $genre_id = $request->getParam('genre_id'))) {
			$what->{'genre.id'} = $genre_id;
			$info    = Slim::Schema->find('Genre', $genre_id)->name;
		}

		if (defined(my $artist_id = $request->getParam('artist_id'))) {
			$what->{'contributor.id'} = $artist_id;
			$info    = Slim::Schema->find('Contributor', $artist_id)->name;
		}

		if (defined(my $album_id = $request->getParam('album_id'))) {
			$what->{'album.id'} = $album_id;
			my $album = Slim::Schema->find('Album', $album_id);
			$info    = $album->title;
			$artwork = $album->artwork || 0;
		}

		if (defined(my $year = $request->getParam('year'))) {
			$what->{'year.id'} = $year;
			$info    = $year;
		}

		# Fred: form year_id DEPRECATED in 7.0
		if (defined(my $year_id = $request->getParam('year_id'))) {

			$what->{'year.id'} = $year_id;
		}
		
		@tracks = _playlistXtracksCommand_parseSearchTerms($client, $what);
	}

	# don't call Xtracks if we got no songs
	if (@tracks) {
		
		my @infoTags;

		if ($load || $add || $insert) {
			$info ||= $tracks[0]->title;
			@infoTags = ('infoText:' . $info);
			push @infoTags, "infoIcon:$artwork" if $artwork;
		}

		$cmd .= "tracks";

		Slim::Control::Request::executeRequest(
			$client, ['playlist', $cmd, 'listRef', \@tracks, undef, $jumpIndex, @infoTags],
			sub {
				$request->setRawResults($_[0]->getResults());
				$request->addResult('count', scalar(@tracks));
				$request->setStatusDone();
			}
		);
		
		$request->setStatusProcessing() unless $request->isStatusDone();
	} else {
		$request->addResult('count', 0);
		$request->setStatusDone();
	}
}


sub playlistsEditCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlists'], ['edit']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $playlist_id = $request->getParam('playlist_id');
	my $cmd = $request->getParam('cmd');
	my $itemPos = $request->getParam('index');
	my $newPos = $request->getParam('toindex');

	if ($request->paramUndefinedOrNotOneOf($cmd, ['up', 'down', 'delete', 'add', 'move'])) {
		$request->setStatusBadParams();
		return;
	}

	if (!$playlist_id) {
		$request->setStatusBadParams();
		return;
	}

	if (!defined($itemPos) && $cmd ne 'add') {
		$request->setStatusBadParams();
		return;
	}

	if (!defined($newPos) && $cmd eq 'move') {
		$request->setStatusBadParams();
		return;
	}

	# transform the playlist id in a playlist obj
	my $playlist = Slim::Schema->find('Playlist', $playlist_id);

	if (!blessed($playlist)) {
		$request->setStatusBadParams();
		return;
	}
	
	# now perform the operation
	my @items   = $playlist->tracks;
	my $changed = 0;

	# Once we move to using DBIx::Class::Ordered, most of this code can go away.
	if ($cmd eq 'delete') {

		splice(@items, $itemPos, 1);

		$changed = 1;

	} elsif ($cmd eq 'up') {

		# Up function - Move entry up in list
		if ($itemPos != 0) {

			my $item = $items[$itemPos];
			$items[$itemPos] = $items[$itemPos - 1];
			$items[$itemPos - 1] = $item;

			$changed = 1;
		}

	} elsif ($cmd eq 'down') {

		# Down function - Move entry down in list
		if ($itemPos != scalar(@items) - 1) {

			my $item = $items[$itemPos];
			$items[$itemPos] = $items[$itemPos + 1];
			$items[$itemPos + 1] = $item;

			$changed = 1;
		}

	} elsif ($cmd eq 'move') {

		if ($itemPos != $newPos && $itemPos < scalar(@items) && $itemPos >= 0 
			&& $newPos < scalar(@items)	&& $newPos >= 0) {

			# extract the item to be moved
			my $item = splice @items, $itemPos, 1;
			my @tail = splice @items, ($newPos);
			push @items, $item, @tail;

			$changed = 1;
		}
	
	} elsif ($cmd eq 'add') {

		# Add function - Add entry it not already in list
		my $found = 0;
		my $title = $request->getParam('title');
		my $url   = $request->getParam('url');

		if ($url) {

			my $playlistTrack = Slim::Schema->updateOrCreate({
				'url'      => $url,
				'readTags' => 1,
				'commit'   => 1,
			});

			for my $item (@items) {

				if ($item->id eq $playlistTrack->id) {

					$found = 1;
					last;
				}
			}

			# XXXX - call ->appendTracks() once this is reworked.
			if ($found == 0) {
				push @items, $playlistTrack;
			}

			if ($title) {
				$playlistTrack->title($title);
				$playlistTrack->titlesort(Slim::Utils::Text::ignoreCaseArticles($title));
				$playlistTrack->titlesearch(Slim::Utils::Text::ignoreCaseArticles($title, 1));
			}

			$playlistTrack->update;

			$changed = 1;
		}
	}

	if ($changed) {

		my $log = logger('player.playlist');

		main::INFOLOG && $log->info("Playlist has changed via editing - saving new list of tracks.");

		$playlist->setTracks(\@items);
		$playlist->update;

		if ($playlist->content_type eq 'ssp') {

			main::INFOLOG && $log->info("Writing out playlist to disk..");

			Slim::Formats::Playlists->writeList(\@items, undef, $playlist->url);
		}
		
		$playlist = undef;

		Slim::Schema->forceCommit;
		Slim::Schema->wipeCaches;
	}

	$request->setStatusDone();
}


sub playlistsDeleteCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlists'], ['delete']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $playlist_id = $request->getParam('playlist_id');

	if (!$playlist_id) {
		$request->setStatusBadParams();
		return;
	}

	# transform the playlist id in a playlist obj
	my $playlistObj = Slim::Schema->find('Playlist', $playlist_id);

	if (!blessed($playlistObj) || !$playlistObj->isPlaylist()) {
		$request->setStatusBadParams();
		return;
	}

	# show feedback if this action came from jive cometd session
	if ($request->source && $request->source =~ /\/slim\/request/) {
		$request->client->showBriefly({
			'jive' => {
				'text'    => [	
					$request->string('JIVE_DELETE_PLAYLIST', $playlistObj->name)
				],
			},
		});
	}

	_wipePlaylist($playlistObj);

	$request->setStatusDone();
}


sub _wipePlaylist {
	my $playlistObj = shift;
	
	if ( ! ( blessed($playlistObj) && $playlistObj->isPlaylist() ) ) {
		$log->error('PlaylistObj not right for this sub: ', $playlistObj);
		$log->error('PlaylistObj not right for this sub: ', $playlistObj->isPlaylist() );
		return 0;
	}

	Slim::Player::Playlist::removePlaylistFromDisk($playlistObj);
	
	# Do a fast delete, and then commit it.
	$playlistObj->setTracks([]);
	$playlistObj->delete;

	$playlistObj = undef;

	Slim::Schema->forceCommit;

}


sub playlistsNewCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlists'], ['new']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# can't do much without playlistdir!
	if (!Slim::Utils::Misc::getPlaylistDir()) {
		$request->setStatusBadConfig();
		return;
	}

	# get the parameters
	my $title  = $request->getParam('name');
	$title = Slim::Utils::Misc::cleanupFilename($title);

	my $titlesort = Slim::Utils::Text::ignoreCaseArticles($title);

	# create the playlist URL
	my $newUrl   = Slim::Utils::Misc::fileURLFromPath(
		catfile(Slim::Utils::Misc::getPlaylistDir(), Slim::Utils::Unicode::encode_locale($title) . '.m3u')
	);

	my $existingPlaylist = Slim::Schema->objectForUrl({
		'url' => $newUrl,
		'playlist' => 1,
	});

	if (blessed($existingPlaylist)) {

		# the name already exists!
		$request->addResult("overwritten_playlist_id", $existingPlaylist->id());
	}
	else {

		my $playlistObj = Slim::Schema->updateOrCreate({

			'url' => $newUrl,
			'playlist' => 1,

			'attributes' => {
				'TITLE' => $title,
				'CT'    => 'ssp',
			},
		});

		$playlistObj->set_column('titlesort', $titlesort);
		$playlistObj->update;

		Slim::Schema->forceCommit;

		Slim::Player::Playlist::scheduleWriteOfPlaylist(undef, $playlistObj);

		$request->addResult('playlist_id', $playlistObj->id);
	}
	
	$request->setStatusDone();
}


sub playlistsRenameCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlists'], ['rename']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $playlist_id = $request->getParam('playlist_id');
	my $newName = $request->getParam('newname');
	my $dry_run = $request->getParam('dry_run');

	if (!$playlist_id || !$newName) {
		$request->setStatusBadParams();
		return;
	}

	# transform the playlist id in a playlist obj
	my $playlistObj = Slim::Schema->find('Playlist', $playlist_id);

	if (!blessed($playlistObj)) {
		$request->setStatusBadParams();
		return;
	}

	$newName = Slim::Utils::Misc::cleanupFilename($newName);

	# now perform the operation
	
	my $newUrl   = Slim::Utils::Misc::fileURLFromPath(
		catfile(Slim::Utils::Misc::getPlaylistDir(), Slim::Utils::Unicode::encode_locale($newName) . '.m3u')
	);

	my $existingPlaylist = Slim::Schema->objectForUrl({
		'url' => $newUrl,
		'playlist' => 1,
	});

	if (blessed($existingPlaylist)) {

		$request->addResult("overwritten_playlist_id", $existingPlaylist->id());
	}
	
	if (!$dry_run) {

		if (blessed($existingPlaylist) && $existingPlaylist->id ne $playlistObj->id) {

			Slim::Control::Request::executeRequest(undef, ['playlists', 'delete', 'playlist_id:' . $existingPlaylist->id]);

			$existingPlaylist = undef;
		}
		
		my $index = Slim::Formats::Playlists::M3U->readCurTrackForM3U( $playlistObj->path );

		Slim::Player::Playlist::removePlaylistFromDisk($playlistObj);

		$playlistObj->set_column('url', $newUrl);
		$playlistObj->set_column('urlmd5', md5_hex($newUrl));
		$playlistObj->set_column('title', $newName);
		$playlistObj->set_column('titlesort', Slim::Utils::Text::ignoreCaseArticles($newName));
		$playlistObj->set_column('titlesearch', Slim::Utils::Text::ignoreCaseArticles($newName, 1));
		$playlistObj->update;

		if (!defined Slim::Formats::Playlists::M3U->write( 
			[ $playlistObj->tracks ],
			undef,
			$playlistObj->path,
			1,
			$index,
		)) {
			$request->addResult('writeError', 1);
		}
	}

	$request->setStatusDone();
}


sub prefCommand {
	my $request = shift;

	if ($request->isNotCommand([['pref']]) && $request->isNotCommand([['playerpref']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client;

	if ($request->isCommand([['playerpref']])) {
		
		$client = $request->client();
		
		unless ($client) {			
			$request->setStatusBadDispatch();
			return;
		}
	}

	# get our parameters
	my $prefName = $request->getParam('_prefname');
	my $newValue = $request->getParam('value') || $request->getParam('_newvalue');

	# split pref name from namespace: name.space.pref:
	my $namespace = 'server';
	if ($prefName =~ /^(.*?):(.+)$/) {
		$namespace = $1;
		$prefName = $2;
	}
	
	if ($newValue =~ /^value:/) {
		$newValue =~ s/^value://;
	}

	if (!defined $prefName || !defined $newValue || !defined $namespace) {
		$request->setStatusBadParams();
		return;
	}	

	if ($client) {
		preferences($namespace)->client($client)->set($prefName, $newValue);
	}
	else {
		preferences($namespace)->set($prefName, $newValue);
	}
	
	$request->setStatusDone();
}

sub rescanCommand {
	my $request = shift;

	if ($request->isNotCommand([['rescan']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# if scan is running or we're told to queue up requests, return quickly
	if ( Slim::Music::Import->stillScanning() || Slim::Music::Import->doQueueScanTasks ) {
		Slim::Music::Import->queueScanTask($request);
		$request->setStatusDone();
		return;
	}

	# get our parameters
	my $originalMode;
	my $mode = $originalMode = $request->getParam('_mode') || 'full';
	my $singledir = $request->getParam('_singledir');
	
	if ($singledir) {
		$singledir = Slim::Utils::Misc::pathFromFileURL($singledir);
	}
	
	# Bug 17358, if any plugin importers are enabled such as iTunes/MusicIP, run an old-style external rescan
	# XXX Rewrite iTunes and MusicIP to support async rescan
	my $importers = Slim::Music::Import->importers();
	while ( my ($class, $config) = each %{$importers} ) {
		if ( $class =~ /Plugin/ && $config->{use} ) {
			$mode = 'external';
		}
	}
	
	if ( $mode eq 'external' ) {
		# The old way of rescanning using scanner.pl
		my %args = (
			cleanup => 1,
		);

		if ($originalMode eq 'playlists') {
			$args{playlists} = 1;
		}
		else {
			$args{rescan} = 1;
		}		
		
		$args{singledir} = $singledir if $singledir;

		Slim::Music::Import->launchScan(\%args);
	}
	else {
		# In-process scan   
	
		my @dirs = @{ Slim::Utils::Misc::getMediaDirs() };
		# if we're scanning already, don't do it twice
		if (scalar @dirs) {
		
			if ( Slim::Utils::OSDetect::getOS->canAutoRescan && $prefs->get('autorescan') ) {
				require Slim::Utils::AutoRescan;
				Slim::Utils::AutoRescan->shutdown;
			}
		
			Slim::Utils::Progress->clear();
		
			# we only want to scan folders for video/pictures
			my %seen = (); # to avoid duplicates
			@dirs = grep { !$seen{$_}++ } @{ Slim::Utils::Misc::getVideoDirs() }, @{ Slim::Utils::Misc::getImageDirs() };
			
			if ($singledir) {
				@dirs = grep { /$singledir/ } @dirs;
			}

			if ((main::IMAGE || main::VIDEO) && $mode ne 'playlists') {
				# XXX - we need a better way to handle the async mode, eg. passing the exception list together with the folder list to Media::Scan
				my $lms;
				$lms = sub {
					if (scalar @dirs) {
						Slim::Utils::Scanner::LMS->rescan( shift @dirs, {
							scanName   => 'directory',
							progress   => 1,
							onFinished => sub {
								# XXX - delay call to self for a second, or we segfault
								Slim::Utils::Timers::setTimer(undef, time() + 1, $lms);
							},
						} );
					}
				};
				
				# Audio scan is run first, when done, the LMS scanner is run
				my $audio;
				$audio = sub {
					my $audiodirs = Slim::Utils::Misc::getAudioDirs();
					
					if ($singledir) {
						$audiodirs = [ grep { /$singledir/ } @{$audiodirs} ];
					}
					else {
						# scan playlist folder too
						push @$audiodirs, Slim::Utils::Misc::getPlaylistDir();
					}
					
					# XXX until libmediascan supports audio, run the audio scanner now
					Slim::Utils::Scanner::Local->rescan( $audiodirs, {
						types      => 'list|audio',
						scanName   => 'directory',
						progress   => 1,
						onFinished => $lms,
					} );
				};
			
				$audio->();
			}
			elsif ($mode eq 'playlists') {
				my $playlistdir = Slim::Utils::Misc::getPlaylistDir();
				
				# XXX until libmediascan supports audio, run the audio scanner now
				Slim::Utils::Scanner::Local->rescan( $playlistdir, {
					types    => 'list',
					scanName => 'playlist',
					progress => 1,
				} );
			}
			else {
				my $audiodirs = Slim::Utils::Misc::getAudioDirs();
				
				if ($singledir) {
					$audiodirs = [ grep { /$singledir/ } @{$audiodirs} ];
				}
				else {
					# scan playlist folder too
					push @$audiodirs, Slim::Utils::Misc::getPlaylistDir();
				}
				
				# XXX until libmediascan supports audio, run the audio scanner now
				Slim::Utils::Scanner::Local->rescan( $audiodirs, {
					types    => 'list|audio',
					scanName => 'directory',
					progress => 1,
				} );
			}
		}
	}

	$request->setStatusDone();
}

sub stopServer {
	my $request = shift;

	if ($request->isNotCommand([['stopserver']]) && $request->isNotCommand([['restartserver']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# pass true value if we want to restart the server
	if ($request->isCommand([['restartserver']])) {
		main::restartServer();
	}
	else {
		main::stopServer();
	}
	
	$request->setStatusDone();
}


sub wipecacheCommand {
	my $request = shift;

	if ($request->isNotCommand([['wipecache']])) {
		$request->setStatusBadDispatch();
		return;
	}

	if ( Slim::Music::Import->stillScanning() || Slim::Music::Import->doQueueScanTasks ) {
		Slim::Music::Import->queueScanTask($request);
	}
	
	# if we're scanning already, don't do it twice
	else {
		if (main::LOCAL_PLAYERS) {
			# Clear all the active clients's playlists
			for my $client (Slim::Player::Client::clients()) {
				$client->execute([qw(playlist clear)]);
			}
		}
		
		if ( Slim::Utils::OSDetect::getOS->canAutoRescan && $prefs->get('autorescan') ) {
			require Slim::Utils::AutoRescan;
			Slim::Utils::AutoRescan->shutdown;
		}

		Slim::Utils::Progress->clear();
		
		if ( Slim::Utils::OSDetect::isSqueezeOS() ) {
			# Wipe/rescan in-process on SqueezeOS

			# XXX - for the time being we're going to assume that the embedded server will only handle one folder
			my $dir = Slim::Utils::Misc::getAudioDirs()->[0];
			
			my %args = (
				types    => 'list|audio',
				scanName => 'directory',
				progress => 1,
				wipe     => 1,
			);
			
			Slim::Utils::Scanner::Local->rescan( $dir, \%args );
		}
		else {
			# Launch external scanner on normal systems
			Slim::Music::Import->launchScan( {
				wipe => 1,
			} );
		}
	}

	$request->setStatusDone();
}

sub ratingCommand {
	my $request = shift;

	# check this is the correct command.
	if ( $request->isNotCommand( [['rating']] ) ) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $item   = $request->getParam('_item');      #p1
	my $rating = $request->getParam('_rating');    #p2, optional

	if ( !defined $item ) {
		$request->setStatusBadParams();
		return;
	}

	if ( defined $rating ) {
		main::INFOLOG && $log->info("Setting rating for $item to $rating");
	}

	my $track = blessed($item);

	if ( !$track ) {
		# Look for track based on ID or URL
		if ( $item =~ /^\d+$/ ) {
			$track = Slim::Schema->rs('Track')->find($item);
		}
		else {
			my $url = Slim::Utils::Misc::fileURLFromPath($item);
			if ( $url ) {
				$track = Slim::Schema->objectForUrl( { url => $url } );
			}
		}
	}

	if ( !blessed($track) || $track->audio != 1 || track->remote ) {
		$log->warn("Can't find local track: $item");
		$request->setStatusBadParams();
		return;
	}

	if ( defined $rating ) {
		if ( $rating < 0 || $rating > 100 ) {
			$request->setStatusBadParams();
			return;
		}

		Slim::Schema->rating( $track, $rating );
	}
	else {
		$rating = Slim::Schema->rating($track);
		
		$request->addResult( '_rating', defined $rating ? $rating : 0 );
	}

	$request->setStatusDone();
}

sub pragmaCommand {
	my $request = shift;
	
	my $pragma = join( ' ', grep { $_ ne 'pragma' } $request->renderAsArray );
	
	# XXX need to pass pragma to artwork cache even if using MySQL
	Slim::Utils::OSDetect->getOS()->sqlHelperClass()->pragma($pragma);
	
	$request->setStatusDone();
}

################################################################################
# Helper functions
################################################################################

sub _playlistXitem_load_done {
	my ($client, $index, $request, $url, $error, $noShuffle, $fadeIn, $noplay, $wipePlaylist) = @_;
	
	# dont' keep current song on loading a playlist
	if ( main::LOCAL_PLAYERS && !$noShuffle  && $client->isLocalPlayer) {
		Slim::Player::Playlist::reshuffle($client,
			(Slim::Player::Source::playmode($client) eq "play" || ($client->power && Slim::Player::Source::playmode($client) eq "pause")) ? 0 : 1
		);
	}

	if (main::LOCAL_PLAYERS && defined($index) && $client->isLocalPlayer) {
		$client->execute(['playlist', 'jump', $index, $fadeIn, $noplay ]);
	}

	if ($wipePlaylist) {
		my $playlistObj = Slim::Schema->objectForUrl($url);
		_wipePlaylist($playlistObj);

	}

	Slim::Control::Request::notifyFromArray($client, ['playlist', 'load_done']);
}


sub _insert_done {
	my ($client) = @_;

	Slim::Control::Request::notifyFromArray($client, ['playlist', 'load_done']);
}


sub _playlistXalbum_singletonRef {
	my $arg = shift;

	if (!defined($arg)) {
		return [];
	} elsif ($arg eq '*') {
		return [];
	} elsif ($arg) {
		# force stringification of a possible object.
		return ["" . $arg];
	} else {
		return [];
	}
}


sub _playlistXtracksCommand_parseSearchTerms {
	my $client = shift;
	my $what   = shift;

	# if there isn't an = sign, then change the first : to a =
	if ($what !~ /=/) {
		$what =~ s/(.*)?:(.*)/$1=$2/;
	}

	my %find   = ();
	my $terms  = {};
	my %attrs  = ();
	my @fields = map { lc($_) } Slim::Schema->sources;
	my ($sort, $limit, $offset);

	# Bug: 3629 - sort by album, then disc, tracknum, titlesort
	my $sqlHelperClass = Slim::Utils::OSDetect->getOS()->sqlHelperClass();
	
	my $collate = $sqlHelperClass->collate();
	
	my $albumSort 
		= $sqlHelperClass->append0("album.titlesort") . " $collate"
		. ', me.disc, me.tracknum, '
		. $sqlHelperClass->append0("me.titlesort") . " $collate";
		
	my $trackSort = "me.disc, me.tracknum, " . $sqlHelperClass->append0("me.titlesort") . " $collate";
	
	if ( main::SLIM_SERVICE || !Slim::Schema::hasLibrary()) {
		return ();
	}

	# Setup joins as needed - we want to end up with Tracks in the end.
	my %joinMap = ();

	# Accept both the old key=value "termlist", and internal use by passing a hash ref.
	if (ref($what) eq 'HASH') {

		$terms = $what;

	} else {

		for my $term (split '&', $what) {

			# If $terms has a leading &, split will generate an initial empty string
			next if !$term;

			if ($term =~ /^(.*)=(.*)$/ && grep { $1 =~ /$_\.?/ } @fields) {

				my $key   = URI::Escape::uri_unescape($1);
				my $value = URI::Escape::uri_unescape($2);

				$terms->{$key} = $value;

			}
		}
	}

	while (my ($key, $value) = each %{$terms}) {

		# ignore anti-CSRF token
		if ($key eq 'pageAntiCSRFToken') {
			next;
		}

		# Bug: 4063 - don't enforce contributor.role when coming from
		# the web UI's search.
		elsif ($key eq 'contributor.role') {
			next;
		}

		# Bug: 3582 - reconstitute from 0 for album.compilation.
		elsif ($key eq 'album.compilation' && $value == 0) {

			$find{$key} = [ { 'is' => undef }, { '=' => 0 } ];
		}

		# Do some mapping from the player browse mode. This is
		# already done in the web ui.
		elsif ($key =~ /^(playlist|age|album|contributor|genre|year)$/) {
			$key = "$1.id";
		}

		# New Music browsing is working on the
		# tracks.timestamp column, but shows years.
		# Use the album-id in the track instead of joining with the album table.
		if ($key eq 'album.id' || $key eq 'age.id') {
			$key = 'track.album';
		}

		# Setup the join mapping
		if ($key =~ /^genre\./) {

			$sort = $albumSort;
			$joinMap{'genre'} = { 'genreTracks' => 'genre' };

		} elsif ($key =~ /^album\./) {

			$sort = $albumSort;
			$joinMap{'album'} = 'album';

		} elsif ($key =~ /^year\./) {

			$sort = $albumSort;
			$joinMap{'year'} = 'year';

		} elsif ($key =~ /^contributor\./) {

			$sort = $albumSort;
			$joinMap{'contributor'} = { 'contributorTracks' => 'contributor' };
		}

		# Turn 'track.*' into 'me.*'
		if ($key =~ /^(playlist)?track(\.?.*)$/) {
			$key = "me$2";
		}

		# Meta tags that are passed.
		if ($key =~ /^(?:limit|offset)$/) {

			$attrs{$key} = $value;

		} elsif ($key eq 'sort') {

			$sort = $value;

		} else {

			if ($key =~ /\.(?:name|title)search$/) {
				
				# BUG 4536: if existing value is a hash, don't create another one
				if (ref $value eq 'HASH') {
					$find{$key} = $value;
				} else {
					$find{$key} = { 'like' => Slim::Utils::Text::searchStringSplit($value) };
				}

			} else {

				$find{$key} = Slim::Utils::Text::ignoreCaseArticles($value, 1);
			}
		}
	}

	# 
	if ($find{'playlist.id'} && !$find{'me.id'}) {

		# Treat playlists specially - they are containers.
		my $playlist = Slim::Schema->find('Playlist', $find{'playlist.id'});

		if (blessed($playlist) && $playlist->can('tracks')) {

			$client->currentPlaylist($playlist) if main::LOCAL_PLAYERS && $client->isLocalPlayer;

			return $playlist->tracks;
		}

		return ();

	} else {

		# on search, only grab audio items.
		$find{'audio'} = 1;

		# Bug 2271 - allow VA albums.
		if (defined $find{'album.compilation'} && $find{'album.compilation'} == 1) {

			delete $find{'contributor.id'};
		}

		if ($find{'me.album'} && $find{'contributor.id'} && 
			$find{'contributor.id'} == Slim::Schema->variousArtistsObject->id) {

			delete $find{'contributor.id'};
		}

		if ($find{'playlist.id'}) {
		
			delete $find{'playlist.id'};
		}

		# If we have an album and a year - remove the year, since
		# there is no explict relationship between Track and Year.
		if ($find{'me.album'} && $find{'year.id'}) {

			delete $find{'year.id'};
			delete $joinMap{'year'};

		} elsif ($find{'year.id'}) {

			$find{'album.year'} = delete $find{'year.id'};
			delete $joinMap{'year'};
		}
		
		if ($sort && $sort eq $albumSort) {
			if ($find{'me.album'}) {
				# Don't need album-sort if we have a specific album-id
				$sort = undef;
			} else {
				# Bug: 3629 - if we're sorting by album - be sure to include it in the join table.
				$joinMap{'album'} = 'album';
			}
		}

		# limit & offset may have been populated above.
		$attrs{'order_by'} = $sort || $trackSort;
		$attrs{'join'}     = [ map { $_ } values %joinMap ];
		$attrs{'rows'}     = $attrs{'limit'} if $attrs{'limit'};

		return Slim::Schema->rs('Track')->search(\%find, \%attrs)->distinct->all;
	}
}

my %mapAttributes = (
	artist => 'artistname',
	album => 'albumname',
	duration => 'secs',
	type => 'content_type',
	disccount => 'discc',
	genre => undef,
);


sub _playlistXtracksCommand_parseDataRef {
	my $client  = shift;
	my $term    = shift;
	my $list    = shift;
	
	my @tracks = ();
	for ( @$list ) {
		my $url = delete $_->{url};
		
		while (my($from, $to) = each %mapAttributes) {
			my $v = delete($_->{$from});
			if ($to && defined $v) {
				$_->{$to} = $v;
			}
		}
		
		my $track = Slim::Schema->updateOrCreate({
			url        => $url,
			attributes => $_,
		});
		push @tracks, $track if blessed($track) && $track->id;
	}

	return @tracks;
}

sub _playlistXtracksCommand_constructTrackList {
	my $client  = shift;
	my $term    = shift;
	my $list    = shift;
	
	my @list = split (/,/, $list);
	my @tracks = ();
	for my $url ( @list ) {
		my $track = Slim::Schema->objectForUrl($url);
		push @tracks, $track if blessed($track) && $track->id;
	}

	return @tracks;

}

sub _playlistXtracksCommand_parseListRef {
	my $client  = shift;
	my $term    = shift;
	my $listRef = shift;

	if ($term =~ /listref=(\w+)&?/i) {
		$listRef = $client->modeParam($1);
	}

	if (defined $listRef && ref $listRef eq "ARRAY") {

		return @$listRef;
	}

	return ();
}

sub _playlistXtracksCommand_parseSearchRef {
	my $client    = shift;
	my $term      = shift;
	my $searchRef = shift;

	if ($term =~ /searchRef=(\w+)&?/i) {
		$searchRef = $client->modeParam($1);
	}

	my $cond = $searchRef->{'cond'} || {};
	my $attr = $searchRef->{'attr'} || {};

	# XXX - For some reason, the join key isn't passed along with the ref.
	# Perl bug because 'join' is a keyword?
	if (!$attr->{'join'} && $attr->{'joins'}) {
		$attr->{'join'} = delete $attr->{'joins'};
	}

	return Slim::Schema->rs('Track')->search($cond, $attr)->distinct->all;
}

# Allow any URL to be a favorite - this includes things like iTunes playlists.
sub _playlistXtracksCommand_parseDbItem {
	my $client  = shift;
	my $url     = shift;

	my %classes;
	my $class   = 'Track';
	my $obj     = undef;

	# Bug: 2569
	# We need to ask for the right type of object.
	# 
	# Contributors, Genres & Albums have a url of:
	# db:contributor.namesearch=BEATLES
	#
	# Remote playlists are Track objects, not Playlist objects.
	if ($url =~ /^db:(\w+\.\w+=.+)$/) {
	  
		for my $term ( split '&', $1 ) {

			# If $terms has a leading &, split will generate an initial empty string
			next if !$term;

			if ($term =~ /^(\w+)\.(\w+)=(.*)$/) {

				my $key   = URI::Escape::uri_unescape($2);
				my $value = URI::Escape::uri_unescape($3);

				if (!utf8::is_utf8($value) && !utf8::decode($value)) { $log->warn("The following value is not UTF-8 encoded: $value"); }

				if (utf8::is_utf8($value)) {
					utf8::decode($value);
					utf8::encode($value);
				}

				$class = ucfirst($1);
				$obj   = Slim::Schema->single( $class, { $key => $value } );
				
				$classes{$class} = $obj;
			}
		}

	}
	elsif ( Slim::Music::Info::isPlaylist($url) && !Slim::Music::Info::isRemoteURL($url) ) {

		%classes = (
			Playlist => Slim::Schema->rs($class)->objectForUrl( {
				url => $url,
			} )
		);
	}
	else {

		# else we assume it's a track
		%classes = (
			Track => Slim::Schema->rs($class)->objectForUrl( {
				url => $url,
			} )
		);
	}

	# Bug 4790: we get a track object of content type 'dir' if a fileurl for a directory is passed
	# this needs scanning so pass empty list back to playlistXitemCommand in this case
	my $terms = "";
	while ( ($class, $obj) = each %classes ) {
		if ( blessed($obj) && (
			$class eq 'Album' || 
			$class eq 'Contributor' || 
			$class eq 'Genre' ||
			$class eq 'Year' ||
			( $obj->can('content_type') && $obj->content_type ne 'dir') 
		) ) {
			$terms .= "&" if ( $terms ne "" );
			$terms .= sprintf( '%s.id=%d', lc($class), $obj->id );
		}
	}
	
	if ( $terms ne "" ) {
			return _playlistXtracksCommand_parseSearchTerms($client, $terms);
	}
	else {
		return ();
	}
}


=head1 SEE ALSO

L<Slim::Control::Request.pm>

=cut

1;

__END__
