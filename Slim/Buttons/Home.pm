package Slim::Buttons::Home;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);

use Slim::Buttons::BrowseID3;
use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Buttons::Search;
use Slim::Buttons::Settings;
use Slim::Buttons::Synchronize;
use Slim::Utils::Strings qw (string);

Slim::Buttons::Common::addMode('home',getFunctions(),\&setMode);

# button functions for top-level home directory

my %homeChoices;

my %functions = (
	'add' => sub  {
		my $client = shift;
	
		if ($homeChoices{$client}->[$client->homeSelection] eq 'MUSIC') {
			# add the whole of the music folder to the playlist!
			Slim::Buttons::Block::block($client, string('ADDING_TO_PLAYLIST'), string('MUSIC'));
			Slim::Control::Command::execute($client, ['playlist', 'add', Slim::Utils::Prefs::get('audiodir')], \&Slim::Buttons::Block::unblock, [$client]);
		} elsif($homeChoices{$client}->[$client->homeSelection] eq 'NOW_PLAYING') {
			$client->showBriefly(string('CLEARING_PLAYLIST'), '');
			Slim::Control::Command::execute($client, ['playlist', 'clear']);
		} else {
			(getFunctions())->{'right'}($client);
		}
	},
	'play' => sub  {
		my $client = shift;
	
		if ($homeChoices{$client}->[$client->homeSelection] eq 'MUSIC') {
			# play the whole of the music folder!
			if (Slim::Player::Playlist::shuffle($client)) {
				Slim::Buttons::Block::block($client, string('PLAYING_RANDOMLY_FROM'), string('MUSIC'));
			} else {
				Slim::Buttons::Block::block($client, string('NOW_PLAYING_FROM'), string('MUSIC'));
			}
			Slim::Control::Command::execute($client, ['playlist', 'load', Slim::Utils::Prefs::get('audiodir')], \&Slim::Buttons::Block::unblock, [$client]);
		} elsif($homeChoices{$client}->[$client->homeSelection] eq 'NOW_PLAYING') {
			Slim::Control::Command::execute($client, ['play']);
			#The address of the %functions hash changes from compile time to run time
			#so it is necessary to get a reference to it from a function outside of the hash
			(getFunctions())->{'right'}($client);
		}  elsif (($homeChoices{$client}->[$client->homeSelection] eq 'BROWSE_BY_GENRE')  ||
				  ($homeChoices{$client}->[$client->homeSelection] eq 'BROWSE_BY_ARTIST') ||
				  ($homeChoices{$client}->[$client->homeSelection] eq 'BROWSE_BY_ALBUM')  ||
				  ($homeChoices{$client}->[$client->homeSelection] eq 'BROWSE_BY_SONG')) {
			if (Slim::Player::Playlist::shuffle($client)) {
				Slim::Buttons::Block::block($client, string('PLAYING_RANDOMLY'), string('EVERYTHING'));
			} else {
				Slim::Buttons::Block::block($client, string('NOW_PLAYING'), string('EVERYTHING'));
			}
			Slim::Control::Command::execute($client, ["playlist", "loadalbum", "*", "*", "*"], \&Slim::Buttons::Block::unblock, [$client]);
		} else {
			(getFunctions())->{'right'}($client);
		}
	},
	'up' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, (scalar(@{$homeChoices{$client}})), $client->homeSelection);
		$client->homeSelection($newposition);
		$client->update();
	},
	'down' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, (scalar(@{$homeChoices{$client}})), $client->homeSelection);
		$client->homeSelection($newposition);
		$client->update();
	},
	'left' => sub  {
		my $client = shift;
		# doesn't do anything, we're already at the top level
		$client->bumpLeft();
	},
	'right' => sub  {
		my $client = shift;
		my @oldlines = Slim::Display::Display::curLines($client);
		# navigate to the current selected top level item:
		if ($homeChoices{$client}->[$client->homeSelection] eq 'NOW_PLAYING') {
			# reset to the top level of the music
			Slim::Buttons::Common::pushModeLeft($client, 'playlist');
		} elsif ($homeChoices{$client}->[$client->homeSelection] eq 'BROWSE_MUSIC') {
			Slim::Buttons::Common::pushModeLeft($client, 'browsemenu',{});
		} elsif ($homeChoices{$client}->[$client->homeSelection] eq 'BROWSE_BY_GENRE') {
			Slim::Buttons::Common::pushModeLeft($client, 'browseid3',{});
		} elsif ($homeChoices{$client}->[$client->homeSelection] eq 'BROWSE_BY_ARTIST') {
			Slim::Buttons::Common::pushModeLeft($client, 'browseid3',{'genre'=>'*'});
		} elsif ($homeChoices{$client}->[$client->homeSelection] eq 'BROWSE_BY_ALBUM') {
			Slim::Buttons::Common::pushModeLeft($client, 'browseid3', {'genre'=>'*', 'artist'=>'*'});
		} elsif ($homeChoices{$client}->[$client->homeSelection] eq 'BROWSE_BY_SONG') {
			Slim::Buttons::Common::pushModeLeft($client, 'browseid3', {'genre'=>'*', 'artist'=>'*', 'album'=>'*'});
		} elsif ($homeChoices{$client}->[$client->homeSelection] eq 'SETTINGS') {
			Slim::Buttons::Common::pushModeLeft($client, 'settings');
		} elsif ($homeChoices{$client}->[$client->homeSelection] eq 'PLUGINS') {
			Slim::Buttons::Common::pushModeLeft($client, 'plugins');
		} elsif ($homeChoices{$client}->[$client->homeSelection] eq 'BROWSE_MUSIC_FOLDER') {
			# reset to the top level of the music
			Slim::Buttons::Common::pushMode($client, 'browse');
			Slim::Buttons::Browse::loadDir($client, '', 'right', \@oldlines);
		} elsif ($homeChoices{$client}->[$client->homeSelection] eq 'SAVED_PLAYLISTS') {
			Slim::Buttons::Common::pushMode($client, 'browse');
			Slim::Buttons::Browse::loadDir($client, '__playlists', 'right', \@oldlines);
		} elsif ($homeChoices{$client}->[$client->homeSelection] eq 'SEARCH_FOR_ARTISTS') {
			my %params = Slim::Buttons::Search::searchFor($client, 'ARTISTS');
			Slim::Buttons::Common::pushModeLeft($client, $params{'useMode'},\%params);
		} elsif ($homeChoices{$client}->[$client->homeSelection] eq 'SEARCH_FOR_ALBUMS') {
			my %params = Slim::Buttons::Search::searchFor($client, 'ALBUMS');
			Slim::Buttons::Common::pushModeLeft($client, $params{'useMode'},\%params);
		} elsif ($homeChoices{$client}->[$client->homeSelection] eq 'SEARCH_FOR_SONGS') {
			my %params = Slim::Buttons::Search::searchFor($client, 'SONGS');
			Slim::Buttons::Common::pushModeLeft($client, $params{'useMode'},\%params);
		} elsif ($homeChoices{$client}->[$client->homeSelection] eq 'SEARCH') {
			Slim::Buttons::Common::pushModeLeft($client, 'search');
		} else {
			Slim::Buttons::Common::pushModeLeft($client, "PLUGIN.".$homeChoices{$client}->[$client->homeSelection]);
		}
	},
	'numberScroll' => sub  {
		my $client = shift;
		my $button = shift;
		my $digit = shift;
		my $newpos;
		$client->homeSelection(Slim::Buttons::Common::numberScroll($client, $digit, $homeChoices{$client}, 0));
		$client->update();
	}
);

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;

	$client->lines(\&lines);
	updateMenu($client);
 	if (!defined($client->homeSelection) || $client->homeSelection < 0 || $client->homeSelection >= scalar(@{$homeChoices{$client}})) {
 		$client->homeSelection(0);
 	}
 }
 
 my @menuOptions = ('NOW_PLAYING',
 					'BROWSE_MUSIC',
 					'BROWSE_BY_GENRE',
 					'BROWSE_BY_ARTIST',
 					'BROWSE_BY_ALBUM',
					'BROWSE_BY_SONG',
 					'BROWSE_MUSIC_FOLDER',
 					'SEARCH_FOR_ARTISTS',
 					'SEARCH_FOR_ALBUMS',
 					'SEARCH_FOR_SONGS',
 					'SEARCH',
 					'SAVED_PLAYLISTS',
 					'PLUGINS',
 					'SETTINGS',
 					);
 
