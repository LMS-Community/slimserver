package Slim::Buttons::SearchFor;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw (string);

Slim::Buttons::Common::addMode('searchfor',getFunctions(),\&setMode);

my @searchChars = (
	Slim::Hardware::VFD::symbol('rightarrow'),
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
	'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
	' ',

	'.', ',', "'", '?', '!', '@', '-', '_', '#', '$', '%', '^', '&',
	'(', ')', '{', '}', '[', ']', '\\','|', ';', ':', '"', '<', '>',
	'*', '=', '+', '`', '/', 'ß', 

	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
);

# button functions for search text entry
my %functions = (
	'up' => sub  {
		my $client = shift;
		my $char = $client->searchTerm($client->searchCursor);
		my $index = 0;
		foreach my $match (@searchChars) {
			last if ($match eq $char);
			$index++;
		}
		$index = Slim::Buttons::Common::scroll($client, -1, scalar(@searchChars), $index);

		if ($index < 0) { $index = scalar @searchChars - 1; };
		$client->searchTerm($client->searchCursor,$searchChars[$index]);
		Slim::Utils::Timers::killTimers($client, \&nextChar);
		$client->update();
	},
	'down' => sub  {
		my $client = shift;
		my $char = $client->searchTerm($client->searchCursor);
		my $index = 0;
		foreach my $match (@searchChars) {
			last if ($match eq $char);
			$index++;
		}
		$index = Slim::Buttons::Common::scroll($client, +1, scalar(@searchChars), $index);

		if ($index >= scalar @searchChars) { $index = 0 };
		$client->searchTerm($client->searchCursor,$searchChars[$index]);
		Slim::Utils::Timers::killTimers($client, \&nextChar);
		$client->update();
	},
	'left' => sub  {
		my $client = shift;
		my $funct  = shift;
		my $functarg = shift;
		Slim::Utils::Timers::killTimers($client, \&nextChar);
		if ($client->searchCursor == 0) {
			if (!$functarg) { #don't repeat out of searchfor mode
				Slim::Buttons::Common::popModeRight($client);
			}
		} else {
			$client->searchTerm($client->searchCursor, undef);
			$client->searchCursor($client->searchCursor - 1);
			$client->update();
		}
	},
	'right' => sub  {
		my $client = shift;
		my $char = $client->searchTerm($client->searchCursor);
		Slim::Utils::Timers::killTimers($client, \&nextChar);
		if ($char eq Slim::Hardware::VFD::symbol('rightarrow')) {
			startSearch($client);
		} else {
			nextChar($client);
		}
	},
	'search' => sub {
		my $client = shift;
		startSearch($client);
	},
	
	'play' => sub {
		my $client = shift;
		my $line1;
		my $line2;
		my $term = searchTerm($client);
		my $printableterm = $term;
		$printableterm =~ s/^\*(.+)\*$/$1/;
		
		if (length($printableterm) == 0) {
			Slim::Display::Animation::bumpRight($client);
			return;
		}
		if (Slim::Player::Playlist::shuffle($client)) {
			$line1 = string('PLAYING_RANDOMLY_FROM');
		} else {
			$line1 = string('NOW_PLAYING_FROM')
		}
		
		if ($client->searchFor eq 'ARTISTS') {
			$line2 = string('ARTISTSMATCHING');
		} elsif ($client->searchFor eq 'ALBUMS') {
			$line2 = string('ALBUMSMATCHING');
		} else {
			$line2 = string('SONGSMATCHING');
		}
		
		$line2 .= ' ' . $printableterm;
		
		Slim::Display::Animation::showBriefly($client, $line1, $line2);

		if ($client->searchFor eq 'ARTISTS') {
			Slim::Control::Command::execute($client, ["playlist", "loadalbum", '*', searchTerm($client)]);
		} elsif ($client->searchFor eq 'ALBUMS') {
			Slim::Control::Command::execute($client, ["playlist", "loadalbum", '*', '*', searchTerm($client)]);
		} else {
			Slim::Control::Command::execute($client, ["playlist", "loadalbum", '*', '*', '*', searchTerm($client)]);
		}
		Slim::Control::Command::execute($client, ["playlist", "jump", "0"]);
		
	},
	
	'add' => sub {
		my $client = shift;
		my $line1;
		my $line2;
		my $term = searchTerm($client);
		my $printableterm = $term;
		$printableterm =~ s/^\*(.+)\*$/$1/;
		if (length($printableterm) == 0) {
			Slim::Display::Animation::bumpRight($client);
			return;
		}
		
		$line1 = string('ADDING_TO_PLAYLIST');
		
		if ($client->searchFor eq 'ARTISTS') {
			$line2 = string('ARTISTSMATCHING');
		} elsif ($client->searchFor eq 'ALBUMS') {
			$line2 = string('ALBUMSMATCHING');
		} else {
			$line2 = string('SONGSMATCHING');
		}
		
		$line2 .= ' ' . $printableterm;
		
		Slim::Display::Animation::showBriefly($client, $line1, $line2);

		if ($client->searchFor eq 'ARTISTS') {
			Slim::Control::Command::execute($client, ["playlist", "addalbum", '*', searchTerm($client)]);
		} elsif ($client->searchFor eq 'ALBUMS') {
			Slim::Control::Command::execute($client, ["playlist", "addalbum", '*', '*', searchTerm($client)]);
		} else {
			Slim::Control::Command::execute($client, ["playlist", "addalbum", '*', '*', '*', searchTerm($client)]);
		}
	},
	'numberScroll' => sub  {
		my $client = shift;
		my $button = shift;
		my $digit = shift;
		Slim::Utils::Timers::killTimers($client, \&nextChar);
		# if it's a different number, then skip ahead
		if (Slim::Buttons::Common::testSkipNextNumberLetter($client, $digit) && 
			($client->searchTerm($client->searchCursor) ne Slim::Hardware::VFD::symbol('rightarrow'))) {
			$client->searchCursor($client->searchCursor+1);
			$client->update();
		}
		# update the search term
		$client->searchTerm($client->searchCursor,
				Slim::Buttons::Common::numberLetter($client, $digit));
		# set up a timer to automatically skip ahead
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + Slim::Utils::Prefs::get("displaytexttimeout"), \&nextChar);
		#update the display
		$client->update();
	}
);

