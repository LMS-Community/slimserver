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
	return 'settings/server/basic.html';
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my @prefs = qw(language audiodir playlistdir rescantype rescan);

	for my $importer (qw(iTunes MusicMagic)) {

		if (exists $Slim::Music::Import::Importers{"Plugins::".$importer."::Plugin"}) {
			push @prefs, lc($importer);
		}
	}

	# If this is a settings update
	if ($paramRef->{'saveSettings'}) {
logger('scan.scanner')->info("saveSettings");

		if ($paramRef->{'language'} ne Slim::Utils::Prefs::get('language')) {
		
			Slim::Utils::Strings::setLanguage($paramRef->{'language'});
		}

		for my $pref (@prefs) {

			if ($pref eq 'playlistdir' || $pref eq 'audiodir') {

				if ($paramRef->{$pref} ne Slim::Utils::Prefs::get($pref)) {
					
					my ($validDir, $errMsg) = Slim::Utils::Validate::isDir($paramRef->{$pref});
					
					if (!$validDir && $paramRef->{$pref} ne "") {

						$paramRef->{'warning'} .= sprintf(Slim::Utils::Strings::string("SETUP_BAD_DIRECTORY"), $paramRef->{$pref});
	
						delete $paramRef->{$pref};
					}

					else {

						$paramRef->{'rescan'} = 1;

						if ($paramRef->{'rescantype'} ne '2wipedb') {

							$paramRef->{'rescantype'} = ($pref eq 'playlistdir' ? '3playlist' : '2wipedb');
						}
					}
				}
			}

			if (exists $paramRef->{$pref}) {

				Slim::Utils::Prefs::set($pref, $paramRef->{$pref});
			}
		}
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

	my @versions = Slim::Utils::Misc::settingsDiagString();

	$paramRef->{'versionInfo'} = join( "<br />\n", @versions ) . "\n<p>";
	$paramRef->{'newVersion'}  = $::newVersion;
	$paramRef->{'languageoptions'} = Slim::Utils::Strings::languageOptions();

	for my $pref (@prefs) {

		$paramRef->{'prefs'}->{$pref} = Slim::Utils::Prefs::get($pref);
	}
	
	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
