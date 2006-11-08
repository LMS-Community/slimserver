package Slim::Web::Settings::Server::Basic;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub name {
	return 'BASIC_SERVER_SETTINGS';
}

sub page {
	return 'settings/basic.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# itunes, musicmagic & moodlogic here?
	my @prefs = qw(language audiodir playlistdir rescantype rescan);

	for my $pref (@prefs) {

		# If this is a settings update
		if ($paramRef->{'submit'}) {

			Slim::Utils::Prefs::set($pref, $paramRef->{$pref});
		}

		$paramRef->{$pref} = Slim::Utils::Prefs::get($pref);
	}

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
