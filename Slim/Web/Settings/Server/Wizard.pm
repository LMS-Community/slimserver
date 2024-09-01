package Slim::Web::Settings::Server::Wizard;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use File::Slurp qw(read_file);
use File::Spec::Functions qw(catfile);
use FindBin qw($Bin);
use HTTP::Status qw(RC_MOVED_TEMPORARILY);
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::PluginDownloader;
use Slim::Utils::PluginManager;
use Slim::Utils::ExtensionsManager;
use Slim::Utils::Timers;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'wizard',
	'defaultLevel' => 'ERROR',
});

my $serverPrefs = preferences('server');

my @prefs = ('mediadirs', 'playlistdir');
my @pluginsToInstall;
my $finalizeCb;

sub page {
	return 'settings/server/wizard.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup, $httpClient, $response) = @_;

	$paramRef->{languageoptions} = Slim::Utils::Strings::languageOptions();

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
			@pluginsToInstall = ();
			for my $param (keys %$paramRef) {
				if ($paramRef->{$param} && $param =~ /^plugin-(.*)$/) {
					# my $plugin = $1;
					push @pluginsToInstall, $1;
				}
			}

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
				my $dirs = $serverPrefs->get($pref);
				unshift @$dirs, $paramRef->{$pref};

				my %seen;
				my $scanOnChange = $serverPrefs->get('dontTriggerScanOnPrefChange');
				$serverPrefs->set('dontTriggerScanOnPrefChange', 0);

				$serverPrefs->set($pref, [ grep {
					!$seen{$_}++
				} @$dirs ]);

				$serverPrefs->set('dontTriggerScanOnPrefChange', $scanOnChange) if $scanOnChange;
			}
			else {
				$serverPrefs->set($pref, $paramRef->{$pref});
			}

			Slim::Utils::ExtensionsManager::getAllPluginRepos({
				type    => 'plugin',
				cb => sub {
					my ($pluginData, $error) = @_;

					my (undef, undef, $inactive) = Slim::Utils::ExtensionsManager::getCurrentPlugins();

					my %pluginLookup;
					foreach (@$pluginData, @$inactive) {
						$pluginLookup{$_->{name}} = $_;
					}

					foreach my $plugin (@pluginsToInstall) {
						Slim::Utils::ExtensionsManager->enablePlugin($plugin);
						my $pluginDetails = $pluginLookup{$plugin} || {};

						if ($pluginDetails->{url} && $pluginDetails->{sha}) {
							main::INFOLOG && $log->is_info && $log->info("Downloading plugin: $plugin");

							# 3rd party plugin - needs to be downloaded
							Slim::Utils::PluginDownloader->install({
								name => $plugin,
								url => $pluginDetails->{url},
								sha => lc($pluginDetails->{sha})
							});

						}
						elsif ($pluginDetails->{version}) {
							# built-in plugin - install
							main::INFOLOG && $log->is_info && $log->info("Installing plugin: $plugin");
							Slim::Utils::PluginManager->_needsEnable($plugin);
							Slim::Utils::PluginManager->load('', $plugin);
						}
					}

					if (scalar @pluginsToInstall) {
						Slim::Utils::Timers::killTimers(undef, \&_checkPluginDownloads);
						Slim::Utils::Timers::setTimer(undef, time() + 1, \&_checkPluginDownloads);
					}
				},
			});
		}

		if (main::DEBUGLOG && $log->is_debug) {
 			$log->debug("$pref: " . Data::Dump::dump($serverPrefs->get($pref)));
		}

		if ($pref eq 'mediadirs') {
			my $mediadirs = $serverPrefs->get($pref);
			$paramRef->{prefs}->{$pref} = scalar @$mediadirs ? $mediadirs->[0] : '';
		}
		else {
			$paramRef->{prefs}->{$pref} = $serverPrefs->get($pref);
		}
	}

	$paramRef->{serverOS} = Slim::Utils::OSDetect::OS();
	$paramRef->{debug} = main::DEBUGLOG && $log->is_debug;

	my $wzData = {};
	foreach (catfile($Bin, 'HTML'), Slim::Utils::OSDetect::dirsFor('HTML')) {
		my $path = catfile($_, 'EN', 'settings', 'wizard.json');
		if (-f $path) {
			$wzData = from_json(read_file($path));
		}
	}

	$paramRef->{plugins} = $wzData->{plugins};
	$paramRef->{pluginsJSON} = to_json($paramRef->{plugins});

	# if the wizard has been run for the first time, redirect to the main we page
	if ($paramRef->{firstTimeRunCompleted}) {
		$response->code(RC_MOVED_TEMPORARILY);
		$response->header('Location' => '/');

		if (Slim::Utils::PluginDownloader->downloading) {
			$finalizeCb = sub {
				Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
				$pageSetup->( $client, $paramRef, Slim::Web::HTTP::filltemplatefile($class->page, $paramRef), $httpClient, $response );
			};

			return;
		}
	}

	if ($client) {
		$paramRef->{playericon} = Slim::Web::Settings::Player::Basic->getPlayerIcon($client,$paramRef);
		$paramRef->{playertype} = $client->model();
	}

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
}

sub _checkPluginDownloads {
	Slim::Utils::Timers::killTimers(undef, \&_checkPluginDownloads);

	if (Slim::Utils::PluginDownloader->downloading) {
		Slim::Utils::Timers::setTimer(undef, time() + 1, \&_checkPluginDownloads);
		return;
	}

	Slim::Utils::PluginManager->init();
	Slim::Utils::PluginManager->load('', @pluginsToInstall);
	@pluginsToInstall = ();

	# need to reload the strings, as they's be loaded after initial plugin initialization, but we're late here...
	Slim::Utils::Strings::loadStrings();

	# re-initialize the content types map
	Slim::Music::Info::loadTypesConfig();

	# if the MaterialSkin was installed, use it
	my %skins = Slim::Web::HTTP::skins();
	$serverPrefs->set('skin', 'material') if $skins{MATERIAL};

	$finalizeCb->() if $finalizeCb;
}

1;

__END__
