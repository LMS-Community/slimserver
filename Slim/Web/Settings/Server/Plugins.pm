package Slim::Web::Settings::Server::Plugins;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use JSON::XS::VersionOneAndTwo;
use Digest::MD5;

use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::PluginManager;
use Slim::Utils::ExtensionsManager;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(cstring);

Slim::Utils::ExtensionsManager->init();

use constant MAX_DOWNLOAD_WAIT => 30;
use constant GH_IMAGE_URL => "https://raw.githubusercontent.com/LMS-Community/slimserver/public/" . ($::VERSION =~ s/\.\d$//r) . "/Slim/Plugin/%s/HTML/EN/%s";

my $log = logger('server.plugins');
my $rand = Digest::MD5->new->add( 'ExtensionDownloader', preferences('server')->get('securitySecret'), time() )->hexdigest;

sub new {
	my $class = shift;

	$class->SUPER::new();

	# add link for backwards compatibility
	Slim::Web::Pages->addPageFunction(Slim::Web::HTTP::CSRF->protectURI('plugins/Extensions/settings/basic.html'), $class);
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('SETUP_PLUGINS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/server/plugins.html');
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	# Simplistic anti CSRF protection in case the main server protection is off
	if (($params->{'saveSettings'} || $params->{'restart'}) && (!$params->{'rand'} || $params->{'rand'} ne $rand)) {

		$log->error("attempt to set params with band random number - ignoring");

		delete $params->{'saveSettings'};
		delete $params->{'restart'};
	}

	if ($params->{'saveSettings'}) {

		# handle changes to auto mode

		Slim::Utils::ExtensionsManager->autoUpdate($params->{'auto'} || 0);
		Slim::Utils::ExtensionsManager->useUnsupported($params->{'useUnsupported'} || 0);

		# handle changes to repos

		my @new = grep { $_ =~ /^https?:\/\/.*\.xml/ } (ref $params->{'repos'} eq 'ARRAY' ? @{$params->{'repos'}} : $params->{'repos'});

		my %current = map { $_ => 1 } @{ Slim::Utils::ExtensionsManager->repos() };
		my %new     = map { $_ => 1 } @new;

		for my $repo (@new) {
			if (!$current{$repo}) {
				Slim::Utils::ExtensionsManager->addRepo({ repo => $repo });
			}
		}

		for my $repo (keys %current) {
			if (!$new{$repo}) {
				Slim::Utils::ExtensionsManager->removeRepo({ repo => $repo });
			}
		}

		# set policy for which plugins are installed/uninstalled etc
		for my $param (keys %$params) {
			if ($param =~ /^manual:(.*)/) {
				$params->{$1} ? Slim::Utils::PluginManager->enablePlugin($1) : Slim::Utils::PluginManager->disablePlugin($1);
			}

			if ($param =~ /^install:(.*)/) {
				$params->{$1} ? Slim::Utils::ExtensionsManager->enablePlugin($1) : Slim::Utils::ExtensionsManager->disablePlugin($1);
			}
		}
	}

	my $data = { results => {}, errors => {} };

	Slim::Utils::ExtensionsManager::getAllPluginRepos({
		details => 1,
		type    => 'plugin',
		stepCb  => sub {
			my ($res, $info, $weight) = @_;

			if (scalar @{$res || []}) {
				$data->{results}->{$info->{name}} = {
					title   => $info->{title},
					entries => $res,
					weight  => $weight || 1,
				};
			}
		},
		cb => sub {
			$callback->($client, $params, $class->_addInfo($client, $params, $data), @args);
		},
		onError => sub { $data->{errors}->{$_[0]} = $_[1] },
	});
}

sub getRestartMessage {
	my ($class, $paramRef, $noRestartMsg) = @_;

	# show a link/button to restart SC if this is supported by this platform
	if (main::canRestartServer()) {

		$paramRef->{'restartUrl'} = $paramRef->{webroot} . $paramRef->{path} . '?restart=1';
		$paramRef->{'restartUrl'} .= '&rand=' . $paramRef->{'rand'} if $paramRef->{'rand'};

		$paramRef->{'warning'} = '<span id="restartWarning">'
			. Slim::Utils::Strings::string('PLUGINS_CHANGED_NEED_RESTART', $paramRef->{'restartUrl'})
			. '</span>';

	}

	else {

		$paramRef->{'warning'} .= '<span id="popupWarning">'
			. $noRestartMsg
			. '</span>';

	}

	return $paramRef;
}

sub restartServer {
	my ($class, $paramRef, $needsRestart) = @_;

	if ($needsRestart && $paramRef->{restart} && main::canRestartServer()) {

		$paramRef->{'warning'} = '<span id="popupWarning">'
			. Slim::Utils::Strings::string('RESTARTING_PLEASE_WAIT')
			. '</span>';

		# delay the restart a few seconds to return the page to the client first
		Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 2, \&_restartServer);
	}

	return $paramRef;
}

