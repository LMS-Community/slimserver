package Slim::Web::Settings::Server::UserInterface;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
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
	return Slim::Web::HTTP::CSRF->protectName('INTERFACE_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/server/interface.html');
}

sub prefs {
	return ($prefs, qw(displaytexttimeout skin itemsPerPage refreshRate thumbSize additionalPlaylistButtons
					   longdateFormat shortdateFormat timeFormat showArtist showYear titleFormatWeb));
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# handle array prefs in this handler, scalar prefs in SUPER::handler
	my @prefs = qw(titleFormat);

	if ($paramRef->{'saveSettings'}) {

		for my $pref (@prefs) {

			my @array;

			for (my $i = 0; defined $paramRef->{'pref_'.$pref.$i}; $i++) {

				push @array, $paramRef->{'pref_'.$pref.$i} if $paramRef->{'pref_'.$pref.$i};
			}

			$prefs->set($pref, \@array);
		}

		if ($paramRef->{'pref_titleFormatWeb'} ne $prefs->get('titleFormatWeb')) {

			for my $client (Slim::Player::Client::clients()) {

				$client->currentPlaylistChangeTime(Time::HiRes::time());
			}
		}


		if ($paramRef->{'pref_skin'} ne $prefs->get('skin')) {
			# use Classic instead of Default skin if the server's language is set to Hebrew
			if ($prefs->get('language') eq 'HE' && $paramRef->{'pref_skin'} eq 'Default') {
	
				$paramRef->{'pref_skin'} = 'Classic';
	
			}

			$paramRef->{'warning'} .= '<span id="popupWarning">' . string("SETUP_SKIN_OK") . '</span>';
		}


		for my $client (Slim::Player::Client::clients()) {

			$client->currentPlaylistChangeTime(Time::HiRes::time());
		}
	}

	for my $pref (@prefs) {
		$paramRef->{'prefs'}->{ 'pref_'.$pref } = [ @{ $prefs->get($pref) || [] }, '' ];
	}

	$paramRef->{'longdateoptions'}  = Slim::Utils::DateTime::longDateFormats();
	$paramRef->{'shortdateoptions'} = Slim::Utils::DateTime::shortDateFormats();
	$paramRef->{'timeoptions'}      = Slim::Utils::DateTime::timeFormats();

	$paramRef->{'skinoptions'} = { Slim::Web::HTTP::skins(1) };

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
