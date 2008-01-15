package Slim::Utils::PluginManager;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# $Id$

# TODO:
#
# * Enable plugins that OP_NEEDS_ENABLE
# * Disable plugins that OP_NEEDS_DISABLE 
# 
# * Uninstall Plugins that have been marked as OP_NEEDS_UNINSTALL
#
# * Handle install of new plugins from web ui
#   - Unzip zip files to a cache dir, and read install.xml to verify
#   - Perform install of plugins marked OP_NEEDS_INSTALL
#
# * Check plugin versions from cache on new version of SqueezeCenter 
#   - Mark as OP_NEEDS_UPGRADE
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
use constant INSTALLERROR_NO_PLUGIN             => -7;

my @pluginDirs     = Slim::Utils::OSDetect::dirsFor('Plugins');
my @pluginRootDirs = ();
my $plugins        = {};
my $rootDir        = '';

my $prefs = preferences('plugin.state');
my $log   = logger('server.plugins');

sub init {
	my $class = shift;
	
	# Bug 6196, Delay PAR loading to init phase so any temp directories
	# are created as the proper user
	require PAR;
	PAR->import;

	my ($manifestFiles, $newest) = $class->findInstallManifests;

	if (!scalar keys %{$prefs->all}) {

		$log->info("Reparsing plugin manifests - plugin states are not defined.");

		$class->readInstallManifests($manifestFiles);
		
	}

	# Load the plugin cache file
	if ( -r $class->pluginCacheFile ) {
		if (!$class->loadPluginCache) {

			$class->checkPluginVersions;
		}

		# process any pending operations
		$class->runPendingOperations;
	}

	# parse the manifests if cache file is older than newest install.xml file
	if ( (stat($class->pluginCacheFile))[9] < $newest ) {

		$log->info("Reparsing plugin manifests - new manifest found.");

		$class->readInstallManifests($manifestFiles);
	}

	elsif (scalar keys %$plugins != scalar @$manifestFiles) {

		$log->info("Reparsing plugin manifests - cache contains different number of plugins");

		$class->readInstallManifests($manifestFiles);
	}

	elsif ( $rootDir ne $Bin ) {

		$log->info("Reparsing plugin manifests - SC running from different folder than when cache was written");

		$class->readInstallManifests($manifestFiles);
	}

	$class->enablePlugins;

	$class->writePluginCache;
}

sub pluginCacheFile {
	my $class = shift;

	return catdir( preferences('server')->get('cachedir'), 'plugin-data.yaml' );
}

sub writePluginCache {
	my $class = shift;

	$log->info("Writing out plugin data file.");

	# Append the version number of the currently running server, so we
	# can check for updates.
	$plugins->{'__version'} = $::VERSION;

	# Append the SC installation folder, so we
	# can check for moved installations/differnent branch running
	$plugins->{'__installationFolder'} = $Bin;

	YAML::Syck::DumpFile($class->pluginCacheFile, $plugins);

	delete $plugins->{'__version'};
	$rootDir = delete $plugins->{'__installationFolder'};

	return 1;
}

sub loadPluginCache {
	my $class = shift;

	$log->info("Loading plugin data file.");

	$plugins = YAML::Syck::LoadFile($class->pluginCacheFile);

	$rootDir = delete $plugins->{'__installationFolder'};

	my $checkVersion = delete $plugins->{'__version'};

	if (!$checkVersion || $checkVersion ne $::VERSION) {

		return 0;
	}

	return 1;
}

sub findInstallManifests {
	my $class = shift;

	my $newest = 0;
	my @files;

	# Only find plugins that have been installed.
	my $iter = File::Next::files({

		'file_filter' => sub {
			return 1 if /^install\.xml$/;
			return 0;
		},

	}, @pluginDirs);

	while ( my $file = $iter->() ) {

		my $mtime = (stat($file))[9];
		$newest = $mtime if $mtime > $newest;

		push @files, $file;
	}

	return (\@files, $newest);
}

