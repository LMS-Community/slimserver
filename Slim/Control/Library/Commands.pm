package Slim::Control::Commands;

# Logitech Media Server Copyright 2001-2011 Logitech.
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

Slim::Control::Commands - the library related code

=head1 DESCRIPTION

Implements most Logitech Media Server commands and is designed to be exclusively called
through Request.pm and the mechanisms it defines.

=cut

use strict;

use Digest::MD5 qw(md5_hex);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner::Local;

my $log = logger('control.command');
my $prefs = preferences('server');


sub abortScanCommand {
	my $request = shift;

	Slim::Music::Import->abortScan();
	
	$request->setStatusDone();
}


sub artworkspecCommand {
	my $request = shift;
	
	# get the parameters
	my $name = $request->getParam('_name') || '';
	my $spec = $request->getParam('_spec');

	# check this is the correct command.
	if ( !$spec || $request->isNotCommand([['artworkspec'], ['add']]) ) {
		$request->setStatusBadDispatch();
		return;
	}
	
	main::DEBUGLOG && $log->debug("Registering artwork resizing spec: $spec ($name)");
	
	# do some sanity checking
	my ($width, $height, $mode, $bgcolor, $ext) = Slim::Web::Graphics->parseSpec($spec);
	if ($width && $height && $mode) {
		my $specs = Storable::dclone($prefs->get('customArtSpecs'));

		my $oldName = $specs->{$spec};
		if ( $oldName && $oldName !~ /$name/ ) {
			$specs->{$spec} = "$oldName, $name";
		}
		# don't duplicate standard specs!
		elsif ( !$oldName && !(scalar grep /$spec/, Slim::Music::Artwork::getResizeSpecs()) ) {
			$specs->{$spec} = $name;
		}
		
		$prefs->set('customArtSpecs', $specs);
	}
	else {
		$log->error('Invalid artwork resizing specification: ' . $spec);
	}
	
	$request->setStatusDone();
}


sub playlistSaveCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['save']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# can't do much without playlistdir!
	if (!Slim::Utils::Misc::getPlaylistDir()) {
		$request->setStatusBadConfig();
		return;
	}
	
	if (Slim::Music::Import->stillScanning()) {
		$request->addResult('writeError', 1);
		$request->setStatusDone();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $title  = $request->getParam('_title');
	my $silent = $request->getParam('silent') || 0;
	my $titlesort = Slim::Utils::Text::ignoreCaseArticles($title);

	$title = Slim::Utils::Misc::cleanupFilename($title);


	my $playlistObj = Slim::Schema->updateOrCreate({

		'url' => Slim::Utils::Misc::fileURLFromPath(
			catfile( Slim::Utils::Misc::getPlaylistDir(), Slim::Utils::Unicode::encode_locale($title) . '.m3u')
		),
		'playlist' => 1,
		'attributes' => {
			'TITLE' => $title,
			'CT'    => 'ssp',
		},
	});

	my $annotatedList = [];

	if ($prefs->get('saveShuffled')) {

		for my $shuffleitem (@{Slim::Player::Playlist::shuffleList($client)}) {
			push @$annotatedList, Slim::Player::Playlist::song($client, $shuffleitem, 0, 0);
		}
				
	} else {

		$annotatedList = Slim::Player::Playlist::playList($client);
	}

	$playlistObj->set_column('titlesort', $titlesort);
	$playlistObj->set_column('titlesearch', $titlesort);
	$playlistObj->setTracks($annotatedList);
	$playlistObj->update;

	Slim::Schema->forceCommit;

	if (!defined Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj)) {
		$request->addResult('writeError', 1);
	}
	
	$request->addResult('__playlist_id', $playlistObj->id);

	if ( ! $silent ) {
		$client->showBriefly({
			'jive' => {
				'type'    => 'popupplay',
				'text'    => [ $client->string('SAVED_THIS_PLAYLIST_AS', $title) ],
			}
		});
	}

	$request->setStatusDone();
}


