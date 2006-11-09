package Slim::Web::Settings::Server::Basic;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;

sub name {
	return 'BASIC_SERVER_SETTINGS';
}

sub page {
	return 'settings/basic.html';
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my @prefs = qw(language audiodir playlistdir rescantype rescan);

	if (grep {$_ =~ 'iTunes'} keys %Slim::Music::Import::Importers) {
		push @prefs, 'itunes';
		$paramRef->{'itunesavailable'} = 1;
	}
	
	if (grep {$_ =~ 'MusicMagic'} keys %Slim::Music::Import::Importers) {
		push @prefs, 'musicmagic';
		$paramRef->{'musicmagicavailable'} = 1;
	}
	
	if (grep {$_ =~ 'MoodLogic'} keys %Slim::Music::Import::Importers) {
		push @prefs, 'moodlogic';
		$paramRef->{'moodlogicavailable'} = 1;
	}

	if ($paramRef->{'rescan'}) {
		my $rescanType = ['rescan'];

		if ($paramRef->{'rescantype'} eq '2wipedb') {

			$rescanType = ['wipecache'];

		} elsif ($paramRef->{'rescantype'} eq '3playlist') {

			$rescanType = [qw(rescan playlists)];
		}

		logger('scan.scanner')->info(sprintf("Initiating scan of type: %s",join (" ",@{$rescanType})));

		Slim::Control::Request::executeRequest($client, $rescanType);
	}
	
	# If this is a settings update
	if ($paramRef->{'submit'}) {

		if ($paramRef->{'language'} ne Slim::Utils::Prefs::get('language')) {
		
			Slim::Utils::Prefs::set('language', $paramRef->{'language'});
			Slim::Utils::PluginManager::clearPlugins();
			Slim::Utils::Strings::init();
			Slim::Web::Setup::initSetup();
			Slim::Utils::PluginManager::initPlugins();
			Slim::Music::Import->resetSetupGroups;

		}

		for my $pref (@prefs) {

			if ($pref eq 'playlistdir' || $pref eq 'audiodir') {
				if ($paramRef->{$pref} ne Slim::Utils::Prefs::get($pref)) {
					
					my ($validDir, $errMsg) = Slim::Utils::Validate::isDir($paramRef->{$pref});
					
					if (!$validDir && $paramRef->{$pref} ne "") {
						$paramRef->{'warning'} .= sprintf(string("SETUP_BAD_DIRECTORY"),$paramRef->{$pref});
	
						delete $paramRef->{$pref};
					}
				}
			}

			Slim::Utils::Prefs::set($pref, $paramRef->{$pref}) if $paramRef->{$pref};
		}
	}

	my @versions = Slim::Utils::Misc::settingsDiagString();
	$paramRef->{'versionInfo'} = join( "<br />\n", @versions ) . "\n<p>";
	$paramRef->{'newVersion'}  = $::newVersion;

	$paramRef->{'languageoptions'} = {Slim::Utils::Strings::hash_of_languages()};

	for my $pref (@prefs) {
		$paramRef->{$pref} = Slim::Utils::Prefs::get($pref);
	}
	
	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
