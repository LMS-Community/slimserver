package Slim::Web::Pages::History;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Web::Pages;

sub init {
	Slim::Web::Pages->addPageFunction(qr/^hitlist\.(?:htm|xml)/,\&hitlist);
}

# Hitlist fills variables for populating an html file. 
sub hitlist {
	my ($client, $params) = @_;

	my $itemNumber = 0;
	my $maxPlayed  = 0;

	# Fetch 50 tracks that have been played at least once.
	# Limit is hardcoded for now..
	# XXX FIXME
	my $rs = Slim::Schema->search('Track',
		{ 'persistent.playcount' => { '>' => 0 } },
		{ 'join' => qw(persistent), 'order_by'  => 'persistent.playcount desc' },
	)->slice(0, 49);

	while (my $track = $rs->next) {

		my $playCount = $track->persistent->playcount;

		if ($maxPlayed == 0) {
			$maxPlayed = $playCount;
		}

		my %form = (
			'odd'          => ($itemNumber + 1) % 2,
			'song_bar'     => hitlist_bar($params, $playCount, $maxPlayed),
			'player'       => $params->{'player'},
			'skinOverride' => $params->{'skinOverride'},
			'song_count'   => $playCount,
			'attributes'   => '&track.id='.$track->id,
		);

		$track->displayAsHTML(\%form);

		push @{$params->{'browse_items'}}, \%form;

		$itemNumber++;
	}

	Slim::Web::Pages::Common->addLibraryStats($params);

	return Slim::Web::HTTP::filltemplatefile("hitlist.html", $params);
}

sub hitlist_bar {
	my ($params, $curr, $max) = @_;

	my $returnval = "";

	for my $i (qw(9 19 29 39 49 59 69 79 89)) {

		$params->{'cell_full'} = (($curr*100)/$max) > $i;
		$returnval .= ${Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $params)};
	}

	$params->{'cell_full'} = ($curr == $max);
	$returnval .= ${Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $params)};

	return $returnval;
}

1;
