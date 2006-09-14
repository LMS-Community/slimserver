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

	Slim::Buttons::Common::addMode('moodlogic_mood_wheel', undef, \&setMode);
}

sub moodExitHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		my $valueref = $client->param('valueRef');

		Slim::Buttons::Common::pushModeLeft($client, 'moodlogic_variety_combo', {

				'genre'  => $client->param( 'genre'),
				'artist' => $client->param( 'artist'),
				'mood'   => $$valueref,
			});
	}
}

sub setMode {
	my $client = shift;
	my $method   = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $genre  = $client->param('genre');
	my $artist = $client->param('artist');

	if (defined $genre) {

		@browseMoodChoices = @{Plugins::MoodLogic::Plugin::getMoodWheel($genre->moodlogic_id, 'genre')};

	} elsif (defined $artist) {

		@browseMoodChoices = @{Plugins::MoodLogic::Plugin::getMoodWheel($artist->moodlogic_id, 'artist')};

	} else {
	
		$::d_moodlogic && msg("MoodLogic: no/unknown type specified for mood wheel\n");
	}

	my %params = (
		'listRef'        => \@browseMoodChoices,
		'header'         => 'MOODLOGIC_SELECT_MOOD',
		'headerAddCount' => 1,
		'stringHeader'   => 1,
		'callback'       => \&moodExitHandler,
		'overlayRef'     => sub { return (undef, Slim::Display::Display::symbol('rightarrow')) },
		'overlayRefArgs' => '',
		'genre'          => $genre,
		'artist'         => $artist,
	);
		
	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

1;

__END__
