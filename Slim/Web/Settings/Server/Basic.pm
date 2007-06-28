package Slim::Web::Settings::Server::Basic;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

sub name {
	return 'BASIC_SERVER_SETTINGS';
}

sub page {
	return 'settings/server/basic.html';
}

sub prefs {
	return (preferences('server'), qw(language audiodir playlistdir) );
}

# FIXME - add importers back as these are in different namespaces... perhaps they should be in the server namespace...

#for my $importer (qw(iTunes MusicMagic)) {

#	if (exists $Slim::Music::Import::Importers{"Slim::Plugin::".$importer."::Plugin"}) {
#		push @prefs, lc($importer);
#	}
#}

sub handler {
	my ($class, $client, $paramRef) = @_;

	# prefs setting handled by SUPER::handler

	if ($paramRef->{'rescan'}) {

		my $rescanType = ['rescan'];

		if ($paramRef->{'rescantype'} eq '2wipedb') {

			$rescanType = ['wipecache'];

		} elsif ($paramRef->{'rescantype'} eq '3playlist') {

			$rescanType = [qw(rescan playlists)];
		}

		for my $pref (qw(audiodir playlistdir)) {
	
			my (undef, $ok) = preferences('server')->set($pref, $paramRef->{$pref});

			if ($ok) {
				$paramRef->{'validated'}->{$pref} = 1; 
			}
			else { 
				$paramRef->{'warning'} .= sprintf(Slim::Utils::Strings::string('SETTINGS_INVALIDVALUE'), $paramRef->{$pref}, $pref) . '<br/>';
				$paramRef->{'validated'}->{$pref} = 0;
			}
		}

		logger('scan.scanner')->info(sprintf("Initiating scan of type: %s",join (" ",@{$rescanType})));

		Slim::Control::Request::executeRequest(undef, $rescanType);
	}

	$paramRef->{'scanning'} = Slim::Music::Import->stillScanning;

	my @versions = Slim::Utils::Misc::settingsDiagString();

	$paramRef->{'versionInfo'} = join( "<br />\n", @versions ) . "\n";
	$paramRef->{'newVersion'}  = $::newVersion;
	$paramRef->{'languageoptions'} = Slim::Utils::Strings::languageOptions();

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
