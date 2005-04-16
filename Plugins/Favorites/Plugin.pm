# $Id: Favorites.pm,v 1.1 2005/01/10 22:24:47 dave Exp $
#
# Copyright (C) 2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This module defines both a mode for listing all favorites, and a
# mode for displaying the details of a station or track.

# Other modes are encouraged to use the details mode, called
# 'PLUGIN.Favorites.details'.  To use it, setup a hash of params, and
# push into the mode.  The params hash must contain strings for
# 'title' and 'url'.  You may also include an array of strings called
# 'details'.  If included, each string in the details will be
# displayed as well.  The mode also adds a line allowing the user to
# add the url to his/her favorites.

package Plugins::Favorites::Plugin;

use strict;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use Slim::Utils::Misc;
use Slim::Utils::Favorites;
use Slim::Buttons::Common;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.1 $,10);

my %context = ();

my $rightarrow = Slim::Display::Display::symbol('rightarrow');


my %mapping = (
	'play' => 'dead',
	'play.hold' => 'play',
	'play.single' => 'play',
);

my %mainModeFunctions = (
   'play' => sub {
	   my $client = shift;
	   
	   my $listIndex = Slim::Buttons::Common::param($client, 'listIndex');
	   my $urls = Slim::Buttons::Common::param($client, 'urls');
	   
	   Slim::Control::Command::execute( $client, [ 'playlist', 'clear' ] );
	   Slim::Control::Command::execute( $client, [ 'playlist', 'add', $urls->[$listIndex]] );
	   Slim::Control::Command::execute( $client, [ 'play' ] );
   },
);

sub getDisplayName {
	return 'PLUGIN_FAVORITES_MODULE_NAME';
}

sub addMenu {
	$::d_favorites && msg("Favorites Plugin: addMenu\n");
	return "PLUGINS";
}

sub listFavorites {
	my $client = shift;

	my $favs = Slim::Utils::Favorites->new($client);
	my @titles = $favs->titles();
	my @urls = $favs->urls();

	# don't give list mode an empty list!
	if (!scalar @titles) {
		push @titles, $client->string('EMPTY');
	}

	my %params = (
		stringHeader => 1,
		header => 'PLUGIN_FAVORITES_MODULE_NAME',
		listRef => \@titles,
		callback => \&mainModeCallback,
		valueRef => \$context{$client}->{mainModeIndex},
		headerAddCount => scalar (@urls) ? 1 : 0,
		urls => \@urls,
		overlayRef => sub {
			if (scalar @urls) {
				return (undef,Slim::Display::Display::symbol('notesymbol'));
			} else {
				return undef;
			}
		},
		parentMode => Slim::Buttons::Common::mode($client),
	);

	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
	$client->update();
}







# the routines
sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		if (!$context{$client}->{blocking}) {
			Slim::Buttons::Common::popMode($client);
		}
		return;
	}

	listFavorites($client);
}


sub mainModeCallback {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	  } 
	elsif ($exittype eq 'RIGHT') {
		my $listIndex = Slim::Buttons::Common::param($client, 'listIndex');
		my $urls = Slim::Buttons::Common::param($client, 'urls');

# 		my %params = (
# 			stationTitle => $context{$client}->{mainModeIndex},
# 			stationURL => $urls->[$listIndex],
# 		);
# 		Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.Favorites.details',
# 											\%params);

		my %params = (
			title => $context{$client}->{mainModeIndex},
			url => $urls->[$listIndex],
		);
 		Slim::Buttons::Common::pushModeLeft($client,
											'remotetrackinfo',
											\%params);

	}
	else {
		$client->bumpRight();
	}
}

sub defaultMap {
	return \%mapping;
}

sub getFunctions {
	return \%mainModeFunctions;
}



####################################################################
# Adds a mapping for 'playFavorite' function in all modes
####################################################################
sub playFavorite {
	my $client = shift;
	my $button = shift;
	my $digit = shift;

	if ($digit == 0) {
		$digit = 10;
	}
	my $index = $digit - 1;

	my $favs = Slim::Utils::Favorites->new($client);
	my @titles = $favs->titles();
	my @urls = $favs->urls();

	if (!$urls[$index]) {
		$client->showBriefly("Favorite #$digit not defined.");
	} else {
		$::d_favorites && msg("Favorites Plugin: playing favorite number $digit, " . $titles[$index] . "\n");
		$client->showBriefly("Playing favorite #$digit", $titles[$index]);
		Slim::Control::Command::execute( $client, [ 'playlist', 'clear' ] );
		Slim::Control::Command::execute( $client, 
										 [ 'playlist', 'add', 
										   $urls[$index] ] );
		Slim::Control::Command::execute( $client, [ 'play' ] );
	}

}

sub addFavorite {
	my $client = shift;

	my $url = Slim::Player::Playlist::song($client);
	my $title = Slim::Music::Info::standardTitle($client, $url);

	Slim::Control::Command::execute($client, 
									['favorite', 'add',
									 $url, $title]);
}

sub initPlugin {
	$::d_favorites && msg("Favorites Plugin: initPlugin\n");
	Slim::Buttons::Common::addMode('PLUGIN.Favorites', 
								   \%mainModeFunctions, 
								   \&setMode);
	#Slim::Buttons::Home::addMenuOption('FAVORITES', 
	#								   {'useMode' => 'PLUGIN.Favorites'});

	Slim::Buttons::Common::setFunction('playFavorite', \&playFavorite);
	Slim::Buttons::Common::setFunction('addFavorite', \&addFavorite);


}


sub strings {
	return "
PLUGIN_FAVORITES_MODULE_NAME
	DE	Favoriten
	EN	Favorites


";}

1;

__END__
