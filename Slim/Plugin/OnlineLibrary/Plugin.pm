package Slim::Plugin::OnlineLibrary::Plugin;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

use Async::Util;
use Tie::RegexpHash;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring string);
use Slim::Utils::Timers;

use Slim::Plugin::OnlineLibrary::BrowseArtist;
use Slim::Plugin::OnlineLibrary::Libraries;

use constant DELAY_FIRST_POLL => 240;
use constant POLLING_INTERVAL => 60 * 60;

my $prefs = preferences('plugin.onlinelibrary');
my $serverPrefs = preferences('server');

my %onlineLibraryProviders;
my %onlineLibraryIconProvider;

my $log = Slim::Utils::Log->addLogCategory( {
	'category'     => 'plugin.onlinelibrary',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_ONLINE_LIBRARY_MODULE_NAME',
} );

sub initPlugin {
	my $class = shift;

	$prefs->init({
		enablePreferLocalLibraryOnly => 0,
		enableLocalTracksOnly => 0,
		enableServiceEmblem => 1,
		genreMappings => [],
	});

	$prefs->setChange( sub {
		$class->initLibraries($_[0], $_[1] || 0);
	}, 'enablePreferLocalLibraryOnly', 'enableLocalTracksOnly' );

	# only save genre mapping if it is changed
	$prefs->setValidate({
		validator => sub {
			my ($pref, $new, $params, $old, $client) = @_;

			return unless $new && ref $new;

			$old ||= [];
			return 1 if scalar @$new != scalar @$old;

			my $i = 0;
			return grep {
				my $oldItem = $old->[$i++];
				$_->{field} ne $oldItem->{field} || $_->{text} ne $oldItem->{text} || $_->{genre} ne $oldItem->{genre};
			} @$new;
		}
	}, 'genreMappings');

	# make sure the value is defined, otherwise it would be enabled again
	$prefs->setChange( sub {
		$prefs->set($_[0], 0) unless defined $_[1];
	}, 'enableServiceEmblem' );

	$prefs->setChange( sub {
		Slim::Control::Request::executeRequest(undef, ['rescan', 'onlinelibrary']);
	}, 'genreMappings');

	$prefs->setChange( \&Slim::Web::XMLBrowser::wipeCaches, 'enableServiceEmblem' );

	if ( main::WEBUI ) {
		require Slim::Plugin::OnlineLibrary::Settings;
		Slim::Plugin::OnlineLibrary::Settings->new;
	}

	Slim::Music::Import->addScanType('onlinelibrary', {
		cmd  => ['rescan', 'onlinelibrary'],
		name => 'PLUGIN_ONLINE_LIBRARY_SETUP_RESCAN',
	});

	# tell LMS that we need to run the external scanner
	Slim::Music::Import->addImporter('Plugins::OnlineLibrary::Importer', { use => 1 });

	Slim::Menu::SystemInfo->registerInfoProvider( onlinelibrary => (
		after => 'library',
		before => 'currentplayer',
		func  => \&systemInfoMenu,
	) );

	Slim::Plugin::OnlineLibrary::BrowseArtist->init();
	Slim::Plugin::OnlineLibrary::Libraries->initLibraries();
}

sub postinitPlugin {
	my ($class) = @_;

	# create (module => enable flag) tupels
	%onlineLibraryProviders = map {
		my $pluginData = Slim::Utils::PluginManager->dataForPlugin($_);
		$_ => ($pluginData && $pluginData->{onlineLibrary}) ? 'enable_' . $pluginData->{name} : '';
	} grep { $_->can('onlineLibraryNeedsUpdate') } Slim::Utils::PluginManager->enabledPlugins();

	if (scalar keys %onlineLibraryProviders) {
		# initialize prefs to enable importers by default
		$prefs->init({
			map {
				$_ => 1;
			} values %onlineLibraryProviders
		});

		$prefs->setChange(sub {
			Slim::Utils::Timers::killTimers(undef, \&_pollOnlineLibraries);
			Slim::Utils::Timers::setTimer(undef, time() + DELAY_FIRST_POLL, \&_pollOnlineLibraries);
		}, values %onlineLibraryProviders);

		Slim::Utils::Timers::setTimer(undef, time() + DELAY_FIRST_POLL, \&_pollOnlineLibraries);

		main::INFOLOG && $log->is_info && $log->info("Online Music Library Integration initialized: " . join(', ', keys %onlineLibraryProviders) . DELAY_FIRST_POLL);
	}
}

