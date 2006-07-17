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
		
		# Bug 3399 problems with playlist 'add' leave this command set non-working.
		# use 'play' as a workaround.
		#$client->execute([ 'playlist', 'clear' ] );
		#$client->execute([ 'playlist', 'add', $urls->[$listIndex]] );
		#$client->execute([ 'play' ] );
		Slim::Control::Request::executeRequest($client, [ 'playlist', 'play', $urls->[$listIndex]] );
	},
	'add' => sub {
		my $client = shift;

		my $listIndex = Slim::Buttons::Common::param($client, 'listIndex');
		my $urls = Slim::Buttons::Common::param($client, 'urls');

		$client->showBriefly( {
			 'line1' => sprintf($client->string('PLUGIN_FAVORITES_ADDING'), $listIndex+1),
			 'line2' => Slim::Music::Info::standardTitle($client, $urls->[$listIndex]),
		});  
		
		Slim::Control::Request::executeRequest( $client, [ 'playlist', 'add', $urls->[$listIndex]] );
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
		Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_FAVORITES_MODULE_NAME' => undef });
	} else {
		Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_FAVORITES_MODULE_NAME' => "plugins/Favorites/favorites_list.html" });
	}

	return (\%pages);
}

sub handleWebIndex {
	my ($client, $params) = @_;
	
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
		if ($client) {
			$params->{'warning'} = $client->string('PLUGIN_FAVORITES_NONE_DEFINED');
		} else {
			$params->{'warning'} = string('PLUGIN_FAVORITES_NONE_DEFINED');
		}
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

	} elsif ($exittype eq 'RIGHT') {
		my $listIndex = Slim::Buttons::Common::param($client, 'listIndex');
		my $urls = Slim::Buttons::Common::param($client, 'urls');

# 		my %params = (
# 			stationTitle => $context{$client}->{mainModeIndex},
# 			stationURL => $urls->[$listIndex],
# 		);
# 		Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.Favorites.details', \%params); 

		my %params = (
			title => $context{$client}->{mainModeIndex},
			url => $urls->[$listIndex],
		);

 		Slim::Buttons::Common::pushModeLeft($client, 'remotetrackinfo', \%params);

	} else {
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
	my $digit  = shift;

	if ($digit == 0) {
		$digit = 10;
	}

	my $listIndex = $digit - 1;

	my $favs   = Slim::Utils::Favorites->new($client);
	my @titles = $favs->titles();
	
	# grab urls into array ref
	my $urls = [$favs->urls()];

	if (!$urls->[$listIndex]) {

		$client->showBriefly( {
			 'line1' => sprintf($client->string('PLUGIN_FAVORITES_NOT_DEFINED'), $digit)
		});

	} else {

		$::d_favorites && msg("Favorites Plugin: playing favorite number $digit, " . $titles[$listIndex] . "\n");

		$client->showBriefly( {
			 'line1' => sprintf($client->string('PLUGIN_FAVORITES_PLAYING'), $digit), 
			 'line2' => $titles[$listIndex],
		});
		
		# Bug 3399 problems with playlist 'add' leave this command set non-working.
		# use 'play' as a workaround.
		#$client->execute([ 'playlist', 'clear' ] );
		#$client->execute([ 'playlist', 'add', $urls[$index]] );
		#$client->execute([ 'play' ] );
		Slim::Control::Request::executeRequest($client, [ 'playlist', 'play', $urls->[$listIndex]] );
	}
}

sub enabled {
	return ($::VERSION ge '6.1');
}