sub readInstallManifests {
	my $class = shift;
	my $files = shift;

	$plugins = {};

	for my $file (@{$files}) {

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

	my $pluginName = $installManifest->{'module'};

	$installManifest->{'basedir'} = dirname($file);

	if (!defined $pluginName && $installManifest->{'jive'}) {
		
		$installManifest->{'error'} = INSTALLERROR_NO_PLUGIN;

		return ($file, $installManifest);
	}

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


	if ($installManifest->{'icon-id'}) {

		Slim::Web::Pages->addPageLinks("icons", { $pluginName => $installManifest->{'icon-id'} });

	}

	$installManifest->{'error'}   = INSTALLERROR_SUCCESS;

	if ($installManifest->{'defaultState'} && !defined $prefs->get($pluginName)) {

		my $state = delete $installManifest->{'defaultState'};

		if ($state eq 'disabled') {

			$prefs->set($pluginName, STATE_DISABLED);

		} else {

			$prefs->set($pluginName, STATE_ENABLED);
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
	my @loaded  = ();

	for my $name (sort keys %$plugins) {

		my $manifest = $plugins->{$name};

		# Skip plugins with no perl module.
		next unless $manifest->{'module'};

		# Skip plugins that can't be loaded.
		if ($manifest->{'error'} != INSTALLERROR_SUCCESS) {

			if ( $log->is_warn ) {
				$log->warn(sprintf("Couldn't load $name. Error: [%s]\n", $manifest->{'error'}));
			}

			next;
		}

		delete $manifest->{opType};

		if (defined $prefs->get($name) && $prefs->get($name) eq STATE_DISABLED) {

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

				if ($file =~ /.*Plugins$/ && -d $file) {
					$loadModule = 1;
					unshift @INC, catdir($baseDir, 'lib');

					last;
				}
			}
		}

		if (-f catdir($baseDir, 'Plugin.pm')) {

			$loadModule = 1;
		}

		# Pull in the module
		if ($loadModule && $module) {

			if (Slim::bootstrap::tryModuleLoad($module)) {

				logWarning("Couldn't load $module");

			} else {

				$prefs->set($module, STATE_ENABLED);

				push @loaded, $module;
			}
		}

		# Add any available HTML to TT's INCLUDE_PATH
		my $htmlDir = catdir($baseDir, 'HTML');

		if (-d $htmlDir) {

			$log->debug("Adding HTML directory: [$htmlDir]");

			Slim::Web::HTTP::addTemplateDirectory($htmlDir);
		}

		# Add any Bin dirs to findbin search path
		my $binDir = catdir($baseDir, 'Bin');

		if (-d $binDir) {

			$log->debug("Adding Bin directory: [$binDir]");

			Slim::Utils::Misc::addFindBinPaths( catdir($binDir, Slim::Utils::OSDetect::details()->{'binArch'}), $binDir );
		}
	}

	# Call init functions for all loaded plugins - multiple passes allows plugins to offer services to each other
	# - plugins offering service to other plugins use preinitPlugin to init themselves and postinitPlugin to start the service
	# - normal plugins use initPlugin and register with services offered by other plugins at this time

	for my $initFunction (qw(preinitPlugin initPlugin postinitPlugin)) {

		for my $module (@loaded) {

			if ($module->can($initFunction)) {

				eval { $module->$initFunction };
				
				if ($@) {

					logWarning("Couldn't call $module->$initFunction: $@");
				}
			}
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

	for my $name ( keys %{$plugins} ) {

		my $manifest = $plugins->{$name};
		
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

	return $class->_filterPlugins('opType', $opType);
}

sub enabledPlugins {
	my $class = shift;

	my @found = ();

	for my $plugin ($class->installedPlugins) {

		if (defined $prefs->get($plugin) && $prefs->get($plugin) == STATE_ENABLED) {

			unless ($plugins->{$plugin}->{opType} eq OP_NEEDS_INSTALL
				|| $plugins->{$plugin}->{opType} eq OP_NEEDS_ENABLE 
				|| $plugins->{$plugin}->{opType} eq OP_NEEDS_UPGRADE) {
					
				push @found, $plugin;
			}
		}

	}

	return @found;
}

sub isEnabled {
	my $class  = shift;
	my $plugin = shift;

	my %found  = map { $_ => 1 } $class->enabledPlugins;

	if (defined $found{$plugin}) {

		return 1;
	}

	return undef;
}

sub enablePlugin {
	my $class  = shift;
	my $plugin = shift;

	my $opType = $plugins->{$plugin}->{'opType'};

	if ($opType eq OP_NEEDS_UNINSTALL) {
		return;
	}

	if ($opType ne OP_NEEDS_ENABLE) {

		$plugins->{$plugin}->{'opType'} = OP_NEEDS_ENABLE;
		$prefs->set($plugin, STATE_ENABLED);
	}
}

sub disablePlugin {
	my $class  = shift;
	my $plugin = shift;

	my $opType = $plugins->{$plugin}->{'opType'};

	if ($opType eq OP_NEEDS_UNINSTALL) {
		return;
	}

	if ($opType ne OP_NEEDS_DISABLE) {

		$plugins->{$plugin}->{'opType'} = OP_NEEDS_DISABLE;
		$prefs->set($plugin, STATE_DISABLED);
	}
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