sub playlistZapCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['zap']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $index    = $request->getParam('_index');;
	
	my $zapped   = $client->string('ZAPPED_SONGS');
	my $zapindex = defined $index ? $index : Slim::Player::Source::playingSongIndex($client);
	my $zapsong  = Slim::Player::Playlist::song($client, $zapindex);

	#  Remove from current playlist
	if (Slim::Player::Playlist::count($client) > 0) {

		# Call ourselves.
		Slim::Control::Request::executeRequest($client, ["playlist", "delete", $zapindex]);
	}

	my $playlistObj = Slim::Schema->updateOrCreate({
		'url'        => Slim::Utils::Misc::fileURLFromPath(
			catfile( Slim::Utils::Misc::getPlaylistDir(), $zapped . '.m3u')
		),
		'playlist'   => 1,

		'attributes' => {
			'TITLE' => $zapped,
			'CT'    => 'ssp',
		},
	});

	$playlistObj->appendTracks([ $zapsong ]);
	$playlistObj->update;

	Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj);

	$client->currentPlaylistModified(1);
	$client->currentPlaylistUpdateTime(Time::HiRes::time());
	Slim::Player::Playlist::refreshPlaylist($client);
	
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

	my @results = _playlistXtracksCommand_parseSearchTerms($client, $find, $cmd);

	$cmd =~ s/album/tracks/;

	Slim::Control::Request::executeRequest($client, ['playlist', $cmd, 'listRef', \@results]);

	$request->setStatusDone();
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
	my $cmd    = shift;

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
	
	if ( !Slim::Schema::hasLibrary()) {
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
			elsif ($term =~ /^(library_id)=(.*)/) {
				$terms->{'librarytracks.library'} = URI::Escape::uri_unescape($2);
			}
		}
	}

	my $library_id;
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
		
		elsif (lc($key) eq 'librarytracks.library') {
			$library_id = $value;
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

				$find{$key} = Slim::Utils::Text::ignoreCase($value, 1);
			}
		}
	}

	# 
	if ($find{'playlist.id'} && !$find{'me.id'}) {

		# Treat playlists specially - they are containers.
		my $playlist = Slim::Schema->find('Playlist', $find{'playlist.id'});

		if (blessed($playlist) && $playlist->can('tracks')) {

			$client->currentPlaylist($playlist) if $cmd && $cmd =~ /^(?:play|load)/;

			return $playlist->tracks($library_id);
		}

		return ();

	} else {

		# on search, only grab audio items.
		$find{'audio'} = 1;
		
		my $vaObjId = Slim::Schema->variousArtistsObject->id;

		if ($find{'contributor.id'} && $find{'contributor.id'} == $vaObjId) {

			$find{'album.compilation'} = 1;
			$joinMap{'albums'} = 'album';
		}

		# Bug 2271 - allow VA albums.
		if (defined $find{'album.compilation'} && $find{'album.compilation'} == 1) {

			delete $find{'contributor.id'};
		}

		if ($find{'me.album'} && $find{'contributor.id'} && 
			$find{'contributor.id'} == $vaObjId) {

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

		if ( main::LIBRARY && ($library_id ||= Slim::Music::VirtualLibraries->getLibraryIdForClient($client)) ) {
			if ( Slim::Music::VirtualLibraries->getRealId($library_id) ) {
				$joinMap{'libraryTracks'} = 'libraryTracks';
				$find{'libraryTracks.library'} = $library_id;
			}
		}

		# limit & offset may have been populated above.
		$attrs{'order_by'} = $sort || $trackSort;
		$attrs{'join'}     = [ map { $_ } values %joinMap ];

		return Slim::Schema->rs('Track')->search(\%find, \%attrs)->distinct->all;
	}
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
				
				if ( $class eq 'LibraryTracks' && $key eq 'library' && $value eq '-1' ) {
					$obj = -1;
				}
				else {
					$obj = Slim::Schema->single( $class, { $key => $value } );
				}
				
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
			( blessed $obj && $obj->can('content_type') && $obj->content_type ne 'dir') 
		) ) {
			$terms .= "&" if ( $terms ne "" );
			$terms .= sprintf( '%s.id=%d', lc($class), $obj->id );
		}
	}
	
	if ( $classes{LibraryTracks} ) {
		$terms .= "&" if ( $terms ne "" );
		$terms .= sprintf( 'librarytracks.library=%d', $classes{LibraryTracks} );
	}
	
	if ( $terms ne "" ) {
			return _playlistXtracksCommand_parseSearchTerms($client, $terms);
	}
	else {
		return ();
	}
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
				$playlistTrack->titlesearch(Slim::Utils::Text::ignoreCase($title, 1));
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
		$playlistObj->set_column('titlesearch', Slim::Utils::Text::ignoreCase($newName, 1));
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


