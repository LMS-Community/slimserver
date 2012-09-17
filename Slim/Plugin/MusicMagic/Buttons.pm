package Slim::Plugin::MusicMagic::Buttons;

# $Id$

# Copyright 2001-2011 Logitech
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Plugin::MusicMagic::Plugin;
use Slim::Plugin::MusicMagic::PlayerSettings;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = logger('plugin.musicip');
my $prefs = preferences('plugin.musicip');

our %mixMap  = (
	'add.single' => 'play_1',
	'add.hold'   => 'play_2'
);

our %mixFunctions = ();

sub init {
	return unless main::IP3K;
	
	Slim::Plugin::MusicMagic::PlayerSettings::init();

	$mixFunctions{'play'} = \&playMix;

	Slim::Buttons::Common::addMode('musicmagic_mix', \%mixFunctions, \&setMixMode);
	Slim::Hardware::IR::addModeDefaultMapping('musicmagic_mix',\%mixMap);
}

sub initMoods {
	Slim::Buttons::Common::addMode('musicmagic_moods', {}, \&setMoodMode);

	my $params = {
		'useMode'  => 'musicmagic_moods',
		'mood'     => 'none',
	}; 
	Slim::Buttons::Home::addMenuOption('MUSICMAGIC_MOODS', $params);
	Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', 'MUSICMAGIC_MOODS', $params);
}

sub defaultMap {
	Slim::Hardware::IR::addModeDefaultMapping('musicmagic_mix', \%mixMap);
}

sub playMix {
	my $client = shift;
	my $button = shift;
	my $append = shift || 0;

	my $line1;
	my $playAddInsert;
	
	if ($append == 1) {

		$line1 = $client->string('ADDING_TO_PLAYLIST');
		$playAddInsert = 'addtracks';

	} elsif ($append == 2) {

		$line1 = $client->string('INSERT_TO_PLAYLIST');
		$playAddInsert = 'inserttracks';

	} elsif (Slim::Player::Playlist::shuffle($client)) {

		$line1 = $client->string('PLAYING_RANDOMLY_FROM');
		$playAddInsert = 'playtracks';

	} else {

		$line1 = $client->string('NOW_PLAYING_FROM');
		$playAddInsert = 'playtracks';
	}

	my $line2 = $client->modeParam('stringHeader') ? $client->string($client->modeParam('header')) : $client->modeParam('header');
	
	$client->showBriefly({
		'line'    => [ $line1, $line2] ,
		'overlay' => [ $client->symbols('notesymbol'),],
	}, { 'duration' => 2});

	$client->execute(["playlist", $playAddInsert, "listref", $client->modeParam('listRef')]);
}

sub setMoodMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my %params = (
		'header'         => $client->string('MUSICMAGIC_MOODS'),
		'listRef'        => &Slim::Plugin::MusicMagic::Plugin::grabMoods,
		'headerAddCount' => 1,
		'overlayRef'     => sub {return (undef, $client->symbols('rightarrow'));},
		'mood'           => 'none',
		'callback'       => sub {
			my $client = shift;
			my $method = shift;

			if ($method eq 'right') {
				
				mixerFunction($client);
			}
			elsif ($method eq 'left') {
				Slim::Buttons::Common::popModeRight($client);
			}
		},
	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
}

sub setMixMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	mixerFunction($client, $prefs->get('player_settings') ? 1 : 0);
}

sub specialPushLeft {
	my $client   = shift;
	my $step     = shift;

	my $now  = Time::HiRes::time();
	my $when = $now + 0.5;
	
	my $mixer  = Slim::Utils::Strings::string('MUSICMAGIC_MIXING');

	if ($step == 0) {

		Slim::Buttons::Common::pushMode($client, 'block');
		$client->pushLeft(undef, { 'line' => [$mixer,''] });
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);

	} elsif ($step == 3) {

		Slim::Buttons::Common::popMode($client);
		$client->pushLeft( { 'line' => [$mixer."...",''] }, undef);

	} else {

		$client->update( { 'line' => [$mixer.("." x $step),''] });
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);
	}
}

