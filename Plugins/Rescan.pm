# Rescan.pm by Andrew Hedges (andrew@hedges.me.uk) October 2002
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
use strict;

###########################################
### Section 1. Change these as required ###
###########################################

package Plugins::Rescan;

use Slim::Control::Command;
use Slim::Utils::Strings qw (string);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.3 $,10);

sub getDisplayName() {return string('PLUGIN_RESCAN_MUSIC_LIBRARY')}

sub strings() { return '
PLUGIN_RESCAN_MUSIC_LIBRARY
	DE	Musikverzeichnis erneut durchsuchen
	EN	Rescan Music Library
	FR	Répertorier musique
	
PLUGIN_RESCAN_RESCANNING
	DE	Server durchsucht Verzeichnisse...
	EN	Server now rescanning...
	FR	En cours...

PLUGIN_RESCAN_PRESS_PLAY
	DE	PLAY drücken, um den Vorgang zu starten
	EN	Press PLAY to rescan your music folder
	FR	Appuyez sur PLAY pour répertorier votre dossier de musique
'};

##################################################
### Section 2. Your variables and code go here ###
##################################################


sub setMode() {
	my $client = shift;
	$client->lines(\&lines);
}

my %functions = (
	'up' => sub  {
		my $client = shift;
		Slim::Display::Animation::bumpUp($client);
	},
	'down' => sub  {
	    my $client = shift;
		Slim::Display::Animation::bumpDown($client);
	},
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		Slim::Display::Animation::bumpRight($client);
	},
	'play' => sub {
		my $client = shift;
		my @pargs=('rescan');
		my ($line1, $line2) = (string('PLUGIN_RESCAN_MUSIC_LIBRARY'), string('PLUGIN_RESCAN_RESCANNING'));
		Slim::Control::Command::execute($client, \@pargs, undef, undef);
		Slim::Display::Animation::showBriefly($client, $line1, $line2);
	}
);

sub lines {
	my ($line1, $line2);
	$line1 = string('PLUGIN_RESCAN_MUSIC_LIBRARY');
	$line2 = string('PLUGIN_RESCAN_PRESS_PLAY');
	return ($line1, $line2);
}

	
################################################
### End of Section 2.                        ###
################################################

################################
### Ignore from here onwards ###
################################

sub getFunctions() {
	return \%functions;
}

1;
