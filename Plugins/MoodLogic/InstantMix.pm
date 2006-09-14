package Plugins::MoodLogic::InstantMix;

#$Id: /mirror/slim/branches/split-scanner/Plugins/MoodLogic/InstantMix.pm 4113 2005-08-29T19:51:42.434193Z adrian  $

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Buttons::Common;
use Slim::Music::TitleFormatter;
use Slim::Utils::Timers;

# button functions for browse directory
our @instantMix = ();

our %functions = ();

sub init {

	Slim::Buttons::Common::addMode('moodlogic_instant_mix', getFunctions(), \&setMode);

	%functions = (
		'play' => sub  {
			my $client = shift;
			my $button = shift;
			my $append = shift;
			my $line1;
			my $line2;
			
			if ($append) {
				$line1 = $client->string('ADDING_TO_PLAYLIST')
			} elsif (Slim::Player::Playlist::shuffle($client)) {
				$line1 = $client->string('PLAYING_RANDOMLY_FROM');
			} else {
				$line1 = $client->string('NOW_PLAYING_FROM')
			}
			$line2 = $client->string('MOODLOGIC_INSTANT_MIX');
			
			$client->showBriefly({
				'line'    => [ $line1, $line2] ,
				'overlay' => [ $client->symbols('notesymbol'),],
			}, { 'duration' => 2});
			
			$client->execute(["playlist", $append ? "append" : "play", $instantMix[0]]);
			
			for (my $i=1; $i<=$#instantMix; $i++) {
				$client->execute(["playlist", "append", $instantMix[$i]]);
			}
		},
	);
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
	
	if ($method eq "push") {
		if (defined $client->param( 'mix')) {
			@instantMix = @{$client->param('mix')};
		}
	}

	my %params = (
		'listRef'        => \@instantMix,
		'externRef'      => \&Slim::Music::Info::standardTitle,
		'header'         => 'MOODLOGIC_INSTANT_MIX',
		'headerAddCount' => 1,
		'stringHeader'   => 1,
		'callback'       => \&mixExitHandler,
		'overlayRef'     => sub { return (undef, Slim::Display::Display::symbol('rightarrow')) },
		'overlayRefArgs' => '',
	);
		
	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

sub mixExitHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		my $valueref = $client->param('valueRef');

		Slim::Buttons::Common::pushMode($client, 'trackinfo', { 'track' => $$valueref });

		$client->pushLeft();
	}
}

1;

__END__
