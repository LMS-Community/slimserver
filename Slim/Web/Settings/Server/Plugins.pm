package Slim::Web::Settings::Server::Plugins;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Digest::MD5;

use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::PluginManager;
use Slim::Utils::PluginRepoManager;
use Slim::Utils::OSDetect;

use constant MAX_DOWNLOAD_WAIT => 120;

my $log = logger('server.plugins');
my $prefs = preferences('plugin.extensions');
my $rand = Digest::MD5->new->add( 'ExtensionDownloader', preferences('server')->get('securitySecret'), time() )->hexdigest;

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

		my $auto = $params->{'auto'} ? 1 : 0;
		$prefs->set('auto', $auto) if $auto != $prefs->get('auto');

		my $useUnsupported = $params->{'useUnsupported'} ? 1 : 0;
		$prefs->set('useUnsupported', $useUnsupported) if $useUnsupported != $prefs->get('useUnsupported');

		# handle changes to repos

		my @new = grep { $_ =~ /^https?:\/\/.*\.xml/ } (ref $params->{'repos'} eq 'ARRAY' ? @{$params->{'repos'}} : $params->{'repos'});

		my %current = map { $_ => 1 } @{ $prefs->get('repos') || [] };
		my %new     = map { $_ => 1 } @new;
		my $changed;

		for my $repo (keys %new) {
			if (!$current{$repo}) {
				Slim::Utils::PluginRepoManager->addRepo({ repo => $repo });
				$changed = 1;
			}
		}

		for my $repo (keys %current) {
			if (!$new{$repo}) {
				Slim::Utils::PluginRepoManager->removeRepo({ repo => $repo });
				$changed = 1;
			}
		}

		$prefs->set('repos', \@new) if $changed;

		# set policy for which plugins are installed/uninstalled etc

		my $plugin = $prefs->get('plugin');
		undef $changed;

		for my $param (keys %$params) {

			if ($param =~ /^manual:(.*)/) {
				$params->{$1} ? Slim::Utils::PluginManager->enablePlugin($1) : Slim::Utils::PluginManager->disablePlugin($1);
			}

			if ($param =~ /^install:(.*)/) {
				if ($params->{$1} && !$plugin->{$1}) {
					$plugin->{$1} = 1;
					$changed = 1;
				} elsif (!$params->{$1} && $plugin->{$1}) {
					delete $plugin->{$1};
					$changed = 1;
				}
			}
		}

		$prefs->set('plugin', $plugin) if $changed;
	}

	# get plugin info from defined repos
	my $repos = Slim::Utils::PluginRepoManager->repos;

	my $data = { remaining => scalar keys %$repos, results => {}, errors => {} };

	for my $repo (keys %$repos) {
		Slim::Utils::PluginRepoManager::getExtensions({
			'name'   => $repo,
			'type'   => 'plugin',
			'target' => Slim::Utils::OSDetect::OS(),
			'version'=> $::VERSION,
			'lang'   => $Slim::Utils::Strings::currentLang,
			'details'=> 1,
			'cb'     => \&_getReposCB,
			'pt'     => [ $class, $client, $params, $callback, \@args, $data, $repos->{$repo} ],
			'onError'=> sub { $data->{'errors'}->{ $_[0] } = $_[1] },
		});
	}

	if (!keys %$repos) {
		_getReposCB( $class, $client, $params, $callback, \@args, $data, undef, {}, {} );
	}
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

sub _getReposCB {
	my ($class, $client, $params, $callback, $args, $data, $weight, $res, $info) = @_;

	if (scalar @$res) {

		$data->{'results'}->{ $info->{'name'} } = {
			'title'   => $info->{'title'},
			'entries' => $res,
			'weight'  => $weight,
		};
	}

	if ( --$data->{'remaining'} <= 0 ) {

		my $pageInfo = $class->_addInfo($client, $params, $data);

		my $finalize;
		my $timeout = Time::HiRes::time() + MAX_DOWNLOAD_WAIT;

		$finalize = sub {
			Slim::Utils::Timers::killTimers(undef, $finalize);

			# if a plugin is still being downloaded, wait a bit longer, or the user might restart the server before we're done
			if ( Time::HiRes::time() <= $timeout && Slim::Utils::PluginDownloader->downloading ) {
				Slim::Utils::Timers::setTimer(undef, time() + 1, $finalize);

				main::DEBUGLOG && $log->is_debug && $log->debug("PluginDownloader is still busy - waiting a little longer...");
				return;
			}
			elsif ( Time::HiRes::time() > $timeout ) {
				$log->warn("Plugin download timed out");
			}

			$callback->($client, $params, $pageInfo, @$args);
		};

		$finalize->();
	}
}

sub _addInfo {
	my ($class, $client, $params, $data) = @_;

	my ($current, $active, $inactive, $hide) = Slim::Utils::PluginRepoManager::getCurrentPlugins();

	my @results = sort { $a->{'weight'} !=  $b->{'weight'} ?
						 $a->{'weight'} <=> $b->{'weight'} :
						 $a->{'title'} cmp $b->{'title'} } values %{$data->{'results'}};

	my @res;

	for my $res (@results) {
		push @res, @{$res->{'entries'}};
	}

	# find update actions and handle

	my $actions = Slim::Utils::PluginRepoManager::findUpdates(\@res, $current, $prefs->get('plugin'), 'info');
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
				if ($prefs->get('auto') ||
					($params->{'saveSettings'} && exists $params->{"update:$plugin"}) ) {

					main::INFOLOG && $log->info("installing $plugin from $entry->{url}");
					Slim::Utils::PluginDownloader->install({ name => $plugin, url => $entry->{'url'}, sha => lc($entry->{'sha'}) });

				}

				# otherwise just add to update list
				else {
					push @updates, $entry->{'info'};
				}

			}

			$hide->{$plugin} = 1;

		} elsif ($entry->{'action'} eq 'uninstall') {

			main::INFOLOG && $log->info("uninstalling $plugin");

			Slim::Utils::PluginDownloader->uninstall($plugin);
		}
	}

	# prune out duplicate entries, favour favour higher version numbers

	# pass 1 - find the higher version numbers
	my $max = {};

	for my $repo (@results) {
		for my $entry (@{$repo->{'entries'}}) {
			my $name = $entry->{'name'};
			if (!defined $max->{$name} || Slim::Utils::Versions->compareVersions($entry->{'version'}, $max->{$name}) > 0) {
				$max->{$name} = $entry->{'version'};
			}
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

	my @repos = ( @{$prefs->get('repos')}, '' );

	$params->{'updates'}  = \@updates;
	$params->{'active'}   = $active;
	$params->{'inactive'} = $inactive;
	$params->{'avail'}    = \@results;
	$params->{'repos'}    = \@repos;
	$params->{'auto'}     = $prefs->get('auto');
	$params->{'rand'}     = $rand;
	$params->{'useUnsupported'} = $prefs->get('useUnsupported');

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

1;

__END__
