# $Id: SavePlaylist.pm,v 1.3 2003/10/28 22:39:03 dean Exp $
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::SavePlaylist;

use strict;
use FileHandle;
use Slim::Player::Playlist;
use Slim::Utils::Strings qw (string);
use File::Spec::Functions qw(:ALL);
use POSIX qw(strftime);
use Slim::Utils::Misc;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.3 $,10);

my %context;

my @LegalChars = (
	Slim::Hardware::VFD::symbol('rightarrow'),
	'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
	'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
	'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
	' ',
	'.', '-', '_',
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
);

my @legalMixed = ([' ','0'], # 0
					 ['.','-','_','1'], # 1
					 ['a','b','c','A','B','C','2'], 				# 2
					 ['d','e','f','D','E','F','3'], 				# 3
					 ['g','h','i','G','H','I','4'], 				# 4
					 ['j','k','l','J','K','L','5'], 				# 5
					 ['m','n','o','M','N','O','6'], 				# 6
					 ['p','q','r','s','P','Q','R','S','7'], 	# 7
					 ['t','u','v','T','U','V','8'], 				# 8
					 ['w','x','y','z','W','X','Y','Z','9']); 			# 9


sub getDisplayName { return string('SAVE_PLAYLIST'); }

# the routines
sub setMode {
	my $client = shift;
	my $push = shift;
	$client->lines(\&lines);
	if ($push ne 'push') {
		my $playlist = '';
	} else {
		$context{$client} = 'A';
		Slim::Buttons::Common::pushMode($client,'INPUT.Text',
						{'callback' => \&Plugins::SavePlaylist::savePluginCallback
						,'valueRef' => \$context{$client}
						,'charsRef' => \@LegalChars
						,'numberLetterRef' => \@legalMixed
						,'header' => string('PLAYLIST_AS')
						,'cursorPos' => 0
						});
	}
}

my %functions = (
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

	my $line1 = string('PLAYLIST_SAVE');
	my $line2 = $context{$client};
	return ($line1, $line2, undef, Slim::Hardware::VFD::symbol('rightarrow'));
}

sub savePlaylist {
	my $client = shift;
	my $playlistfile = shift;
	my $playlistref = Slim::Player::Playlist::playList($client);
	my $playlistdir = Slim::Utils::Prefs::get('playlistdir');
	$playlistfile = catfile($playlistdir,$playlistfile . ".m3u");
	Slim::Formats::Parse::writeM3U($playlistref,$playlistfile);
	Slim::Display::Animation::showBriefly($client,string('PLAYLIST_SAVING'),$playlistfile);
}

sub getFunctions {
	return \%functions;
}

sub savePluginCallback {
	my ($client,$type) = @_;
	if ($type eq 'nextChar') {
		my @oldlines = Slim::Display::Display::curLines($client);
		$context{$client} = Slim::Hardware::VFD::subString($context{$client},0,Slim::Hardware::VFD::lineLength($context{$client})-1);
		Slim::Buttons::Common::popMode($client);
		Slim::Display::Animation::pushLeft($client, @oldlines, lines($client));
	} elsif ($type eq 'backspace') {
		Slim::Buttons::Common::popModeRight($client);
		Slim::Buttons::Common::popModeRight($client);
	} else {
		Slim::Display::Animation::bumpRight($client);
	};
}


####################################################################
# Adds a mapping for 'save' function in Now Playing mode.
####################################################################
my %mapping = ('play.hold' => 'save');
sub defaultMap { return \%mapping; }
Slim::Hardware::IR::addModeDefaultMapping('playlist',\%mapping);
my $functref = Slim::Buttons::Playlist::getFunctions();
$functref->{'save'} = $functions{'save'};

1;

__END__
