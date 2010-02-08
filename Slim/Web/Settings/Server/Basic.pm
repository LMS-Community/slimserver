package Slim::Web::Settings::Server::Basic;

# $Id$

# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('BASIC_SERVER_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/server/basic.html');
}

sub prefs {
	return ($prefs, qw(language audiodir playlistdir libraryname) );
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

	if ($paramRef->{'pref_rescan'}) {

		my $rescanType = ['rescan'];

		if ($paramRef->{'pref_rescantype'} eq '2wipedb') {

			$rescanType = ['wipecache'];

		} elsif ($paramRef->{'pref_rescantype'} eq '3playlist') {

			$rescanType = [qw(rescan playlists)];
		}

		for my $pref (qw(audiodir playlistdir)) {

			my (undef, $ok) = $prefs->set($pref, $paramRef->{"pref_$pref"});

			if ($ok) {
				$paramRef->{'validated'}->{$pref} = 1; 
			}
			else { 
				$paramRef->{'warning'} .= sprintf(Slim::Utils::Strings::string('SETTINGS_INVALIDVALUE'), $paramRef->{"pref_$pref"}, $pref) . '<br/>';
				$paramRef->{'validated'}->{$pref} = 0;
			}
		}

		if ( main::INFOLOG && logger('scan.scanner')->is_info ) {
			logger('scan.scanner')->info(sprintf("Initiating scan of type: %s",join (" ",@{$rescanType})));
		}

		Slim::Control::Request::executeRequest(undef, $rescanType);
	}
	
	if ( $paramRef->{'saveSettings'} ) {
		my $curLang = $prefs->get('language');
		my $lang    = $paramRef->{'pref_language'};

		if ( $lang && $lang ne $curLang ) {
			# use Classic instead of Default skin if the server's language is set to Hebrew
			if ($lang eq 'HE' && $prefs->get('skin') eq 'Default') {
				$prefs->set('skin', 'Classic');
				$paramRef->{'warning'} .= '<span id="popupWarning">' . Slim::Utils::Strings::string("SETUP_SKIN_OK") . '</span>';
			}	

			# Bug 5740, flush the playlist cache
			for my $client (Slim::Player::Client::clients()) {
				$client->currentPlaylistChangeTime(Time::HiRes::time());
			}
		}
	}

	$paramRef->{'newVersion'}  = $::newVersion;
	$paramRef->{'languageoptions'} = Slim::Utils::Strings::languageOptions();

	return $class->SUPER::handler($client, $paramRef);
}

sub beforeRender {
	my ($class, $paramRef) = @_;
	$paramRef->{'scanning'} = Slim::Music::Import->stillScanning;
}

1;

__END__
