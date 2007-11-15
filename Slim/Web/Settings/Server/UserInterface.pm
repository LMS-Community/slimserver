package Slim::Web::Settings::Server::UserInterface;

# $Id$

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Player::Client;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::protectName('INTERFACE_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/server/interface.html');
}

sub prefs {
	return ($prefs, qw(skin itemsPerPage refreshRate thumbSize longdateFormat shortdateFormat timeFormat showArtist showYear titleFormatWeb));
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# handle array prefs in this handler, scalar prefs in SUPER::handler
	my @prefs = qw(titleFormat);

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

				$client->currentPlaylistChangeTime(Time::HiRes::time());
			}
		}


		if ($paramRef->{'skin'} ne $prefs->get('skin')) {
			# use Classic instead of Default skin if the server's language is set to Hebrew
			if ($prefs->get('language') eq 'HE' && $paramRef->{'skin'} eq 'Default') {
	
				$paramRef->{'skin'} = 'Classic';
	
			}
	
			$paramRef->{'warning'} .= join(' ', string("SETUP_SKIN_OK"), $paramRef->{'skin'}, string("HIT_RELOAD"));
		}


		for my $client (Slim::Player::Client::clients()) {

			$client->currentPlaylistChangeTime(Time::HiRes::time());
		}
	}

	for my $pref (@prefs) {
		$paramRef->{'prefs'}->{ $pref } = [ @{ $prefs->get($pref) || [] }, '' ];
	}

	$paramRef->{'longdateoptions'}  = Slim::Utils::DateTime::longDateFormats();
	$paramRef->{'shortdateoptions'} = Slim::Utils::DateTime::shortDateFormats();
	$paramRef->{'timeoptions'}      = Slim::Utils::DateTime::timeFormats();

	$paramRef->{'skinoptions'} = { Slim::Web::HTTP::skins(1) };

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
