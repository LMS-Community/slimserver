package Slim::Buttons::VarietyCombo;

#$Id: VarietyCombo.pm,v 1.10 2005/01/04 03:38:52 dsully Exp $

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Buttons::Common;
use Slim::Music::MoodLogic;
use Slim::Utils::Timers;
use Slim::Display::Display;

my %functions = ();

sub init {
	Slim::Buttons::Common::addMode('moodlogic_variety_combo', getFunctions(), \&setMode);

	# Variety Combo Selection UI
	%functions = (
		
		'up' => sub {
			my $client = shift;
			my $variety = Slim::Utils::Prefs::get('varietyCombo');
			my $inc = 1;
			my $rate = 50; #Hz maximum
			my $accel = 15; #Hz/s

			if (Slim::Hardware::IR::holdTime($client) > 0) {
				$inc *= Slim::Hardware::IR::repeatCount($client,$rate,$accel);
			} else {
				$inc = 2;
			}

			$variety += $inc;
			if ($variety > 100) { $variety = 100; };
			Slim::Utils::Prefs::set('varietyCombo', $variety);
			$client->update();
		},

		'down' => sub  {
			my $client = shift;
			my $variety = Slim::Utils::Prefs::get('varietyCombo');
			my $inc = 1;
			my $rate = 50; #Hz maximum
			my $accel = 15; #Hz/s

			if (Slim::Hardware::IR::holdTime($client) > 0) {
				$inc *= Slim::Hardware::IR::repeatCount($client,$rate,$accel);
			} else {
				$inc = 2;
			}

			$variety -= $inc;
			if ($variety < 0) { $variety = 0; };
			Slim::Utils::Prefs::set('varietyCombo', $variety);
			$client->update();
		},
		
		'left' => sub  {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},
		
		'right' => sub  {
			my $client = shift;
			my @instantMix;
			
			if (defined Slim::Buttons::Common::param($client, 'song')) {

				@instantMix = Slim::Music::MoodLogic::getMix(
					Slim::Music::Info::moodLogicSongId(Slim::Buttons::Common::param($client, 'song')), undef, 'song'
				);

			} elsif (defined Slim::Buttons::Common::param($client,'mood') && defined Slim::Buttons::Common::param($client,'artist')) {

				my @instantMix = Slim::Music::MoodLogic::getMix(
					Slim::Music::Info::moodLogicArtistId(Slim::Buttons::Common::param($client, 'artist')),
					Slim::Buttons::Common::param($client, 'mood'),
					'artist'
				);

			} elsif (defined Slim::Buttons::Common::param($client,'mood') &&defined Slim::Buttons::Common::param($client,'genre')) {

				my @instantMix = Slim::Music::MoodLogic::getMix(
					Slim::Music::Info::moodLogicGenreId(Slim::Buttons::Common::param($client, 'genre')),
					Slim::Buttons::Common::param($client, 'mood'),
					'genre'
				);
			}
			
			if (scalar @instantMix) {
				my @oldlines = Slim::Display::Display::curLines($client);
				Slim::Buttons::Common::pushMode($client, 'instant_mix', { 'mix' => \@instantMix });
				specialPushLeft($client, 0, @oldlines);
			} else {
				$client->bumpRight()
			}
		},

		'play' => sub  {
			my $client = shift;
			my $currentItem;
			if (defined Slim::Buttons::Common::param($client, 'song')) {
				my @oldlines = Slim::Display::Display::curLines($client);
				$currentItem = Slim::Buttons::Common::param($client, 'song');
				Slim::Buttons::Common::pushMode($client, 'instant_mix', {'song' => Slim::Buttons::Common::param($client, 'song')});
				specialPushLeft($client, 0, @oldlines);
			} else {
				$client->bumpRight()
			}
		},
	);
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	
	$client->lines(\&lines);
	$client->update();
}

#
# figure out the lines to be put up to display
#
sub lines {
	my $client = shift;
	my ($line1, $line2);
	my $variety = Slim::Utils::Prefs::get('varietyCombo');
	my $level = int($variety / 100 * 40);
	
	$line1 = $client->linesPerScreen() == 2 ? $client->string('SETUP_VARIETYCOMBO') : $client->string('SETUP_VARIETYCOMBO_DBL');
	$line1 .= " (".$variety.")";

	$line2 = Slim::Display::Display::progressBar($client, $client->displayWidth(), $level / 40);

	if ($client->linesPerScreen() == 1) { $line2 = $line1; }

	return ($line1, $line2, Slim::Display::Display::symbol('rightarrow'),undef);
}

sub specialPushLeft {
	my $client   = shift;
	my $step     = shift;
	my @oldlines = @_;

	my $now  = Time::HiRes::time();
	my $when = $now + 0.5;
	my $mixer;
	
	$mixer  = $client->string('MOODLOGIC_MIXING');
	
	if ($step == 0) {

		Slim::Buttons::Common::pushMode($client, 'block');
		$client->pushLeft(\@oldlines, [$mixer]);
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);

	} elsif ($step == 3) {

		Slim::Buttons::Common::popMode($client);
		$client->pushLeft([$mixer."...", ""], [Slim::Display::Display::curLines($client)]);

	} else {

		$client->update( [$client->renderOverlay($mixer.("." x $step))], undef);
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);
	}
}

1;

__END__
