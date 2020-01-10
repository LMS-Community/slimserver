package Slim::Plugin::OnlineLibrary::Plugin;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use base qw(Slim::Plugin::Base);

use Async::Util;

use strict;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring string);
use Slim::Utils::Timers;

use constant DELAY_FIRST_POLL => 4;
use constant POLLING_INTERVAL => 1 * 60;

my $prefs = preferences('plugin.onlinelibrary');

my @onlineLibraryProviders;

my $log = Slim::Utils::Log->addLogCategory( {
	'category'     => 'plugin.onlinelibrary',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_ONLINE_LIBRARY_MODULE_NAME',
} );

sub initPlugin {
	my $class = shift;

	# $prefs->init({
	# });
	
	if ( main::WEBUI ) {
		require Slim::Plugin::OnlineLibrary::Settings;
		Slim::Plugin::OnlineLibrary::Settings->new;
	}

	# $class->SUPER::initPlugin(@_);
}

sub postinitPlugin {
	my ($class) = @_;

	@onlineLibraryProviders = grep { $_->can('onlineLibraryNeedsUpdate') } Slim::Utils::PluginManager->enabledPlugins();
	if (scalar @onlineLibraryProviders) {
		Slim::Utils::Timers::setTimer(undef, time() + DELAY_FIRST_POLL, \&_pollOnlineLibraries);
	}
}

sub _pollOnlineLibraries {
	Slim::Utils::Timers::killTimers(undef, \&_pollOnlineLibraries);

	return unless scalar @onlineLibraryProviders;

	my @workers = map {
		my $poller = $_;
		sub {
			my ($result, $acb) = @_;

			return $acb->($result) if $result;

			eval {
				$poller->onlineLibraryNeedsUpdate($acb);
			};

			$log->error($@) if $@;
		}
	} @onlineLibraryProviders;

	Async::Util::achain(
		input => undef,
		steps => \@workers,
		cb    => sub {
			my $needsUpdate = shift;

			main::INFOLOG && $log->is_info && $log->info($needsUpdate ? 'needs update' : 'all up to date');

			Slim::Utils::Timers::setTimer(undef, time() + POLLING_INTERVAL, \&_pollOnlineLibraries);
		}
	);
}