# $Id$

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
package Plugins::RadioIO;

use Slim::Buttons::Common;
use Slim::Control::Command;
use Slim::Display::Display;
use Slim::Music::Info;
use Slim::Player::Source;

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

sub initPlugin {
	Slim::Player::Source::registerProtocolHandler("radioio", "Plugins::RadioIO::ProtocolHandler");
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
	'up' => sub {
		my $client = shift;
		$current{$client} = Slim::Buttons::Common::scroll($client, -1, scalar(@station_names), $current{$client} || 0);
		$client->update();
	},
	'down' => sub {
		my $client = shift;
		$current{$client} = Slim::Buttons::Common::scroll($client, 1, scalar(@station_names), $current{$client} || 0);
		$client->update();
	},
	'left' => sub {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub {
		my $client = shift;
		$client->bumpRight();
	},
	'play' => sub {
		my $client = shift;

		my $url = getRadioIOURL($current{$client} || 0);

		if (defined($url)) {
			Slim::Control::Command::execute($client, ['playlist', 'clear']);
			Slim::Control::Command::execute($client, ['playlist', 'add', $url]);
			Slim::Control::Command::execute($client, ['play']);
		}
	},
	'add' => sub {
		my $client = shift;
		
		my $url = getRadioIOURL($current{$client} || 0);

		if (defined($url)) {
			Slim::Control::Command::execute($client, ['playlist', 'add', $url]);
		}
	},
);

sub lines {
	my $client = shift;
	my @lines;
	my $name = $station_names[$current{$client}];

	$lines[0] = $client->string('PLUGIN_RADIOIO_MODULE_TITLE').
	    ' (' .
		($current{$client} + 1) .  ' ' .
		  $client->string('OF') .  ' ' .
			  (scalar(@station_names)) .  ') ' ;
	$lines[1] = $name;
	$lines[3] = Slim::Display::Display::symbol('notesymbol');

	return @lines;
}

sub setMode {
	my $client = shift;
	$current{$client} ||= 0;
	$client->lines(\&lines);
}

sub getFunctions {
	return \%functions;
}

sub addMenu {
	my $menu = "RADIO";
	return $menu;
}

sub getDisplayName {
	return 'PLUGIN_RADIOIO_MODULE_NAME';
}

sub strings
{
	return "
PLUGIN_RADIOIO_MODULE_NAME
	DE	radioio.com Internet Radio
	EN	radioio.com - no boundaries.
	ES	radioio.com - sin límites.

PLUGIN_RADIOIO_MODULE_TITLE
	DE	radioio.com
	EN	radioio.com
	ES	radioio.com
";}

1;

package Plugins::RadioIO::ProtocolHandler;

use strict;
use base  qw(Slim::Player::Protocols::HTTP);

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

	my $pls  = Plugins::RadioIO::getHTTPURL($1);

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

1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
