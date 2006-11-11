package Slim::Web::Settings::Server::TextFormatting;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub name {
	return 'FORMATTING_SETTINGS';
}

sub page {
	return 'settings/server/formatting.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	my @prefs = qw(
		guessFileFormats
		titleFormat
		titleFormatWeb
		longdateFormat
		shortdateFormat
		timeFormat
		showArtist
		showYear
	);

	# If this is a settings update
	if ($paramRef->{'submit'}) {

		for my $pref (@prefs) {

			if ($pref eq 'titleFormat' || $pref eq 'guessFileFormats') {

				Slim::Utils::Prefs::delete($pref);

				my $i = 0;

				while ($paramRef->{$pref.$i}) {

					if (!$paramRef->{$pref.$i}) {
						last;
					}

					Slim::Utils::Prefs::push($pref,$paramRef->{$pref.$i});

					$i++;
				}
				
			} else {

				if ($paramRef->{'titleformatWeb'} ne Slim::Utils::Prefs::get('titleFormatWeb')) {
	
					for my $client (Slim::Player::Client::clients()) {

						$client->currentPlaylistChangeTime(time);
					}
				}
	
				Slim::Utils::Prefs::set($pref, $paramRef->{$pref});
			}
			
		}
	}

	for my $pref (@prefs) {

		if ($pref eq 'guessFileFormats') {

			$paramRef->{$pref} = [Slim::Utils::Prefs::getArray($pref)];

			push @{$paramRef->{$pref}},"";

		} elsif ($pref eq 'titleFormat') {

			$paramRef->{$pref} = [Slim::Utils::Prefs::getArray($pref)];

			push @{$paramRef->{$pref}},"";

		} else {

			$paramRef->{$pref} = Slim::Utils::Prefs::get($pref);
		}
	}
	
	$paramRef->{'longdateoptions'}  = Slim::Utils::DateTime::longDateFormats();
	$paramRef->{'shortdateoptions'} = Slim::Utils::DateTime::shortDateFormats();
	$paramRef->{'timeoptions'}      = Slim::Utils::DateTime::timeFormats();
	
	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
