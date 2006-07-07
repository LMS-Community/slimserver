package Slim::Buttons::TrackInfo;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Displays the extra track information screen that is got into by pressing right on an item 
# in the now playing screen.

use strict;
use Scalar::Util qw(blessed);

use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Misc;
use Slim::Utils::Favorites;

our %functions = ();

# button functions for track info screens
sub init {

	Slim::Buttons::Common::addMode('trackinfo', getFunctions(), \&setMode);

	%functions = (

		'play' => sub  {
			my $client = shift;
			my $button = shift;
			my $addOrInsert = shift;

			playOrAdd($client,$addOrInsert);
			$client->execute(['playlist', 'jump', 0]) unless $addOrInsert;
		},
	);
}

sub playOrAdd {
	my $client = shift;
	my $addOrInsert = shift || 0;

	my ($command, $string, $line1);
	
	if ($addOrInsert == 2) {
		$string = 'INSERT_TO_PLAYLIST';
		$command = "inserttracks";
	} elsif ($addOrInsert == 1) {
		$string = 'ADDING_TO_PLAYLIST';
		$command = "addtracks";
	} else {
		if (Slim::Player::Playlist::shuffle($client)) {
			$string = 'PLAYING_RANDOMLY_FROM';
		} else {
			$string = 'NOW_PLAYING_FROM';
		}
		$command = "loadtracks";
	}
	my $curItem = $client->trackInfoContent->[$client->param('listIndex')];

	unless ($curItem) {
		Slim::Buttons::Common::popModeRight($client);
		$client->execute(["button", $addOrInsert ? "add" : "play", undef]);
		return;
	}

	my ($line2, $termlist) = _trackDataForCurrentItem($client, $curItem);

	if ($client->linesPerScreen == 1) {
		$line2 = $client->doubleString($string);
	} else {
		$line1 = $client->string($string);
	}
	
	$client->showBriefly( {
		'line1' => $line1,
		'line2' => $line2,
		'overlay2' => $client->symbols('notesymbol'),
	});

	$client->execute(['playlist', $command, $termlist]);
}

