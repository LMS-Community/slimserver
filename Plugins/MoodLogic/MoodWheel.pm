package Plugins::MoodLogic::MoodWheel;

#$Id: /mirror/slim/branches/split-scanner/Plugins/MoodLogic/MoodWheel.pm 4595 2005-10-12T17:20:52.108083Z dsully  $

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Buttons::Common;
use Plugins::MoodLogic::Plugin;

# 
our @browseMoodChoices = ();

our %functions = ();

sub init {

	Slim::Buttons::Common::addMode('moodlogic_mood_wheel', getFunctions(), \&setMode);

	%functions = (
		
		'up' => sub  {
			my $client = shift;
			my $button = shift;
			my $count = scalar @browseMoodChoices;
			
			if ($count < 2) {
				$client->bumpUp() if ($button !~ /repeat/);
			} else {
				my $newposition = Slim::Buttons::Common::scroll(
					$client, -1, ($#browseMoodChoices + 1), selection($client, 'mood_wheel_index')
				);

				setSelection($client, 'mood_wheel_index', $newposition);
				$client->pushUp();
			}
		},
		
		'down' => sub  {
			my $client = shift;
			my $button = shift;
			my $count = scalar @browseMoodChoices;

			if ($count < 2) {
				$client->bumpDown() if ($button !~ /repeat/);
			} else {
				my $newposition = Slim::Buttons::Common::scroll(
					$client, +1, ($#browseMoodChoices + 1), selection($client, 'mood_wheel_index')
				);
				setSelection($client, 'mood_wheel_index', $newposition);
				$client->pushDown();
			}
		},
		
		'left' => sub  {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},
		
		'right' => sub  {
			my $client = shift;
		
			Slim::Buttons::Common::pushModeLeft($client, 'moodlogic_variety_combo', {

				'genre'  => $client->param( 'genre'),
				'artist' => $client->param( 'artist'),
				'mood'   => $browseMoodChoices[selection($client, 'mood_wheel_index')]
			});
			
		}
	);
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $push   = shift;

	my $genre  = $client->param('genre');
	my $artist = $client->param('artist');

	if (defined $genre) {

		@browseMoodChoices = @{Plugins::MoodLogic::Plugin::getMoodWheel($genre->moodlogic_id, 'genre')};

	} elsif (defined $artist) {

		@browseMoodChoices = @{Plugins::MoodLogic::Plugin::getMoodWheel($artist->moodlogic_id, 'artist')};

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

	$line1 = $client->string('MOODLOGIC_SELECT_MOOD');
	$line1 .= sprintf(" (%d %s %s)", selection($client, 'mood_wheel_index') + 1, $client->string('OUT_OF'), scalar @browseMoodChoices);
	$line2 = $browseMoodChoices[selection($client, 'mood_wheel_index')];

	return {
		'line1'    => $line1,
		'line2'    => $line2, 
		'overlay2' => $client->symbols('rightarrow'),
	};
}

#	get the current selection parameter from the parameter stack
sub selection {
	my $client = shift;
	my $index = shift;

	my $value = $client->param( $index);

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

	$client->param( $index, $value);
}

1;

__END__
