package Slim::Plugin::YM::Plugin;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::OPMLBased);
use File::Spec::Functions qw(catfile);

use Slim::Plugin::YM::API;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

our $pluginDir;
BEGIN {
	$pluginDir = $INC{"Slim/Plugin/YM/Plugin.pm"};
	$pluginDir =~ s/Plugin.pm$//;
}

my $log = Slim::Utils::Log->addLogCategory({
	category     => 'plugin.ym',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_YM_DESC',
});

my $prefs = preferences('plugin.ym');

sub getDisplayName {
	return 'PLUGIN_YM_NAME';
}

sub initPlugin {
	my ($class) = @_;

	Slim::Utils::Strings::loadFile(catfile($pluginDir, 'strings.txt'));

	$prefs->init({
		token        => '',
		account_name => '',
	});

	if (main::WEBUI) {
		require Slim::Plugin::YM::Settings;
		Slim::Plugin::YM::Settings->new();
	}

	$class->SUPER::initPlugin(
		feed => sub {
			my ($client, $cb, $args) = @_;
			$class->accountMenu($client, $cb, $args);
		},
		tag  => 'ym',
		menu => 'apps',
	);
}

sub accountMenu {
	my ($class, $client, $cb, $args) = @_;

	my $token = $prefs->get('token');

	if (!$token) {
		return $cb->([{
			type  => 'text',
			name  => cstring($client, 'PLUGIN_YM_NOT_CONNECTED'),
			line1 => cstring($client, 'PLUGIN_YM_NOT_CONNECTED'),
			line2 => cstring($client, 'PLUGIN_YM_CONNECT_IN_SETTINGS'),
		}]);
	}

	Slim::Plugin::YM::API->accountStatus($token, sub {
		my $status = shift;

		if (!$status) {
			return $cb->([{
				type  => 'text',
				name  => cstring($client, 'PLUGIN_YM_INVALID_TOKEN'),
				line1 => cstring($client, 'PLUGIN_YM_INVALID_TOKEN'),
				line2 => cstring($client, 'PLUGIN_YM_CONNECT_IN_SETTINGS'),
			}]);
		}

		my $account_name = $status->{account_name} || $prefs->get('account_name');
		my $line2 = $account_name
			? cstring($client, 'PLUGIN_YM_CONNECTED_AS', $account_name)
			: cstring($client, 'PLUGIN_YM_CONNECTED');

		my $items = [{
			type  => 'text',
			name  => cstring($client, 'PLUGIN_YM_CONNECTED'),
			line1 => cstring($client, 'PLUGIN_YM_CONNECTED'),
			line2 => $line2,
		}];

		$cb->($items);
	});
}

1;