sub searchTerm {
	my $client = shift;

	# do the search!
	my $term = "*";
	foreach my $a (@{$client->searchTerm}) {
		if (defined($a) && ($a ne Slim::Hardware::VFD::symbol('rightarrow'))) {
			$term .= $a;
		}
	}
	$term .= "*";
	return $term;
}


sub startSearch {
	my $client = shift;
	my $mode = shift;
	my @oldlines = Slim::Display::Display::curLines($client);
	if ($client->searchCursor == 0) {
		Slim::Display::Animation::bumpRight($client);
	} else {
		my $term = searchTerm($client);
		Slim::Display::Animation::showBriefly($client, string('SEARCHING'));
		if ($client->searchFor eq 'ARTISTS') {
			Slim::Buttons::Common::pushMode($client, 'browseid3', {'genre'=>'*', 'artist' => $term } );
		} elsif ($client->searchFor eq 'ALBUMS') {
			Slim::Buttons::Common::pushMode($client, 'browseid3', {'genre'=>'*', 'artist' => '*', 'album' =>$term });
		} else {
			Slim::Buttons::Common::pushMode($client, 'browseid3', {'genre'=>'*', 'artist' => '*', 'album' => '*', 'song' => $term } );
		}
		Slim::Display::Animation::pushLeft($client, @oldlines, Slim::Display::Display::curLines($client));
	}
}

sub nextChar {
	my $client = shift;
	return if ($client->searchTerm($client->searchCursor) eq Slim::Hardware::VFD::symbol('rightarrow'));
	$client->lastLetterDigit('');
	$client->searchCursor($client->searchCursor+1);
	$client->searchTerm($client->searchCursor, Slim::Hardware::VFD::symbol('rightarrow'));
	$client->update();
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;

	$client->lines(\&lines);
	if (($client->searchCursor == 0) && !defined($client->searchTerm($client->searchCursor))) {
		$client->searchTerm($client->searchCursor, 'A');
	}
}

sub searchFor {
	my $client = shift;
	$client->searchFor(shift);
	$client->searchCursor(0);
	@{$client->searchTerm} = ('A');
}

#
# figure out the lines to be put up to display the directory
#
sub lines {
	my $client = shift;
	my ($line1, $line2);

	if ($client->searchFor eq 'ARTISTS') {
		$line1 = string('SEARCHFOR_ARTISTS');
	} elsif ($client->searchFor eq 'ALBUMS') {
		$line1 = string('SEARCHFOR_ALBUMS');
	} elsif ($client->searchFor eq 'SONGS') {
		$line1 = string('SEARCHFOR_SONGS');
	}

	$line2 = "";
	for (my $i = 0; $i < scalar @{$client->searchTerm}; $i++) {
		if (!defined $client->searchTerm($i)) { last; };

		if ($i == $client->searchCursor) {
			$line2 .= Slim::Hardware::VFD::symbol('cursorpos');
		}
		$line2 .= $client->searchTerm($i);
	}

	return ($line1, $line2);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
