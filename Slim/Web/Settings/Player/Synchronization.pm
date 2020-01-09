package Slim::Web::Settings::Player::Synchronization;

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
	return Slim::Web::HTTP::CSRF->protectName('SETUP_SYNCHRONIZE');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/player/synchronization.html');
}

sub needsClient {
	return 1;
}

sub validFor {
	my $class = shift;
	my $client = shift;

	return $client->isSynced() || (scalar(Slim::Player::Sync::canSyncWith($client)) > 0);
}

sub prefs {
	my ($class, $client) = @_;
	my @prefs = qw(syncVolume syncPower startDelay maintainSync playDelay packetLatency minSyncAdjust);

	return ($prefs->client($client), @prefs);
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	# If this is a settings update
	if ($paramRef->{'saveSettings'}) {

		if ($paramRef->{synchronize}) {
		
			if (my $otherClient = Slim::Player::Client::getClient($paramRef->{synchronize})) {
				$otherClient->execute( [ 'sync', $client->id ] );
			} else {
				$client->execute( [ 'sync', '-' ] );
			}
			
		}
	}

	# Load any option lists for dynamic options.
	$paramRef->{'syncGroups'} = syncGroups($client);
	
	# Set current values for prefs
	# load into prefs hash so that web template can detect exists/!exists
	$paramRef->{'prefs'}->{synchronize} =  -1;

	if ($client->isSynced()) {
		$paramRef->{'prefs'}->{synchronize} = $client->master()->id();
	} 
	
	return $class->SUPER::handler($client, $paramRef);
}


# returns a hash reference to syncGroups available for a client
sub syncGroups {
	my $client = shift;

	my %clients = ();

	for my $eachclient (Slim::Player::Sync::canSyncWith($client)) {

		$clients{$eachclient->id} = Slim::Player::Sync::syncname($eachclient, $client);
	}

	if (Slim::Player::Sync::isMaster($client)) {

		$clients{$client->id} = Slim::Player::Sync::syncname($client, $client);
	}

	$clients{-1} = string('SETUP_NO_SYNCHRONIZATION');

	return \%clients;
}

1;

__END__
