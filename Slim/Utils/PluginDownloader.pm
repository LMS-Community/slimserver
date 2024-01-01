package Slim::Utils::PluginDownloader;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Plugins are downloaded to <cachedir>/DownloadedPlugins and then extracted to <cachedir>/InstalledPlugins/Plugins/
#
# Plugins zip files should not include any additional path information - i.e. they include the install.xml file at the top level
# The plugin 'name' must match the package naming of the plugin, i.e. name 'MyPlugin' equates to package 'Plugins::MyPlugin::Plugin'


use strict;

use File::Spec::Functions qw(:ALL);
use File::Path;
use Digest::SHA1;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Prefs;
use Slim::Utils::Log;

use constant CHECK_INTERVAL => 24*60*60; # check for new plugins once a day

my $log   = logger('server.plugins');
my $prefs = preferences('plugin.state');
my $serverprefs = preferences('server');

my $downloadTo;
my $extractTo;
my $downloading = 0;

sub init {
	my $class = shift;

	if (my $cache = $serverprefs->get('cachedir')) {

		$downloadTo = catdir($cache, 'DownloadedPlugins');
		$extractTo  = catdir($cache, 'InstalledPlugins');

		mkdir $downloadTo unless -d $downloadTo;
		mkdir $extractTo  unless -d $extractTo;

		if (-w $downloadTo && -w $extractTo) {

			main::DEBUGLOG && $log->debug("downloading to $downloadTo");
			main::DEBUGLOG && $log->debug("extracting to $extractTo");

		} else {

			$log->warn("unable to create download locations $downloadTo $extractTo");
			$downloadTo = $extractTo = undef;
		}

	} else {

		$log->error("unable to store downloads in cachedir");
	}
}

sub uninstall {
	my $class = shift;
	my $plugin = shift;

	return unless Slim::Utils::PluginManager->allPlugins->{$plugin};

	main::INFOLOG && $log->info("scheduling uninstall of $plugin on restart");

	$prefs->set($plugin, 'needs-uninstall');
}

sub extract {
	my $class = shift;
	my $plugin = shift;

	if (!$downloadTo || !$extractTo) {

		$log->error("cannot extract - download or extraction directory does not exist");
		return
	}

	my $zipFile   = catdir($downloadTo, "$plugin.zip");
	my $targetDir = catdir($extractTo, 'Plugins', $plugin);

	if (!-r $zipFile) {

		$log->error("unable to install $plugin - $zipFile does not exist");

	} else {

		if (-d $targetDir) {

			main::INFOLOG && $log->info("removing existing $targetDir");

			rmtree $targetDir;
		}

		# FIXME: use system('unzip') on some architectures to avoid loading Archive::Zip?
		my $zip;

		eval {
			require Archive::Zip;
			$zip = Archive::Zip->new();
		};

		if (!defined $zip) {

			$log->error("error loading Archive::Zip $@");

		} elsif (my $zipstatus = $zip->read($zipFile)) {

			$log->warn("error reading zip file $zipFile status: $zipstatus");

		} else {

			# Strip world-writable file permissions:
			foreach my $member ( $zip->members() ) {
				my $attrs = $member->unixFileAttributes() & 0777;
				$member->unixFileAttributes($attrs & ~0022) if $attrs & 0022
			}

			my $source;

			# ignore additional directory information in zip
			for my $search ("Plugins/$plugin/", "$plugin/") {

				if ( $zip->membersMatching("^$search") ) {

					$source = $search;
					last;
				}
			}

			if ( ($zipstatus = $zip->extractTree($source, "$targetDir/")) == Archive::Zip::AZ_OK() ) {

				main::INFOLOG && $log->info("extracted $plugin to $targetDir");

			} else {

				$log->warn("failed to extract $plugin to $targetDir - $zipstatus");

				rmtree $targetDir;
			}
		}

		unlink $zipFile;
	}
}

sub install {
	my $class = shift;
	my $args  = shift;

	if (!$downloadTo) {

		$log->error("cannot download - download directory does not exist");
		return;
	}

	my $name = $args->{'name'};
	my $url  = $args->{'url'} || '';

	my $file = catdir($downloadTo, "$name.zip");

	if (-r $file) {
		my $digest = _getDigest($file);

		if ($args->{sha} ne $digest) {
			main::INFOLOG && $log->is_info && $log->info(sprintf("found existing download, but digest does not match %s - %s will be re-downloaded: expected %s, got %s", $file, $name, $args->{sha}, $digest));
			unlink $file;
		}
	}

	if (-r $file) {
		main::DEBUGLOG && $log->is_debug && $log->debug("found existing download, digest matches - don't re-download: $name");
		_installDownload($file, $args);
	}
	else {
		my $http = Slim::Networking::SimpleAsyncHTTP->new( \&_downloadDone, \&_downloadError, { saveAs => $file, args => $args } );

		main::INFOLOG && $log->info("install - downloading $name from $url");

		$downloading++;

		$http->get($url);
	}
}

