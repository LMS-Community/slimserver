package Slim::Buttons::TrackInfo;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw (string);

# button functions for track info screens

Slim::Buttons::Common::addMode('trackinfo',Slim::Buttons::TrackInfo::getFunctions(),\&Slim::Buttons::TrackInfo::setMode);

my %functions = (

	'play' => sub  {
			my $client = shift;
			my $curitem = $client->trackInfoContent->[currentLine($client)];
			my ($line1, $line2);
			
			if (Slim::Player::Playlist::shuffle($client)) {
				$line1 = string('PLAYING_RANDOMLY_FROM');
			} else {
				$line1 = string('NOW_PLAYING_FROM')
			}
			
			if ($curitem && $curitem eq 'GENRE') {
				$line2 = Slim::Music::Info::genre(track($client));
				Slim::Display::Animation::showBriefly($client, Slim::Display::Display::renderOverlay($line1, $line2, undef, Slim::Hardware::VFD::symbol('notesymbol')), undef,1);
				Slim::Control::Command::execute($client, ["playlist", "loadalbum", Slim::Music::Info::genre(track($client)), "*", "*"]);
				Slim::Control::Command::execute($client, ["playlist", "jump", "0"]);
			} elsif ($curitem && ($curitem eq 'ARTIST')) {
				$line2 = Slim::Music::Info::artist(track($client));
				Slim::Display::Animation::showBriefly($client, Slim::Display::Display::renderOverlay($line1, $line2, undef, Slim::Hardware::VFD::symbol('notesymbol')), undef,1);
				Slim::Control::Command::execute($client, ["playlist", "loadalbum", Slim::Music::Info::genre(track($client)), Slim::Music::Info::artist(track($client)), "*"]);			
				Slim::Control::Command::execute($client, ["playlist", "jump", "0"]);
			} elsif ($curitem && ($curitem eq 'COMPOSER')) {
				$line2 = Slim::Music::Info::composer(track($client));
				Slim::Display::Animation::showBriefly($client, Slim::Display::Display::renderOverlay($line1, $line2, undef, Slim::Hardware::VFD::symbol('notesymbol')), undef,1);
				Slim::Control::Command::execute($client, ["playlist", "loadalbum", Slim::Music::Info::genre(track($client)), Slim::Music::Info::composer(track($client)), "*"]);			
				Slim::Control::Command::execute($client, ["playlist", "jump", "0"]);
			} elsif ($curitem && ($curitem eq 'CONDUCTOR')) {
				$line2 = Slim::Music::Info::conductor(track($client));
				Slim::Display::Animation::showBriefly($client, Slim::Display::Display::renderOverlay($line1, $line2, undef, Slim::Hardware::VFD::symbol('notesymbol')), undef,1);
				Slim::Control::Command::execute($client, ["playlist", "loadalbum", Slim::Music::Info::genre(track($client)), Slim::Music::Info::conductor(track($client)), "*"]);			
				Slim::Control::Command::execute($client, ["playlist", "jump", "0"]);
			} elsif ($curitem && ($curitem eq 'BAND')) {
				$line2 = Slim::Music::Info::band(track($client));
				Slim::Display::Animation::showBriefly($client, Slim::Display::Display::renderOverlay($line1, $line2, undef, Slim::Hardware::VFD::symbol('notesymbol')), undef,1);
				Slim::Control::Command::execute($client, ["playlist", "loadalbum", Slim::Music::Info::genre(track($client)), Slim::Music::Info::band(track($client)), "*"]);			
				Slim::Control::Command::execute($client, ["playlist", "jump", "0"]);
			} elsif ($curitem && $curitem eq 'ALBUM') {
				$line2 = Slim::Music::Info::album(track($client));
				Slim::Display::Animation::showBriefly($client, Slim::Display::Display::renderOverlay($line1, $line2, undef, Slim::Hardware::VFD::symbol('notesymbol')), undef,1);
				Slim::Control::Command::execute($client, ["playlist", "loadalbum", Slim::Music::Info::genre(track($client)), Slim::Music::Info::artist(track($client)), Slim::Music::Info::album(track($client))]);			
				Slim::Control::Command::execute($client, ["playlist", "jump", "0"]);
			} else {
				Slim::Buttons::Common::popModeRight($client);
				Slim::Hardware::IR::executeButton($client, 'play');
			}
	},
	
	'add' => sub  {
			my $client = shift;
			my $curitem = $client->trackInfoContent->[currentLine($client)];
			my ($line1, $line2);
			
			$line1 = string('ADDING_TO_PLAYLIST');
			
			if ($curitem && $curitem eq 'GENRE') {
				$line2 = Slim::Music::Info::genre(track($client));
				Slim::Display::Animation::showBriefly($client, Slim::Display::Display::renderOverlay($line1, $line2, undef, Slim::Hardware::VFD::symbol('notesymbol')), undef,1);
				Slim::Control::Command::execute($client, ["playlist", "addalbum", Slim::Music::Info::genre(track($client)), "*", "*"]);
			} elsif ($curitem && $curitem eq 'ARTIST') {
				$line2 = Slim::Music::Info::artist(track($client));
				Slim::Display::Animation::showBriefly($client, Slim::Display::Display::renderOverlay($line1, $line2, undef, Slim::Hardware::VFD::symbol('notesymbol')), undef,1);
				Slim::Control::Command::execute($client, ["playlist", "addalbum", Slim::Music::Info::genre(track($client)), Slim::Music::Info::artist(track($client)), "*"]);			
			} elsif ($curitem && $curitem eq 'COMPOSER') {
				$line2 = Slim::Music::Info::composer(track($client));
				Slim::Display::Animation::showBriefly($client, Slim::Display::Display::renderOverlay($line1, $line2, undef, Slim::Hardware::VFD::symbol('notesymbol')), undef,1);
				Slim::Control::Command::execute($client, ["playlist", "addalbum", Slim::Music::Info::genre(track($client)), Slim::Music::Info::composer(track($client)), "*"]);			
			} elsif ($curitem && $curitem eq 'CONDUCTOR') {
				$line2 = Slim::Music::Info::conductor(track($client));
				Slim::Display::Animation::showBriefly($client, Slim::Display::Display::renderOverlay($line1, $line2, undef, Slim::Hardware::VFD::symbol('notesymbol')), undef,1);
				Slim::Control::Command::execute($client, ["playlist", "addalbum", Slim::Music::Info::genre(track($client)), Slim::Music::Info::conductor(track($client)), "*"]);			
			} elsif ($curitem && $curitem eq 'BAND') {
				$line2 = Slim::Music::Info::band(track($client));
				Slim::Display::Animation::showBriefly($client, Slim::Display::Display::renderOverlay($line1, $line2, undef, Slim::Hardware::VFD::symbol('notesymbol')), undef,1);
				Slim::Control::Command::execute($client, ["playlist", "addalbum", Slim::Music::Info::genre(track($client)), Slim::Music::Info::band(track($client)), "*"]);			
			} elsif ($curitem && $curitem eq 'ALBUM') {
				$line2 = Slim::Music::Info::album(track($client));
				Slim::Display::Animation::showBriefly($client, Slim::Display::Display::renderOverlay($line1, $line2, undef, Slim::Hardware::VFD::symbol('notesymbol')), undef,1);
				Slim::Control::Command::execute($client, ["playlist", "addalbum", Slim::Music::Info::genre(track($client)), Slim::Music::Info::artist(track($client)), Slim::Music::Info::album(track($client))]);			
			} else {
				Slim::Buttons::Common::popModeRight($client);
				Slim::Hardware::IR::executeButton($client, 'add');
			}
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
		my $push = 0;
		my $curitem = $client->trackInfoContent->[currentLine($client)];
		my @oldlines = Slim::Display::Display::curLines($client);
		if (!defined($curitem)) {
			$curitem = "";
		}
		if ($curitem eq 'ALBUM') {
			Slim::Buttons::BrowseID3::setSelection($client, '*', '*', Slim::Music::Info::album(track($client)), undef);
			Slim::Buttons::Common::pushMode($client, 'browseid3', {'genre'=>'*', 'artist'=>'*', 'album' => Slim::Music::Info::album(track($client)) });
			$push = 1;
		} elsif ($curitem eq 'ARTIST') {
			Slim::Buttons::Common::pushMode($client, 'browseid3', {'genre'=>'*', 'artist' => Slim::Music::Info::artist(track($client)) });
			$push = 1;
		} elsif ($curitem eq 'COMPOSER') {
			Slim::Buttons::Common::pushMode($client, 'browseid3', {'genre'=>'*', 'artist' => Slim::Music::Info::composer(track($client)) });
			$push = 1;
		} elsif ($curitem eq 'CONDUCTOR') {
			Slim::Buttons::Common::pushMode($client, 'browseid3', {'genre'=>'*', 'artist' => Slim::Music::Info::conductor(track($client)) });
			$push = 1;
		} elsif ($curitem eq 'BAND') {
			Slim::Buttons::Common::pushMode($client, 'browseid3', {'genre'=>'*', 'artist' => Slim::Music::Info::band(track($client)) });
			$push = 1;
		} elsif ($curitem eq 'GENRE') {
			Slim::Buttons::Common::pushMode($client, 'browseid3', {'genre'=>Slim::Music::Info::genre(track($client))});
			$push = 1;
		} else {
			Slim::Display::Animation::bumpRight($client);
		}
		if ($push) {
			Slim::Display::Animation::pushLeft($client, @oldlines, Slim::Display::Display::curLines($client));
		}
	},
	'numberScroll' => sub  {
		my $client = shift;
		my $button = shift;
		my $digit = shift;
		currentLine($client, Slim::Buttons::Common::numberScroll($client, $digit, $client->trackInfoLines, 0));
		$client->update();
	}
);

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
	my $line = Slim::Buttons::Common::param($client, 'line', shift);
	if (!defined($line)) {  $line = 0; }
	return $line
}

