package Slim::Buttons::BrowseID3;

# $Id$

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Buttons::TrackInfo;
use Slim::Music::Info;
use Slim::Utils::Misc;

our %functions = ();
our $mixer;

# Code to browse music folder by ID3 information.
sub init {

	Slim::Buttons::Common::addMode('browseid3',Slim::Buttons::BrowseID3::getFunctions(),\&Slim::Buttons::BrowseID3::setMode);

	my %browse = (

		'BROWSE_NEW_MUSIC' => {
			'useMode'  => 'browseid3',
			'genre'    => '*',
			'artist'   => '*',
		},

		'BROWSE_BY_GENRE'  => {
			'useMode'  => 'browseid3',
		},

		'BROWSE_BY_ARTIST' => {
			'useMode'  => 'browseid3',
			'genre'    => '*',
		},

		'BROWSE_BY_ALBUM'  => {
			'useMode'  => 'browseid3',
			'genre'    => '*',
			'artist'   => '*',
		},

		'BROWSE_BY_SONG'   => {
			'useMode'  => 'browseid3',
			'genre'    => '*',
			'artist'   => '*',
			'album'    => '*',
		},
	);
	
	for my $name (sort keys %browse) {

		if ($name ne 'BROWSE_BY_SONG') {
			Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', $name, $browse{$name});
		}

		Slim::Buttons::Home::addMenuOption($name, $browse{$name});
	};

	%functions = (

		'up' => sub  {
			my $client = shift;
			my $button = shift;
			my $inc = shift || 1;
			my $count = scalar @{browseID3dir($client)};
			if ($count < 2) {
				$client->bumpUp() if ($button !~ /repeat/);
			} else {
				$inc = ($inc =~ /\D/) ? -1 : -$inc;
				my $newposition = Slim::Buttons::Common::scroll($client, $inc, $count, browseID3dirIndex($client));
				browseID3dirIndex($client,$newposition);
				updateLastSelection($client);
				$client->update();
			}
		},

		'down' => sub  {
			my $client = shift;
			my $button = shift;
			my $inc = shift || 1;
			my $count = scalar @{browseID3dir($client)};
			if ($count < 2) {
				$client->bumpDown() if ($button !~ /repeat/);
			} else {
				if ($inc =~ /\D/) {$inc = 1}
				my $newposition = Slim::Buttons::Common::scroll($client, $inc, $count, browseID3dirIndex($client));
				browseID3dirIndex($client,$newposition);
				updateLastSelection($client);
				$client->update();
			}
		},

		'left' => sub  {
			my $client = shift;
			my @oldlines = Slim::Display::Display::curLines($client);

			my $genre  = selection($client,'curgenre');
			my $artist = selection($client,'curartist');
			my $album  = selection($client,'curalbum');
			my $song   = selection($client,'cursong');

			my $startgenre  = selection($client, 'genre');
			my $startartist = selection($client, 'artist');
			my $startalbum  = selection($client, 'album');
			my $startsong   = selection($client, 'song');

			updateLastSelection($client);

			if (equal($genre, $startgenre) && equal($artist, $startartist) && equal($album, $startalbum) && equal($song, $startsong)) {

				# we don't know anything, go back to where we came from
				Slim::Buttons::Common::popMode($client);

			} else {

				# go up one level
				if (specified($album)) {

					# we're at the song level
					# forget we knew the album
					setSelection($client,'curalbum', selection($client,'album'));
					loadDir($client);
					# disabled: skip album, if there is only one
					#if (scalar @{browseID3dir($client)} == 1) {
					#	setSelection($client,'curartist', selection($client,'artist'));
					#	loadDir($client);
					#}

				} elsif (specified($artist)) {

					# we're at the album level
					# forget we knew the artist
					setSelection($client,'curartist', selection($client,'artist'));
					loadDir($client);

				} elsif (specified($genre)) {

					# we're at the artist level
					# forget we knew the genre
					setSelection($client,'curgenre', selection($client,'genre'));
					loadDir($client);

				} else {

					loadDir($client);
				}
			}

			$client->pushRight( \@oldlines, [Slim::Display::Display::curLines($client)]);
		},

		'right' => sub  {
			my $client = shift;

			if (scalar @{browseID3dir($client)} == 0) {

				# don't do anything if the list is empty, which shouldn't happen anyways...
				$client->bumpRight();

			} else {
				my $currentItem = browseID3dir($client,browseID3dirIndex($client));

				$::d_files && msg("currentItem == $currentItem\n");

				my @oldlines = Slim::Display::Display::curLines($client);

				updateLastSelection($client);

				my $genre  = selection($client,'curgenre');
				my $artist = selection($client,'curartist');
				my $album  = selection($client,'curalbum');
				my $song   = selection($client,'cursong');

				if (picked($genre) && picked($artist) && picked($album)) {

					# we know the genre, artist, album and song.  show the song info for the track in $currentitem
					Slim::Buttons::Common::pushMode($client, 'trackinfo', { 'track' => $currentItem });

				} elsif (picked($genre) && picked($artist)) {

					# we know the genre, artist and album.  show the songs.
					setSelection($client, 'curalbum', $currentItem);
					loadDir($client);

				} elsif (picked($genre)) {

					# we know the genre and artist.  show the album.
					setSelection($client, 'curartist', $currentItem);
					loadDir($client);
					# Disabled: skip album, if there is only one
					#if (scalar @{browseID3dir($client)} == 1) {
					#	setSelection($client,'curalbum', browseID3dir($client, 0));
					#	loadDir($client);
					#}

				} else {

					# we just chose the genre, show it...
					setSelection($client, 'curgenre', $currentItem);
					loadDir($client);
				}

				$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
			}
		},

		'numberScroll' => sub  {
			my $client = shift;
			my $button = shift;
			my $digit = shift;
			my $newposition;
			my $genre = selection($client,'curgenre');
			my $artist = selection($client,'curartist');
			my $album = selection($client,'curalbum');
			# if it's just songs, then
			if (defined($genre) && defined($artist) && defined($album)) {
				# do an unsorted jump
				$newposition = Slim::Buttons::Common::numberScroll($client, $digit, browseID3dir($client), 0);
			} else {
				# otherwise, scroll to the appropriate letter
				$newposition = Slim::Buttons::Common::numberScroll($client, $digit, browseID3dir($client), 1,
					sub {
						my $ignored = browseID3dir($client)->[shift];
						my $articles =  Slim::Utils::Prefs::get("ignoredarticles");
						$articles =~ s/\s+/|/g;
						$ignored =~ s/^($articles)\s+//i;
						return $ignored;
					}
				);
			}
			browseID3dirIndex($client,$newposition);
			updateLastSelection($client);
			$client->update();
		},

		# this routine handles play, add and insert ($addorinsert would be undef, 1 or 2 respectively)
		'play' => sub  {
			my $client = shift;
			my $button = shift;
			my $addorinsert = shift || 0;

			my $genre  = selection($client,'curgenre');
			my $artist = selection($client,'curartist');
			my $album  = selection($client,'curalbum');

			my $all_albums;
			my $sortbytitle;

			if (defined($album) && ($album eq $client->string('ALL_SONGS'))) {
				$album = '*';
				$sortbytitle = 1;
			}

			if (defined($artist) && ($artist eq $client->string('ALL_ALBUMS'))) {
				$artist = '*';
				$sortbytitle = 1;
			}

			if (defined($genre) && ($genre eq $client->string('ALL_ARTISTS'))) {
				$genre = '*';
			}
			
			my $currentItem = browseID3dir($client, browseID3dirIndex($client));

			my ($line1, $line2) = lines($client);
			
			my $command;
			my $songcommand;
			
			if ($addorinsert == 1) {

				$line1 = $client->string('ADDING_TO_PLAYLIST');
				$command = "addalbum";	

			} elsif ($addorinsert == 2) {

				$line1 = $client->string('INSERT_TO_PLAYLIST');
				$command = "insertalbum";

			} else {

				$command = "loadalbum";

				if (Slim::Player::Playlist::shuffle($client)) {
					$line1 = $client->string('PLAYING_RANDOMLY_FROM');
				} else {
					$line1 = $client->string('NOW_PLAYING_FROM');
				}
			}
			
			$client->showBriefly(
				$client->renderOverlay($line1, $line2, undef, Slim::Display::Display::symbol('notesymbol')),
				undef,
				1
			);
			
			# if we've chosen a particular song to append, then append it
			if (picked($genre) && picked($artist) && picked($album)) {

				if ($addorinsert || $album eq '*' || !Slim::Utils::Prefs::get('playtrackalbum')) {

					$command = 'play';
					$command = 'append' if $addorinsert == 1;
					$command = 'insert' if $addorinsert == 2;

					Slim::Control::Command::execute($client, ["playlist", $command, $currentItem]);

				} else {

					my $wasShuffled = Slim::Player::Playlist::shuffle($client);

					Slim::Player::Playlist::shuffle($client, 0);

					Slim::Control::Command::execute($client, ["playlist", "clear"]);
					Slim::Control::Command::execute($client, 
						["playlist", "addalbum", $genre, $artist, picked($album) ? $album : $currentItem]
					);

					Slim::Control::Command::execute($client, ["playlist", "jump", picked($album) ? browseID3dirIndex($client) : "0"]);

					if ($wasShuffled) {
						Slim::Control::Command::execute($client, ["playlist", "shuffle", 1]);
					}
				}

			# if we've picked an album or song to play then play the album 
			# if we've picked an album to append, then append the album
			} elsif (picked($genre) && picked($artist)) {

				$::d_files && msg("song  or album $currentItem\n"); 

				my $whichalbum = picked($album) ? $album : (($currentItem eq $client->string('ALL_SONGS')) ? '*' : $currentItem);

				Slim::Control::Command::execute($client, 
					["playlist", $command, $genre, $artist, $whichalbum, undef, $currentItem eq $client->string('ALL_SONGS')
				]);

			# if we've picked an artist to append or play, then do so.
			} elsif (picked($genre)) {

				$::d_files && msg("artist $currentItem\n");
				my $whichartist = picked($artist) ? $artist : (($currentItem eq $client->string('ALL_ALBUMS')) ? '*' : $currentItem);

				#TODO this sometime causes a warning
				my $whichalbum = (defined $album && $album ne $client->string('ALL_ALBUMS')) ? $currentItem : '*';
				my $whichgenre = ($genre eq $client->string('ALL_ARTISTS')) ? '*' : $genre;

				Slim::Control::Command::execute($client, 
					["playlist", $command, $whichgenre, $whichartist, $whichalbum, undef, $sortbytitle]
				);

			# if we've picked a genre to play or append, then do so
			} else {

				$::d_files && msg("genre: $currentItem\n");

				$currentItem = ($currentItem eq $client->string('ALL_ALBUMS')) ? '*' : $currentItem;

				Slim::Control::Command::execute($client, ["playlist", $command,$currentItem, "*", "*"]);
			}

			$::d_files && msg("currentItem == $currentItem\n");
		},

		'create_mix' => sub  {
			my $client = shift;

			my $Imports = Slim::Music::Import::importers();
		
			my @mixers = ();
			
			for my $import (keys %{$Imports}) {
			
				if (defined $Imports->{$import}->{'mixer'} && $Imports->{$import}->{'use'}) {
					push @mixers, $import;
				}
			}

			if (scalar @mixers == 1) {
				
				$::d_plugins && msg("Running Mixer $mixers[0]\n");
				&{$Imports->{$mixers[0]}->{'mixer'}}($client);
				
			} elsif (@mixers) {
				
				my $params = $client->modeParameterStack(-1);
				$params->{'listRef'} = \@mixers;
				$params->{'stringExternRef'} = 1;
				
				$params->{'header'} = 'INSTANT_MIX';
				$params->{'headerAddCount'} = 1;
				$params->{'callback'} = \&mixerExitHandler;
		
				$params->{'overlayRef'} = sub { return (undef, Slim::Display::Display::symbol('rightarrow')) };
		
				$params->{'overlayRefArgs'} = '';
				$params->{'valueRef'} = \$mixer;
				
				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', $params);
			
			} else {
			
				# if we don't have mix generation, then just play
				(getFunctions())->{'play'}($client);
			}
		},

	);
}

