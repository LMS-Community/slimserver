package Slim::Web::Settings::Server::UserInterface;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Player::Client;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Validate;
use Slim::Web::Setup;

sub name {
	return 'INTERFACE_SETTINGS';
}

sub page {
	return 'settings/server/interface.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	my @prefs = qw(skin itemsPerPage refreshRate coverArt artfolder thumbSize);

	# If this is a settings update
	if ($paramRef->{'saveSettings'}) {

		$paramRef->{'warning'} = "";

		for my $pref (@prefs) {

			if ($pref eq 'itemsPerPage') {

				if ($paramRef->{'itemsPerPage'} < 1) {

					$paramRef->{'itemsPerPage'} = 1;
				}
			}
			
			if ($pref eq 'refreshRate') {

				if ($paramRef->{'refreshRate'} < 2) {

					$paramRef->{'refreshRate'} = 2;
				}
			}

			if ($pref eq 'thumbSize') {

				if ($paramRef->{'thumbSize'} < 25)  {

					$paramRef->{'thumbSize'} = 25;
				}

				if ($paramRef->{'thumbSize'} > 250) {

					$paramRef->{'thumbSize'} = 250;
				}
			}

			if ($paramRef->{'skin'} ne Slim::Utils::Prefs::get('skin')) {

				$paramRef->{'warning'} .= join(' ', string("SETUP_SKIN_OK"), string("HIT_RELOAD"));

				for my $client (Slim::Player::Client::clients()) {

					$client->currentPlaylistChangeTime(time);
				}
			}

			if ($pref eq 'artfolder' && $paramRef->{'artfolder'} ne Slim::Utils::Prefs::get('artfolder')) {

				my ($validDir, $errMsg) = Slim::Utils::Validate::isDir($paramRef->{'artfolder'});

				if (!$validDir && $paramRef->{'artfolder'} ne "") {

					$paramRef->{'warning'} .= sprintf(string("SETUP_BAD_DIRECTORY"), $paramRef->{'artfolder'});

					delete $paramRef->{'artfolder'};
				}
			}

			if (exists $paramRef->{$pref}) {

				Slim::Utils::Prefs::set($pref, $paramRef->{$pref});
			}
		}
	}

	for my $pref (@prefs) {
		$paramRef->{$pref} = Slim::Utils::Prefs::get($pref);
	}
	
	$paramRef->{'skinoptions'} = { Slim::Web::HTTP::skins(1) };
	
	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
