package Slim::Buttons::TrackInfo;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Utils::Misc;
use Slim::Utils::Favorites;

our %functions = ();

# button functions for track info screens
sub init {

	Slim::Buttons::Common::addMode('trackinfo', getFunctions(), \&setMode);

	%functions = (

		'play' => sub  {
			my $client = shift;

			my $curItem = $client->trackInfoContent->[currentLine($client)];

			unless ($curItem) {
				Slim::Buttons::Common::popModeRight($client);
				$client->execute(["button", "play", undef]);
				return;
			}

			my $line1 = '';

			if (Slim::Player::Playlist::shuffle($client)) {
				$line1 = $client->string('PLAYING_RANDOMLY_FROM');
			} else {
				$line1 = $client->string('NOW_PLAYING_FROM')
			}
			
			my ($line2, @search) = _trackDataForCurrentItem($client, $curItem);

			$client->showBriefly($client->renderOverlay($line1, $line2, undef, Slim::Display::Display::symbol('notesymbol')), undef,1);

			$client->execute(['playlist', 'loadalbum', @search]);
			$client->execute(['playlist', 'jump', 0]);
		},
		
		'add' => sub  {
			my $client = shift;

			my $curItem = $client->trackInfoContent->[currentLine($client)];

			unless ($curItem) {
				Slim::Buttons::Common::popModeRight($client);
				$client->execute(["button", "add", undef]);
				return;
			}

			my $line1  = $client->string('ADDING_TO_PLAYLIST');
			my ($line2, @search) = _trackDataForCurrentItem($client, $curItem);

			$client->showBriefly($client->renderOverlay($line1, $line2, undef, Slim::Display::Display::symbol('notesymbol')), undef,1);

			$client->execute(["playlist", "addalbum", @search]);
		},
		
		'up' => sub  {
			my $client = shift;

			my $newpos = Slim::Buttons::Common::scroll($client, -1, $#{$client->trackInfoLines} + 1, currentLine($client));
			if ($newpos != 	currentLine($client)) {
				currentLine($client, $newpos);
				$client->pushUp();
			}
		},

		'down' => sub  {
			my $client = shift;
			my $newpos = Slim::Buttons::Common::scroll($client, +1, $#{$client->trackInfoLines} + 1, currentLine($client));
			if ($newpos != 	currentLine($client)) {
				currentLine($client, $newpos);
				$client->pushDown();
			}
		},

		'left' => sub  {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},

		'right' => sub  {
			my $client = shift;

			my $push     = 1;
			my $curitem  = $client->trackInfoContent->[currentLine($client)];
			my @oldlines = Slim::Display::Display::curLines($client);

			if (!defined($curitem)) {
				$curitem = "";
			}

			# Pull directly from the datasource
			my $ds      = Slim::Music::Info::getCurrentDataStore();
			my $track   = $ds->objectForUrl(track($client));

			if ($curitem eq 'ALBUM') {

				my $album = $track->album();

				Slim::Buttons::Common::pushMode($client, 'browsedb', {
					'hierarchy'  => 'track',
					'level'      => 0,
					'findCriteria' => { 'album' => $album->id() },
				});

			} elsif ($curitem =~ /^(?:ARTIST|COMPOSER|CONDUCTOR|BAND)$/) {

				my $lcItem = lc($curitem);

				my ($contributor) = $track->$lcItem();

				Slim::Buttons::Common::pushMode($client, 'browsedb', {
					'hierarchy'  => 'album,track',
					'level'      => 0,
					'findCriteria' => { 'artist' => $contributor->id() },
				});

			} elsif ($curitem eq 'GENRE') {

				my $genre = $track->genre();
				Slim::Buttons::Common::pushMode($client, 'browsedb', {
					'hierarchy'  => 'artist,album,track',
					'level'      => 0,
					'findCriteria' => { 'genre' => $genre->id() },
				});

			} elsif ($curitem eq 'FAVORITE') {
				my $num = $client->param('favorite');
				if ($num < 0) {
					my $num = Slim::Utils::Favorites->clientAdd($client, track($client), $track->title());
					$client->showBriefly($client->string('FAVORITES_ADDING'),
										 $track->title());
					$client->param('favorite', $num);
				} else {
					Slim::Utils::Favorites->deleteByClientAndURL($client, track($client));
					$client->showBriefly($client->string('FAVORITES_DELETING'),
										 $track->title());
					$client->param('favorite', -1);
				}
				$push = 0;
			} else {

				$push = 0;
				$client->bumpRight();
			}

			if ($push) {
				$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
			}
		},

		'numberScroll' => sub  {
			my ($client, $button, $digit) = @_;

			currentLine($client, Slim::Buttons::Common::numberScroll($client, $digit, $client->trackInfoLines, 0));
			$client->update();
		}
	);
}

sub _trackDataForCurrentItem {
	my $client = shift;
	my $item   = shift || return;

	# Pull directly from the datasource
	my $ds      = Slim::Music::Info::getCurrentDataStore();
	my $track   = $ds->objectForUrl(track($client));

	# genre is used by everything		
	my $genre   = $track->genre();

	my @search  = ();
	my $line2;
	
	if ($item eq 'GENRE') {

		$line2 = $genre;

		push @search, $genre, '*', '*';

	} elsif ($item =~ /^(?:ARTIST|COMPOSER|CONDUCTOR|BAND)$/) {

		my $lcItem = lc($item);

		$line2 = $track->$lcItem();

		push @search, $genre, $line2, '*';

	} elsif ($item eq 'ALBUM') {

		$line2 = $track->album()->title();

		push @search, $genre, $track->artist(), $line2;
	}

	return ($line2, @search);
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $item = shift;
	$client->lines(\&lines);
	preloadLines($client, track($client));
}

# get (and optionally set) the track URL
sub track {
	my $client = shift;
	return $client->param( 'track', shift);
}

# get (and optionally set) the track info scroll position
sub currentLine {
	my $client = shift;

	my $line = $client->param( 'line', shift) || 0;

	return $line
}

sub preloadLines {
	my $client = shift;
	my $url    = shift;

	@{$client->trackInfoLines}   = ();
	@{$client->trackInfoContent} = ();

	my $ds    = Slim::Music::Info::getCurrentDataStore();
	my $track = $ds->objectForUrl($url);

	# Couldn't get a track or URL? How do people get in this state?
	if (!$url || !$track) {
		push (@{$client->trackInfoLines}, "Error! url: [$url] is empty or a track could not be retrieved.\n");
		push (@{$client->trackInfoContent}, undef);

		return;
	}

	if (my $title = $track->title()) {
		push (@{$client->trackInfoLines}, $client->string('TITLE') . ": $title");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my ($artist) = $track->artist()) {
		push (@{$client->trackInfoLines}, $client->string('ARTIST') . ": $artist");
		push (@{$client->trackInfoContent}, 'ARTIST');
	}

	if (my ($band) = $track->band()) {
		push (@{$client->trackInfoLines}, $client->string('BAND') . ": $band");
		push (@{$client->trackInfoContent}, 'BAND');
	}

	if (my ($composer) = $track->composer()) {
		push (@{$client->trackInfoLines}, $client->string('COMPOSER') . ": $composer");
		push (@{$client->trackInfoContent}, 'COMPOSER');
	}

	if (my ($conductor) = $track->conductor()) {
		push (@{$client->trackInfoLines}, $client->string('CONDUCTOR') . ": $conductor");
		push (@{$client->trackInfoContent}, 'CONDUCTOR');
	}

	if (my $album = $track->album()) {
		push (@{$client->trackInfoLines}, $client->string('ALBUM') . ": $album");
		push (@{$client->trackInfoContent}, 'ALBUM');
	}

	if (my $tracknum = $track->tracknum()) {
		push (@{$client->trackInfoLines}, $client->string('TRACK') . ": $tracknum");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $year = $track->year()) {
		push (@{$client->trackInfoLines}, $client->string('YEAR') . ": $year");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $genre = $track->genre()) {
		push (@{$client->trackInfoLines}, $client->string('GENRE') . ": $genre");
		push (@{$client->trackInfoContent}, 'GENRE');
	}

	if (my $ct = $ds->contentType($track)) {
		push (@{$client->trackInfoLines}, $client->string('TYPE') . ": " . $client->string(uc($ct)));
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $comment = $track->comment()) {
		push (@{$client->trackInfoLines}, $client->string('COMMENT') . ": $comment");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $duration = $track->duration()) {
		push (@{$client->trackInfoLines}, $client->string('LENGTH') . ": $duration");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $bitrate = $track->bitrate()) {

		my $undermax = Slim::Player::Source::underMax($client, $url);

		my $rate = (defined $undermax && $undermax) ? $bitrate : Slim::Utils::Prefs::maxRate($client).$client->string('KBPS')." CBR";

		push (@{$client->trackInfoLines}, 
			$client->string('BITRATE').": $bitrate " .
				(($client->param( 'current') && (defined $undermax && !$undermax)) 
					? '('.$client->string('CONVERTED_TO').' '.$rate.')' : ''));

		push (@{$client->trackInfoContent}, undef);
	}

	if (my $len = $track->filesize()) {
		push (@{$client->trackInfoLines}, $client->string('FILELENGTH') . ": " . Slim::Utils::Misc::delimitThousands($len));
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $age = $track->modificationTime()) {
		push (@{$client->trackInfoLines}, $client->string('MODTIME').": $age");
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::isURL($url)) {
		push (@{$client->trackInfoLines}, "URL: ". $url);
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $tag = $track->tagversion()) {
		push (@{$client->trackInfoLines}, $client->string('TAGVERSION') . ": $tag");
		push (@{$client->trackInfoContent}, undef);
	}

	if ($track->drm()) {
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

#
# figure out the lines to be put up to display the directory
#
sub lines {
	my $client = shift;

	# Show the title of the song with a note symbol
	my $line1 = Slim::Music::Info::standardTitle($client, track($client));

	# add position string
	my $overlay1 = ' (' . (currentLine($client)+1)
				. ' ' . $client->string('OF') .' ' . scalar(@{$client->trackInfoLines}) . ')';
	
	$overlay1 .= Slim::Display::Display::symbol('notesymbol');
	
	my $line2 = $client->trackInfoLines->[currentLine($client)];
	my $overlay2 = defined($client->trackInfoContent->[currentLine($client)]) ? Slim::Display::Display::symbol('rightarrow') : undef;

	# special case favorites line, which must be determined dynamically
	if ($line2 eq 'FAVORITE') {
		if ((my $num = $client->param('favorite')) < 0) {
			$line2 = $client->string('FAVORITES_RIGHT_TO_ADD');
		} else {
			$line2 = $client->string('FAVORITES_FAVORITE_NUM') . "$num " . $client->string('FAVORITES_RIGHT_TO_DELETE');
		}
		$overlay2 = undef;
	}

	return ($line1, $line2, $overlay1, $overlay2);
}

1;

__END__