sub menuOptions {
	my $client = shift;
	my %menuChoices = ();
	$menuChoices{""} = "";
	foreach my $menuOption (@menuOptions) {
		if ($menuOption eq 'BROWSE_MUSIC_FOLDER' && !Slim::Utils::Prefs::get('audiodir')) {
			next;
		}
		if ($menuOption eq 'SAVED_PLAYLISTS' && !Slim::Utils::Prefs::get('playlistdir')) {
			next;
		}
		$menuChoices{$menuOption} = string($menuOption);
	}
	my %disabledplugins = map {$_ => 1} Slim::Utils::Prefs::getArray('disabledplugins');
	my $pluginsRef = Slim::Buttons::Plugins::installedPlugins();
	foreach my $menuOption (keys %{$pluginsRef}) {
		next if (exists $disabledplugins{$menuOption});
		no strict 'refs';
		if (exists &{"Plugins::" . $menuOption . "::enabled"} && $client &&
			! &{"Plugins::" . $menuOption . "::enabled"}($client) ) {
			next;
		}
		$menuChoices{$menuOption} = $pluginsRef->{$menuOption};
	}
	return %menuChoices;
}

sub unusedMenuOptions {
	my $client = shift;
	my %menuChoices = menuOptions($client);
	delete $menuChoices{""};
	foreach my $usedOption (@{$homeChoices{$client}}) {
		delete $menuChoices{$usedOption};
	}
	return sort { $menuChoices{$a} cmp $menuChoices{$b} } keys %menuChoices;
}