sub _restartServer {

	if (Slim::Utils::PluginDownloader->downloading) {

		Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 2, \&_restartServer);

	} else {

		main::restartServer();
	}
}

sub _addInfo {
	my ($class, $client, $params, $data) = @_;

	my ($current, $active, $inactive, $hide) = Slim::Utils::ExtensionsManager::getCurrentPlugins();

	my @results = sort { $a->{'weight'} !=  $b->{'weight'} ?
						 $a->{'weight'} <=> $b->{'weight'} :
						 $a->{'title'} cmp $b->{'title'} } values %{$data->{'results'}};

	my @res;

	for my $res (@results) {
		push @res, @{$res->{'entries'}};
	}

	# find update actions and handle

	my $actions = Slim::Utils::ExtensionsManager::findUpdates(\@res, $current, 'plugin', 'info');
	my @updates;

	for my $plugin (keys %$actions) {

		my $entry = $actions->{$plugin};

		if ($entry->{'action'} eq 'install' && $entry->{'url'} && $entry->{'sha'}) {

			# we distinguish between plugins that are to be installed from new
			# and already installed plugins for which an update is available

			if (!defined $current->{$plugin}) {
				# plugin is not installed, so this is a new install

				# install now, but only if explicitly selected on the extensions settings page
				if ($params->{'saveSettings'} && exists $params->{"install:$plugin"}) {

					main::INFOLOG && $log->info("installing $plugin from $entry->{url}");
					Slim::Utils::PluginDownloader->install({ name => $plugin, url => $entry->{'url'}, sha => lc($entry->{'sha'}) });

				}
			}
			else {
				# plugin already installed, this is an update

				# install update now if in auto mode or if explicitly selected
				if (Slim::Utils::ExtensionsManager->autoUpdate ||
					($params->{'saveSettings'} && exists $params->{"update:$plugin"}) ) {

					main::INFOLOG && $log->info("installing $plugin from $entry->{url}");
					Slim::Utils::PluginDownloader->install({ name => $plugin, url => $entry->{'url'}, sha => lc($entry->{'sha'}) });

				}

				# otherwise just add to update list
				else {
					my $info = $entry->{'info'};

					if (!$info->{'icon'}) {
						my ($current) = grep { $_->{'name'} eq $plugin } @$active;
						$info->{'icon'} = $current->{'icon'} if $current;
					}

					push @updates, $info;
				}

			}

			$hide->{$plugin} = 1;

		} elsif ($entry->{'action'} eq 'uninstall') {

			main::INFOLOG && $log->info("uninstalling $plugin");

			Slim::Utils::PluginDownloader->uninstall($plugin);
		}
	}

	# prune out duplicate entries, favour higher version numbers

	# pass 1 - find the higher version numbers
	my $max = {};
	my %pluginDataLookup;

	for my $repo (@results) {
		for my $entry (@{$repo->{'entries'}}) {
			my $name = $entry->{'name'};
			if (!defined $max->{$name} || Slim::Utils::Versions->compareVersions($entry->{'version'}, $max->{$name}) > 0) {
				$max->{$name} = $entry->{'version'};
			}
			$pluginDataLookup{$name} = $entry;
		}
	}

	# pass 2 - prune out lower versions or entries which are hidden as they are shown in enabled plugins
	for my $repo (@results) {
		my $i = 0;
		while (my $entry = $repo->{'entries'}->[$i]) {
			if ($hide->{$entry->{'name'}} || $max->{$entry->{'name'}} ne $entry->{'version'}) {
				splice @{$repo->{'entries'}}, $i, 1;
				next;
			}
			$i++;
		}
	}

	my @repos = ( @{Slim::Utils::ExtensionsManager->repos()}, '' );

	my $searchData = {};
	my $categories = {};

	prepareDetails($active, $searchData, $categories, 1, \%pluginDataLookup);
	prepareDetails($inactive, $searchData, $categories, undef, \%pluginDataLookup);
	foreach (@results) {
		prepareDetails($_->{entries}, $searchData, $categories, undef, \%pluginDataLookup);
	}

	my @categories = (
		['', cstring($client, 'SETUP_EXTENSIONS_CATEGORY_ALL')],
		sort {
			$a->[0] cmp $b->[0]
		} map {
			[$_, cstring($client, 'SETUP_EXTENSIONS_CATEGORY_' . uc($_)) || ucfirst($_)]
		} grep {
			$_
		} keys %$categories
	);

	$params->{'searchData'} = to_json($searchData);
	$params->{'categories'} = \@categories;
	$params->{'updates'}  = \@updates;
	$params->{'active'}   = $active;
	$params->{'inactive'} = $inactive;
	$params->{'avail'}    = \@results;
	$params->{'repos'}    = \@repos;
	$params->{'auto'}     = Slim::Utils::ExtensionsManager->autoUpdate();
	$params->{'rand'}     = $rand;
	$params->{'useUnsupported'} = Slim::Utils::ExtensionsManager->useUnsupported();

	# don't offer the restart before the plugin download has succeeded.
	my $needsRestart = Slim::Utils::PluginManager->needsRestart || Slim::Utils::PluginDownloader->downloading;

	$params->{'warning'} = $needsRestart ? Slim::Utils::Strings::string("SETUP_EXTENSIONS_RESTART_MSG") : '';

	Slim::Utils::PluginManager->message($needsRestart);

	# show a link/button to restart SC if this is supported by this platform
	if ($needsRestart) {
		$params = $class->getRestartMessage($params, Slim::Utils::Strings::string("SETUP_EXTENSIONS_RESTART_MSG"));
	}

	$params = $class->restartServer($params, $needsRestart);

	for my $repo (keys %{$data->{'errors'}}) {
		$params->{'warning'} .= Slim::Utils::Strings::string("SETUP_EXTENSIONS_REPO_ERROR") . " $repo - $data->{errors}->{$repo}<p/>";
	}

	return $class->SUPER::handler($client, $params);
}

