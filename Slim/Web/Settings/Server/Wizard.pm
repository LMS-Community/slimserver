package Slim::Web::Settings::Server::Wizard;

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $showProxy = 1;
my $prefs = preferences('server');

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'wizard',
	'defaultLevel' => 'DEBUG',
});

my %prefs = (
	'server' => ['weproxy', 'sn_email', 'sn_password', 'audiodir', 'playlistdir'],
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
	$http->get('http://www.squeezenetwork.com/');

	$class->SUPER::new($class);
}

sub page {
	return 'settings/server/wizard.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# handle language separately, as it is in its own form
	if ($paramRef->{'saveLanguage'}) {
		preferences('server')->set('language', $paramRef->{'language'});		
	}
	$paramRef->{'prefs'}->{'language'} = preferences('server')->get('language');

	foreach my $namespace (keys %prefs) {
		foreach my $pref (@{$prefs{$namespace}}) {
			if ($paramRef->{'saveSettings'}) {
				
				# reset audiodir if it had been disabled
				if ($pref eq 'audiodir' && !$paramRef->{'useAudiodir'})	{
					$paramRef->{'audiodir'} = '';
				}

				if ($pref eq 'itunes' && !$paramRef->{'itunes'})	{
					$paramRef->{'itunes'} = '0';
				}

				if ($pref eq 'musicmagic' && !$paramRef->{'musicmagic'})	{
					$paramRef->{'musicmagic'} = '0';
				}

				$log->debug("$namespace.$pref: " . $paramRef->{$pref});

				preferences($namespace)->set($pref, $paramRef->{$pref});
			}

			$paramRef->{'prefs'}->{$pref} = preferences($namespace)->get($pref);

			# Cleanup the checkbox
			if ($pref =~ /itunes|musicmagic/) {
				$paramRef->{'prefs'}->{$pref} = defined $paramRef->{'prefs'}->{$pref} ? $paramRef->{'prefs'}->{$pref} : 0;
			}
		}
	}

	$paramRef->{'showProxy'} = $showProxy;
	$paramRef->{'showiTunes'} = !Slim::Plugin::iTunes::Common->canUseiTunesLibrary();
	$paramRef->{'showMusicIP'} = !Slim::Plugin::MusicMagic::Plugin::canUseMusicMagic();
	$paramRef->{'languageoptions'} = Slim::Utils::Strings::languageOptions();

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
}

1;

__END__
