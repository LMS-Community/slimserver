package Slim::Web::History;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Web::Pages;

# Histlist fills variables for populating an html file. 
sub hitlist {
	my ($client, $params) = @_;

	my $itemNumber = 0;
	my $maxPlayed  = 0;

	my $ds     = Slim::Music::Info::getCurrentDataStore();

	# Fetch 50 tracks that have been played at least once.
	# Limit is hardcoded for now.. This should make use of
	# Class::DBI::Pager or similar. Requires reworking of template
	# generation.
	my $tracks = $ds->find('track', { 'playCount' => { '>' => 0 } }, 'playCount', 50, 0);

	for my $track (reverse @$tracks) {

		my $playCount = $track->playCount();

		if ($maxPlayed == 0) {
			$maxPlayed = $playCount;
		}

		my %form  = %$params;

		$form{'title'} 	      = Slim::Music::Info::standardTitle(undef, $track);
		$form{'artist'}       = $track->artist();
		$form{'album'} 	      = $track->album();
		$form{'itempath'}     = $track->url();
		$form{'odd'}	      = ($itemNumber + 1) % 2;
		$form{'song_bar'}     = hitlist_bar($params, $playCount, $maxPlayed);
		$form{'player'}	      = $params->{'player'};
		$form{'skinOverride'} = $params->{'skinOverride'};
		$form{'song_count'}   = $playCount;

		$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("hitlist_list.html", \%form)};

		$itemNumber++;
	}

	Slim::Web::Pages::addLibraryStats($params);

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