sub updateMenu {
	my $client = shift;
	my @home = ();
	
	my %disabledplugins = map {$_ => 1} Slim::Utils::Prefs::getArray('disabledplugins');
	foreach my $menuItem (Slim::Utils::Prefs::clientGetArray($client,'menuItem')) {
		if ($menuItem eq 'BROWSE_MUSIC_FOLDER' && !Slim::Utils::Prefs::get('audiodir')) {
			next;
		}
		if ($menuItem eq 'SAVED_PLAYLISTS' && 
			!Slim::Utils::Prefs::get('playlistdir') && 
			!Slim::Music::iTunes::useiTunesLibrary() && 
			!Slim::Music::MoodLogic::useMoodLogic() ) {
			next;
		}
		next if (exists $disabledplugins{$menuItem});

		push @home, $menuItem;
	}
	if (!scalar @home) {
		push @home, 'NOW_PLAYING';
	}
	$homeChoices{$client} = \@home;
}
 
sub jump {
	my $client = shift;
	my $item = shift;
	my $pos = 0;

	if (defined($item)) {
		foreach my $i (@{$homeChoices{$client}}) {
			last if ($i eq $item);
			$pos++;
		}
	}

	if ($pos > scalar @{$homeChoices{$client}}) {
		$pos = 0;
	}

	$client->homeSelection($pos);
}
#
# figure out the lines to be put up to display the directory
#
sub lines {
	my $client = shift;
	my ($line1, $line2);
	if ($client->isa("Slim::Player::SLIMP3")) {
		$line1 = string('SLIMP3_HOME');
	} elsif ($client->isa("Slim::Player::Softsqueeze")) {
		$line1 = string('SOFTSQUEEZE_HOME');
	} else {
		$line1 = string('SQUEEZEBOX_HOME');
	}
	my $menuChoice = $homeChoices{$client}->[$client->homeSelection];
	for(my $i=0;$i<=$#menuOptions;$i++){

		if ($menuOptions[$i] eq $menuChoice) {
			$line2 = $client->linesPerScreen() == 1 ? Slim::Utils::Strings::doubleString($menuChoice) : string($menuChoice);
			return ($line1, $line2, undef, Slim::Display::Display::symbol('rightarrow'));
		} else {
			my $pluginsRef = Slim::Buttons::Plugins::installedPlugins();
			$line2 = $pluginsRef->{$menuChoice};
		}

	}

	return ($line1, $line2, undef, Slim::Display::Display::symbol('rightarrow'));
}

1;

__END__