sub mixerExitHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);
	
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	
	} elsif ($exittype eq 'RIGHT') {
		my $Imports = Slim::Music::Import::importers();
	
		if (defined $Imports->{$mixer}->{'mixer'}) {
			$::d_plugins && msg("Running Mixer $mixer\n");
			&{$Imports->{$mixer}->{'mixer'}}($client);
		} else {
			$client->bumpRight();
		}
	
	} else {
		return;
	}
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $push = shift;

	if ($push eq 'push') {
		setSelection($client,'curgenre', selection($client,'genre'));
		setSelection($client,'curartist', selection($client,'artist'));
		setSelection($client,'curalbum', selection($client,'album'));
		setSelection($client,'cursong', selection($client,'song'));
		setSelection($client,'cursearch', selection($client,'search'));
	}
	
	$client->lines(\&lines);
	loadDir($client);
}

sub safe {
	my $i = shift;
	
	return defined($i) ? $i : "";
}

sub updateLastSelection {
	my $client = shift;

	my $artist = safe(selection($client,'curartist'));
	my $album  = safe(selection($client,'curalbum'));
	my $song   = safe(selection($client,'cursong'));
	my $genre  = safe(selection($client,'curgenre'));
	my $search = safe(selection($client,'cursearch'));

	my $select = join('-', $genre, $artist, $album, $song, $search);

	lastSelection($client, $select, browseID3dirIndex($client));

	$client->lastID3Selection($select, browseID3dirIndex($client));
}

