package Slim::Plugin::SavePlaylist::Plugin;

# This code is derived from code with the following copyright message:
#
# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Player::Playlist;
use File::Spec::Functions qw(:ALL);
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

use base qw(Slim::Plugin::Base);

my $prefsServer = preferences('server');

our %context = ();
our %functions;

our @LegalChars = (
	undef, # placeholder for rightarrrow
	'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
	'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
	'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
	' ',
	'.', '-', '_',
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
);

our @legalMixed = (
	[' ','0'], 				# 0
	['.','-','_','1'], 			# 1
	['a','b','c','A','B','C','2'],		# 2
	['d','e','f','D','E','F','3'], 		# 3
	['g','h','i','G','H','I','4'], 		# 4
	['j','k','l','J','K','L','5'], 		# 5
	['m','n','o','M','N','O','6'], 		# 6
	['p','q','r','s','P','Q','R','S','7'], 	# 7
	['t','u','v','T','U','V','8'], 		# 8
	['w','x','y','z','W','X','Y','Z','9'] 	# 9
);

sub getDisplayName { 
	return 'SAVE_PLAYLIST';
}

# the routines
sub setMode {
	my $class  = shift;
	my $client = shift;
	my $push = shift;
	
	$client->lines(\&lines);
	
	if (!Slim::Utils::Misc::getPlaylistDir()) {
		# do nothing if there is no playlist folder defined.
		
	} elsif ($push eq 'pop') {
		
		# back out one more step since we've saved the playlist and are only partly backed out.
		Slim::Buttons::Common::popModeRight($client);
	} elsif ($client->modeParam('playlist') ne '') {
		# don't do anything if we have a playlist name, since this
		# means we've done the text entry

	} else {

		# default to the existing title for a known playlist, otherwise just start with 'A'
		$context{$client} = $client->currentPlaylist ? 
			Slim::Music::Info::standardTitle($client, $client->currentPlaylist) : 'A';

		# set cursor position to end of playlist title if the playlist is known
		my $cursorpos = $client->currentPlaylist ?  length($context{$client}) : 0;

		Slim::Buttons::Common::pushMode($client,'INPUT.Text', {
			'callback'        => \&savePluginCallback,
			'valueRef'        => \$context{$client},
			'charsRef'        => \@LegalChars,
			'numberLetterRef' => \@legalMixed,
			'header'          => $client->string('PLAYLIST_AS'),
			'cursorPos'       => $cursorpos,
		});
	}
}

sub lines {
	my $client = shift;

	my ($line1, $line2, $arrow);
	
	my $playlistfile = $context{$client};
	
	my $newUrl   = Slim::Utils::Misc::fileURLFromPath(
		catfile(Slim::Utils::Misc::getPlaylistDir(), $playlistfile . '.m3u')
	);

	if (!Slim::Utils::Misc::getPlaylistDir()) {

		$line1 = $client->string('NO_PLAYLIST_DIR');
		$line2 = $client->string('NO_PLAYLIST_DIR_MORE');

	} elsif ($playlistfile ne Slim::Utils::Misc::cleanupFilename($playlistfile)) {
		# Special text for overwriting an existing playlist
		# if large text, make sure we show the message instead of the playlist name
		if ($client->linesPerScreen == 1) {
			$line2 = $client->doubleString('FILENAME_WARNING');
		} else {
			$line1 = $client->string('FILENAME_WARNING');
			$line2 = $context{$client};
		}

	} elsif (Slim::Schema->objectForUrl($newUrl)) {
		
		# Special text for overwriting an existing playlist
		# if large text, make sure we show the message instead of the playlist name
		if ($client->linesPerScreen == 1) {
			$line2 = $client->doubleString('PLAYLIST_OVERWRITE');
		} else {
			$line1 = $client->string('PLAYLIST_OVERWRITE');
			$line2 = $context{$client};
		}
		
		$arrow = $client->symbols('rightarrow');

	} else {

		$line1 = $client->string('PLAYLIST_SAVE');
		$line2 = $context{$client};
		$arrow = $client->symbols('rightarrow');

	}
	
	return {
		'line'    => [ $line1, $line2 ],
		'overlay' => [ undef, $arrow ]
	};
}

sub savePlaylist {
	my $client = shift;
	my $playlistfile = shift;

	$client->execute(['playlist', 'save', $playlistfile]);

	$client->showBriefly(
			{
				line => [ $client->string('PLAYLIST_SAVING'), $playlistfile ]
			},
			{
				callback =>  sub {
						Slim::Buttons::Common::popModeRight($client);
						Slim::Buttons::Common::popModeRight($client);
				},
			},
	);
}

sub getFunctions {
	return \%functions;
}

sub savePluginCallback {
	my ($client, $type) = @_;

	if ($type eq 'nextChar') {

		# re-enter plugin with the new playlist title to get the confirmation screen for saving the playlist.
		Slim::Buttons::Common::pushModeLeft($client,'Slim::Plugin::SavePlaylist::Plugin', {
			'playlist' => $context{$client},
		});
			
	} elsif ($type eq 'backspace') {

		Slim::Buttons::Common::popModeRight($client);
	
	} else {

		$client->bumpRight();
	}
}

####################################################################
# Adds a mapping for 'save' function in Now Playing mode.
####################################################################
our %mapping = ('play.hold' => 'save');

sub defaultMap { 
	return \%mapping; 
}

sub initPlugin {
	my $class = shift;
	
	%functions = (
		'left' => sub  {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},
		'right' => sub  {
			my $client = shift;
			my $playlistfile = $context{$client};
			
			if ($playlistfile ne Slim::Utils::Misc::cleanupFilename($playlistfile)) {
				$client->bumpRight();
			} else {
				savePlaylist($client,$playlistfile);
			}
		},
		'save' => sub {
			my $client = shift;
			Slim::Buttons::Common::pushModeLeft($client, 'Slim::Plugin::SavePlaylist::Plugin');
		},
	);

	
	# programmatically add the playlist mode function for 'save' when play.hold button is detected
	Slim::Hardware::IR::addModeDefaultMapping('playlist', \%mapping);

	our $functref = Slim::Buttons::Playlist::getFunctions();

	$functref->{'save'} = $functions{'save'};
	
	$class->SUPER::initPlugin();
}

1;

__END__
