package Slim::Buttons::Search;

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Buttons::SearchFor;
use Slim::Utils::Strings qw (string);

# button functions for search directory
my @searchChoices = ('ARTISTS','ALBUMS','SONGS');
my %functions = (
	'up' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#searchChoices + 1), $client->searchSelection);
		$client->searchSelection($newposition);
		$client->update();
	},
	'down' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#searchChoices + 1), $client->searchSelection);
		$client->searchSelection($newposition);
		$client->update();
	},
	'left' => sub  {
		my $client = shift;
		my @oldlines = Slim::Display::Display::curLines($client);
		Slim::Buttons::Common::setMode($client, 'home');
		Slim::Display::Animation::pushRight($client, @oldlines, Slim::Display::Display::curLines($client));
	},
	'right' => sub  {
		my $client = shift;
		my @oldlines = Slim::Display::Display::curLines($client);
		Slim::Buttons::Common::pushMode($client, 'searchfor');
		Slim::Buttons::SearchFor::searchFor($client, $searchChoices[$client->searchSelection]);
		Slim::Display::Animation::pushLeft($client, @oldlines, Slim::Display::Display::curLines($client));
	}
);

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	if (!defined($client->searchSelection)) { $client->searchSelection(0); };
	$client->lines(\&lines);
}

#
# figure out the lines to be put up to display the directory
#
sub lines {
	my $client = shift;
	my ($line1, $line2);
	$line1 = string('SEARCH');
	$line2 = string('SEARCHFOR') . ' ' . string($searchChoices[$client->searchSelection]);
	return ($line1, $line2, undef, Slim::Hardware::VFD::symbol('rightarrow'));
}

1;

__END__
