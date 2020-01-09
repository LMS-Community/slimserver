package Slim::Web::Settings::Server::TextFormatting;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('FORMATTING_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/server/formatting.html');
}

sub prefs {
	return ($prefs, qw(coverArt artfolder));
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# handle array prefs in this handler, scalar prefs in SUPER::handler
	my @prefs = qw(guessFileFormats);

	if ($paramRef->{'saveSettings'}) {

		for my $pref (@prefs) {

			my @array;

			for (my $i = 0; defined $paramRef->{'pref_'.$pref.$i}; $i++) {

				push @array, $paramRef->{'pref_'.$pref.$i} if $paramRef->{'pref_'.$pref.$i};
			}

			$prefs->set($pref, \@array);
		}

	}

	for my $pref (@prefs) {
		$paramRef->{'prefs'}->{ 'pref_'.$pref } = [ @{ $prefs->get($pref) || [] }, '' ];
	}

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