my $isPolling;
sub _pollOnlineLibraries {
	Slim::Utils::Timers::killTimers(undef, \&_pollOnlineLibraries);

	if ($isPolling || Slim::Music::Import->stillScanning()) {
		main::INFOLOG && $log->is_info && $log->info("Online library poll or scan is active - try again later");
		Slim::Utils::Timers::setTimer(undef, time() + POLLING_INTERVAL, \&_pollOnlineLibraries);
		return;
	}

	# no need for polling when there's no provider
	if (!scalar values %onlineLibraryProviders) {
		main::INFOLOG && $log->is_info && $log->info("No need to poll - no online libraries available");
		return;
	}

	my @enabledImporters = grep {
		/^Plugins::/ && $prefs->get($onlineLibraryProviders{$_}) == 1;
	} keys %onlineLibraryProviders;

	# no need for polling if all importers are disabled
	if (!scalar @enabledImporters) {
		main::INFOLOG && $log->is_info && $log->info("No need to poll - all online library polling is disabled");
		return;
	}

	main::INFOLOG && $log->is_info && $log->info("Starting poll for updated online library...");

	my @workers = map {
		my $poller = $_;
		my $pref   = $onlineLibraryProviders{$_};

		sub {
			my ($result, $acb) = @_;

			return $acb->($result) if $result;

			main::INFOLOG && $log->is_info && $log->info("Going to check $poller");

			eval {
				$poller->onlineLibraryNeedsUpdate(sub {
					my $pollerResult = shift;

					if ($pollerResult && $pollerResult == -1) {
						$log->warn("Disabling polling for $poller lack of account information");
						$prefs->set($pref, 0);
						$pollerResult = 0;
					}
					$acb->($pollerResult);
				});
			};

			$log->error($@) if $@;
		}
	} @enabledImporters;

	Async::Util::achain(
		input => undef,
		steps => \@workers,
		cb    => sub {
			my $needsUpdate = shift;

			main::INFOLOG && $log->is_info && $log->info("Online library " . ($needsUpdate ? 'needs update' : 'is up to date'));

			if ($needsUpdate) {
				Slim::Control::Request::executeRequest(undef, ['rescan', 'onlinelibrary']);
			}

			Slim::Utils::Timers::setTimer(undef, time() + POLLING_INTERVAL, \&_pollOnlineLibraries);
		}
	);
}

sub systemInfoMenu {
	my $client = shift;

	return if Slim::Music::Import->stillScanning;

	my $items = [];

	my @enabledImporters = grep {
		$prefs->get($onlineLibraryProviders{$_});
	} keys %onlineLibraryProviders;

	foreach my $serviceClass (@enabledImporters) {
		if ($serviceClass->can('getLibraryStats')) {
			my ($title, $totals) = $serviceClass->getLibraryStats();

			next unless ($title && $totals && ($totals->{tracks} || $totals->{albums} || $totals->{artists}));

			my $item = {
				name => cstring($client, $title),
				items => [],
				web  => {
					group  => 'onlinelibrary',
					unfold => 1,
				},
			};

			if ($totals->{tracks}) {
				push @{$item->{items}}, {
					type => 'text',
					name => cstring($client, 'INFORMATION_TRACKS') . cstring($client, 'COLON') . ' ' . Slim::Utils::Misc::delimitThousands($totals->{tracks}),
				};
			}

			if ($totals->{albums}) {
				push @{$item->{items}}, {
					type => 'text',
					name => cstring($client, 'INFORMATION_ALBUMS') . cstring($client, 'COLON') . ' ' . Slim::Utils::Misc::delimitThousands($totals->{albums}),
				};
			}

			if ($totals->{artists}) {
				push @{$item->{items}}, {
					type => 'text',
					name => cstring($client, 'INFORMATION_ARTISTS') . cstring($client, 'COLON') . ' ' . Slim::Utils::Misc::delimitThousands($totals->{artists}),
				};
			}

			if ($totals->{playlists}) {
				push @{$item->{items}}, {
					type => 'text',
					name => cstring($client, 'INFORMATION_PLAYLISTS') . cstring($client, 'COLON') . ' ' . Slim::Utils::Misc::delimitThousands($totals->{playlists}),
				};
			}

			if ($totals->{playlistTracks}) {
				push @{$item->{items}}, {
					type => 'text',
					name => cstring($client, 'PLUGIN_ONLINE_LIBRARY_INFORMATION_PLAYLISTTRACKS') . cstring($client, 'COLON') . ' ' . Slim::Utils::Misc::delimitThousands($totals->{playlistTracks}),
				};
			}

			push @$items, $item;

			main::idleStreams();
		}
	}

	return [ sort { $a->{name} cmp $b->{name}} @$items ];
}

sub getLibraryProviders {
	my ($class) = @_;
	return \%onlineLibraryProviders;
}

sub initLibraries {
	my ($class, $pref, $newValue) = @_;

	my $library = $pref;
	$library =~ s/^enable//;

	if ( defined $newValue && !$newValue ) {
		Slim::Music::VirtualLibraries->unregisterLibrary(lcfirst($library));
	}

	if ( $prefs->get($pref) ) {
		Slim::Plugin::OnlineLibrary::Libraries->initLibraries();

		# if we were called on a onChange event, re-build the library
		Slim::Music::VirtualLibraries->rebuild($library) if $newValue;
	}
}

sub addLibraryIconProvider {
	my ($class, $serviceTag, $iconUrl) = @_;

	return unless $serviceTag && $iconUrl;

	$onlineLibraryIconProvider{$serviceTag} = $iconUrl;
}

sub getServiceIconProviders {
	return \%onlineLibraryIconProvider;
}

sub getServiceIcon {
	my ($class, $id) = @_;

	return unless $id;
	return unless $prefs->get('enableServiceEmblem');

	$id =~ s/^(\w+?):.*/$1/;

	return $onlineLibraryIconProvider{$id} || '';
}

1;