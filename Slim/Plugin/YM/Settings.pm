package Slim::Plugin::YM::Settings;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(catdir);

use base qw(Slim::Web::Settings);

use Slim::Plugin::YM::API;
use Slim::Plugin::YM::Plugin;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('plugin.ym');
my $log   = logger('plugin.ym');

{
	Slim::Web::HTTP::addTemplateDirectory(
		catdir($Slim::Plugin::YM::Plugin::pluginDir, 'HTML')
	);
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_YM_NAME');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/YM/settings.html');
}

sub prefs {
	return ($prefs, 'token');
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ($params->{pref_logout}) {
		$prefs->remove('token');
		$prefs->remove('account_name');
	}
	elsif ($params->{saveSettings}) {
		if ($params->{pref_token}) {
			Slim::Plugin::YM::API->accountStatus($params->{pref_token}, sub {
				my $status = shift;

				if ($status && $status->{account_name}) {
					$prefs->set('account_name', $status->{account_name});
				}
				else {
					$params->{warning} = string('PLUGIN_YM_INVALID_TOKEN');
					$params->{pref_token} = '';
					$prefs->remove('account_name');
				}

				my $body = $class->SUPER::handler($client, $params);
				$callback->($client, $params, $body, @args);
			});

			return;
		}

		$prefs->remove('account_name');
	}

	return $class->SUPER::handler($client, $params);
}

sub beforeRender {
	my ($class, $params, $client) = @_;
	$params->{has_token} = $prefs->get('token') ? 1 : 0;
	$params->{account_name} = $prefs->get('account_name');
}

1;
