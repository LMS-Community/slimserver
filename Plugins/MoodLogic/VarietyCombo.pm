package Plugins::MoodLogic::VarietyCombo;

#$Id: /mirror/slim/branches/split-scanner/Plugins/MoodLogic/VarietyCombo.pm 4595 2005-10-12T17:20:52.108083Z dsully  $

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Buttons::Common;
use Plugins::MoodLogic::Plugin;
use Slim::Utils::Timers;
use Slim::Music::Info;
use Slim::Display::Display;

our %functions = ();

sub init {
	Slim::Buttons::Common::addMode('moodlogic_variety_combo', getFunctions(), \&setMode);

	%functions = ();
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
	
	my $variety = Slim::Utils::Prefs::get('varietyCombo');
	
	Slim::Buttons::Common::pushMode($client, 'INPUT.Bar', {
		'header'       => 'SETUP_VARIETYCOMBO',
		'stringHeader' => 1,
		'headerValue'  => sub { return " (".$_[1].") ".$client->string('MUSICMAGIC_MIXRIGHT'); },
		'onChange'     => sub {
				Slim::Utils::Prefs::set('varietyCombo', $_[1])}
			,
		'initialValue' => \$variety,
		'valueRef'     => \$variety,
		'callback'     => \&varietyExitHandler,
		'increment'    => 1,
		'screen2'      => 'inherit',
		'mood'         => $client->modeParam('mood'),
		'track'        => $client->modeParam('song'),
		'artist'       => $client->modeParam('artist'),
		'genre'        => $client->modeParam('genre'),
	});
}


sub varietyExitHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {
	
		my $instantMix;
	
		my $mood   = $client->modeParam('mood');
		my $track  = $client->modeParam('song');
		my $artist = $client->modeParam('artist');
		my $genre  = $client->modeParam('genre');
	
		if (defined $track) {
	
			$instantMix = Plugins::MoodLogic::Plugin::getMix($track->moodlogic_id, undef, 'song');
	
		} elsif (defined $mood && defined $artist) {
	
			$instantMix = Plugins::MoodLogic::Plugin::getMix($artist->moodlogic_id, $mood, 'artist');
	
		} elsif (defined $mood && defined $genre) {
	
			$instantMix = Plugins::MoodLogic::Plugin::getMix($genre->moodlogic_id, $mood, 'genre');
		}
	
		if (scalar @$instantMix) {
	
			Slim::Buttons::Common::pushMode($client, 'moodlogic_instant_mix', { 'mix' => $instantMix });
			specialPushLeft($client, 0);
	
		} else {
	
			$client->bumpRight()
		}
	}
}

sub specialPushLeft {
	my $client   = shift;
	my $step     = shift;

	my $now  = Time::HiRes::time();
	my $when = $now + 0.5;
	my $mixer;
	
	$mixer  = $client->string('MOODLOGIC_MIXING');
	
	if ($step == 0) {

		$client->update( {'line' => [$mixer]});
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);

	} elsif ($step == 3) {

		$client->pushLeft({ 'line' => [$mixer."..."]});

	} else {

		$client->update( { 'line' => [$mixer.("." x $step)]});
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);
	}
}

1;

__END__