sub _downloadDone {
	my $http  = shift;

	my $file  = $http->params('saveAs');
	my $args  = $http->params('args');

	my $name  = $args->{'name'};

	main::INFOLOG && $log->info("downloaded $name to $file");

	$downloading--;

	_installDownload($file, $args);
}

sub _installDownload {
	my ($file, $args) = @_;

	my $name  = $args->{'name'};
	my $digest= $args->{'sha'};

	if (-r $file) {

		my $gotDigest = _getDigest($file);

		if ($digest ne $gotDigest) {

			$log->error("digest does not match $file - $name will not be installed: expected $digest, got " . $gotDigest);

			if (main::DEBUGLOG && $log->is_debug && (my $cacheDir = $serverprefs->get('cachedir'))) {
				require File::Basename;
				require File::Copy;

				my ($filename, undef, $ext) = File::Basename::fileparse($file, '.zip');
				my $backup = catfile($cacheDir, $filename . '-' . $gotDigest . $ext);
				$log->debug("Moving downloaded file for you to investigate:\n  from: $file\n  to:   $backup");
				File::Copy::move($file, $backup);
			}
			else {
				unlink $file;
			}

		} else {

			main::INFOLOG && $log->info("digest matches - scheduling $name for install on restart");

			$prefs->set($name, 'needs-install');
		}
	}
}

sub _getDigest {
	my ($file) = @_;

	my $sha1 = Digest::SHA1->new;

	open my $fh, '<', $file or $log->error("Failed to open $file");

	binmode $fh;

	$sha1->addfile($fh);

	close $fh;

	return $sha1->hexdigest;
}

sub _downloadError {
	my $http  = shift;
	my $error = shift;

	my $args  = $http->params('args');
	my $name  = $args->{'name'};
	my $url   = $http->url;

	$downloading--;

	$log->error("unable to download $name from $url - $error");
}

sub downloading {
	return $downloading;
}

sub periodicCheckForUpdates {
	my $class = shift;

	$class->checkForUpdates;

	Slim::Utils::Timers::killTimers($class, \&periodicCheckForUpdates);
	Slim::Utils::Timers::setTimer($class, time() + ($serverprefs->get('checkVersionInterval') || CHECK_INTERVAL), \&periodicCheckForUpdates);
}

sub checkForUpdates {
	my $class = shift;

	# send the information provider a list of installed plugins, versions and states + server version and platform
	# information provider will respond with set of actions of which plugins to update (if any)

	my $plugins = Slim::Utils::PluginManager->allPlugins;
	my $current = {};

	main::INFOLOG && $log->info("generating apps query to find latest plugin state");

	my $request = Slim::Control::Request->new(undef, ['appsquery']);

	$request->addParam(args => {
		type => 'plugin',
		current => $current,
	});

	for my $plugin (keys %$plugins) {
		if ($plugins->{$plugin}->{'basedir'} =~ /InstalledPlugins/ && $prefs->get($plugin) !~ /needs/) {
			$current->{$plugin} = $plugins->{$plugin}->{'version'} || 'noversion';
		}
	}

	$request->callbackParameters(\&_handleResponse, [ $class, $request ]);
	$request->execute();
}

sub _handleResponse {
	my $class = shift;
	my $request = shift;

	# appsquery returns a list of actions for plugins which should be updated:
	#  - install   - install plugin with given details
	#  - uninstall - remove plugin from filesystem

	my $updates = $request->getResult('updates');
	my $actions = $request->getResult('actions');

	if ( $updates ) {
		my $plugins = Slim::Utils::PluginManager->allPlugins;

		# localize plugin names
		$updates = join(', ',
			map {
				Slim::Utils::Strings::string($plugins->{$_}->{name});
			} split(/,/, $updates)
		);

		Slim::Utils::PluginManager->message(
			sprintf( "%s (%s)", Slim::Utils::Strings::string('PLUGINS_UPDATES_AVAILABLE'), $updates )
		);

		# $updates is only set if we don't want to auto-update
		return;
	}

	for my $plugin (keys %{ $actions || {} }) {

		if ($prefs->get($plugin) && $prefs->get($plugin) =~ /needs/) {

			main::INFOLOG && $log->info("ignoring response - $plugin already pending action: " . $prefs->get($plugin));
			next;
		}

		my $entry = $actions->{$plugin};

		if ($entry->{'action'} eq 'install' && $entry->{'url'} && $entry->{'sha'}) {

			$class->install({ name => $plugin, url => $entry->{'url'}, sha => $entry->{'sha'} });

		} elsif ($entry->{'action'} eq 'uninstall') {

			$class->uninstall($plugin);
		}
	}
}

1;
