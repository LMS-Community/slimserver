package Slim::Buttons::VarietyCombo;
#$Id: VarietyCombo.pm,v 1.2 2004/06/30 05:00:16 kdf Exp $

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Buttons::Common;
use Slim::Music::MoodLogic;
use Slim::Utils::Strings qw (string);
use Slim::Utils::Timers;
use Slim::Hardware::VFD;

Slim::Buttons::Common::addMode('moodlogic_variety_combo',getFunctions(),\&setMode);

#### Variety Combo Selection UI
my %functions = (
	
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
		my $currentItem;
		if (defined Slim::Buttons::Common::param($client, 'song')) {
			my @oldlines = Slim::Display::Display::curLines($client);
			$currentItem = Slim::Buttons::Common::param($client, 'song');
			Slim::Buttons::Common::pushMode($client, 'moodlogic_instant_mix', {'song' => Slim::Buttons::Common::param($client, 'song')});
			specialPushLeft($client, 0, @oldlines);
		} elsif (defined Slim::Buttons::Common::param($client,'mood')) {
			my @oldlines = Slim::Display::Display::curLines($client);
			Slim::Buttons::Common::pushMode($client, 'moodlogic_instant_mix', {'genre' => Slim::Buttons::Common::param($client, 'mood'),
					'artist' => Slim::Buttons::Common::param($client, 'artist'),
					'mood' => Slim::Buttons::Common::param($client, 'mood')});
			specialPushLeft($client, 0, @oldlines);
		} else {
			Slim::Display::Animation::bumpRight($client)
		}
	},
	'play' => sub  {
		my $client = shift;
		my $currentItem;
		if (defined Slim::Buttons::Common::param($client, 'song')) {
			my @oldlines = Slim::Display::Display::curLines($client);
			$currentItem = Slim::Buttons::Common::param($client, 'song');
			Slim::Buttons::Common::pushMode($client, 'moodlogic_instant_mix', {'song' => Slim::Buttons::Common::param($client, 'song')});
			if (Slim::Utils::Prefs::get('animationLevel') == 3) {
				Slim::Buttons::InstantMix::specialPushLeft($client, 0, @oldlines);
			} else {
				Slim::Display::Animation::pushLeft($client, @oldlines, Slim::Display::Display::curLines($client));
			}
		} else {
			Slim::Display::Animation::bumpRight($client)
		}
	},
);

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
	
	$line1 = string('SETUP_VARIETYCOMBO');
	$line1 .= " (".$variety.")";

	$line2 = Slim::Display::Display::progressBar($client, 40, $level / 40);

	if (Slim::Utils::Prefs::clientGet($client,'doublesize')) { $line1 = string('SETUP_VARIETYCOMBO')." (".$variety.")"; $line2 = $line1; }

	return ($line1, $line2, Slim::Hardware::VFD::symbol('rightarrow'),undef);
}

sub specialPushLeft {
	my $client = shift @_;
	my $step = shift @_;
	my @oldlines = @_;

	my $now = Time::HiRes::time();
	my $when = $now + 0.5;
	
	if ($step == 0) {
		Slim::Buttons::Common::pushMode($client, 'block');
		Slim::Display::Animation::pushLeft($client, @oldlines, string('MOODLOGIC_MIXING'));
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);
	} elsif ($step == 3) {
		Slim::Buttons::Common::popMode($client);            
		Slim::Display::Animation::pushLeft($client, string('MOODLOGIC_MIXING')."...", "", Slim::Display::Display::curLines($client));
	} else {
		Slim::Hardware::VFD::vfdUpdate($client, Slim::Display::Display::renderOverlay(string('MOODLOGIC_MIXING').("." x $step), undef, undef, undef));
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);
	}
}

1;

__END__
