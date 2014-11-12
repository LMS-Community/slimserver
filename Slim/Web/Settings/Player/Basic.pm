package Slim::Web::Settings::Player::Basic;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('BASIC_PLAYER_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/player/basic.html');
}

sub needsClient {
	return 1;
}

sub prefs {
	my ($class, $client) = @_;

	return if (!defined $client);

	my @prefs = qw(playername playtrackalbum);

	if ($client->isPlayer && !$client->display->isa('Slim::Display::NoDisplay')) {

		push @prefs, qw(titleFormatCurr playingDisplayMode);

		push @prefs, qw(screensaver alarmsaver idlesaver offsaver screensavertimeout);

		if ($client->display->isa('Slim::Display::Transporter')) {

			push @prefs, qw(visualMode);
		}
	}
	
	# Bug 8069, show title format pref for HTTP clients
	if ( $client->isa('Slim::Player::HTTP') ) {
		push @prefs, 'titleFormatCurr';
	}

	return ($prefs->client($client), @prefs);
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	if (!defined $client) {
		return $class->SUPER::handler($client, $paramRef);
	}

	# reset all client preferences to factory defaults
	if ($paramRef->{resetprefs}) {
		$client->resetPrefs();
	}

	# array prefs handled by this handler not handler::SUPER
	my @prefs = ();

	if (defined $client && $client->isPlayer() && !$client->display->isa('Slim::Display::NoDisplay')) {

		push @prefs, qw(titleFormat playingDisplayModes);

		if ($client->display->isa('Slim::Display::Transporter')) {

			push @prefs, qw(visualModes);
		}
	}
	
	# Bug 8069, show title format pref for HTTP clients
	if ( $client->isa('Slim::Player::HTTP') ) {
		push @prefs, 'titleFormat';
	}

	if ($paramRef->{'saveSettings'}) {

		for my $pref (@prefs) {

			my $i = 0;
			my @array;

			while (defined $paramRef->{'pref_'.$pref.$i}) {

				if ($paramRef->{'pref_'.$pref.$i} ne "-1") {push @array, $paramRef->{'pref_'.$pref.$i};}
				$i++;
			}

			$prefs->client($client)->set($pref, \@array);
		}

		if ($client->isPlayer && $client->isa('Slim::Player::SqueezePlay') && defined $paramRef->{'defeatDestructiveTouchToPlay'}) {
			$prefs->client($client)->set('defeatDestructiveTouchToPlay', $paramRef->{'defeatDestructiveTouchToPlay'});
		}
	}

	$paramRef->{'prefs'}->{'pref_playername'} ||= $client->name;

	for my $pref (@prefs) {
		$paramRef->{'prefs'}->{'pref_'.$pref} = [ @{ $prefs->client($client)->get($pref) }, "-1" ];
	}

	$paramRef->{'titleFormatOptions'}  = hashOfPrefs('titleFormat');
	
	if ($client && !$client->display->isa('Slim::Display::NoDisplay')) {
		$paramRef->{'playingDisplayOptions'} = getPlayingDisplayModes($client);
		$paramRef->{'visualModeOptions'}     = getVisualModes($client);
		$paramRef->{'saveropts'}             = Slim::Buttons::Common::validSavers($client);
	}

	$paramRef->{'playerinfo'} = Slim::Menu::SystemInfo::infoCurrentPlayer( $client );
	$paramRef->{'playerinfo'} = $paramRef->{'playerinfo'}->{web}->{items};
	$paramRef->{'macaddress'} = $client->macaddress;
		
	$paramRef->{'playericon'} = $class->getPlayerIcon($client,$paramRef);

	if ($client->isPlayer && $client->isa('Slim::Player::SqueezePlay')) {
		$paramRef->{'defeatDestructiveTouchToPlay'} = $prefs->client($client)->get('defeatDestructiveTouchToPlay');
		$paramRef->{'defeatDestructiveTouchToPlay'} = $prefs->get('defeatDestructiveTouchToPlay') unless defined $paramRef->{'defeatDestructiveTouchToPlay'};
	}
	
	my $page = $class->SUPER::handler($client, $paramRef);

	if ($client && $client->display->isa('Slim::Display::Transporter')) {
		Slim::Buttons::Common::updateScreen2Mode($client);
	}
	
	return $page;
}

# returns a hash of title formats with the key being their array index and the
# value being the format string
sub hashOfPrefs {
	my $pref = shift;

	my %prefs = ();

	# used to delete a title format from the list
	$prefs{'-1'} = ' ';

	my $i = 0;

	for my $item (@{ $prefs->get($pref) }) {

		if (Slim::Utils::Strings::stringExists($item)) {

			$prefs{$i++} = string($item);

		} else {

			$prefs{$i++} = $item;
		}
	}

	return \%prefs;
}

sub getPlayingDisplayModes {
	my $client = shift || return {};

	my $display = {
		'-1' => ' '
	};

	my $modes  = $client->display->modes;
	my $nmodes = $client->display->nmodes;

	for (my $i = 0; $i <= $nmodes; $i++) {

		my $desc = $modes->[$i]{'desc'};

		for (my $j = 0; $j < scalar @$desc; $j++) {

			$display->{$i} .= ' ' if $j > 0;
			$display->{$i} .= string(@{$desc}[$j]);
		}
	}

	return $display;
}

sub getVisualModes {
	my $client = shift;

	if (!defined $client || !$client->display->isa('Slim::Display::Transporter')) {

		return {};
	}

	my $display = {
		'-1' => ' '
	};

	my $modes  = $client->display->visualizerModes;
	my $nmodes = $client->display->visualizerNModes;

	for (my $i = 0; $i <= $nmodes; $i++) {

		my $desc = $modes->[$i]{'desc'};

		for (my $j = 0; $j < scalar @$desc; $j++) {

			$display->{$i} .= ' ' if ($j > 0);
			$display->{$i} .= string(@{$desc}[$j]);
		}
	}

	return $display;
}

sub getPlayerIcon {
	my ($class, $client, $paramRef) = @_;
	$paramRef ||= {};

	my $model = $client->model(1);

	# default icon for software emulators and media players
	$model = 'squeezebox' if $model eq 'squeezebox2';
	
	# Check if $model image exists else use 'default'
	$model = Slim::Web::HTTP::fixHttpPath($paramRef->{'skinOverride'} || $prefs->get('skin'), "html/images/Players/$model.png")
		? $model 
		: 'softsqueeze';

	return $model;
}

1;

__END__
