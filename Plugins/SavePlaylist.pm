# $Id$
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::SavePlaylist;

use strict;
use Slim::Player::Playlist;
use File::Spec::Functions qw(:ALL);
use Slim::Utils::Misc;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.10 $,10);

our %context = ();

my $rightarrow = Slim::Display::Display::symbol('rightarrow');

our @LegalChars = (
	Slim::Display::Display::symbol('rightarrow'),
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

sub enabled {
	return ($::VERSION ge '6.1');
}

# the routines
sub setMode {
	my $client = shift;
	my $push = shift;
	
	$client->lines(\&lines);
	
	if (!Slim::Utils::Prefs::get('playlistdir')) {
		# do nothing if there is no playlist folder defined.
		
	} elsif ($push ne 'push') {
		my $playlist = '';
	
	} elsif ($client->param('playlist') ne '') {
		# don't do anything if we have a playlist name, since this means we've done the text entry
	
	} else {
	
		# default to the existing title for a known playlist, otherwise just start with 'A'
		$context{$client} = $client->currentPlaylist ? 
								Slim::Music::Info::standardTitle($client, $client->currentPlaylist) : 
								'A';
		
		# set cursor position to end of playlist title if the playlist is known
		my $cursorpos = $client->currentPlaylist ?
							length($context{$client}) :
							0;

		Slim::Buttons::Common::pushMode($client,'INPUT.Text', {
			'callback'        => \&Plugins::SavePlaylist::savePluginCallback,
			'valueRef'        => \$context{$client},
			'charsRef'        => \@LegalChars,
			'numberLetterRef' => \@legalMixed,
			'header'          => $client->string('PLAYLIST_AS'),
			'cursorPos'       => $cursorpos,
		});
	}
}

our %functions = (
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		my $playlistfile = $context{$client};
		Slim::Buttons::Common::setMode($client, 'playlist');
		savePlaylist($client,$playlistfile);
	},
	'save' => sub {
		my $client = shift;
		Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.SavePlaylist');
	},
);

sub lines {
	my $client = shift;

	my ($line1, $line2, $arrow);
	
	my $newUrl   = Slim::Utils::Misc::fileURLFromPath(
		catfile(Slim::Utils::Prefs::get('playlistdir'), $context{$client} . '.m3u')
	);

	if (!Slim::Utils::Prefs::get('playlistdir')) {

		$line1 = $client->string('NO_PLAYLIST_DIR');
		$line2 = $client->string('NO_PLAYLIST_DIR_MORE');

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
		'line1'    => $line1,
		'line2'    => $line2, 
		'overlay2' => $arrow,
	};
}

sub savePlaylist {
	my $client = shift;
	my $playlistfile = shift;
	$client->execute(['playlist', 'save', $playlistfile]);
	$client->showBriefly( {
		'line1' => $client->string('PLAYLIST_SAVING'),
		'line2' => $playlistfile,
	});
}

sub getFunctions {
	return \%functions;
}

sub savePluginCallback {
	my ($client,$type) = @_;
	if ($type eq 'nextChar') {
		$context{$client} =~ s/$rightarrow//;
		
		# re-enter plugin with the new playlist title to get the confirmation screen for saving the playlist.
		Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.SavePlaylist',{
				'playlist' => $context{$client},
			});
			
	} elsif ($type eq 'backspace') {
		Slim::Buttons::Common::popModeRight($client);
		Slim::Buttons::Common::popModeRight($client);
	
	} else {
		$client->bumpRight();
	};
}

sub strings {
	return '';
}

####################################################################
# Adds a mapping for 'save' function in Now Playing mode.
####################################################################
our %mapping = ('play.hold' => 'save');

sub defaultMap { 
	return \%mapping; 
}

sub initPlugin {
	
	# programmatically add the playlist mode function for 'save' when play.hold button is detected
	Slim::Hardware::IR::addModeDefaultMapping('playlist',\%mapping);
	our $functref = Slim::Buttons::Playlist::getFunctions();
	$functref->{'save'} = $functions{'save'};
}
1;

__END__
