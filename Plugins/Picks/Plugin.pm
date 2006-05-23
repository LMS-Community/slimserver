package Plugins::Picks::Plugin;

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

# $Id$

use IO::String;
use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner;

my $FEED = 'http://www.slimdevices.com/picks/radio.opml';

my $picksurl = 'http://update.slimdevices.com/update/picks.pls';

my %context              = ();
my $stationList          = [];
my $lastStationLoadTime  = 0;
my %mainModeFunctions    = ();
my %detailsModeFunctions = ();
my %mapping              = ();

sub enabled {
	return ($::VERSION ge '6.3');
}

sub initPlugin {

	%mapping = (
		'play'        => 'dead',
		'play.hold'   => 'play',
		'play.single' => 'play',   
		'add'         => 'dead',
		'add.hold'    => 'add',
		'add.single'  => 'add',
	);

	%mainModeFunctions = (

		'play' => sub {
			my $client = shift;

			my $listIndex     = $client->param('listIndex');
			my $stations      = $client->param('stations');
			my $stationTitles = $client->param('listRef');  

			$client->showBriefly({
				'line1'    => $client->string('CONNECTING_FOR'), 
				'line2'    => $stationTitles->[$listIndex], 
				'overlay2' => $client->symbols('notesymbol'),
			});

			$client->execute([ 'playlist', 'play', $stations->[$listIndex]] );
		},

		'add' => sub {
			my $client = shift;

			my $listIndex     = $client->param('listIndex');
			my $stations      = $client->param('stations');
			my $stationTitles = $client->param('listRef');

			$client->showBriefly( {
				'line1'    => $client->string('ADDING_TO_PLAYLIST'), 
				'line2'    => Slim::Music::Info::standardTitle($client, $stations->[$listIndex]), 
				'overlay2' => $client->symbols('notesymbol'),
			});

			$client->execute([ 'playlist', 'add', $stations->[$listIndex]] );
		}
	);

	%detailsModeFunctions = (

		'play' => sub {
			my $client = shift;

			my $station      = $client->param('stationURL');
			my $stationTitle = $client->param('header');

			$client->showBriefly({
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

			my $station      = $client->param('stationURL');
			my $stationTitle = $client->param('header');

			$client->showBriefly({
				'line1'    => $client->string('ADDING_TO_PLAYLIST'),
				'line2'    => Slim::Music::Info::standardTitle($client, $station), 
				'overlay2' => $client->symbols('notesymbol'),
			});

			$client->execute(['playlist', 'add', $station]);
		}
	);

	Slim::Buttons::Common::addMode('PLUGIN.Picks.details', \%detailsModeFunctions, \&detailsSetMode);
}

sub mainModeCallback {
	my ($client, $exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		my $listIndex = $client->param('listIndex');
		my $stations  = $client->param('stations');

		my %params = (
			title => $context{$client}->{'mainModeIndex'},
			url   => $stations->[$listIndex],
		);

		Slim::Buttons::Common::pushModeLeft($client, 'remotetrackinfo', \%params);

	} else {

		$client->bumpRight();
	}
}
 
sub listStations {
	my $client = shift;

	my @stationTitles = map Slim::Music::Info::standardTitle($client, $_), @$stationList;
															 
	my %params = (
		stringHeader   => 1,
		header         => 'PLUGIN_PICKS_MODULE_NAME',
		listRef        => \@stationTitles,
		callback       => \&mainModeCallback,
		valueRef       => \$context{$client}->{'mainModeIndex'},
		headerAddCount => 1,
		stations       => $stationList,
		parentMode     => Slim::Buttons::Common::mode($client),		  

		overlayRef     => sub {
			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);

	$client->update;
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {

		if (!$context{$client}->{'blocking'}) {
			Slim::Buttons::Common::popMode($client);
		}

		return;
	}

	my $now = Time::HiRes::time();

	# Only regrab every hour
	if (defined($stationList) && (($now - $lastStationLoadTime) < PLAYLIST_RELOAD_INTERVAL)) {

		listStations($client);

	} else {

		$client->block($client->string('PLUGIN_PICKS_LOADING_PICKS'));

		$context{$client}->{'blocking'} = 1;

		$context{$client}->{'stations'} = [];

		my $http = Slim::Networking::SimpleAsyncHTTP->new(
			\&doneLoading,
			\&doneLoading,
			{
				'client' => $client,
				'url'    => $picksurl,
			},
		);

		$http->get($picksurl);
	}
}

# This is generic enough that it should be moved?
sub doneLoading {
	my $http   = shift;

	my $client  = $http->params('client');
	my $content = $http->content;

	$http->close;

	$client->unblock;
	$client->update;

	$context{$client}->{'blocking'} = 0;

	if (!$content) {

		$client->showBriefly($client->string('PLUGIN_PICKS_LOADING_ERROR'));

		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $ds    = Slim::Music::Info::getCurrentDataStore();

	my $track = $ds->updateOrCreate({
		'url' => $http->params('url'),
	});

	my @stations = Slim::Utils::Scanner->scanPlaylistFileHandle(
		$track, IO::String->new($content),
	);

	$lastStationLoadTime = Time::HiRes::time();

	$stationList = $context{$client}->{'stations'} = \@stations;

	listStations($client);
}

sub defaultMap {
	return \%mapping;
}

sub getFunctions {
	return {};
}

sub detailsModeCallback {
	my ($client, $exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		$client->bumpRight;
	}
}

sub detailsSetMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $stationURL   = $client->param('stationURL');
	my $stationTitle = $client->param('stationTitle');

	my @details = (
		join(':', $client->string('PLUGIN_PICKS_STATION'), $stationTitle),
		join(':', $client->string('URL'), $stationURL),
	);

	my %params = (
		header     => $stationTitle,
		listRef    => \@details,
		callback   => \&detailsModeCallback,
		valueRef   => \$context{$client}->{'detailsModeIndex'},
		parentMode => Slim::Buttons::Common::mode($client),
		stationURL => $stationURL,

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},

		overlayRef => sub {
			my $client = shift;

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		},
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

sub getDisplayName { 
	return 'PLUGIN_PICKS_MODULE_NAME';
}

sub addMenu {
	return 'RADIO';
}

sub webPages {
	my %pages = (
		"index\.htm" => \&handleWebIndex
	);

	if (grep {$_ eq 'Picks::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages->addPageLinks("radio", { 'PLUGIN_PICKS_MODULE_NAME' => undef });

	} else {
		Slim::Web::Pages->addPageLinks("radio", { 'PLUGIN_PICKS_MODULE_NAME' => "plugins/Picks/index.html" });
	}

	return \%pages;
}

sub handleWebIndex {
	my ($client, $params) = @_;
	
	my $now = Time::HiRes::time();

	# Only regrab every hour
	unless (defined($stationList) && (($now - $lastStationLoadTime) < PLAYLIST_RELOAD_INTERVAL)) {

		$stationList = [ Slim::Utils::Scanner->scanRemoteURL({
			'url' => $picksurl,
		}) ];
	}

	if (my $url = $params->{'p0'}) {

		# let's open the stream to get some more information
		my $stream = Plugins::RadioIO::ProtocolHandler->new({ url => $url });
		my $ds     = Slim::Music::Info::getCurrentDataStore();

		my $track  = $ds->objectForUrl($url, 1, 1);

		if (blessed($track) && $track->can('bitrate')) {

			$params->{'stationname'} = Slim::Music::Info::standardTitle($client, $track);
			$params->{'bitrate'}     = $track->bitrate;
			$params->{'type'}        = Slim::Music::Info::contentType($track);
			$params->{'url'}         = $url;
		}

		undef $stream;

	} else {

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
	HE	המומלצים
	NL	De beste van Slim Devices

PLUGIN_PICKS_LOADING_PICKS
	DE	Lade Slim Devices Picks...
	EN	Loading Slim Devices Picks...
	ES	Cargando las Preferidas de Slim Devices...
	HE	טוען מועדפים
	NL	Laden van de beste van Slim Devices...
";}

1;
