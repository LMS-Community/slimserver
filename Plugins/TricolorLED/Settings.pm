package Plugins::TricolorLED::Settings;

# SqueezeCenter Copyright (c) 2001-2008 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use Slim::Utils::Prefs;

# ----------------------------------------------------------------------------
# Global variables
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# References to other classes
my $classPlugin		= undef;

# ----------------------------------------------------------------------------
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.tricolorled',
	'defaultLevel' => 'OFF',
	'description'  => 'PLUGIN_TRICOLORLED_MODULE_NAME',
});

# ----------------------------------------------------------------------------
my $prefs = preferences( 'plugin.tricolorled');

# ----------------------------------------------------------------------------
# Define own constructor
# - to save references to Plugin.pm
# ----------------------------------------------------------------------------
sub new {
	my $class = shift;

	$classPlugin = shift;

	$log->debug( "*** TricolorLED::Settings::new() " . $classPlugin . "\n");

	$class->SUPER::new();

	return $class;
}

# ----------------------------------------------------------------------------
# Name in the settings dropdown
# ----------------------------------------------------------------------------
sub name {
	return 'PLUGIN_TRICOLORLED_MODULE_NAME';
}

# ----------------------------------------------------------------------------
# Webpage served for settings
# ----------------------------------------------------------------------------
sub page {
	return 'plugins/TricolorLED/setup_index.html';
}

# ----------------------------------------------------------------------------
# Settings are per player
# ----------------------------------------------------------------------------
sub needsClient {
	return 1;
}

# ----------------------------------------------------------------------------
# Only show plugin for Receiver players
# ----------------------------------------------------------------------------
sub validFor {
	my $class = shift;
	my $client = shift;

	return $client->isPlayer && $client->isa('Slim::Player::Receiver');
}

# ----------------------------------------------------------------------------
# Handler for settings page
# ----------------------------------------------------------------------------
sub handler {
	my ($class, $client, $params) = @_;

	# $client is the client that is selected on the right side of the web interface!!!
	# We need the client identified by 'playerid'

	# Find player that fits the mac address supplied in $params->{'playerid'}
	my @playerItems = Slim::Player::Client::clients();
	foreach my $play (@playerItems) {
		if( $params->{'playerid'} eq $play->macaddress()) {
			$client = $play;
			last;
		}
	}
	if( !defined( $client)) {
		return $class->SUPER::handler($client, $params);
	}
	
	$log->debug( "*** TricolorLED: found player: " . $client . "\n");
	
	# Fill in name of player
	if( !$params->{'playername'}) {
		$params->{'playername'} = $client->name();
	}

	my $i = 0;

	for( $i = 1; $i < 11; $i++) {
		if( $params->{'mode'} eq ( "color_s_" . $i)) {
			$classPlugin->setColorRed( $client, $params->{'selColorRed_' . $i});
			$classPlugin->setColorGreen( $client, $params->{'selColorGreen_' . $i});
			$classPlugin->setColorBlue( $client, $params->{'selColorBlue_' . $i});
			$classPlugin->sendColor( $client, 0); # set direct
		}
		if( $params->{'mode'} eq ( "color_t_" . $i)) {
			$classPlugin->setColorRed( $client, $params->{'selColorRed_' . $i});
			$classPlugin->setColorGreen( $client, $params->{'selColorGreen_' . $i});
			$classPlugin->setColorBlue( $client, $params->{'selColorBlue_' . $i});
			$classPlugin->sendColor( $client, 1); # transition
		}
	}

	for( $i = 1; $i < 11; $i++) {
		my %list_form = ();
		$list_form{'id'} = $i;
		$list_form{'red_color'} = $params->{'selColorRed_' . $i};
		$list_form{'green_color'} = $params->{'selColorGreen_' . $i};
		$list_form{'blue_color'} = $params->{'selColorBlue_' . $i};
		$params->{'color_list'} .= ${Slim::Web::HTTP::filltemplatefile('plugins/TricolorLED/color_list.html',\%list_form)};
	}

	# ***********************************
	# ----- RED -----

	if( $params->{'mode'} eq "colorred_0") {
#		$prefs->client($client)->set( 'colorred', $params->{'selColorRed'});
		$classPlugin->setColorRed( $client, $params->{'selColorRed_0'});
		$classPlugin->sendColor( $client, 0);
	}
#	$params->{'selColorRed'} = $prefs->client($client)->get( 'colorred');
	$params->{'selColorRed_0'} = $classPlugin->getColorRed( $client);

	# ***********************************
	# ----- GREEN -----

	if( $params->{'mode'} eq "colorgreen_0") {
#		$prefs->client($client)->set( 'colorgreen', $params->{'selColorGreen'});
		$classPlugin->setColorGreen( $client, $params->{'selColorGreen_0'});
		$classPlugin->sendColor( $client, 0);
	}
#	$params->{'selColorGreen'} = $prefs->client($client)->get( 'colorgreen');
	$params->{'selColorGreen_0'} = $classPlugin->getColorGreen( $client);

	# ***********************************
	# ----- BLUE -----

	if( $params->{'mode'} eq "colorblue_0") {
#		$prefs->client($client)->set( 'colorblue', $params->{'selColorBlue'});
		$classPlugin->setColorBlue( $client, $params->{'selColorBlue_0'});
		$classPlugin->sendColor( $client, 0);
	}
#	$params->{'selColorBlue'} = $prefs->client($client)->get( 'colorblue');
	$params->{'selColorBlue_0'} = $classPlugin->getColorBlue( $client);

	return $class->SUPER::handler($client, $params);
}

1;

__END__

