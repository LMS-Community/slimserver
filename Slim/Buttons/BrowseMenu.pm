package Slim::Buttons::BrowseMenu;
# $Id:

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Buttons::Browse;
use Slim::Utils::Strings qw (string);

Slim::Buttons::Common::addMode('browsemenu',Slim::Buttons::BrowseMenu::getFunctions(),\&Slim::Buttons::BrowseMenu::setMode);

# button functions for browse directory
my @browseMenuChoices = ('GENRES','ARTISTS','ALBUMS','MUSIC','SONGS');
my %functions = (
	
	'up' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#browseMenuChoices + 1), $client->browseMenuSelection);
		$client->browseMenuSelection($newposition);
		$client->update();
	},
	
	'down' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#browseMenuChoices + 1), $client->browseMenuSelection);
		$client->browseMenuSelection($newposition);
		$client->update();
	},
	
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	
	'right' => sub  {
		my $client = shift;
	
		my @oldlines = Slim::Display::Display::curLines($client);
		my $push = 1;
		# navigate to the current selected top level item:
		if ($browseMenuChoices[$client->browseMenuSelection] eq 'MUSIC') {
			# reset to the top level of the music
			Slim::Buttons::Common::pushMode($client, 'browse');
			Slim::Buttons::Browse::loadDir($client, '', "right", \@oldlines);
			$push = 0;
		} elsif ($browseMenuChoices[$client->browseMenuSelection] eq 'SAVED_PLAYLISTS') {
			Slim::Buttons::Common::pushMode($client, 'browse');
			Slim::Buttons::Browse::loadDir($client, '__playlists', "right", \@oldlines);
			$push = 0;
		} elsif ($browseMenuChoices[$client->browseMenuSelection] eq 'ALBUMS') {
			Slim::Buttons::Common::pushMode($client, 'browseid3', {'genre'=>'*', 'artist'=>'*'});
		} elsif ($browseMenuChoices[$client->browseMenuSelection] eq 'ARTISTS') {
			Slim::Buttons::Common::pushMode($client, 'browseid3',{'genre'=>'*'});
		} elsif ($browseMenuChoices[$client->browseMenuSelection] eq 'GENRES') {
			Slim::Buttons::Common::pushMode($client, 'browseid3',{});
		} elsif ($browseMenuChoices[$client->browseMenuSelection] eq 'SONGS') {
			Slim::Buttons::Common::pushModeLeft($client, 'browseid3', {'genre'=>'*', 'artist'=>'*', 'album'=>'*'});
		}
		if ($push) {
			Slim::Display::Animation::pushLeft($client, @oldlines, Slim::Display::Display::curLines($client));
		}
	}
);

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;

	if (!defined($client->browseMenuSelection)) { $client->browseMenuSelection(0); };
	$client->lines(\&lines);
}

#
# figure out the lines to be put up to display the directory
#
sub lines {
	my $client = shift;
	my ($line1, $line2);

	$line1 = string('BROWSEMENU');
	$line2 = string($browseMenuChoices[$client->browseMenuSelection]);

	return ($line1, $line2, undef, Slim::Hardware::VFD::symbol('rightarrow'));
}

1;

__END__
