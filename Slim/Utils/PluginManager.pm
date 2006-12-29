package Slim::Utils::PluginManager;

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# $Id$

# TODO:
#
# * Check plugin cache timestamp vs XML files, and load newer.
# * Enable plugins that OP_NEEDS_ENABLE
# * Disable plugins that OP_NEEDS_DISABLE 
# 
# * Uninstall Plugins that have been marked as OP_NEEDS_UNINSTALL
#
# * Handle install of new plugins from web ui
#   - Unzip zip files to a cache dir, and read install.xml to verify
#   - Perform install of plugins marked OP_NEEDS_INSTALL
#
# * Check plugin versions from cache on new version of slimserver 
#   - Mark as OP_NEEDS_UPGRADE
# 
# * Slim::Utils::PluginManager->addDefaultMaps(); does not exist.
#   Needs to be rethought. Shouldn't be here.
#
# * Install by id (UUID)?
# * Copy HTML/* into a common folder, so INCLUDE_PATH is shorter?
#   There's already a namespace for each plugin.

use strict;

use File::Basename qw(dirname);
use File::Spec::Functions qw(:ALL);
use File::Next;
use FindBin qw($Bin);
use Path::Class;
use PAR;
use XML::Simple;
use YAML::Syck;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Versions;

# XXXX - These constants will probably change. This is just a rough start.
use constant STATE_ENABLED  => 1;
use constant STATE_DISABLED => 0;

use constant OP_NONE            => "";
use constant OP_NEEDS_INSTALL   => "needs-install";
use constant OP_NEEDS_UPGRADE   => "needs-upgrade";
use constant OP_NEEDS_UNINSTALL => "needs-uninstall";
use constant OP_NEEDS_ENABLE    => "needs-enable";
use constant OP_NEEDS_DISABLE   => "needs-disable";

use constant INSTALLERROR_SUCCESS               =>  0;
use constant INSTALLERROR_INVALID_VERSION       => -1;
use constant INSTALLERROR_INVALID_GUID          => -2;
use constant INSTALLERROR_INCOMPATIBLE_VERSION  => -3;
use constant INSTALLERROR_PHONED_HOME           => -4;
use constant INSTALLERROR_INCOMPATIBLE_PLATFORM => -5;
use constant INSTALLERROR_BLOCKLISTED           => -6;

my @pluginDirs     = Slim::Utils::OSDetect::dirsFor('Plugins');
my @pluginRootDirs = ();
my $plugins        = {};

my $log = logger('server.plugins');

sub init {
	my $class = shift;

	# Check to see if we're starting from scratch, 
	# or if we've been run before.
	if (!-r $class->pluginCacheFile) {

		$log->info("No plugin cache file exists - finding shipped plugins.");

		$class->findInstalledPlugins;

	} else {

		# XXXX - need to check for newer versions of the install.xml files.
		if (!$class->loadPluginCache) {

			$class->checkPluginVersions;
		}

		# process any pending operations
		$class->runPendingOperations;
	}

	$class->enablePlugins;

	$class->writePluginCache;
}

sub pluginCacheFile {
	my $class = shift;

	return catdir( Slim::Utils::Prefs::get('cachedir'), 'plugin-data.yaml' );
}

sub writePluginCache {
	my $class = shift;

	$log->info("Writing out plugin data file.");

	# Append the version number of the currently running server, so we
	# can check for updates.
	$plugins->{'__version'} = $::VERSION;

	YAML::Syck::DumpFile($class->pluginCacheFile, $plugins);

	delete $plugins->{'__version'};

	return 1;
}

sub loadPluginCache {
	my $class = shift;

	$log->info("Loading plugin data file.");

	$plugins = YAML::Syck::LoadFile($class->pluginCacheFile);

	my $checkVersion = delete $plugins->{'__version'};

	if (!$checkVersion || $checkVersion ne $::VERSION) {

		return 0;
	}

	return 1;
}

sub findInstalledPlugins {
	my $class = shift;

	# Only find plugins that have been installed.
	my $iter = File::Next::files({

		'file_filter' => sub {
			return 1 if /^install\.xml$/;
			return 0;
		},

	}, @pluginDirs);

	while ( my $file = $iter->() ) {

		my ($pluginName, $installManifest) = $class->_parseInstallManifest($file);

		if (!defined $pluginName) {

			next;
		}

		if ($installManifest->{'error'} == INSTALLERROR_SUCCESS) {

		}

		$plugins->{$pluginName} = $installManifest;
	}
}

