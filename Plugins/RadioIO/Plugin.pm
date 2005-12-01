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
#
package Plugins::RadioIO::Plugin;

use strict;
use Scalar::Util qw(blessed);

use Slim::Buttons::Common;
use Slim::Control::Command;
use Slim::Player::ProtocolHandlers;
use Slim::Music::Info;

our %current = ();

our %stations = (
	'radioio70s'  => '3765',			
	'radioio70sPOP'  => '3910',			
	'radioio80s'  => '3795',
	'radioio80sPOP'  => '3935',			
	'radioioACOUSTIC' => '3675',
	'radioioAMBIENT'  => '3605',
	'radioioBEAT' => '3725',
	'radioioCLASSICAL' => '3635',
	'radioioCOUNTRY' => '3055',				 
	'radioioECLECTIC' => '3586',
	'radioioEDGE' => '3995',
	'radioioJAM' => '3970',
	'radioioJAZZ' => '3545',
	'radioioPOP' => '3965',
	'radioioROCK' => '3515',
);

our @station_names = sort keys %stations;

sub enabled {
	return ($::VERSION ge '6.1');
}

sub initPlugin {

	Slim::Player::ProtocolHandlers->registerHandler('radioio', 'Plugins::RadioIO::ProtocolHandler');
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

			$client->execute(['playlist', 'clear']);
			$client->execute(['playlist', 'add', $url]);
			$client->execute(['play']);
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
	
	if (defined $params->{'p0'} && $stations{$params->{'p0'}}) {
		$params->{'stationname'} = $params->{'p0'};

		# let's open the stream to get some more information
		my $url = "radioio://$params->{'p0'}.mp3";
		my $stream = Plugins::RadioIO::ProtocolHandler->new({ url => $url });
		my $ds = Slim::Music::Info::getCurrentDataStore();
		my $track = $ds->objectForUrl($url, 1, 1);

		if (blessed($track) && $track->can('bitrate')) {

			$params->{'fulltitle'} = Slim::Music::Info::getCurrentTitle($client, $url);
			$params->{'bitrate'} = $track->bitrate();
			$params->{'type'} = Slim::Music::Info::contentType($url);
		}

		undef $stream;

	} else {

		$params->{'stationnames'} = \@station_names;
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/RadioIO/index.html', $params);
}


sub strings
{
	return "
PLUGIN_RADIOIO_MODULE_NAME
	EN	radioio.com - no boundaries.
	ES	radioio.com - sin límites.

PLUGIN_RADIOIO_MODULE_TITLE
	EN	radioio.com
";}

1;

package Plugins::RadioIO::ProtocolHandler;

use strict;
use base  qw(Slim::Player::Protocols::HTTP);

use Scalar::Util qw(blessed);

use Slim::Formats::Parse;
use Slim::Player::Source;

sub new {
	my $class  = shift;
	my $args   = shift;

	my $url    = $args->{'url'};
	my $client = $args->{'client'};

	if ($url !~ /^radioio:\/\/(.*?)\.mp3/) {
		return undef;
	}

	my $pls  = Plugins::RadioIO::Plugin::getHTTPURL($1);

	my $sock = $class->SUPER::new({
		'url'    => $pls,
		'client' => $client
	}) || return undef;
	
	my @items = Slim::Formats::Parse::parseList($pls, $sock);

	return undef unless scalar(@items);

	return $class->SUPER::new({
		'url'     => $items[0],
		'client'  => $client,
		'infoUrl' => $url,
	});
}

sub canDirectStreamDisabled {
	my $self = shift;
	my $url = shift;

	if ($url =~ /^radioio:\/\/stream\/(.*)/) {
		return 'http://' . Plugins::RadioIO::Plugin::decrypt($1);
	}
	elsif ($url =~ /^radioio:\/\/(.*?)\.mp3/) {
		return Plugins::RadioIO::Plugin::getHTTPURL($1);
	}

	return undef;
}

sub parseDirectBody {
	my $self = shift;
	my $url = shift;
	my $body = shift;

	my $io = IO::String->new($body);
	my @items = Slim::Formats::Parse::parseList($url, $io);

	return () unless scalar(@items);

	my $stream = $items[0];
	$stream =~ s/http:\/\///;
	$stream = 'radioio://stream/' . Plugins::RadioIO::Plugin::decrypt($stream);

	my $currentDB = Slim::Music::Info::getCurrentDataStore();
	my $track = $currentDB->objectForUrl($url);

	if (blessed($track) && $track->can('title')) {

		Slim::Music::Info::setTitle($stream, $track->title());
	}

	return ($stream);
}

1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