sub initPlugin {
	$::d_favorites && msg("Favorites Plugin: initPlugin\n");

	Slim::Buttons::Common::addMode('PLUGIN.Favorites', \%mainModeFunctions, \&setMode);

	#Slim::Buttons::Home::addMenuOption('FAVORITES', {'useMode' => 'PLUGIN.Favorites'});

	Slim::Buttons::Common::setFunction('playFavorite', \&playFavorite);

	# register our functions
	
#		  |requires Client
#		  |  |is a Query
#		  |  |  |has Tags
#		  |  |  |  |Function to call
#		  C  Q  T  F
	Slim::Control::Request::addDispatch(['favorites', '_index', '_quantity'],  
		[0, 1, 1, \&listQuery]);
	Slim::Control::Request::addDispatch(['favorites', 'move', '_fromindex', '_toindex'],  
		[0, 0, 0, \&moveCommand]);
	Slim::Control::Request::addDispatch(['favorites', 'delete', '_index'],
		[0, 0, 0, \&deleteCommand]);
	Slim::Control::Request::addDispatch(['favorites', 'add', '_url', '_title'],
		[0, 0, 0, \&addCommand]);

}

# move from to command
sub moveCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['favorites'], ['move']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client    = $request->client();
	my $fromindex = $request->getParam('_fromindex');;
	my $toindex   = $request->getParam('_toindex');;

	if (!defined $fromindex || !defined $toindex) {
		$request->setStatusBadParams();
		return;
	}

	Slim::Utils::Favorites->moveItem($client, $fromindex, $toindex);

	$request->setStatusDone();
}

# add to favorites
sub addCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['favorites'], ['add']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $url    = $request->getParam('_url');;
	my $title  = $request->getParam('_title');;

	if (!defined $url || !defined $title) {
		$request->setStatusBadParams();
		return;
	}

	Slim::Utils::Favorites->clientAdd($client, $url, $title);

	$request->setStatusDone();
}

# delete command
sub deleteCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['favorites'], ['delete']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $index  = $request->getParam('_index');;

	if (!defined $index) {
		$request->setStatusBadParams();
		return;
	}

	Slim::Utils::Favorites->deleteByClientAndId($client, $index);

	$request->setStatusDone();
}

# favorites list
sub listQuery {
	my $request = shift;

	if ($request->isNotQuery([['favorites']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client   = $request->client();
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	
	my $favs   = Slim::Utils::Favorites->new($client);
	my @titles = $favs->titles();
	my @urls   = $favs->urls();
	
	my $count  = scalar(@titles);

	$request->addResult('count', $count);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {
		my $idx = $start;
		my $cnt = 0;

		for my $eachtitle (@titles[$start..$end]) {
			$request->addResultLoop('@favorites', $cnt, 'id', $idx);
			$request->addResultLoop('@favorites', $cnt, 'title', $eachtitle);
			$request->addResultLoop('@favorites', $cnt, 'url', $urls[$idx]);
			$cnt++;
			$idx++;
		}	
	}

	$request->setStatusDone();
}

sub strings {
	return "
PLUGIN_FAVORITES_MODULE_NAME
	DE	Favoriten
	EN	Favorites
	ES	Favoritas
	FI	Suosikit
	FR	Favoris
	HE	מועדפים
	IT	Favoriti
	NL	Favorieten

PLUGIN_FAVORITES_NOT_DEFINED
	DE	Favorit Nr. %s existiert nicht!
	EN	Favorite #%s not defined.
	ES	Favorita #%s no definida
	FR	Favori n°%s non défini
	NL	Favoriet #%s niet gedefinieerd.

PLUGIN_FAVORITES_NONE_DEFINED
	DE	Es sind noch keine Favoriten definiert
	EN	No Favorites exist
	ES	No existen Favoritas
	FI	Suosikkeja ei ole
	FR	Aucun favori défini
	NL	Er zijn geen favorieten

PLUGIN_FAVORITES_PLAYING
	DE	Spiele Favorit Nr. %s...
	EN	Playing favorite #%s
	ES	Se está escuchando favorita #%s
	FR	Lecture favori n°%s
	NL	Speel favoriet #%s

PLUGIN_FAVORITES_ADDING
	DE	Füge Favorit Nr. %s zur Wiedergabeliste hinzu...
	EN	Adding favorite #%s
	FR	Ajout favori n°%s
	ES	Añadiendo favorita #%s
	NL	Toevoegen favoriet #%s
";}

1;

__END__
