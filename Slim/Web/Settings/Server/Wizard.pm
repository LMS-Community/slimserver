package Slim::Web::Settings::Server::Wizard;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);
use Digest::SHA1 qw(sha1_base64);
use HTTP::Status qw(RC_MOVED_TEMPORARILY);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'wizard',
	'defaultLevel' => 'ERROR',
});

my $serverPrefs = preferences('server');
my @prefs = ('mediadirs', 'playlistdir');

sub page {
	return 'settings/server/wizard.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup, $httpClient, $response) = @_;

	$paramRef->{languageoptions} = Slim::Utils::Strings::languageOptions();

	# The hostname for mysqueezebox.com
	$paramRef->{sn_server} = Slim::Networking::SqueezeNetwork->get_server("sn") if !main::NOMYSB;

	# make sure we only enforce the wizard at the very first startup
	if ($paramRef->{saveSettings}) {

		$serverPrefs->set('wizardDone', 1);
		$paramRef->{wizardDone} = 1;
		delete $paramRef->{firstTimeRun};		

	}

	if (!$serverPrefs->get('wizardDone')) {
		$paramRef->{firstTimeRun} = 1;

		# try to guess the local language setting
		# only on non-Windows systems, as the Windows installer is setting the language
		if (!main::ISWINDOWS && !$paramRef->{saveLanguage}
			&& defined $response->{_request}->{_headers}->{'accept-language'}) {

			main::DEBUGLOG && $log->debug("Accepted-Languages: " . $response->{_request}->{_headers}->{'accept-language'});

			require I18N::LangTags;

			foreach my $language (I18N::LangTags::extract_language_tags($response->{_request}->{_headers}->{'accept-language'})) {
				$language = uc($language);
				$language =~ s/-/_/;  # we're using zh_cn, the header says zh-cn
	
				main::DEBUGLOG && $log->debug("trying language: " . $language);
				if (defined $paramRef->{languageoptions}->{$language}) {
					$serverPrefs->set('language', $language);
					main::INFOLOG && $log->info("selected language: " . $language);
					last;
				}
			}

		}

		Slim::Utils::DateTime::setDefaultFormats();
	}
	
	# handle language separately, as it is in its own form
	if ($paramRef->{saveLanguage}) {
		main::DEBUGLOG && $log->debug( 'setting language to ' . $paramRef->{language} );
		$serverPrefs->set('language', $paramRef->{language});
		Slim::Utils::DateTime::setDefaultFormats();
	}

	$paramRef->{prefs}->{language} = Slim::Utils::Strings::getLanguage();
	
	# set right-to-left orientation for Hebrew users
	$paramRef->{rtl} = 1 if ($paramRef->{prefs}->{language} eq 'HE');

	foreach my $pref (@prefs) {

		if ($paramRef->{saveSettings}) {
				
			# if a scan is running and one of the music sources has changed, abort scan
			if ( 
				( ($pref eq 'playlistdir' && $paramRef->{$pref} ne $serverPrefs->get($pref))
					|| ($pref eq 'mediadirs' && scalar (grep { $_ ne $paramRef->{$pref} } @{ $serverPrefs->get($pref) }))
				) && Slim::Music::Import->stillScanning ) 
			{
				main::DEBUGLOG && $log->debug('Aborting running scan, as user re-configured music source in the wizard');
				Slim::Music::Import->abortScan();
			}
			
			# revert logic: while the pref is "disable", the UI is opt-in
			# if this value is set we actually want to not disable it...
			elsif ($pref eq 'sn_disable_stats') {
				$paramRef->{$pref} = $paramRef->{$pref} ? 0 : 1;
			}

			if ($pref eq 'mediadirs') {
				$serverPrefs->set($pref, [ $paramRef->{$pref} ]);
			}
			else {
				$serverPrefs->set($pref, $paramRef->{$pref});
			}
		}

		if (main::DEBUGLOG && $log->is_debug) {
 			$log->debug("$pref: " . $serverPrefs->get($pref));
		}
		
		if ($pref eq 'mediadirs') {
			my $mediadirs = $serverPrefs->get($pref);
			$paramRef->{prefs}->{$pref} = scalar @$mediadirs ? $mediadirs->[0] : '';
		}
		else {
			$paramRef->{prefs}->{$pref} = $serverPrefs->get($pref);
		}
	}

	$paramRef->{useiTunes} = preferences('plugin.itunes')->get('itunes');
	$paramRef->{useMusicIP} = preferences('plugin.musicip')->get('musicip');
	$paramRef->{serverOS} = Slim::Utils::OSDetect::OS();

	# if the wizard has been run for the first time, redirect to the main we page
	if ($paramRef->{firstTimeRunCompleted}) {

		$response->code(RC_MOVED_TEMPORARILY);
		$response->header('Location' => '/');
	}

	else {
		
		# use local path if neither iTunes nor MusicIP is available, or on anything but Windows/OSX
		$paramRef->{useAudiodir} = Slim::Utils::OSDetect::OS() !~ /^(?:mac|win)$/ || !($paramRef->{useiTunes} || $paramRef->{useMusicIP});
	}
	
	if ( $paramRef->{saveSettings} ) {

		if (   !main::NOMYSB 
			&& $paramRef->{sn_email}
			&& $paramRef->{sn_password_sha}
			&& $serverPrefs->get('sn_sync')
		) {			
			Slim::Networking::SqueezeNetwork->init();
		}

		# Disable iTunes and MusicIP plugins if they aren't being used
		if ( !$paramRef->{useiTunes} && Slim::Utils::PluginManager->isEnabled('Slim::Plugin::iTunes::Plugin') ) {
			Slim::Utils::PluginManager->disablePlugin('iTunes');
		}
		
		if ( !$paramRef->{useMusicIP} && Slim::Utils::PluginManager->isEnabled('Slim::Plugin::MusicMagic::Plugin') ) {
			Slim::Utils::PluginManager->disablePlugin('MusicMagic');
		}
	}
	
	
	if ($client) {
		$paramRef->{playericon} = Slim::Web::Settings::Player::Basic->getPlayerIcon($client,$paramRef);
		$paramRef->{playertype} = $client->model();
	}

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
}

1;

__END__
