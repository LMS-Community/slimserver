package Slim::Buttons::MoodWheel;
#$Id: MoodWheel.pm,v 1.6 2004/08/03 17:29:10 vidur Exp $

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Buttons::Common;
use Slim::Music::MoodLogic;
use Slim::Utils::Strings qw (string);

Slim::Buttons::Common::addMode('moodlogic_mood_wheel',getFunctions(),\&setMode);

# 
my @browseMoodChoices = ();

my %functions = (
	
	'up' => sub  {
		my $client = shift;
		my $count = scalar @browseMoodChoices;
		
		if ($count < 2) {
			$client->bumpUp();
		} else {
			my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#browseMoodChoices + 1), selection($client, 'mood_wheel_index'));
			setSelection($client, 'mood_wheel_index', $newposition);
			$client->update();
		}
	},
	
	'down' => sub  {
		my $client = shift;
		my $count = scalar @browseMoodChoices;

		if ($count < 2) {
			$client->bumpDown();
		} else {
			my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#browseMoodChoices + 1), selection($client, 'mood_wheel_index'));
			setSelection($client, 'mood_wheel_index', $newposition);
			$client->update();
		}
	},
	
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	
	'right' => sub  {
		my $client = shift;
	
		my @oldlines = Slim::Display::Display::curLines($client);
		Slim::Buttons::Common::pushMode($client, 'moodlogic_variety_combo', {'genre' => Slim::Buttons::Common::param($client, 'genre'), 'artist' => Slim::Buttons::Common::param($client, 'artist'), 'mood' => $browseMoodChoices[selection($client, 'mood_wheel_index')]});
		
		$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
	}
);

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $push = shift;

	if (defined Slim::Buttons::Common::param($client, 'genre')) {
		@browseMoodChoices = Slim::Music::MoodLogic::getMoodWheel(Slim::Music::Info::moodLogicGenreId(Slim::Buttons::Common::param($client, 'genre')), 'genre');
	} elsif (defined Slim::Buttons::Common::param($client, 'artist')) {
		@browseMoodChoices = Slim::Music::MoodLogic::getMoodWheel(Slim::Music::Info::moodLogicArtistId(Slim::Buttons::Common::param($client, 'artist')), 'artist');
	} else {
		die 'no/unknown type specified for mood wheel';
	}

	if ($push eq "push") {
		setSelection($client, 'mood_wheel_index', 0);
	}
	
	$client->lines(\&lines);
}

#
# figure out the lines to be put up to display
#
sub lines {
	my $client = shift;
	my ($line1, $line2);

	$line1 = string('MOODLOGIC_SELECT_MOOD');
	$line1 .= sprintf(" (%d ".string('OUT_OF')." %s)", selection($client, 'mood_wheel_index') + 1, scalar @browseMoodChoices);
	$line2 = $browseMoodChoices[selection($client, 'mood_wheel_index')];

	return ($line1, $line2, undef, Slim::Display::Display::symbol('rightarrow'));
}

#	get the current selection parameter from the parameter stack
sub selection {
	my $client = shift;
	my $index = shift;

	my $value = Slim::Buttons::Common::param($client, $index);

	if (defined $value  && $value eq '__undefined') {
		undef $value;
	}

	return $value;
}

#	set the current selection parameter from the parameter stack
sub setSelection {
	my $client = shift;
	my $index = shift;
	my $value = shift;

	if (!defined $value) {
		$value = '__undefined';
	}

	Slim::Buttons::Common::param($client, $index, $value);
}

1;

__END__