sub _parseInstallManifest {
	my $class = shift;
	my $file  = shift;

	my $installManifest = eval { XMLin($file) };

	if ($@) {

		logWarning("Unable to parse XML in file [$file]: [$@]");

		return undef;
	}

	my $pluginName = $installManifest->{'module'} || return undef;

	if (!$class->checkPluginVersion($installManifest)) {

		$installManifest->{'error'} = INSTALLERROR_INVALID_VERSION;

		return ($pluginName, $installManifest);
	}

	# Check the OS matches
	my $osDetails    = Slim::Utils::OSDetect::details();
	my $osType       = $osDetails->{'os'};
	my $osArch       = $osDetails->{'osArch'};

	my $requireOS    = 0;
	my $matchingOS   = 0;
	my $requireArch  = 0;
	my $matchingArch = 0;
	my @platforms    = $installManifest->{'targetPlatform'} || ();

	if (ref($installManifest->{'targetPlatform'}) eq 'ARRAY') {

		@platforms = @$installManifest->{'targetPlatform'};
	}

	for my $platform (@platforms) {

		$requireOS = 1;

		my ($targetOS, $targetArch) = split /-/, $platform;

		if ($osType =~ /$targetOS/i) {

			$matchingOS = 1;

			if ($targetArch) {

				$requireArch = 1;

				if ($osArch =~ /$targetArch/i) {

					$matchingArch = 1;
					last;
				}
			}
		}
	}

	if ($requireOS && (!$matchingOS || ($requireArch && !$matchingArch))) {

		$installManifest->{'error'} = INSTALLERROR_INCOMPATIBLE_PLATFORM;

		return ($pluginName, $installManifest);
	}

	$installManifest->{'error'}   = INSTALLERROR_SUCCESS;
	$installManifest->{'basedir'} = dirname($file);

	if ($installManifest->{'defaultState'}) {

		my $state = delete $installManifest->{'defaultState'};

		if ($state eq 'disabled') {

			$installManifest->{'state'} = STATE_DISABLED;

		} else {

			$installManifest->{'state'} = STATE_ENABLED;
		}
	}

	return ($pluginName, $installManifest);
}

sub checkPluginVersions {
	my $class = shift;

	while (my ($name, $manifest) = each %{$plugins}) {

		if (!$class->checkPluginVersion($manifest)) {

			$plugins->{$name}->{'error'} = INSTALLERROR_INVALID_VERSION;
		}
	}
}

sub checkPluginVersion {
	my ($class, $manifest) = @_;

	if (!$manifest->{'targetApplication'} || ref($manifest->{'targetApplication'}) ne 'HASH') {

		return 0;
	}

	my $min = $manifest->{'targetApplication'}->{'minVersion'};
	my $max = $manifest->{'targetApplication'}->{'maxVersion'};

	# Didn't match the version? Next..
	if (!Slim::Utils::Versions->checkVersion($::VERSION, $min, $max)) {

		return 0;
	}

	return 1;
}

sub enablePlugins {
	my $class = shift;

	my @incDirs = ();

	for my $name (sort keys %$plugins) {

		my $manifest = $plugins->{$name};

		# Skip plugins that can't be loaded.
		if ($manifest->{'error'} != INSTALLERROR_SUCCESS) {

			$log->warn(sprintf("Couldn't load $name. Error: [%s]\n", $manifest->{'error'}));

			next;
		}

		if (defined $manifest->{'state'} && $manifest->{'state'} eq STATE_DISABLED) {

			$log->warn("Skipping plugin: $name - disabled");

			next;
		}

		$log->info("Enabling plugin: [$name]");

		my $baseDir    = $manifest->{'basedir'};
		my $module     = $manifest->{'module'};
		my $loadModule = 0;

		# Look for a lib dir that has a PAR file or otherwise.
		if (-d catdir($baseDir, 'lib')) {

			my $dir = dir( catdir($baseDir, 'lib') );

			for my $file ($dir->children) {

				if ($file =~ /\.par$/) {

					$loadModule = 1;

					PAR->import({ file => $file->stringify });

					last;
				}

				if ($file =~ /\.pm$/) {

					$loadModule = 1;

					unshift @INC, catdir($baseDir, 'lib');

					last;
				}
			}
		}

		if (-f catdir($baseDir, 'Plugin.pm')) {

			$loadModule = 1;

			unshift @INC, $baseDir;
		}

		# Pull in the module
		if ($loadModule && $module) {

			Slim::bootstrap::tryModuleLoad($module);

			# Initialize the plugin now that it's been loaded.
			if ($module->can('initPlugin')) {

				eval { $module->initPlugin };

				if ($@) {

					logWarning("Couldn't call $module->initPlugin: $@");

				} else {

					$manifest->{'state'} = STATE_ENABLED;
				}

			} else {

				logWarning("Couldn't load $module");
			}
		}

		# Add any available HTML to TT's INCLUDE_PATH
		my $htmlDir = catdir($baseDir, 'HTML');

		if (-d $htmlDir) {

			$log->debug("Adding HTML directory: [$htmlDir]");

			Slim::Web::HTTP::addTemplateDirectory($htmlDir);
		}
	}
}

