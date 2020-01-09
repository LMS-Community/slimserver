package Slim::Web::Settings::Player::Remote;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('REMOTE_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/player/remote.html');
}

sub needsClient {
	return 1;
}

sub validFor {
	my $class = shift;
	my $client = shift;
	
	return $client->hasIR;
}

sub prefs {
	my ($class, $client) = @_;

	my @prefs = ();

	push @prefs, 'irmap' if (scalar(keys %{Slim::Hardware::IR::mapfiles()}) > 1);

	return ($prefs->client($client), @prefs);
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	if ($client->isPlayer()) {

		# handle disabledirsets here
		if ($paramRef->{'saveSettings'}) {

			my @irsets = keys %{Slim::Hardware::IR::irfiles($client)};
			my @disabled = ();

			for my $i (0 .. (scalar(@irsets)-1)) {
				
				# The HTML form contains 2 irsetlistN items, so if the user
				# unchecks the box to disable a set, we won't get an arrayref
				if ( !ref $paramRef->{'pref_irsetlist'.$i} ) {

					push @disabled, $paramRef->{'pref_irsetlist'.$i};
				}

				Slim::Hardware::IR::loadIRFile($irsets[$i]);
			}

			$prefs->client($client)->set('disabledirsets', \@disabled);
		}

		$paramRef->{'prefs'}->{'pref_disabledirsets'} = { map {$_ => 1} @{ $prefs->client($client)->get('disabledirsets') || [] } };

		$paramRef->{'irmapOptions'}   = { %{Slim::Hardware::IR::mapfiles()}};
		$paramRef->{'irsetlist'}      = { map {$_ => Slim::Hardware::IR::irfileName($_)} sort(keys %{Slim::Hardware::IR::irfiles($client)})};

	} else {

		# non-SD player, so no applicable display settings
		$paramRef->{'warning'} = string('SETUP_NO_PREFS');
	}

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