sub getLastSelection {
	my $client = shift;

	my $artist = safe(selection($client,'curartist'));
	my $album  = safe(selection($client,'curalbum'));
	my $song   = safe(selection($client,'cursong'));
	my $genre  = safe(selection($client,'curgenre'));
	my $search = safe(selection($client,'cursearch'));

	my $select = join('-', $genre, $artist, $album, $song, $search);

	my $last   = lastSelection($client, $select);

	if (!defined($last)) {
		$last = $client->lastID3Selection($select);
	}

	return $last || 0;
}

# create a directory listing, and append it to dirItems
sub loadDir {
	my ($client) = @_;

	my $genre  = selection($client, 'curgenre');
	my $artist = selection($client, 'curartist');
	my $album  = selection($client, 'curalbum');
	my $song   = selection($client, 'cursong');
	my $search = selection($client, 'cursearch');

	my $sortByTitle;

	# This whole * or not * thing is very wonky to me. Maybe it can be
	# cleaned up with the new DataStores API.
	if (defined($album) && $album eq $client->string('ALL_SONGS')) {
		$album = '*';
		$sortByTitle = 1;
	}

	if (defined($artist) && ($artist eq $client->string('ALL_ALBUMS'))) {
		$artist = '*';
		$sortByTitle = picked($album) ? 0 : 1;
	}

	if (defined($genre) && ($genre eq $client->string('ALL_ARTISTS'))) {
		$genre = '*';
		$sortByTitle = picked($album) ? 0 : 1;
	}

	if ($genre && $genre eq '*' && $artist && $artist eq '*' && $album && $album eq '*' && !specified($song)) {

		$sortByTitle = 1;
	}

	$::d_files && msgf(
		"loading dir for genre: %s artist: %s album: %s song: %s search: %s\n",
		($genre || 'undef'), ($artist || 'undef'), ($album || 'undef'), ($song || 'undef'), ($search || 0)
	);

	# If we've changed into a different mode (say trackinfo) and back,
	# it's hard to keep track of the modestack parameters - so in
	# Search.pm we set the search to be the terms (which may be an
	# arrayref), and if that is equal to any of the below, we've gotten
	# back to the top level (before the search entry), which should be a
	# search and not a regular find().
	my $setSearch = selection($client, 'search');

	if (defined $setSearch && defined $artist && $setSearch eq $artist) {
		$search = $artist;
	} elsif (defined $setSearch && defined $album && $setSearch eq $album) {
		$search = $album;
	} elsif (defined $setSearch && defined $song && $setSearch eq $song) {
		$search = $song;
	}

	# Build up a query hash
	my $ds   = Slim::Music::Info::getCurrentDataStore();
	my $find = {};

	if ($search) {

		$find->{'contributor.name'} = singletonRef($artist) if defined $artist && !specified($artist);
		$find->{'album.title'}      = singletonRef($album)  if defined $album  && !specified($album);
		$find->{'track.title'}      = singletonRef($song)   if defined $song   && !specified($song);

		# Don't try to search again when we're walking through the results tree.
		setSelection($client, 'cursearch', 0);

	} else {

		$find->{'genre'}       = singletonRef($genre)  if specified($genre);
		$find->{'contributor'} = singletonRef($artist) if specified($artist);
		$find->{'album'}       = singletonRef($album)  if specified($album);
		$find->{'track'}       = singletonRef($song)   if specified($song);
	}

	# Limit ourselves to artists only by default.
	if (($find->{'contributor'} || 
	     $find->{'contributor.name'} || 
	     $client->curSelection($client->curDepth()) eq 'BROWSE_BY_ARTIST') && !Slim::Utils::Prefs::get('composerInArtists')) {

		$find->{'contributor.role'} = $Slim::DataStores::DBI::ContributorTrack::contributorToRoleMap{'ARTIST'};
	}

	# These really shouldn't be unrolling the (potentially large) array
	# But there's some wackiness when I try to make it use the ref directly.
	# The wackiness is due to caching of result sets in Slim::Datastores::DBI::DBIStore
	# This combined with the pushes below result in the ALL_X being added
	# to the cached result set each time you perform a loadDir.
	if (picked($genre) && picked($artist) && picked($album)) {

		my $sortBy  = $sortByTitle ? 'title' : 'tracknum';

		@{browseID3dir($client)} = $ds->find('track', $find, $sortBy);

	} elsif (picked($genre) && picked($artist)) {

		# The user has selected the New Music item
		if ($client->curSelection($client->curDepth()) eq 'BROWSE_NEW_MUSIC') {

			@{browseID3dir($client)} = $ds->find('album', $find, 'age', Slim::Utils::Prefs::get('browseagelimit'), 0);

		} else {

			@{browseID3dir($client)} = $ds->find('album', $find, 'album');

			if (scalar @{browseID3dir($client)} > 1) {

				push @{browseID3dir($client)}, $client->string('ALL_SONGS');
			}
		}

	} elsif (picked($genre)) {

		@{browseID3dir($client)} = $ds->find('artist', $find, 'artist');

		if (scalar @{browseID3dir($client)} > 1) {
			push @{browseID3dir($client)}, $client->string('ALL_ALBUMS');
		}

	} else {

		@{browseID3dir($client)} = $ds->find('genre', $find, 'genre');

		if (scalar @{browseID3dir($client)} > 1) { 
			push @{browseID3dir($client)}, $client->string('ALL_ARTISTS');
		}
	}

	return browseID3dirIndex($client, getLastSelection($client));
}

