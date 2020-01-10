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

use constant DELAY_FIRST_POLL => 24;
use constant POLLING_INTERVAL => 5 * 60;

my $prefs = preferences('plugin.onlinelibrary');

my @onlineLibraryProviders;

my $log = Slim::Utils::Log->addLogCategory( {
	'category'     => 'plugin.onlinelibrary',
	'defaultLevel' => 'INFO',
	'description'  => 'PLUGIN_ONLINE_LIBRARY_MODULE_NAME',
} );

sub initPlugin {
	my $class = shift;

	$prefs->init({
		pollForUpdates => 1
	});
	
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
		$prefs->setChange(sub {
			Slim::Utils::Timers::killTimers(undef, \&_pollOnlineLibraries);
			Slim::Utils::Timers::setTimer(undef, time() + DELAY_FIRST_POLL, \&_pollOnlineLibraries);
		}, 'pollForUpdates');

		Slim::Utils::Timers::setTimer(undef, time() + DELAY_FIRST_POLL, \&_pollOnlineLibraries);
	}
}

my $isPolling;
sub _pollOnlineLibraries {
	# no need for polling when there's no provider
	return unless scalar @onlineLibraryProviders && $prefs->get('pollForUpdates');

	Slim::Utils::Timers::killTimers(undef, \&_pollOnlineLibraries);

	if ($isPolling || Slim::Music::Import->stillScanning()) {
		main::INFOLOG && $log->is_info && $log->info("Online library poll or scan is active - try again later");
		Slim::Utils::Timers::setTimer(undef, time() + POLLING_INTERVAL, \&_pollOnlineLibraries);
		return;
	}

	main::INFOLOG && $log->is_info && $log->info("Starting poll for updated online library...");

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

			main::INFOLOG && $log->is_info && $log->info("Online library " . ($needsUpdate ? 'needs update' : 'is up to date'));

			if ($needsUpdate) {
				Slim::Control::Request::executeRequest(undef, ['rescan']);
			}

			Slim::Utils::Timers::setTimer(undef, time() + POLLING_INTERVAL, \&_pollOnlineLibraries);
		}
	);
}

1;