sub prepareDetails {
	my ($data, $searchData, $categories, $installed, $pluginDataLookup) = @_;

	foreach (@$data) {
		$categories->{$_->{category}}++;

		if (my $data = $pluginDataLookup->{$_->{name}}) {
			$_->{icon} ||= $data->{icon};
			$_->{icon} = $data->{icon} if $data->{icon} && $_->{icon} !~ /^http/;
			$_->{category} ||= $data->{category};
		}

		my $icon = $_->{icon};
		if (!$installed && $icon && $icon !~ /^http/ && $icon =~ m|(plugins/(.*?)/html/.*)|) {
			$_->{icon} = sprintf(GH_IMAGE_URL, $2, $1);
		}
		elsif (!$icon) {
			$_->{icon} = 'html/images/' . ($_->{category} || 'misc') . '.svg';
			$_->{fallbackIcon} = 1;
		}

		$_->{creator} = join(', ', @{$_->{creator}}) if ref $_->{creator};

		if (!$searchData->{$_->{name}}) {
			$searchData->{$_->{name}} = {
				category => $_->{category} || '',
				content  => $_->{name} . ' ' . $_->{creator} . ' ' . $_->{desc} . ' ' . $_->{email} . ' ' . $_->{title},
			};
		}
	}
}

1;

__END__
