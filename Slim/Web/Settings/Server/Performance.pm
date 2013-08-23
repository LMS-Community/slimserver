package Slim::Web::Settings::Server::Performance;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PERFORMANCE_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/server/performance.html');
}

sub prefs {
	my @prefs = ( $prefs, qw(dbhighmem disableStatistics serverPriority scannerPriority 
 				precacheArtwork maxPlaylistLength useLocalImageproxy) );
 	push @prefs, qw(autorescan autorescan_stat_interval) if Slim::Utils::OSDetect::getOS->canAutoRescan;
 	return @prefs;
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;
		
	if ( $paramRef->{'saveSettings'} ) {
		my $curAuto = $prefs->get('autorescan');
		if ( $curAuto != $paramRef->{pref_autorescan} ) {
			require Slim::Utils::AutoRescan;
			if ( $paramRef->{pref_autorescan} == 1 ) {
				Slim::Utils::AutoRescan->init;
			}
			else {
				Slim::Utils::AutoRescan->shutdown;
			}
		}
		
		my $specs = Storable::dclone($prefs->get('customArtSpecs'));
		
		my @delete = @{ ref $paramRef->{delete} eq 'ARRAY' ? $paramRef->{delete} : [ $paramRef->{delete} ] };
	
		for my $deleteItem (@delete) {
			delete $specs->{$deleteItem};
		}
	
		$prefs->set( customArtSpecs => $specs );
		
	}
	
	# Restart message if dbhighmem is changed
	my $curmem = $prefs->get('dbhighmem') || 0;
	if ( $paramRef->{pref_dbhighmem} && $paramRef->{pref_dbhighmem} != $curmem ) {
		# Trigger restart required message
		$paramRef = Slim::Web::Settings::Server::Plugins->getRestartMessage($paramRef, Slim::Utils::Strings::string('PLUGINS_CHANGED'));
	}
	
	# Restart if restart=1 param is set
	if ( $paramRef->{restart} ) {
		$paramRef = Slim::Web::Settings::Server::Plugins->restartServer($paramRef, 1);
	}

	$paramRef->{'options'} = {
		''   => 'SETUP_PRIORITY_CURRENT',
		map { $_ => {
			-16 => 'SETUP_PRIORITY_HIGH',
			 -6 => 'SETUP_PRIORITY_ABOVE_NORMAL',
			  0 => 'SETUP_PRIORITY_NORMAL',
			  5 => 'SETUP_PRIORITY_BELOW_NORMAL',
			  15 => 'SETUP_PRIORITY_LOW'
			}->{$_} } (-20 .. 20)
	};
	
	$paramRef->{pref_customArtSpecs} = $prefs->get('customArtSpecs');

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