sub dataForPlugin {
	my $class  = shift;
	my $plugin = shift;

	if ($plugins->{$plugin}) {

		return $plugins->{$plugin};
	}

	return undef;
}

sub allPlugins {
	my $class = shift;

	return $plugins;
}

sub installedPlugins {
	my $class = shift;

	return $class->_filterPlugins('error', INSTALLERROR_SUCCESS);
}

sub _filterPlugins {
	my ($class, $category, $opType) = @_;

	my @found = ();

	while (my ($name, $manifest) = each %{$plugins}) {

		if (defined $manifest->{$category} && $manifest->{$category} eq $opType) {

			push @found, $name;
		}
	}

	return @found;
}

sub runPendingOperations {
	my $class = shift;

	# These first two should be no-ops.
	for my $plugin ($class->getPendingOperations(OP_NEEDS_ENABLE)) {

		my $manifest = $plugins->{$plugin};
	}

	for my $plugin ($class->getPendingOperations(OP_NEEDS_DISABLE)) {

		my $manifest = $plugins->{$plugin};
	}

	# Uninstall first, then install
	for my $plugin ($class->getPendingOperations(OP_NEEDS_UPGRADE)) {

		#$class->uninstallPlugin($plugin);
		my $manifest = $plugins->{$plugin};
	}

	for my $plugin ($class->getPendingOperations(OP_NEEDS_INSTALL)) {

		my $manifest = $plugins->{$plugin};
	}

	for my $plugin ($class->getPendingOperations(OP_NEEDS_UNINSTALL)) {

		my $manifest = $plugins->{$plugin};

		if (-d $manifest->{'basedir'}) {

			$log->info("Uninstall: Removing $manifest->{'basedir'}");

			# rmtree($manifest->{'basedir'});
		}

		delete $plugins->{$plugin};
	}
}

sub getPendingOperations {
	my ($class, $opType) = @_;

	return $class->_filterPlugins('state', $opType);
}

sub enabledPlugins {
	my $class = shift;

	my @found = ();

	for my $plugin ($class->installedPlugins) {

		if ($plugins->{$plugin}->{'state'} eq OP_NONE) {

			push @found, $plugin;
		}
	}

	return @found;
}

sub isEnabled {
	my $class  = shift;
	my $plugin = shift;

	my %found  = map { $_ => 1 } $class->enabledPlugins;

	if (defined $found{$plugin}) {

		return $found{$plugin};
	}

	return undef;
}

sub enablePlugin {
	my $class  = shift;
	my $name   = shift;

	my $plugin = $plugins->{$name};
	my $opType = $plugin->{'opType'};

	if ($opType == OP_NEEDS_UNINSTALL) {
		return;
	}

	if ($opType != OP_NEEDS_ENABLE) {

		$plugin->{'opType'} = OP_NEEDS_ENABLE;
		$plugin->{'state'}  = STATE_ENABLED;
	}
}

sub disablePlugin {
	my $class  = shift;
	my $name   = shift;

	my $plugin = $plugins->{$name};
	my $opType = $plugin->{'opType'};

	if ($opType == OP_NEEDS_UNINSTALL) {
		return;
	}

	if ($opType != OP_NEEDS_DISABLE) {

		$plugin->{'opType'} = OP_NEEDS_DISABLE;
		$plugin->{'state'}  = STATE_DISABLED;
	}
}

sub _setPluginState {
	my $class  = shift;
	my $plugin = shift;
	my $state  = shift;


}

sub shutdownPlugins {
	my $class = shift;

	$log->info("Shutting down plugins...");

	my %enabledPlugins = $class->enabledPlugins;

	for my $plugin (sort keys %enabledPlugins) {

		$class->shutdownPlugin($plugin);
	}
}

sub shutdownPlugin {
	my $class  = shift;
	my $plugin = shift;

	if ($plugin->can('shutdownPlugin')) {

		$plugin->shutdownPlugin;
	}
}

# XXX - this should go away in favor of specifying strings.txt, convert.conf,
# etc in install.xml, and having callers ask for those files.
sub pluginRootDirs {
	my $class = shift;

	if (scalar @pluginRootDirs) {
		return @pluginRootDirs;
	}

	for my $path (@pluginDirs) {

		opendir(DIR, $path) || next;

		for my $plugin ( readdir(DIR) ) {

			if (-d catdir($path, $plugin) && $plugin !~ m/^\./i) {

				push @pluginRootDirs, catdir($path, $plugin);
			}
		}

		closedir(DIR);
	}

	return @pluginRootDirs;
}

1;

__END__