sub preloadLines {
	my $client = shift;
	my $url = shift;

	@{$client->trackInfoLines} = ();
	@{$client->trackInfoContent} = ();

	if (Slim::Music::Info::title($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('TITLE').": ".Slim::Music::Info::title($url));
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::artist($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('ARTIST').": ".Slim::Music::Info::artist($url));
		push (@{$client->trackInfoContent}, 'ARTIST');
	}

	if (Slim::Music::Info::band($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('BAND').": ".Slim::Music::Info::band($url));
		push (@{$client->trackInfoContent}, 'BAND');
	}

	if (Slim::Music::Info::composer($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('COMPOSER').": ".Slim::Music::Info::composer($url));
		push (@{$client->trackInfoContent}, 'COMPOSER');
	}

 	if (Slim::Music::Info::conductor($url)) {
 		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('CONDUCTOR').": ".Slim::Music::Info::conductor($url));
 		push (@{$client->trackInfoContent}, 'CONDUCTOR');
 	}

	if (Slim::Music::Info::album($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('ALBUM').": ".Slim::Music::Info::album($url));
		push (@{$client->trackInfoContent}, 'ALBUM');
	}

	if (Slim::Music::Info::trackNumber($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('TRACK').": ".Slim::Music::Info::trackNumber($url));
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::year($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('YEAR').": ".Slim::Music::Info::year($url));
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::genre($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('GENRE').": ".Slim::Music::Info::genre($url));
		push (@{$client->trackInfoContent}, 'GENRE');
	}

	if (Slim::Music::Info::contentType($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('TYPE').": ". string(uc(Slim::Music::Info::contentType($url))));
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::comment($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('COMMENT').": ".Slim::Music::Info::comment($url));
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::duration($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('LENGTH').": ". Slim::Music::Info::duration($url));
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::bitrate($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('BITRATE').": ".Slim::Music::Info::bitrate($url));
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::fileLength($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('FILELENGTH').": ".Slim::Utils::Misc::delimitThousands(Slim::Music::Info::fileLength($url)));
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::age($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('MODTIME').": ".Slim::Utils::Misc::shortDateF(Slim::Music::Info::age($url)) . ", " . Slim::Utils::Misc::timeF(Slim::Music::Info::age($url)));
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::isURL($url)) {
		push (@{$client->trackInfoLines}, "URL: ". $url);
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::tagVersion($url)) {
		push (@{$client->trackInfoLines}, Slim::Utils::Strings::string('TAGVERSION').": ".Slim::Music::Info::tagVersion($url));
		push (@{$client->trackInfoContent}, undef);
	}

}

#
# figure out the lines to be put up to display the directory
#
sub lines {
	my $client = shift;
	my ($line1, $line2);

	# Show the title of the song with a note symbol
	$line1 = Slim::Music::Info::standardTitle($client, track($client));
	$line2 = $client->trackInfoLines->[currentLine($client)];
	my $overlay1 = Slim::Hardware::VFD::symbol('notesymbol');
	my $overlay2 = defined($client->trackInfoContent->[currentLine($client)]) ? Slim::Hardware::VFD::symbol('rightarrow') : undef;
	return ($line1, $line2, $overlay1, $overlay2);
}

1;

__END__
