# $Id$

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
package Plugins::Picks;

use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Scan;

# Could be configurable through preferences if we wanted.
use constant PLAYLIST_RELOAD_INTERVAL => 600;

my $picksurl = 'http://update.slimdevices.com/update/picks.pls';

my %context;
my $stationList;
my $lastStationLoadTime = 0;

my %mapping = (
	'play' => 'dead',
	'play.hold' => 'play',
	'play.single' => 'play',   
	'add' => 'dead',
	'add.hold' => 'add',
	'add.single' => 'add',
);

###############
# Main mode
#
our %mainModeFunctions = (
   'play' => sub {
	   my $client = shift;

	   my $listIndex = $client->param( 'listIndex');
	   my $stations = $client->param( 'stations');

	   Slim::Control::Command::execute( $client, [ 'playlist', 'clear' ] );
	   Slim::Control::Command::execute( $client, [ 'playlist', 'add', $stations->[$listIndex]] );
	   Slim::Control::Command::execute( $client, [ 'play' ] );
   },
   'add' => sub {
	   my $client = shift;

	   my $listIndex = $client->param( 'listIndex');
	   my $stations = $client->param( 'stations');

	   Slim::Control::Command::execute( $client, [ 'playlist', 'add', $stations->[$listIndex]] );
   }
);

sub mainModeCallback {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} 
	elsif ($exittype eq 'RIGHT') {
		my $listIndex = $client->param( 'listIndex');
		my $stations = $client->param( 'stations');

		my %params = (
			stationTitle => $context{$client}->{mainModeIndex},
			stationURL => $stations->[$listIndex],
		);
		Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.Picks.details',
											\%params);
	}
	else {
		$client->bumpRight();
	}
}
 
sub doneLoading {
	my $client = shift;
	
	Slim::Buttons::Block::unblock($client);
	$context{$client}->{blocking} = 0;

	if (scalar @{$context{$client}->{stations}} == 0) {
		Slim::Display::Animation::showBriefly($client, $client->string('PLUGIN_PICKS_LOADING_ERROR'));
		Slim::Buttons::Common::popMode($client);
	} else {
		$lastStationLoadTime = Time::HiRes::time();
		$stationList = $context{$client}->{stations};
		listStations($client);
	}
}

sub listStations {
	my $client = shift;

	my @stationTitles = map Slim::Music::Info::standardTitle($client, $_), @$stationList;
															 
	my %params = (
		stringHeader => 1,
		header => 'PLUGIN_PICKS_MODULE_NAME',
		listRef => \@stationTitles,
		callback => \&mainModeCallback,
		valueRef => \$context{$client}->{mainModeIndex},
		headerAddCount => 1,
		stations => $stationList,
		overlayRef => sub {return (undef,Slim::Display::Display::symbol('notesymbol'));},
		parentMode => Slim::Buttons::Common::mode($client),		  
	);

	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
	$client->update();
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		if (!$context{$client}->{blocking}) {
			Slim::Buttons::Common::popMode($client);
		}
		return;
	}

	my $now = Time::HiRes::time();
	# Only regrab every hour
	if (defined($stationList) &&
		(($now - $lastStationLoadTime) < PLAYLIST_RELOAD_INTERVAL)) {
		listStations($client);
	}
	else {
		Slim::Buttons::Block::block($client, $client->string('PLUGIN_PICKS_LOADING_PICKS'));
		$context{$client}->{blocking} = 1;

		$context{$client}->{stations} = [];
		Slim::Utils::Scan::addToList($context{$client}->{stations}, $picksurl, 0, 0, \&doneLoading, $client);
	}
}

sub defaultMap {
	return \%mapping;
}

sub getFunctions {
	return \%mainModeFunctions;
}

###############
# Details mode
#
our %detailsModeFunctions = (
   'play' => sub {
	   my $client = shift;

	   my $station = $client->param( 'stationURL');

	   Slim::Control::Command::execute( $client, [ 'playlist', 'clear' ] );
	   Slim::Control::Command::execute( $client, [ 'playlist', 'add', $station ] );
	   Slim::Control::Command::execute( $client, [ 'play' ] );
   },
   'add' => sub {
	   my $client = shift;

	   my $station = $client->param( 'stationURL');

	   Slim::Control::Command::execute( $client, [ 'playlist', 'add', $station ] );
   }
);

sub detailsModeCallback {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} 
	elsif ($exittype eq 'RIGHT') {
		$client->bumpRight();
	}
}

sub detailsSetMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $stationURL = $client->param( 'stationURL');
	my $stationTitle = $client->param( 'stationTitle');

	my @details = ( $client->string('PLUGIN_PICKS_STATION') . ': ' . $stationTitle,
					$client->string('URL') . ': ' . $stationURL );
	my %params = (
		header => $stationTitle,
		listRef => \@details,
		callback => \&detailsModeCallback,
		valueRef => \$context{$client}->{detailsModeIndex},
		overlayRef => sub {return (undef,Slim::Display::Display::symbol('notesymbol'));},
		parentMode => Slim::Buttons::Common::mode($client),
		stationURL => $stationURL,
	);

	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
	$client->update();
}

Slim::Buttons::Common::addMode('PLUGIN.Picks.details', \%detailsModeFunctions, \&detailsSetMode);

sub getDisplayName { 
	return 'PLUGIN_PICKS_MODULE_NAME';
}

sub addMenu {
	return "RADIO";
}

sub strings {
	return "
PLUGIN_PICKS_MODULE_NAME
	DE	Slim Devices Auswahl
	EN	Slim Devices Picks

PLUGIN_PICKS_LOADING_PICKS
	DE	Lade Slim Devices Picks...
	EN	Loading Slim Devices Picks...

PLUGIN_PICKS_STATION
	DE	Sender
	EN	Station

PLUGIN_PICKS_LOADING_ERROR
	DE	Fehler beim Laden der Slim Devices Picks
	EN	Error loading Slim Devices Picks
";}

1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
