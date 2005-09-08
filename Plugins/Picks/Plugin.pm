# $Id: Picks.pm 2766 2005-03-27 22:16:25Z vidur $

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
package Plugins::Picks::Plugin;

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

sub enabled {
	return ($::VERSION ge '6.1');
}


###############
# Main mode
#
our %mainModeFunctions = (
   'play' => sub {
	   my $client = shift;
	   
	   my $listIndex = $client->param( 'listIndex');
	   my $stations = $client->param( 'stations');
	   my $stationTitles = $client->param('listRef');  

	   $client->showBriefly( {
		   'line1'    => $client->string('CONNECTING_FOR'), 
		   'line2'    => $stationTitles->[$listIndex], 
		   'overlay2' => $client->symbols('notesymbol'),
	   });

	   $client->execute([ 'playlist', 'play', $stations->[$listIndex]] );
   },
   'add' => sub {
	   my $client = shift;

	   my $listIndex = $client->param( 'listIndex');
	   my $stations = $client->param( 'stations');
	   my $stationTitles = $client->param('listRef');

	   $client->showBriefly( {
		   'line1'    => $client->string('ADDING_TO_PLAYLIST'), 
		   'line2'    => Slim::Music::Info::standardTitle($client, $stations->[$listIndex]), 
		   'overlay2' => $client->('notesymbol'),
	   });
	   
	   $client->execute([ 'playlist', 'add', $stations->[$listIndex]] );
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
			title => $context{$client}->{mainModeIndex},
			url => $stations->[$listIndex],
		);
		Slim::Buttons::Common::pushModeLeft($client, 'remotetrackinfo',
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
		Slim::Utils::Scan::addToList($context{$client}->{stations}, $picksurl, 0, \&doneLoading, $client);
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
	   my $stationTitle = $client->param('header');

	   $client->showBriefly( {
		   'line1'    => $client->string('CONNECTING_FOR'), 
		   'line2'    => Slim::Music::Info::standardTitle($client, $station), 
		   'overlay2' => $client->('notesymbol'),
	   });

	   $client->execute(['playlist', 'clear']);
	   $client->execute(['playlist', 'add', $station]);
	   $client->execute(['play']);
   },
   'add' => sub {
	   my $client = shift;

	   my $station = $client->param( 'stationURL');
	   my $stationTitle = $client->param('header');

	   $client->showBriefly( {
		   'line1'    => $client->string('ADDING_TO_PLAYLIST'),
		   'line2'    => Slim::Music::Info::standardTitle($client, $station), 
		   'overlay2' => $client->symbols('notesymbol'),
	   });

	   $client->execute(['playlist', 'add', $station]);
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
}

Slim::Buttons::Common::addMode('PLUGIN.Picks.details', \%detailsModeFunctions, \&detailsSetMode);

sub getDisplayName { 
	return 'PLUGIN_PICKS_MODULE_NAME';
}

sub addMenu {
	return "RADIO";
}


# Web pages

sub webPages {
    my %pages = ("index\.htm" => \&handleWebIndex);

	if (grep {$_ eq 'Picks::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages::addLinks("radio", { 'PLUGIN_PICKS_MODULE_NAME' => undef });
	} else {
		Slim::Web::Pages::addLinks("radio", { 'PLUGIN_PICKS_MODULE_NAME' => "plugins/Picks/index.html" });
	}

    return (\%pages);
}

sub handleWebIndex {
	my ($client, $params) = @_;
	
	my $now = Time::HiRes::time();
	# Only regrab every hour
	unless (defined($stationList) && (($now - $lastStationLoadTime) < PLAYLIST_RELOAD_INTERVAL)) {
		$stationList = [];
		Slim::Utils::Scan::addToList($stationList, $picksurl, 0);
	}

	if (defined $params->{'p0'}) {
		# let's open the stream to get some more information
		my $stream = Plugins::RadioIO::ProtocolHandler->new({ url => $params->{'p0'}});
		my $ds = Slim::Music::Info::getCurrentDataStore();
		my $track = $ds->objectForUrl($params->{'p0'}, 1, 1);

		$params->{'stationname'} = Slim::Music::Info::standardTitle($client, $params->{'p0'});
		$params->{'bitrate'} = $track->bitrate();
		$params->{'type'} = Slim::Music::Info::contentType($params->{'p0'});
		$params->{'url'} = $params->{'p0'};
		undef $stream;
	}
	else {
		$params->{'stationList'} = {};
		foreach (@$stationList) {
			$params->{'stationList'}{Slim::Music::Info::standardTitle($client, $_)} = $_;
		}
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/Picks/index.html', $params);
}


sub strings {
	return "
PLUGIN_PICKS_MODULE_NAME
	DE	Slim Devices Auswahl
	EN	Slim Devices Picks
	ES	Preferidas de Slim Devices

PLUGIN_PICKS_LOADING_PICKS
	DE	Lade Slim Devices Picks...
	EN	Loading Slim Devices Picks...
	ES	Cargando las Preferidas de Slim Devices...

PLUGIN_PICKS_STATION
	CZ	Stanice
	DE	Sender
	EN	Station
	ES	Estación

PLUGIN_PICKS_LOADING_ERROR
	DE	Fehler beim Laden der Slim Devices Picks
	EN	Error loading Slim Devices Picks
	ES	Error al cargar las Preferidas de Slim Devices
";}

1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
