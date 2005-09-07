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

	   $client->showBriefly( {
	       'line1' => sprintf($client->string('PLUGIN_FAVORITES_PLAYING'), $listIndex+1),
	       'line2' => Slim::Music::Info::standardTitle($client, $urls->[$listIndex]),
	   });
	   
	   $client->execute([ 'playlist', 'clear' ] );
	   $client->execute([ 'playlist', 'add', $urls->[$listIndex]] );
	   $client->execute([ 'play' ] );
   },
   'add' => sub {
	   my $client = shift;

	   my $listIndex = Slim::Buttons::Common::param($client, 'listIndex');
	   my $urls = Slim::Buttons::Common::param($client, 'urls');

	   $client->showBriefly( {
	       'line1' => sprintf($client->string('PLUGIN_FAVORITES_ADDING'), $listIndex+1),
	       'line2' => Slim::Music::Info::standardTitle($client, $urls->[$listIndex]),
	   });  
	   
	   Slim::Control::Command::execute( $client, [ 'playlist', 'add', $urls->[$listIndex]] );
   },
);

sub getDisplayName {
	return 'PLUGIN_FAVORITES_MODULE_NAME';
}

sub addMenu {
	$::d_favorites && msg("Favorites Plugin: addMenu\n");
	return "PLUGINS";
}

# Web pages

sub webPages {
	my %pages = ("favorites_list\.htm" => \&handleWebIndex);

	if (grep {$_ eq 'Favorites::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages::addLinks("browse", { 'PLUGIN_FAVORITES_MODULE_NAME' => undef });
	} else {
		Slim::Web::Pages::addLinks("browse", { 'PLUGIN_FAVORITES_MODULE_NAME' => "plugins/Favorites/favorites_list.html" });
	}

	return (\%pages);
}

sub handleWebIndex {
	my ($client, $params) = @_;
	
	my $now = Time::HiRes::time();

	if (defined $params->{'p0'}) {
		if ($params->{'p0'} eq 'move') {
			Slim::Utils::Favorites::moveItem($client, $params->{'p1'}, $params->{'p2'});
		} elsif ($params->{'p0'} eq 'delete') {
			Slim::Utils::Favorites->deleteByClientAndId($client, $params->{'p1'});
		}
	}

		$params->{'favList'} = {};
		
		my $favs = Slim::Utils::Favorites->new($client);
		my @titles = $favs->titles();
		my @urls = $favs->urls();
		my $i = 0;
		
		if (scalar @titles) {
			$params->{'titles'}= \@titles;
			$params->{'urls'}= \@urls;
			foreach (@titles) {
				$params->{'faves'}{$_} = $urls[$i];
				$i++;
			}
		} else {
			$params->{'warning'} = $client->string('PLUGIN_FAVORITES_NONE_DEFINED');
		}

	return Slim::Web::HTTP::filltemplatefile('plugins/Favorites/favorites_list.html', $params);
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
		externRef => sub {return $_[1] || $_[0]->string('EMPTY')},
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
		$client->showBriefly( {
		    'line1' => sprintf($client->string('PLUGIN_FAVORITES_NOT_DEFINED'), $digit)
		});
	} else {
		$::d_favorites && msg("Favorites Plugin: playing favorite number $digit, " . $titles[$index] . "\n");
		$client->showBriefly( {
		    'line1' => sprintf($client->string('PLUGIN_FAVORITES_PLAYING'), $digit), 
		    'line2' => $titles[$index],
		});
		$client->execute(['playlist', 'clear']);
		$client->execute(['playlist', 'add', $urls[$index]]);
		$client->execute(['play']);
	}
}

sub addFavorite {
	my $client = shift;

	my $url = Slim::Player::Playlist::song($client);
	my $title = Slim::Music::Info::standardTitle($client, $url);

	$client->execute(['favorite', 'add', $url, $title]);
}

sub enabled {
	return ($::VERSION ge '6.1');
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
	ES	Favoritas

PLUGIN_FAVORITES_NOT_DEFINED
	DE	Favorit Nr. %s existiert nicht!
	EN	Favorite #%s not defined.
	ES	Favorita #%s no definida

PLUGIN_FAVORITES_NONE_DEFINED
	EN	No Favorites exist

PLUGIN_FAVORITES_PLAYING
	DE	Spiele Favorit Nr. %s...
	EN	Playing favorite #%s
	ES	Se está escuchando favorita #%s

PLUGIN_FAVORITES_ADDING
	DE	Füge Favorit Nr. %s zur Playlist hinzu...
	EN	Adding favorite #%s
	ES	Añadiendo favorita #%s
";}

1;

__END__
