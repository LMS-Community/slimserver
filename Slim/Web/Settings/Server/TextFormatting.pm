package Slim::Web::Settings::Server::TextFormatting;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub name {
	return 'FORMATTING_SETTINGS';
}

sub page {
	return 'settings/server/formatting.html';
}

sub prefs {
	return ($prefs, qw(longdateFormat shortdateFormat timeFormat showArtist showYear titleFormatWeb) );
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# handle array prefs in this handler, scalar prefs in SUPER::handler
	my @prefs = qw(guessFileFormats titleFormat);

	if ($paramRef->{'saveSettings'}) {

		for my $pref (@prefs) {

			my @array;

			for (my $i = 0; defined $paramRef->{$pref.$i}; $i++) {

				push @array, $paramRef->{$pref.$i} if $paramRef->{$pref.$i};
			}

			$prefs->set($pref, \@array);
		}

		if ($paramRef->{'titleformatWeb'} ne $prefs->get('titleFormatWeb')) {

			for my $client (Slim::Player::Client::clients()) {

				$client->currentPlaylistChangeTime(time);
			}
		}
	}

	for my $pref (@prefs) {
		$paramRef->{'prefs'}->{ $pref } = [ @{ $prefs->get($pref) || [] }, '' ];
	}

	$paramRef->{'longdateoptions'}  = Slim::Utils::DateTime::longDateFormats();
	$paramRef->{'shortdateoptions'} = Slim::Utils::DateTime::shortDateFormats();
	$paramRef->{'timeoptions'}      = Slim::Utils::DateTime::timeFormats();

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