#
# figure out the lines to be put up to display the directory
#
sub lines {
	my $client = shift;
	my ($line1, $line2, $overlay1, $overlay2);

	my $songlist = 0;
	
	my $genre  = _deRef(selection($client,'curgenre'));
	my $artist = _deRef(selection($client,'curartist'));
	my $album  = _deRef(selection($client,'curalbum'));
	my $song   = _deRef(selection($client,'cursong'));

	my $list   = browseID3dir($client);
	my $plural = scalar @$list > 1 ? 'S' : '';

	if (!defined($genre)) {
		$line1 = $client->string('GENRES');
	} elsif ($genre eq '*' && !defined($artist)) {
		$line1 = $client->string('ARTISTS');
	} elsif ($genre eq '*' && $artist eq '*' && !defined($album)) {
		$line1 = $client->string('ALBUMS');
	} elsif ($genre eq '*' && $artist eq '*' && $album eq '*' && !defined($song)) {
		$line1 = $client->string('SONGS');
		$songlist = 1;
	} elsif ($genre eq '*' && $artist eq '*' && $album eq '*' && !specified($song)) {
		$line1 = $client->string('TRACK'.$plural.'MATCHING') . " \"" . searchTerm($song) . "\"";
		$songlist = 1;
	} elsif ($genre eq '*' && $artist eq '*' && !specified($album)) {
		$line1 = $client->string('ALBUM'.$plural.'MATCHING') . " \"" . searchTerm($album) . "\"";
	} elsif ($genre eq '*' && $artist eq '*' && specified($album) && !defined($song)) {
		$line1 = $album;
		$songlist = 1;
	} elsif ($genre eq '*' && !specified($artist)) {
		$line1 = $client->string('ARTIST'.$plural.'MATCHING') . " \"" . searchTerm($artist) . "\"";
	} elsif (specified($genre) && !defined($artist)) {
		$line1 = $genre;
	} elsif ($genre eq '*' && specified($artist) && !defined($album)) {
		$line1 = $artist;
	} elsif (specified($genre) && specified($artist) && !defined($album)) {
		$line1 = $genre.'/'.$artist;
	} elsif (specified($genre) && specified($artist) && specified($album) && !defined($song)) {
		$line1 = $artist.'/'.$album;
		$songlist = 1;
	} elsif ($genre eq '*' && specified($artist) && specified($album) && !defined($song)) {
		$line1 = $artist.'/'.$album;
		$songlist = 1;
	} else {
		die "can't calculate string for $genre $artist $album $song";
	}

	if (scalar @$list == 0) {

		$line2 = $client->string('EMPTY');

	} else {

		$line1 .= sprintf(" (%d %s %s)", browseID3dirIndex($client) + 1, $client->string('OUT_OF'), scalar @$list);

		my $ds = Slim::Music::Info::getCurrentDataStore();

		if ($songlist) {

			my $line = browseID3dir($client, browseID3dirIndex($client));
			my $obj  = $ds->objectForUrl($line);

			$line2 = Slim::Music::Info::standardTitle($client, $obj);

			if (defined $obj && ref $obj) {

				if ($obj->moodlogic_mixable() || $obj->musicmagic_mixable()) {

					$overlay1 = Slim::Display::Display::symbol('mixable');
				}

			} else {

				Slim::Utils::Misc::msg("Couldn't get object for url: [$line]\n");
			}

			$overlay2 = Slim::Display::Display::symbol('notesymbol');

		} else {

			$line2 = browseID3dir($client, browseID3dirIndex($client));
			my $obj;

			# genre
			if (!defined($genre) && !defined($artist) && !defined($album)) {

				($obj) = $ds->find('genre', { 'genre' => $line2 });
			}

			# artist
			if (defined($genre) && !defined($artist) && !defined($album)) {

				($obj) = $ds->find('contributor', { 'contributor' => $line2 });
			}

			# album
			if (defined($genre) && defined($artist) && ! defined($album)) {

				($obj) = $ds->find('album', { 'album' => $line2 });
			}

			# Music Magic is everywhere, MoodLogic doesn't exist on albums
			if (defined $obj && ref $obj) {

				if (($obj->can('moodlogic_mixable') && $obj->moodlogic_mixable()) || $obj->musicmagic_mixable()) {

					$overlay1 = Slim::Display::Display::symbol('mixable');
				}
			}

			$overlay2 = Slim::Display::Display::symbol('rightarrow');
		}
	}

	return ($line1, $line2, $overlay1, $overlay2);
}

