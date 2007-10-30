package Slim::Web::Settings::Server::Wizard;

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);
use I18N::LangTags qw(extract_language_tags);
use HTTP::Status qw(RC_MOVED_TEMPORARILY);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

my $showProxy = 1;
my $serverPrefs = preferences('server');

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'wizard',
	'defaultLevel' => 'WARN',
});

my %prefs = (
	'server' => ['webproxy', 'sn_email', 'sn_password', 'audiodir', 'playlistdir'],
	'plugin.itunes' => ['itunes', 'xml_file'],
	'plugin.musicmagic' => ['musicmagic', 'port']
);

sub new {
	my $class = shift;

	# try to connect to squeezenetwork.com to test for the need of proxy settings
	# just don't start the wizard before the request has been answered/failed
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $http = shift;
			# TODO: check for a proxy server's answer
			$showProxy = 0;
		},
		sub {
			my $http = shift;
			$log->error("Couldn't connect to squeezenetwork.com - do we need a proxy?\n" . $http->error);
		}
	);
	
	# Any async HTTP in init must be on a timer
	Slim::Utils::Timers::setTimer(
		undef,
		time(),
		sub {
			$http->get('http://www.squeezenetwork.com/api/v1/time');
		},
	);

	return $class->SUPER::new($class);
}

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
		# only on non-Windows systems, as the Windows installer is setting the langugae
		if (Slim::Utils::OSDetect::OS() ne 'win'  && !$paramRef->{saveLanguage}
			&& defined $response->{_request}->{_headers}->{'accept-language'}) {

			$log->debug("Accepted-Languages: " . $response->{_request}->{_headers}->{'accept-language'});

			foreach my $language (extract_language_tags($response->{_request}->{_headers}->{'accept-language'})) {
				$language = uc($language);
				$language =~ s/-/_/;  # we're using zh_cn, the header says zh-cn
	
				$log->debug("trying language: " . $language);
				if (defined $paramRef->{languageoptions}->{$language}) {
					$serverPrefs->set('language', $language);
					$log->info("selected language: " . $language);
					last;
				}
			}

		}
	}
	
	# handle language separately, as it is in its own form
	if ($paramRef->{saveLanguage}) {
		$serverPrefs->set('language', $paramRef->{language});		
	}
	$paramRef->{prefs}->{language} = Slim::Utils::Strings::getLanguage();

	foreach my $namespace (keys %prefs) {
		foreach my $pref (@{$prefs{$namespace}}) {
			if ($paramRef->{saveSettings}) {
				
				# reset audiodir if it had been disabled
				if ($pref eq 'audiodir' && !$paramRef->{useAudiodir})	{
					$paramRef->{audiodir} = '';
				}

				if ($pref eq 'itunes' && !$paramRef->{itunes})	{
					$paramRef->{itunes} = '0';
				}

				if ($pref eq 'musicmagic' && !$paramRef->{musicmagic})	{
					$paramRef->{musicmagic} = '0';
				}

				preferences($namespace)->set($pref, $paramRef->{$pref});
			}

			if ($log->is_debug) {
	 			$log->debug("$namespace.$pref: " . preferences($namespace)->get($pref));
			}
			$paramRef->{prefs}->{$pref} = preferences($namespace)->get($pref);

			# Cleanup the checkbox
			if ($pref =~ /itunes|musicmagic/) {
				$paramRef->{prefs}->{$pref} = defined $paramRef->{prefs}->{$pref} ? $paramRef->{prefs}->{$pref} : 0;
			}
		}
	}

	# if the wizard has been run for the first time, redirect to the main we page
	if ($paramRef->{firstTimeRunCompleted}) {
		$response->code(RC_MOVED_TEMPORARILY);
		$response->header('Location' => '/');
	}
	else {
		$paramRef->{showProxy} = $showProxy;
		$paramRef->{showiTunes} = !Slim::Plugin::iTunes::Common->canUseiTunesLibrary();
		$paramRef->{showMusicIP} = !Slim::Plugin::MusicMagic::Plugin::canUseMusicMagic();
		$paramRef->{serverOS} = Slim::Utils::OSDetect::OS();

		# presets for first execution:
		# - use iTunes if available
		# - use local path if no iTunes available
		if (!$serverPrefs->get('wizardDone')) {
			$paramRef->{prefs}->{iTunes} = $paramRef->{prefs}->{iTunes} || Slim::Plugin::iTunes::Common->canUseiTunesLibrary();
			$paramRef->{useAudiodir} = $paramRef->{prefs}->{audiodir} || !$paramRef->{prefs}->{iTunes};
		}
		else {
			$paramRef->{useAudiodir} = $paramRef->{prefs}->{audiodir};			
		}
	}

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
}

1;

__END__
