package Plugins::RadioIO::Plugin;

# $Id: RadioIO.pm 2278 2005-03-02 08:44:14Z dsully $

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use Scalar::Util qw(blessed);

use Slim::Buttons::Common;
use Slim::Control::Request;
use Slim::Player::ProtocolHandlers;
use Slim::Music::Info;

use Plugins::RadioIO::ProtocolHandler;

our %current = ();

our %stations = (
	'radioio70s'       => '3765',			
	'radioio70sPOP'    => '3910',			
	'radioio80s'       => '3795',
	'radioio80sPOP'    => '3935',	
	'radioio90s'       => '3860',
	'radioioACOUSTIC'  => '3675',
	'radioioAMBIENT'   => '3605',
	'radioioBEAT'      => '3725',
	'radioioCLASSICAL' => '3635',
	'radioioCOUNTRY'   => '3055',				 
	'radioioECLECTIC'  => '3586',
	'radioioEDGE'      => '3995',
	'radioioHISTORY'   => '3845',
	'radioioJAM'       => '3970',
	'radioioJAZZ'      => '3545',
	'radioioONE'       => '3900',
	'radioioPOP'       => '3965',
	'radioioROCK'      => '3515',
	'radioioWORLD'     => '3820',
);

our @station_names = sort keys %stations;

sub enabled {
	return ($::VERSION ge '6.1');
}

sub initPlugin {

	Slim::Player::ProtocolHandlers->registerHandler('radioio', 'Plugins::RadioIO::ProtocolHandler');
	
	# register our functions
	
#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F

    Slim::Control::Request::addDispatch(['radioio.stations', '_index', '_quantity'],  
        [0, 1, 1, \&stationsQuery]);
    Slim::Control::Request::addDispatch(['radioio.stationinfo'],  
        [0, 1, 1, \&stationinfoQuery]);
}

# Just so we don't have plain text URLs in the code.
sub decrypt {
	my $str = shift;
	
	$str =~ tr/a-zA-Z/n-za-mN-ZA-M/;
	$str =~ tr/0-9/5-90-4/;

	return $str;
}

sub getHTTPURL {
	my $key = shift;
	my $port = $stations{$key};
	my $url = "http://" . decrypt("enqvbvb.fp.yyajq.arg") . ":" .
		decrypt($port) . "/" . decrypt("yvfgra.cyf");
	return $url;
}

sub getRadioIOURL {
	my $num = shift;

	my $key = $station_names[$num];
	my $url = "radioio://" . $key . ".mp3";

	my %cacheEntry = (
		'TITLE' => $key,
		'CT'    => 'mp3',
		'VALID' => 1,
	);

	Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);

	return $url;
}

our %functions = (
	'play' => sub {
		my $client = shift;
		my $url = getRadioIOURL($client->param('listIndex'));

		if (defined($url)) {
			$client->showBriefly({
				'line1' => $client->string('CONNECTING_FOR'), 
				'line2' => ${$client->param('valueRef')}, 
				'overlay1' => $client->symbols('notesymbol')
			});

#			$client->execute(['playlist', 'clear']);
#			$client->execute(['playlist', 'add', $url]);
#			$client->execute(['play']);
			$client->execute(['playlist', 'load', $url]);
		}
	},
	'add' => sub {
		my $client = shift;
		my $url = getRadioIOURL($client->param('listIndex'));

		if (defined($url)) {
			$client->showBriefly({
				'line1' => $client->string('ADDING_TO_PLAYLIST'), 
				'line2' => ${$client->param('valueRef')}, 
				'overlay1' => $client->symbols('notesymbol'),
			});

			$client->execute(['playlist', 'add', $url]);
		}
	},
);

sub setMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	$current{$client} ||= 0;

	my %params = (
		header => $client->string('PLUGIN_RADIOIO_MODULE_TITLE'),
		listRef => \@station_names,
		headerAddCount => 1,
		overlayRef => sub {return (undef, $client->symbols('notesymbol'));},
#		isSorted => 'I',
		valueRef => \$current{$client},
		callback => sub {
			my $client = shift;
			my $method = shift;

			if ($method eq 'right') {
				# use remotetrackinfo mode to display details
				my %params = (
					url => getRadioIOURL($client->param('listIndex')),
					title => ${$client->param('valueRef')}, 
				);
				Slim::Buttons::Common::pushModeLeft($client, 'remotetrackinfo', \%params);
			}
			elsif ($method eq 'left') {
				Slim::Buttons::Common::popModeRight($client);
			}
		},
	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
}