sub browseID3dir {
	my $client = shift;
	my $index = shift;
	my $value = shift;

	# get a reference to the browseID3dir array that's kept in param stack
	my $arrayref = $client->param( 'browseID3dir');

	# if it doesn't exist, make a new one (anonymously)
	if (!defined $arrayref) {

		$arrayref = [];

		$client->param( 'browseID3dir', $arrayref);
	}

	# if the value is set, then save it in the array
	if (defined $value && $index) {
		$arrayref->[$index] = $value;
	}

	# if the index is set, then return it, otherwise return a reference to the array itself
	if (defined $index) {
		return $arrayref->[$index];
	} else {
		return $arrayref;
	}
}

#	get the current selection parameter from the parameter stack (artist, album, genre, etc...)
sub selection {
	my $client = shift;
	my $index = shift;

	my $value = $client->param( $index);

	if (defined $value  && $value eq '__undefined') {
		undef $value;
	}

	return $value;
}

#	set the current selection parameter from the parameter stack (artist, album, genre, etc...)
sub setSelection {
	my $client = shift;
	my $index  = shift;
	my $value  = shift;

	if (!defined $value) {
		$value = '__undefined';
	}

	$client->param( $index, $value);
}

#	get or set the lastSelection in the hash in the parameter stack
sub lastSelection {
	my $client = shift;
	my $index = shift;
	my $value = shift;

	my $arrayref = $client->param( 'lastSelection');

	if (!defined $arrayref) {
		$arrayref = {};
		$client->param( 'lastSelection', $arrayref);
	}

	if (defined $value) {
		$arrayref->{$index} = $value;
	}

	if (defined $index) {
		return $arrayref->{$index};
	} else {
		return $arrayref;
	}
}

