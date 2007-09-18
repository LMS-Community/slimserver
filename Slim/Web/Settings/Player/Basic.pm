package Slim::Web::Settings::Player::Basic;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('server');

sub name {
	return 'BASIC_PLAYER_SETTINGS';
}

sub page {
	return 'settings/player/basic.html';
}

sub needsClient {
	return 1;
}

sub prefs {
	my ($class, $client) = @_;

	my @prefs = qw(playername titleFormatCurr);

	if ($client->isPlayer) {

		push @prefs, qw(playingDisplayMode);

		if (scalar(keys %{ Slim::Buttons::Common::hash_of_savers() }) > 0) {

			push @prefs, qw(screensaver idlesaver offsaver screensavertimeout);
		}

		if ($client->display->isa('Slim::Display::Transporter')) {

			push @prefs, qw(visualMode);
		}
	}

	return ($prefs->client($client), @prefs);
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	# array prefs handled by this handler not handler::SUPER
	my @prefs = qw(titleFormat);

	if (defined $client && $client->isPlayer()) {

		push @prefs, qw(playingDisplayModes);

		if ($client->display->isa('Slim::Display::Transporter')) {

			push @prefs, qw(visualModes);
		}
	}

	if ($paramRef->{'saveSettings'}) {

		for my $pref (@prefs) {

			my $i = 0;
			my @array;

			while (defined $paramRef->{$pref.$i} && $paramRef->{$pref.$i} ne "-1") {

				push @array, $paramRef->{$pref.$i};
				$i++;
			}

			$prefs->client($client)->set($pref, \@array);
		}
	}

	for my $pref (@prefs) {
		$paramRef->{'prefs'}->{$pref} = [ @{ $prefs->client($client)->get($pref) }, "-1" ];
	}

	$paramRef->{'titleFormatOptions'}    = hashOfPrefs('titleFormat');
	
	if (!$client->display->isa('Slim::Display::NoDisplay')) {
		$paramRef->{'playingDisplayOptions'} = getPlayingDisplayModes($client);
		$paramRef->{'visualModeOptions'}     = getVisualModes($client);
		$paramRef->{'screensavers'}          = Slim::Buttons::Common::hash_of_savers();
	}

	$paramRef->{'version'}        = $client->revision;
	$paramRef->{'ipaddress'}      = $client->ipport;
	$paramRef->{'macaddress'}     = $client->macaddress;
	$paramRef->{'signalstrength'} = $client->signalStrength;
	$paramRef->{'voltage'}        = $client->voltage;

	my $page = $class->SUPER::handler($client, $paramRef);

	if ($client && $client->display->isa('Slim::Display::Transporter')) {
		Slim::Buttons::Common::updateScreen2Mode();
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

1;

__END__
