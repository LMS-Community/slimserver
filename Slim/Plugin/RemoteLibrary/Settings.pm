package Slim::Plugin::RemoteLibrary::Settings;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.remotelibrary');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_REMOTE_LIBRARY_MODULE_NAME');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/RemoteLibrary/settings.html');
}

sub prefs {
	return ($prefs, qw(useLMS useUPnP ignoreFolders transcodeLMS));
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	if ( defined $paramRef->{pref_useLMS} && $paramRef->{pref_useLMS} && !$prefs->get('useLMS') ) {
		# Start LMS discovery if the user enabled it
		require Slim::Plugin::RemoteLibrary::LMS;
		Slim::Plugin::RemoteLibrary::LMS->init();
	}

	if ($paramRef->{'saveSettings'}) {
		my @array;

		for (my $i = 0; defined $paramRef->{'pref_remoteLMS' . $i}; $i++) {
			push @array, $paramRef->{'pref_remoteLMS' . $i} if $paramRef->{'pref_remoteLMS' . $i};
		}

		$prefs->set('remoteLMS', \@array);
	}
	
	$paramRef->{'prefs'}->{ 'pref_remoteLMS' } = [ @{ $prefs->get('remoteLMS') || [] }, '' ];
	$paramRef->{'remoteLMSDetails'} = $prefs->get('remoteLMSDetails');

	if ( defined $paramRef->{pref_useUPnP} && $paramRef->{pref_useUPnP} ne $prefs->get('useUPnP') ) {
		# Shut down all UPnP activity - don't load module if it wasn't loaded yet
		eval { Slim::Plugin::RemoteLibrary::UPnP::MediaServer->shutdown() };
		
		# Start it up again if the user enabled it
		if ( $paramRef->{pref_useUPnP} ) {
			require Slim::Plugin::RemoteLibrary::UPnP;
			Slim::Plugin::RemoteLibrary::UPnP->init();
		}
	}

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;
