package Slim::Buttons::TrackInfo;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Utils::Misc;

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
				Slim::Control::Command::execute($client, ["button", "play", undef]);
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

			Slim::Control::Command::execute($client, ['playlist', 'loadalbum', @search]);
			Slim::Control::Command::execute($client, ['playlist', 'jump', 0]);
		},
		
		'add' => sub  {
			my $client = shift;

			my $curItem = $client->trackInfoContent->[currentLine($client)];

			unless ($curItem) {
				Slim::Buttons::Common::popModeRight($client);
				Slim::Control::Command::execute($client, ["button", "add", undef]);
				return;
			}

			my $line1  = $client->string('ADDING_TO_PLAYLIST');
			my ($line2, @search) = _trackDataForCurrentItem($client, $curItem);

			$client->showBriefly($client->renderOverlay($line1, $line2, undef, Slim::Display::Display::symbol('notesymbol')), undef,1);

			Slim::Control::Command::execute($client, ["playlist", "addalbum", @search]);
		},
		
		'up' => sub  {
			my $client = shift;

			currentLine($client, Slim::Buttons::Common::scroll($client, -1, $#{$client->trackInfoLines} + 1, currentLine($client)));
			$client->update();
		},

		'down' => sub  {
			my $client = shift;

			currentLine($client, Slim::Buttons::Common::scroll($client, +1, $#{$client->trackInfoLines} + 1, currentLine($client)));
			$client->update();
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

				my $album = $track->album()->title();

				Slim::Buttons::BrowseID3::setSelection($client, '*', '*', $album, undef);

				Slim::Buttons::Common::pushMode($client, 'browseid3', {
					'genre'  => '*',
					'artist' => '*',
					'album'  => $album
				});

			} elsif ($curitem =~ /^(?:ARTIST|COMPOSER|CONDUCTOR|BAND)$/) {

				my $lcItem = lc($curitem);

				Slim::Buttons::Common::pushMode($client, 'browseid3', {
					'genre'  => '*',
					'artist' => $track->$lcItem(),
				});

			} elsif ($curitem eq 'GENRE') {

				Slim::Buttons::Common::pushMode($client, 'browseid3', {
					'genre' => $track->genre(),
				});

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
	return Slim::Buttons::Common::param($client, 'track', shift);
}

# get (and optionally set) the track info scroll position
sub currentLine {
	my $client = shift;

	my $line = Slim::Buttons::Common::param($client, 'line', shift) || 0;

	return $line
}

sub preloadLines {
	my $client = shift;
	my $url = shift;

	@{$client->trackInfoLines} = ();
	@{$client->trackInfoContent} = ();

	my $ds    = Slim::Music::Info::getCurrentDataStore();
	my $track = $ds->objectForUrl($url);

	if (my $title = $track->title()) {
		push (@{$client->trackInfoLines}, $client->string('TITLE') . ": $title");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $artist = $track->artist()) {
		push (@{$client->trackInfoLines}, $client->string('ARTIST') . ": $artist");
		push (@{$client->trackInfoContent}, 'ARTIST');
	}

	if (my $band = $track->band()) {
		push (@{$client->trackInfoLines}, $client->string('BAND') . ": $track");
		push (@{$client->trackInfoContent}, 'BAND');
	}

	if (my $composer = $track->composer()) {
		push (@{$client->trackInfoLines}, $client->string('COMPOSER') . ": $composer");
		push (@{$client->trackInfoContent}, 'COMPOSER');
	}

	if (my $conductor = $track->conductor()) {
		push (@{$client->trackInfoLines}, $client->string('CONDUCTOR') . ": $conductor");
		push (@{$client->trackInfoContent}, 'CONDUCTOR');
	}

	if (my $album = $track->album()->title()) {
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

	if (my $ct = $ds->contentType($track, 1)) {
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
				((Slim::Buttons::Common::param($client, 'current') && (defined $undermax && !$undermax)) 
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
}

#
# figure out the lines to be put up to display the directory
#
sub lines {
	my $client = shift;

	# Show the title of the song with a note symbol
	my $line1 = Slim::Music::Info::standardTitle($client, track($client));
	my $line2 = $client->trackInfoLines->[currentLine($client)];

	my $overlay1 = Slim::Display::Display::symbol('notesymbol');
	my $overlay2 = defined($client->trackInfoContent->[currentLine($client)]) ? Slim::Display::Display::symbol('rightarrow') : undef;

	return ($line1, $line2, $overlay1, $overlay2);
}

1;

__END__