sub rescanCommand {
	my $request = shift;

	if ($request->isNotCommand([['rescan']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $originalMode;
	my $mode = $originalMode = $request->getParam('_mode') || 'full';
	my $singledir = $request->getParam('_singledir');
	
	if ($singledir) {
		$singledir = Slim::Utils::Misc::pathFromFileURL($singledir);
		
		# don't run scan if newly added entry is disabled for all media types
		if ( grep { /\Q$singledir\E/ } @{ Slim::Utils::Misc::getInactiveMediaDirs() }) {
			main::INFOLOG && $log->info("Ignore scan request for folder, it's disabled for all media types: $singledir");
			$request->setStatusDone();
			return;
		}
	}

	# if scan is running or we're told to queue up requests, return quickly
	if ( Slim::Music::Import->stillScanning() || Slim::Music::Import->doQueueScanTasks() || Slim::Music::Import->hasScanTask() ) {
		Slim::Music::Import->queueScanTask($request);
		
		# trigger the scan queue if we're not scanning yet
		Slim::Music::Import->nextScanTask() unless Slim::Music::Import->stillScanning() || Slim::Music::Import->doQueueScanTasks();
		
		$request->setStatusDone();
		return;
	}
	
	# Bug 17358, if any plugin importers are enabled such as iTunes/MusicIP, run an old-style external rescan
	# XXX Rewrite iTunes and MusicIP to support async rescan
	my $importers = Slim::Music::Import->importers();
	while ( my ($class, $config) = each %{$importers} ) {
		if ( $class =~ /(?:Plugin|Slim::Music::VirtualLibraries)/ && $config->{use} ) {
			$mode = 'external';
		}
	}
	
	if ( $mode eq 'external' ) {
		# The old way of rescanning using scanner.pl
		my %args = ();

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
			@dirs = grep { 
				!$seen{$_}++ 
			} @{ Slim::Utils::Misc::getVideoDirs($singledir) }, @{ Slim::Utils::Misc::getImageDirs($singledir) };

			if ( main::MEDIASUPPORT && scalar @dirs && $mode ne 'playlists' ) {
				require Slim::Utils::Scanner::LMS;

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
				my $audiodirs = Slim::Utils::Misc::getAudioDirs($singledir);

				if (my $playlistdir = Slim::Utils::Misc::getPlaylistDir()) {
					# scan playlist folder too
					push @$audiodirs, $playlistdir;
				}

				# XXX until libmediascan supports audio, run the audio scanner now
				Slim::Utils::Scanner::Local->rescan( $audiodirs, {
					types      => 'list|audio',
					scanName   => 'directory',
					progress   => 1,
					onFinished => $lms,
				} );
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
				my $audiodirs = Slim::Utils::Misc::getAudioDirs($singledir);

				if (my $playlistdir = Slim::Utils::Misc::getPlaylistDir()) {
					# scan playlist folder too
					push @$audiodirs, $playlistdir;
				}
				
				# XXX until libmediascan supports audio, run the audio scanner now
				Slim::Utils::Scanner::Local->rescan( $audiodirs, {
					types    => 'list|audio',
					scanName => 'directory',
					progress => 1,
				} ) if scalar @$audiodirs;
			}
		}
	}

	$request->setStatusDone();
}


sub wipecacheCommand {
	my $request = shift;

	if ($request->isNotCommand([['wipecache']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# if we're scanning already, don't do it twice
	if ( Slim::Music::Import->stillScanning() || Slim::Music::Import->doQueueScanTasks || $request->getParam('_queue') ) {
		Slim::Music::Import->queueScanTask($request);
	}
	
	else {

		# replace local tracks with volatile versions - we're gong to wipe the database
		for my $client (Slim::Player::Client::clients()) {

			Slim::Player::Playlist::makeVolatile($client);
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


1;