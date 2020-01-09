package Slim::Player::CapabilitiesHelper;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

sub samplerateLimit {
	my $song     = shift;
	
	my $srate = $song->currentTrack()->samplerate;
	
	return undef if ! $srate;

	my $maxRate = 0;
	
	foreach ($song->master()->syncGroupActiveMembers()) {
		my $rate = $_->maxSupportedSamplerate();
		if ($rate && ($maxRate && $maxRate > $rate || !$maxRate)) {
			$maxRate = $rate;
		}
	}
	
	if ($maxRate && $maxRate < $srate) {
		if (($maxRate % 12000) == 0 && ($srate % 11025) == 0) {
			$maxRate = int($maxRate * 11025 / 12000);
		}
		return $maxRate;
	}
	
	return undef;
}

sub supportedFormats {
	my $client = shift;
	
	my @supportedformats = ();
	my %formatcounter    = ();

	my @playergroup = $client->syncGroupActiveMembers();

	foreach my $everyclient (@playergroup) {
		foreach my $supported ($everyclient->formats()) {
			$formatcounter{$supported}++;
		}
	}
	
	foreach my $testformat ($client->formats()) {
		if (($formatcounter{$testformat} || 0) == @playergroup) {
			push @supportedformats, $testformat;
		}
	}
	
	return @supportedformats;
}

1;

__END__