sub mixerFunction {
	my ($client, $noSettings, $track) = @_;

	# look for parentParams (needed when multiple mixers have been used)
	my $paramref = defined $client->modeParam('parentParams') ? $client->modeParam('parentParams') : $client->modeParameterStack->[-1];
	# if prefs say to offer player settings, and we're not already in that mode, then go into settings.
	if ($prefs->get('player_settings') && !$noSettings) {

		Slim::Buttons::Common::pushModeLeft($client, 'MMMsettings', { 'parentParams' => $paramref });
		return;

	}

	$track ||= $paramref->{'track'};
	my $trackinfo = ( defined($track) && blessed($track) && $track->path ) ? 1 : 0;

	my $listIndex = $paramref->{'listIndex'};
	my $items     = $paramref->{'listRef'};
	my $hierarchy = $paramref->{'hierarchy'};
	my $level     = $paramref->{'level'} || 0;
	my $descend   = $paramref->{'descend'};

	my @levels    = split(",", $hierarchy);
	my $mix;
	my $mixSeed   = '';

	my $currentItem = $items->[$listIndex];

	# start by checking for a passed track (trackinfo)
	if ( $trackinfo ) {
		$currentItem = $track;
		$levels[$level] = 'track';
		
	# use _prepare_mix for artist/album/genre
	# XXX - consolidate all mixes to using this method!
	} elsif ($paramref->{track_id} || $paramref->{artist_id} || $paramref->{album_id} || $paramref->{genre_id}) {
		my $params = {
#			song        => $paramref->{'song_id'}, 
			track       => $paramref->{'track_id'},
			artist      => $paramref->{'artist_id'},
#			contributor => $paramref->{'contributor_id'},
			album       => $paramref->{'album_id'},
			genre       => $paramref->{'genre_id'},
#			year        => $paramref->{'year'},
#			mood        => $paramref->{'mood'},
#			playlist    => $paramref->{'playlist'},
		};
	
		$mix = Slim::Plugin::MusicMagic::Plugin::_prepare_mix($client, $params);
		
	# then moods
	} elsif ($paramref->{'mood'}) {
		$mixSeed = $currentItem;
		$levels[$level] = 'mood';
	
	# if we've chosen a particular song
	} elsif (!$descend || $levels[$level] eq 'track') {

		$mixSeed = $currentItem->path;

	} elsif ($levels[$level] eq 'album' || $levels[$level] eq 'age') {

		$mixSeed = $currentItem->tracks->next->path;

	} elsif ($levels[$level] eq 'contributor') {
		
		# MusicIP uses artist instead of contributor.
		$levels[$level] = 'artist';
		$mixSeed = $currentItem->name;
	
	} elsif ($levels[$level] eq 'genre') {
		
		$mixSeed = $currentItem->name;
	}

	if (defined $mix && ref($mix) eq 'ARRAY' && scalar @$mix) {
		# nothing to do here - we already got a mix using _prepare_mix
	}
	# Bug: 7478: special handling for playlist tracks.
	elsif ($levels[$level] eq 'playlistTrack' || $trackinfo ) {

		$mixSeed = $currentItem->path;
		$mix = Slim::Plugin::MusicMagic::Plugin::Slim::Plugin::MusicMagic::Plugin::getMix($client, $mixSeed, 'track');

	} elsif ($currentItem && ($paramref->{'mood'} || $currentItem->musicmagic_mixable)) {

		# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
		$mix = Slim::Plugin::MusicMagic::Plugin::getMix($client, $mixSeed, $levels[$level]);
	}

	if (defined $mix && ref($mix) eq 'ARRAY' && scalar @$mix) {
		my %params = (
			'listRef'        => $mix,
			'externRef'      => \&Slim::Music::Info::standardTitle,
			'header'         => 'MUSICMAGIC_MIX',
			'headerAddCount' => 1,
			'stringHeader'   => 1,
			'callback'       => \&mixExitHandler,
			'overlayRef'     => sub { return (undef, shift->symbols('rightarrow')) },
			'overlayRefArgs' => 'C',
			'parentMode'     => 'musicmagic_mix',
		);
		
		Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);

		specialPushLeft($client, 0);

	} else {

		# don't do anything if nothing is mixable
		$client->bumpRight;
	}
}

sub mixExitHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		my $valueref = $client->modeParam('valueRef');

		Slim::Buttons::Common::pushMode($client, 'trackinfo', { 'track' => $$valueref });

		$client->pushLeft();
	}
}

1;