sub _trackDataForCurrentItem {
	my $client = shift;
	my $item   = shift || return;

	my $track  = Slim::Schema->rs('Track')->objectForUrl(track($client));

	if (!blessed($track) || !$track->can('genre')) {

		errorMsg("_trackDataForCurrentItem: Unable to get objectForUrl!\n");
		return 0;
	}

	# genre is used by everything		
	my $genre   = $track->genre;
		
	my @search  = ();
	my $line2;
	
	if ($item eq 'GENRE') {

		$line2 = $genre;

		push @search, join('=', 'genre.id', $genre->id);

	# TODO make this work for other contributors
	#} elsif ($item =~ /^(?:ARTIST|COMPOSER|CONDUCTOR|BAND)$/) {
	} elsif ($item eq 'ARTIST') {

		my $lcItem = lc($item);

		$line2 = $track->artist;

		push @search, join('=', 'contributor.id', $track->artist->id);

	} elsif ($item eq 'ALBUM') {

		$line2 = $track->album->title;

		push @search, join('=', 'album.id', $track->album->id);

	} elsif ($item eq 'YEAR') {

		$line2 = $track->year;

		push @search, join('=', 'album.year', $track->year);
	}

	return ($line2, join('&', @search));
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	preloadLines($client, track($client));
	
	my %params = (
		'header'         => sub { return Slim::Music::Info::getCurrentTitle($_[0], track($_[0]))},
		'headerArgs'     => 'CVI',
		'listRef'        => \@{$client->trackInfoLines},
		'externRef'      => \&infoLine,
		'externRefArgs'  => 'CVI',
		'overlayRef'     => \&overlay,
		'overlayRefArgs' => 'CVI',
		'callback'       => \&listExitHandler,
		
		# carry some params forward
		'track'          => $client->param('track'),
		'current'        => $client->param('current'),
		'favorite'       => $client->param('favorite'),
	);
	
	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

# get (and optionally set) the track URL
sub track {
	my $client = shift;

	return $client->param('track', shift);
}

sub preloadLines {
	my $client = shift;
	my $url    = shift;

	@{$client->trackInfoLines}   = ();
	@{$client->trackInfoContent} = ();

	my $track = Slim::Schema->rs('Track')->objectForUrl($url);

	# Couldn't get a track or URL? How do people get in this state?
	if (!$url || !blessed($track) || !$track->can('title')) {
		push (@{$client->trackInfoLines}, "Error! url: [$url] is empty or a track could not be retrieved.\n");
		push (@{$client->trackInfoContent}, undef);

		return;
	}

	if (my $title = $track->title) {
		push (@{$client->trackInfoLines}, $client->string('TITLE') . ": $title");
		push (@{$client->trackInfoContent}, undef);
	}

	# Loop through the contributor types and append
	for my $role (sort $track->contributorRoles) {

		for my $contributor ($track->contributorsOfType($role)) {

			push (@{$client->trackInfoLines}, sprintf('%s: %s', $client->string(uc($role)), $contributor->name));
			push (@{$client->trackInfoContent}, uc($role));
		}
	}

	my $album = $track->album;

	if ($album) {
		push (@{$client->trackInfoLines}, join(': ', $client->string('ALBUM'), $album->name));
		push (@{$client->trackInfoContent}, 'ALBUM');
	}

	if (my $tracknum = $track->tracknum) {
		push (@{$client->trackInfoLines}, $client->string('TRACK') . ": $tracknum");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $year = $track->year) {
		push (@{$client->trackInfoLines}, $client->string('YEAR') . ": $year");
		push (@{$client->trackInfoContent}, 'YEAR');
	}

	if (my $genre = $track->genre) {
		push (@{$client->trackInfoLines}, join(': ', $client->string('GENRE'), $genre->name));
		push (@{$client->trackInfoContent}, 'GENRE');
	}

	if (my $ct = Slim::Schema->contentType($track)) {
		push (@{$client->trackInfoLines}, $client->string('TYPE') . ": " . $client->string(uc($ct)));
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $comment = $track->comment) {
		push (@{$client->trackInfoLines}, $client->string('COMMENT') . ": $comment");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $duration = $track->duration) {
		push (@{$client->trackInfoLines}, $client->string('LENGTH') . ": $duration");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $replaygain = $track->replay_gain) {
		push (@{$client->trackInfoLines}, $client->string('REPLAYGAIN') . ": " . sprintf("%2.2f",$replaygain) . " dB");
		push (@{$client->trackInfoContent}, undef);
	}
	
	if (my $rating = $track->rating) {
		push (@{$client->trackInfoLines}, $client->string('RATING') . ": " . sprintf("%d",$rating) . " /100");
		push (@{$client->trackInfoContent}, undef);
	}
	
	if (blessed($album) && $album->can('replay_gain')) {

		if (my $albumreplaygain = $album->replay_gain) {
			push (@{$client->trackInfoLines}, $client->string('ALBUMREPLAYGAIN') . ": " . sprintf("%2.2f",$albumreplaygain) . " dB");
			push (@{$client->trackInfoContent}, undef);
		}
	}

	if (my $bitrate = ( Slim::Music::Info::getCurrentBitrate($url) || $track->prettyBitRate ) ) {

		my $undermax = Slim::Player::TranscodingHelper::underMax($client, $url);

		my $rate = (defined $undermax && $undermax) ? $bitrate : Slim::Utils::Prefs::maxRate($client).$client->string('KBPS')." ABR";

		push (@{$client->trackInfoLines}, 
			$client->string('BITRATE').": $bitrate " .
				(($client->param( 'current') && (defined $undermax && !$undermax)) 
					? '('.$client->string('CONVERTED_TO').' '.$rate.')' : ''));

		push (@{$client->trackInfoContent}, undef);
	}

	if ($track->samplerate) {
		push (@{$client->trackInfoLines}, $client->string('SAMPLERATE') . ": " . $track->prettySampleRate);
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $len = $track->filesize) {
		push (@{$client->trackInfoLines}, $client->string('FILELENGTH') . ": " . Slim::Utils::Misc::delimitThousands($len));
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $age = $track->modificationTime) {
		push (@{$client->trackInfoLines}, $client->string('MODTIME').": $age");
		push (@{$client->trackInfoContent}, undef);
	}

	if (blessed($track) && $track->can('url')) {
		push (@{$client->trackInfoLines}, "URL: ". Slim::Utils::Misc::unescape($track->url));
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $tag = $track->tagversion) {
		push (@{$client->trackInfoLines}, $client->string('TAGVERSION') . ": $tag");
		push (@{$client->trackInfoContent}, undef);
	}

	if ($track->drm) {
		push (@{$client->trackInfoLines}, $client->string('DRM'));
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::isURL($url)) {
		my $fav = Slim::Utils::Favorites->findByClientAndURL($client, $url);
		if ($fav) {
			$client->param('favorite', $fav->{'num'});
		} else {
			$client->param('favorite', -1);
		}
		push (@{$client->trackInfoLines}, 'FAVORITE'); # replaced in lines()
		push (@{$client->trackInfoContent}, 'FAVORITE');
	}
}

sub listExitHandler {
	my ($client,$exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);
		
	} elsif ($exittype eq 'RIGHT') {

		my $push     = 1;
		# Look up if this is an artist, album, year etc
		my $curitem  = $client->trackInfoContent->[$client->param('listIndex')];
		my @oldlines = Slim::Display::Display::curLines($client);

		if (!defined($curitem)) {
			$curitem = "";
		}

		# Get object for currently being browsed song from the datasource
		# This probably isn't necessary as track($client) is already an object!
		my $track = Slim::Schema->rs('Track')->objectForUrl(track($client));

		if (!blessed($track) || !$track->can('album') || !$track->can('artist')) {

			errorMsg("Unable to fetch valid track object for currently selected item!\n");
			return 0;
		}

		my $album  = $track->album;
		my $artist = $track->artist;

		# Bug: 2528
		#
		# Only check to see if album & artist are valid
		# objects if we're going to be performing a method
		# call on them. Otherwise it's ok to not have them for
		# Internet Radio streams which can be saved to favorites.
		if ($curitem =~ /^(?:ALBUM|ARTIST|COMPOSER|CONDUCTOR|BAND|YEAR|GENRE)$/) {

			if (!blessed($album) || !blessed($artist) || !$album->can('id') || !$artist->can('id')) {

				errorMsg("Unable to fetch valid album or artist object for currently selected track!\n");
				return 0;
			}
		}

		my $selectionCriteria = {
			'track'       => $track->id,
			'album'       => $album->id,
			'contributor' => $artist->id,
		};

		if ($curitem eq 'ALBUM') {

			Slim::Buttons::Common::pushMode($client, 'browsedb', {
				'hierarchy'         => 'album,track',
				'level'             => 1,
				'findCriteria'      => { 'album.id' => $album->id },
				'selectionCriteria' => $selectionCriteria,
			});

		} elsif ($curitem =~ /^(?:ARTIST|COMPOSER|CONDUCTOR|BAND)$/) {

			my $lcItem = lc($curitem);

			my ($contributor) = $track->$lcItem();

			Slim::Buttons::Common::pushMode($client, 'browsedb', {
				'hierarchy'         => 'contributor,album,track',
				'level'             => 1,
				'findCriteria'      => { 'contributor.id' => $contributor->id },
				'selectionCriteria' => $selectionCriteria,
			});

		} elsif ($curitem eq 'GENRE') {

			my $genre = $track->genre;
			Slim::Buttons::Common::pushMode($client, 'browsedb', {
				'hierarchy'         => 'genre,contributor,album,track',
				'level'             => 1,
				'findCriteria'      => { 'genre.id' => $genre->id },
				'selectionCriteria' => $selectionCriteria,
			});

		} elsif ($curitem eq 'YEAR') {

			my $year = $track->year;

			Slim::Buttons::Common::pushMode($client, 'browsedb', {
				'hierarchy'         => 'year,album,track',
				'level'             => 1,
				'findCriteria'      => { 'album.year' => $year },
				'selectionCriteria' => $selectionCriteria,
			});

		} elsif ($curitem eq 'FAVORITE') {

			my $num = $client->param('favorite');

			if ($num < 0) {

				$num = Slim::Utils::Favorites->clientAdd($client, track($client), $track->title);

				$client->showBriefly($client->string('FAVORITES_ADDING'), $track->title);

				$client->param('favorite', $num);

			} else {

				Slim::Utils::Favorites->deleteByClientAndURL($client, track($client));

				$client->showBriefly($client->string('FAVORITES_DELETING'), $track->title);

				$client->param('favorite', -1);
			}

			$push = 0;

		} else {

			$push = 0;
			$client->bumpRight;
		}

		if ($push) {
			$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
		}
	}
}

sub infoLine {
	my ($client,$value,$index) = @_;

	# 2nd line's content is provided entirely by trackInfoLines, which returns an array of information lines
	my $line2 = $client->trackInfoLines->[$index];

	# special case favorites line, which must be determined dynamically
	if ($line2 eq 'FAVORITE') {
		if ((my $num = $client->param('favorite')) < 0) {
			$line2 = $client->string('FAVORITES_RIGHT_TO_ADD');
		} else {
			$line2 = $client->string('FAVORITES_FAVORITE_NUM') . "$num " . $client->string('FAVORITES_RIGHT_TO_DELETE');
		}
	}

	return $line2;
}

sub overlay {
	my ($client,$value,$index) = @_;

	# add position string
	my $overlay1 = ' (' . ($index+1)
				. ' ' . $client->string('OF') .' ' . scalar(@{$client->trackInfoLines}) . ')';
	# add note symbol
	$overlay1 .= Slim::Display::Display::symbol('notesymbol');
	
	# add right arrow symbol if current line can point to more info e.g. artist, album, year etc
	my $overlay2 = defined($client->trackInfoContent->[$index]) ? Slim::Display::Display::symbol('rightarrow') : undef;

	return ($overlay1, $overlay2);
}

1;

__END__
