package Slim::Web::Settings::Player::Basic;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);

sub name {
	return 'BASIC_PLAYER_SETTINGS';
}

sub page {
	return 'settings/player/basic.html';
}

sub needsClient {
	return 1;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my @prefs = qw(playername titleFormat titleFormatCurr);

	# isPlayer means not a HTTP client.
	if (defined $client && $client->isPlayer()) {

		push @prefs, qw(playingDisplayMode playingDisplayModes);
		
		if ($client->display->isa('Slim::Display::Transporter')) {

			push @prefs, qw(visualMode visualModes);
		}
		
		my $savers = Slim::Buttons::Common::hash_of_savers();

		if (scalar(keys %{$savers}) > 0) {

			push @prefs, qw(screensaver idlesaver offsaver screensavertimeout);
		}
	}
	
	# If this is a settings update
	if (defined $client && $paramRef->{'saveSettings'}) {

		my @changed = ();

		my $vismodeChange = 0;

		if (${$paramRef->{'visualModes'}}[$paramRef->{'visualMode'}] ne $client->prefGet('visualModes',$paramRef->{'visualMode'})) {

			$vismodeChange = 1;
		}

		for my $pref (@prefs) {

			if ($pref eq 'visualModes' || $pref eq 'playingDisplayModes' || $pref eq 'titleFormat') {

				$client->prefDelete($pref);

				my $i = 0;

				while (defined $paramRef->{$pref.$i}) {

					if ($paramRef->{$pref.$i} eq "-1") {
						last;
					}

					$client->prefPush($pref, $paramRef->{$pref.$i});

					$i++;
				}

			} else {
			
				if ($paramRef->{$pref} ne $client->prefGet($pref)) {
					push @changed, $pref;
				}
			
				if (defined $paramRef->{$pref}) {

					$client->prefSet($pref, $paramRef->{$pref});
				}
			}
		}
		
		if ($vismodeChange) {

			Slim::Buttons::Common::updateScreen2Mode();
		}
		
		$class->_handleChanges($client, \@changed, $paramRef);

	}

	$paramRef->{'titleFormatOptions'}    = hashOfPrefs('titleFormat');
	$paramRef->{'playingDisplayOptions'} = getPlayingDisplayModes($client);
	$paramRef->{'visualModeOptions'}     = getVisualModes($client);
	$paramRef->{'screensavers'}          = Slim::Buttons::Common::hash_of_savers();

	for my $pref (@prefs) {

		if ($pref eq 'visualModes' || $pref eq 'playingDisplayModes' || $pref eq 'titleFormat') {

			$paramRef->{'prefs'}->{$pref} = [ $client->prefGetArray($pref) ];

			push @{$paramRef->{'prefs'}->{$pref}}, "-1";

		} else {

			$paramRef->{'prefs'}->{$pref} = $client->prefGet($pref);
		}
	}

	if (defined $client->revision) {

		$paramRef->{'versionInfo'} = sprintf("%s%s%s", 
			string("PLAYER_VERSION"),
			string("COLON"),
			$client->revision,
		);
	}
	
	$paramRef->{'ipaddress'}      = $client->ipport;
	$paramRef->{'macaddress'}     = $client->macaddress;
	$paramRef->{'signalstrength'} = $client->signalStrength;
	$paramRef->{'voltage'}        = $client->voltage;

	return $class->SUPER::handler($client, $paramRef);
}

# returns a hash of title formats with the key being their array index and the
# value being the format string
sub hashOfPrefs {
	my $pref = shift;

	my %prefs = ();

	# used to delete a title format from the list
	$prefs{'-1'} = ' ';

	my $i = 0;

	for my $item (Slim::Utils::Prefs::getArray($pref)) {

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

	for (my $i = 0; $i < scalar @$modes; $i++) {

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

	for (my $i = 0; $i < $nmodes; $i++) {

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