sub getFunctions {
	return \%functions;
}

sub addMenu {
	return 'RADIO';
}

sub getDisplayName {
	return 'PLUGIN_RADIOIO_MODULE_NAME';
}

# Web pages

sub webPages {
	my %pages = ("index\.htm" => \&handleWebIndex);

	if (grep {$_ eq 'RadioIO::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages->addPageLinks("radio", { 'PLUGIN_RADIOIO_MODULE_NAME' => undef });
	} else {
		Slim::Web::Pages->addPageLinks("radio", { 'PLUGIN_RADIOIO_MODULE_NAME' => "plugins/RadioIO/index.html" });
	}
	
	return (\%pages);
}

sub handleWebIndex {
	my ($client, $params) = @_;
	
	if (defined $params->{'stationinfo'} && $stations{$params->{'stationinfo'}}) {
		$params->{'stationname'} = $params->{'stationinfo'};

		my $data = stationInfo($params->{'stationname'});
		
		if (defined $data) {
			$params->{'fulltitle'} = $data->{'fulltitle'};
			$params->{'bitrate'}   = $data->{'bitrate'};
			$params->{'type'}      = $data->{'type'};
		}

	} else {

		$params->{'stationnames'} = \@station_names;
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/RadioIO/index.html', $params);
}

# returns data about a station
sub stationInfo {
	my $station = shift;
	
	# let's open the stream to get some more information
	my $url     = "radioio://$station.mp3";
	my $stream  = Plugins::RadioIO::ProtocolHandler->new({ url => $url });

	my $ds      = Slim::Music::Info::getCurrentDataStore();
	my $track   = $ds->objectForUrl($url, 1, 1);

	my %result;

	if (blessed($track) && $track->can('bitrate')) {

		$result{'fulltitle'} = Slim::Music::Info::getCurrentTitle(undef, $track);
		$result{'bitrate'}   = $track->bitrate;
		$result{'type'}      = $track->content_type;
		$result{'station'}   = $station;
		$result{'url'}       = $url;
	}
	
	undef $stream;
	
	return \%result;
}


# handles the "radioio.stations" query
sub stationsQuery {
	my $request = shift;
 
	#msg("RadioIO::stationsQuery()\n");
 
	if ($request->isNotQuery([['radioio.stations']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	
	my $count = scalar(@station_names);
	$request->addResult('count', $count);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {
		my $idx = $start;
		my $cnt = 0;

		for my $eachstation (@station_names[$start..$end]) {
			$request->addResultLoop('@stations', $cnt, 'station', $eachstation);
			$request->addResultLoop('@stations', $cnt, 'url', "radioio://$eachstation.mp3");
			$cnt++;
		}	
	}

	$request->setStatusDone();
}

# handles the "radioio.stationinfo" query
sub stationinfoQuery {
	my $request = shift;
 
	#msg("RadioIO::stationinfoQuery()\n");
 
	if ($request->isNotQuery([['radioio.stationinfo']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $station  = $request->getParam('station');

	if (!defined $station || !$stations{$station}) {
		$request->setStatusBadParams();
		return;
	}

	my $data = stationInfo($station);

	if (defined $data) {
	
		$request->addResult('fulltitle', $data->{'fulltitle'});
		$request->addResult('bitrate', $data->{'bitrate'});
		$request->addResult('type', $data->{'type'});
		$request->addResult('url', $data->{'url'});
	}

	$request->setStatusDone();
}

sub strings
{
	return "
PLUGIN_RADIOIO_MODULE_NAME
	EN	radioio.com - no boundaries.
	ES	radioio.com - sin límites.
	HE	רדיו אינטרנט ללא גבולות

PLUGIN_RADIOIO_MODULE_TITLE
	EN	radioio.com
";}

1;
