package Slim::Web::Settings::Player::Remote;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);

sub name {
	return 'REMOTE_SETTINGS';
}

sub page {
	return 'settings/player/remote.html';
}

sub needsClient {
	return 1;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my @prefs = ();

	if ($client->isPlayer()) {

		if (scalar(keys %{Slim::Hardware::IR::mapfiles()}) > 1) {  

			push @prefs, 'irmap';  
		}
		
		# If this is a settings update
		if ($paramRef->{'submit'}) {
	
			my @changed = ();

			for my $pref (@prefs) {
	
				# parse indexed array prefs.
				if ($paramRef->{$pref} ne $client->prefGet($pref)) {

					push @changed, $pref;
				}
				
				if (defined $paramRef->{$pref}) {

					$client->prefSet($pref, $paramRef->{$pref});
				}
			}
			
			$client->prefDelete('disabledirsets');
			
			my @irsets = keys %{Slim::Hardware::IR::irfiles($client)};

			for my $i (0 .. (scalar(@irsets)-1)) {
			
				if ($paramRef->{'irsetlist'.$i}) {

					$client->prefPush('disabledirsets',$paramRef->{'irsetlist'.$i});
				}

				Slim::Hardware::IR::loadIRFile($irsets[$i]);
			}
			
			$class->_handleChanges($client, \@changed, $paramRef);
		}
	
		$paramRef->{'irmapOptions'}   = { %{Slim::Hardware::IR::mapfiles()}};
		$paramRef->{'irsetlist'}      = { map {$_ => Slim::Hardware::IR::irfileName($_)} sort(keys %{Slim::Hardware::IR::irfiles($client)})};
		$paramRef->{'disabledirsets'} = { map {$_ => 1} $client->prefGetArray('disabledirsets')};
	
		# Set current values for prefs
		# load into prefs hash so that web template can detect exists/!exists
		for my $pref (@prefs) {
			
			$paramRef->{'prefs'}->{$pref} = $client->prefGet($pref);
		}
		
	} else {

		# non-SD player, so no applicable display settings
		$paramRef->{'warning'} = string('SETUP_NO_PREFS');
	}

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
