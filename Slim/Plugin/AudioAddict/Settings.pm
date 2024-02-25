package Slim::Plugin::AudioAddict::Settings;

# Logitech Media Server Copyright 2001-2023 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(catdir);

use base qw(Slim::Web::Settings);

use Slim::Plugin::AudioAddict::Plugin;
use Slim::Plugin::AudioAddict::API;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.audioaddict');
my $log   = logger('plugin.audioaddict');

# add this plugin's HTML folder - the plugin manager would not do so, as this class must to be inherited, but not used directly
{
	Slim::Web::HTTP::addTemplateDirectory(
		catdir($Slim::Plugin::AudioAddict::Plugin::pluginDir, 'HTML')
	);
}

sub page { 'plugins/AudioAddict/settings.html' }

sub prefs { ($prefs, 'username')}

sub new {
	my $class = shift;

	my $network = $class->network;
	my $page = $class->page || return;

	$page =~ s/AudioAddict/$network/;

	Slim::Web::Pages->addPageFunction($page, $class);
	Slim::Web::Pages->addPageLinks('setup', { $class->name => $page }) if $class->name;
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	$params->{servicePageLink} = $class->servicePageLink();

	if ( $params->{pref_logout} ) {
		$prefs->remove('listen_key');
		$prefs->remove('subscriptions');
	}
	elsif ( $params->{saveSettings} ) {
		# set credentials if mail changed or a password is defined and it has changed
		if ( $params->{pref_username} && $params->{password} ) {
			Slim::Plugin::AudioAddict::API->authenticate({
				username => $params->{pref_username},
				password => $params->{password},
				network  => $class->network
			}, sub {
				my $body = $class->SUPER::handler($client, $params);
				$callback->( $client, $params, $body, @args );
			});

			return;
		}
	}

	return $class->SUPER::handler($client, $params);
}

sub beforeRender {
	my ($class, $params, $client) = @_;
	$params->{has_session} = $prefs->get('listen_key') && $prefs->get('subscriptions') && 1;
}

1;