# get (and optionally set) the directory index
sub browseID3dirIndex {
	my $client = shift;

	return $client->param( 'browseID3dirIndex', shift) || 0;
}

# undefined or contains a *
sub any {
	my $i = shift;
	return (!defined $i || $i =~ /\*/);
}

sub equal {
	my $a = shift;
	my $b = shift;
	if (!defined($a) && !defined($b)) { return 1; }
	if (!defined($a) || !defined($b)) { return 0; }
	if ($a eq $b) { return 1; }
	return 0;
}

# defined, but does not contain a *
sub specified {
	my $i = shift;

	return 0 if ref($i) eq 'ARRAY';
	return 0 unless defined $i;
	return $i !~ /\*/;
}

# defined and does not contain a star or equals star
sub picked {
	my $i = shift;

	return 0 if ref($i) eq 'ARRAY';
	return 0 unless defined $i;
	return (specified($i) || $i eq "*");
}

sub searchTerm {
	my $t = shift;
	
	$t =~ s/^\*?(.+)\*$/$1/;
	return $t;
}

sub singletonRef {
	my $arg = shift;

	unless (defined($arg)) {

		return $arg;

	} elsif ($arg eq '*') {

		return [];

	} elsif (my ($g1) = ($arg =~ /^\*(.*)\*$/)) {

		my @sa = ();
		for my $ss (split(' ',$g1)) {
			push @sa, "*" . $ss . "*";
		}

		return \@sa;

	} elsif (ref $arg eq 'ARRAY') {

		return $arg;

	} elsif ($arg) {

		return [$arg];

	} else {

		return [];
	}
}

sub _deRef {
	my $item = shift;

	return $item->[0] if ref($item) eq 'ARRAY';
	return $item;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
