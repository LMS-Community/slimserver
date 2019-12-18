package Slim::Utils::PluginManager;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# $Id$

use strict;

use File::Basename qw(dirname);
use File::Spec::Functions qw(:ALL);
use File::Next;
use File::Path;
use FindBin qw($Bin);
use Path::Class qw(dir);
use XML::Simple;
use YAML::XS;
use Config;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;
use Slim::Utils::Versions;

my $log   = logger('server.plugins');

my $prefs = preferences('plugin.state'); # per plugin state or pending state
# valid states: disabled, enabled, needs-enable, needs-disable, needs-install, needs-uninstall

my $plugins   = {};
my $loaded    = {};
my $disabled  = {};
my $cacheInfo = {};
my $message;
my $downloader;

use constant CACHE_VERSION => 4;

# Skip unwanted plugins
my %SKIP = ();

sub init {
	my $class = shift;
	my $moduleType = shift || '';
	my $useCache = shift;
	$useCache = 1 if !defined $useCache;

	# migrate state info to new pref format
	$prefs->migrate(1, sub {
		for my $old (keys %{$prefs->all}) {
			my $new;
			if    ($old =~ /^Plugins::(.*)::/)                { $new = $1 }
			elsif ($old =~ /^Slim::Plugin::(.*)::/)           { $new = $1 }
			elsif ($old =~ /.*[\/|\\](.*)[\/|\\]install.xml/) { $new = $1 }
			if ($new) {
				$prefs->set($new, $prefs->get($old) ? 'enabled' : 'disabled');
			}
			$prefs->remove($old);
		}
		1;
	});

	if ( main::WEBUI ) {
		eval {
			require Slim::Utils::PluginDownloader;
			$downloader = 'Slim::Utils::PluginDownloader';
			$downloader->init;
		};
		
		$@ && $log->error("Failed to load plugin downloader: $@");
	}

	my $pendingOps;
	my $cacheInvalid;
	my $osDetails = Slim::Utils::OSDetect::details();
	
	%SKIP = map {$_ => 1} Slim::Utils::OSDetect::skipPlugins();

	# load the manifest cache
	if ( $useCache ) {
		$class->_loadPluginCache;

		# process any pending operations (using cache which will potentially become stale)
		for my $plugin (keys %{$prefs->all}) {

			my $val = $prefs->get($plugin);

			if ($val =~ /needs/) {

				$pendingOps = 1;

				if       ($val eq 'needs-enable') {

					$class->_needsEnable($plugin);

				} elsif ($val eq 'needs-disable') {

					$class->_needsDisable($plugin);

				} elsif ($val eq 'needs-uninstall') { 

					$class->_needsUninstall($plugin); 

				} elsif ($val eq 'needs-install') {

					$class->_needsInstall($plugin);
				}
			}
		}
	}

	# validate the cache
	my ($manifestFiles, $sum) = $class->_findInstallManifests;

	if ($main::failsafe) {

		$cacheInvalid = 'starting in failsafe mode - do not load optional plugins';

	} elsif (!scalar keys %{$prefs->all}) {

		$cacheInvalid = 'plugins states are not defined';

	} elsif ($pendingOps) {

		$cacheInvalid = 'processed pending operations';

	} elsif ($cacheInfo && $cacheInfo->{'version'}) {
	
		if ($cacheInfo->{'version'} != CACHE_VERSION) {

			$cacheInvalid = 'cache version does not match';

		} elsif ($cacheInfo->{'bin'} ne $Bin) {

			$cacheInvalid = 'binary location does not match';

		} elsif ($cacheInfo->{'count'} != scalar @{$manifestFiles}) {

			$cacheInvalid = 'different number of plugins in cache';

		} elsif ($cacheInfo->{'mtimesum'} != $sum) {

			$cacheInvalid = 'manifest checksum differs';

		} elsif ($cacheInfo->{'server'} ne $::VERSION) {

			$cacheInvalid = 'server version changed';

		} elsif ($cacheInfo->{'revision'} ne $::REVISION) {

			$cacheInvalid = 'server revision changed';

		} elsif ($cacheInfo->{'osType'} ne $osDetails->{'os'} || $cacheInfo->{'osArch'} ne $osDetails->{'osArch'}) {

			$cacheInvalid = 'os or os architecture changed';
		}

	} else {

		$cacheInvalid = 'no plugin cache or cache disabled by caller';
	}
	
	if ($cacheInvalid) {

		$log->warn("Reparsing plugin manifests - $cacheInvalid");

		$class->_readInstallManifests($manifestFiles, $moduleType);

		if ( $useCache ) {
			$cacheInfo = {
				'version' => CACHE_VERSION,
				'bin'     => $Bin,
				'count'   => scalar @{$manifestFiles},
				'mtimesum'=> $sum,
				'server'  => $::VERSION,
				'revision'=> $::REVISION,
				'osType'  => $osDetails->{'os'},
				'osArch'  => $osDetails->{'osArch'},
			};
		
			$class->_writePluginCache unless $main::failsafe;
		}
	}
} 

sub load {
	my $class = shift;
	my $moduleType = shift || '';

	for my $name (sort keys %$plugins) {
		
		my $state = $prefs->get($name);
		
		my $manifest = $plugins->{$name};

		# Skip plugins with no perl module.
		next unless $manifest->{ $moduleType . 'module' };
		
		my $baseDir    = $manifest->{'basedir'};
		my $module     = $manifest->{ $moduleType . 'module' };
		
		# Initialize all plugins into the disabled list, they are removed below
		# if they are loaded
		$disabled->{$module} = $plugins->{$name};

		# in failsafe mode skip all plugins which aren't required
		next if ($main::failsafe && !$plugins->{$name}->{'enforce'});
		
		if ( main::NOMYSB && ($plugins->{$name}->{needsMySB} && $plugins->{$name}->{needsMySB} !~ /false|no/i) ) {
			main::INFOLOG && $log->info("Skipping plugin: $name - requires mysqueezebox.com, but support for mysqueezebox.com is disabled.");
			next;
		}

		if (defined $state && $state !~ /enabled|disabled/) {
			$log->error("Skipping plugin: $name - in erroneous state: $state");
			next;
		}

		if (defined $state && $state eq 'disabled') {
			# bug 17647 - we must re-enable an enforced plugin if it has been disabled
			if ( $plugins->{$name}->{'enforce'} ) {
				$log->warn("Re-enabling plugin as it is enforced: $name");
				$state = $class->_needsEnable($name);
			}
			else {
				$log->warn("Skipping plugin: $name - disabled");
				next;
			}
		}

		# Skip plugins that can't be loaded.
		if ($manifest->{'error'} ne 'INSTALLERROR_SUCCESS') {
			$log->error(sprintf("Couldn't load $name. Error: %s\n", $class->getErrorString($name)));
			next;
		}

		main::INFOLOG && $log->info("Loading plugin: $name");

		my $loadModule = 0;

		# Look for a lib dir that has a PAR file or otherwise.
		if (-d (my $lib = catdir($baseDir, 'lib')) ) {

			my $dir = dir( catdir($baseDir, 'lib') );

			for my $file ($dir->children) {

				if ($file =~ /\.par$/) {

					$loadModule = 1;

					require PAR;
					PAR->import({ file => $file->stringify });

					last;
				}

				if ($file =~ /\.pm$/) {
					$loadModule = 1;
					last;
				}

				if ($file =~ /.*Plugins$/ && -d $file) {
					$loadModule = 1;
					last;
				}
			}

			unshift @INC, $lib;

			# allow plugins to include architecture specific modules
 			my $arch = $Config::Config{'archname'};
			$arch =~ s/^i[3456]86-/i386-/;
			$arch =~ s/gnu-//;
	
			# Check for use64bitint Perls
			my $is64bitint = $arch =~ /64int/;
			
			# Some ARM platforms use different arch strings, just assume any arm*linux system
			# can run our binaries, this will fail for some people running invalid versions of Perl
			# but that's OK, they'd be broken anyway.
			if ( $arch =~ /^arm.*linux/ ) {
				$arch = $arch =~ /gnueabihf/ 
					? 'arm-linux-gnueabihf-thread-multi' 
					: 'arm-linux-gnueabi-thread-multi';
				$arch .= '-64int' if $is64bitint;
			}
			
			# Same thing with PPC
			if ( $arch =~ /^(?:ppc|powerpc).*linux/ ) {
				$arch = 'powerpc-linux-thread-multi';
				$arch .= '-64int' if $is64bitint;
			}

			my $perlmajorversion = $Config{'version'};
			$perlmajorversion =~ s/\.\d+$//;

			foreach my $v ( $perlmajorversion, $Config::Config{'version'} ) {
				foreach my $a ( $arch, $Config::Config{'archname'}) {
					unshift @INC, catdir($lib, $v, $a, 'auto') if -d catdir($lib, $v, $a, 'auto');
					unshift @INC, catdir($lib, $v, $a)         if -d catdir($lib, $v, $a);
				}
			}
			
			my %seen;
			@INC = grep { ! $seen{$_} ++ } @INC;
		}

		if (-f catdir($baseDir, 'Plugin.pm')) {

			$loadModule = 1;
		}

		# Pull in the module
		if ($loadModule && $module) {

			if (Slim::bootstrap::tryModuleLoad($module)) {

				logError("Couldn't load $module");

				$plugins->{$name}->{error} = 'INSTALLERROR_FAILED_TO_LOAD';

			} else {

				$loaded->{$module} = $plugins->{$name};
				
				delete $disabled->{$module};
			}
		}

		# Add any Bin dirs to findbin search path
		my $binDir = catdir($baseDir, 'Bin');

		if (-d $binDir) {
			Slim::Utils::OSDetect::getOS()->initSearchPath($binDir);

			# XXXX - this is legacy code, as some Slim::Utils::OS::Custom classes
			#        might not be updated to pass on the $binDir to initSearchPath
			main::DEBUGLOG && $log->debug("Adding Bin directory: [$binDir]");

			my $osDetails = Slim::Utils::OSDetect::details();
			my $binArch = $osDetails->{'binArch'};
			my @paths = ( catdir($binDir, $binArch), catdir($binDir, $^O), $binDir );

			if ( $binArch =~ /i386-linux/i ) {
	 			my $arch = $Config::Config{'archname'};
	 			
				if ( $arch && $arch =~ s/^x86_64-([^-]+).*/x86_64-$1/ ) {
					unshift @paths, catdir($binDir, $arch);
				}
			}
			elsif ( $binArch && $binArch eq 'armhf-linux' ) {
				push @paths, catdir($binDir, 'arm-linux');
			}
			elsif ( $binArch =~ /darwin/i && $osDetails->{osArch} =~ /x86_64/ ) {
				unshift @paths, catdir($binDir, $^O . '-' . $osDetails->{osArch});
				unshift @paths, catdir($binDir, $binArch . '-' . $osDetails->{osArch});
			}

			Slim::Utils::Misc::addFindBinPaths( @paths );
		}

		# add skin folders even in noweb mode: we'll need them for the icons
		if ( !main::SCANNER ) {
			# Add any available HTML to TT's INCLUDE_PATH
			my $htmlDir = catdir($baseDir, 'HTML');

			if (-d $htmlDir) {

				main::DEBUGLOG && $log->debug("Adding HTML directory: [$htmlDir]");

				Slim::Web::HTTP::addTemplateDirectory($htmlDir);
			}
		}
	}

	# Call init functions for all loaded plugins - multiple passes allows plugins to offer services to each other
	# - plugins offering service to other plugins use preinitPlugin to init themselves and postinitPlugin to start the service
	# - normal plugins use initPlugin and register with services offered by other plugins at this time

	for my $initFunction (qw(preinitPlugin initPlugin postinitPlugin)) {

		for my $module (sort keys %$loaded) {

			if ($module->can($initFunction)) {
				
				eval { $module->$initFunction };
				
				if ($@) {

					logWarning("Couldn't call $module->$initFunction: $@");
				}
			}
		}
	}

	# check for plugin updates
	if ($downloader) {
		$downloader->periodicCheckForUpdates;
	}
}

sub shutdownPlugins {
	my $class = shift;

	main::INFOLOG && $log->info("Shutting down plugins...");

	for my $module (sort keys %$loaded) {

		if ($module->can('shutdownPlugin')) {

			eval { $module->shutdownPlugin };

			if ($@) {
				logWarning("error running ${module}->shutdownPlugin: $@");
			}
		}
	}
}

sub dirsFor {
	my $class = shift;
	my $type  = shift;
	
	my @dirs = ();
	my $disabledTokens = {};

	for my $name (keys %$plugins) {

		# include name & description strings for disabled plugins so the settings page works
		my $enabled = $prefs->get($name) eq 'enabled';
		if ($type eq 'strings' || $enabled) {
			push @dirs, $plugins->{$name}->{'basedir'};
			
			# we don't want to read all tokens for disabled plugins - only those used in the name & description
			if (!$enabled) {
				my $tokens = {};
				foreach my $item ('name', 'description') {
					$tokens->{$plugins->{$name}->{$item}}++ if $plugins->{$name}->{$item};
				}
				$disabledTokens->{$dirs[-1]} = $tokens if scalar keys %$tokens;
			}
		}
	}
	
	push @dirs, $disabledTokens if scalar keys %$disabledTokens;
	
	return @dirs;
}

sub allPlugins {
	my $class = shift;

	return $plugins;
}

sub getErrorString {
	my $class = shift;
	my $plugin = shift;

	unless ($plugins->{$plugin}->{error} =~ /INSTALLERROR_SUCCESS|INSTALLERROR_NO_MODULE/) {

		return Slim::Utils::Strings::getString($plugins->{$plugin}->{error});
	}

	return '';
}

sub dataForPlugin {
	my $class  = shift;
	my $module = shift;

	if ($loaded->{$module}) {

		return $loaded->{$module};
	}

	return undef;
}

sub installedPlugins {
	my $class = shift;

	my @found = ();

	for my $plugin ( keys %{$plugins} ) {

		if ($plugins->{$plugin}->{error} =~ /INSTALLERROR_SUCCESS|INSTALLERROR_NO_MODULE/) {

			push @found, $plugin;
		}
	}

	return @found;
}

# this returns all plugins modules which are loaded (i.e. enabled and successfully loaded)
sub enabledPlugins {
	my $class = shift;

	return keys %$loaded;
}

# this returns all plugins which are disabled
sub disabledPlugins {
	my $class = shift;
	
	return $disabled;
}

# this returns plugins if a plugin module is currently loaded (i.e. enabled and successfully loaded)
sub isEnabled {
	my $class  = shift;
	my $module = shift || return;
	
	return $loaded->{$module};
}

sub isConfiguredEnabled {
	my $class = shift;
	my $plugin = shift;

    return $prefs->get($plugin) && $prefs->get($plugin) =~ /needs-enable|enabled/;
}

sub enablePlugin {
	my $class  = shift;
	my $plugin = shift;

	if ($prefs->get($plugin) ne 'enabled') {

		main::INFOLOG && $log->info("Setting plugin $plugin to state: needs-enable");

		$prefs->set($plugin, 'needs-enable');
	}
}

sub disablePlugin {
	my $class  = shift;
	my $plugin = shift;

	if ($plugins->{$plugin}->{enforce}) {

		$log->warn("Can't disable plugin: $plugin - 'enforce' set in install.xml");
		return;
	}

	if ($prefs->get($plugin) ne 'disabled') {

		main::INFOLOG && $log->info("Setting plugin $plugin to state: needs-disable");

		$prefs->set($plugin, 'needs-disable');
	}
}

sub needsRestart {
	return grep { /needs/ } values %{$prefs->all};
}

sub message {
	my $class = shift;

	$message = shift if @_;

	return $class->needsRestart 
		? Slim::Utils::Strings::string('PLUGINS_RESTART_MSG') . ' (' .
			join(', ',
				map {
					Slim::Utils::Strings::string($plugins->{$_}->{name});
				} grep {
					$prefs->get($_) =~ /needs/
				} keys %{$prefs->all}
			) .
		')' : $message;
}

sub _pluginCacheFile {
	my $class = shift;

	return catdir( preferences('server')->get('cachedir'), 'plugin-data.yaml' );
}

sub _writePluginCache {
	my $class = shift;

	main::INFOLOG && $log->info("Writing out plugin cache file.");

	# add the cacheinfo data
	$plugins->{'__cacheinfo'} = $cacheInfo;

	YAML::XS::DumpFile($class->_pluginCacheFile, $plugins);

	delete $plugins->{'__cacheinfo'};
}

sub _loadPluginCache {
	my $class = shift;

	my $file = $class->_pluginCacheFile;

	if (!-r $file) {
		main::INFOLOG && $log->info("No plugin cache file.");
		return;
	}

	main::INFOLOG && $log->info("Loading plugin cache file.");

	$plugins = YAML::XS::LoadFile($file);

	$cacheInfo = delete $plugins->{'__cacheinfo'} || { 
		'version' => -1,
	};

	if (main::DEBUGLOG && $log->is_debug) {
		$log->debug("Cache Info: " . Data::Dump::dump($cacheInfo) );
		for my $plugin (sort keys %{$plugins}){
			$log->debug("$plugin");
		}
	}
}

sub _findInstallManifests {
	my $class = shift;

	my $mtimesum = 0;
	my @files;

	# Only find plugins that have been installed.
	my $iter = File::Next::files({

		'file_filter' => sub {
			return 1 if /^install\.xml$/;
			return 0;
		},

	}, Slim::Utils::OSDetect::dirsFor('Plugins'));

	while ( my $file = $iter->() ) {

		$mtimesum += (stat($file))[9];
		push @files, $file;
	}

	return (\@files, $mtimesum);
}

sub _readInstallManifests {
	my $class = shift;
	my $files = shift;
	my $moduleType = shift;

	$plugins = {};

	for my $file (@{$files}) {

		my ($pluginName, $installManifest) = $class->_parseInstallManifest($file, $moduleType);

		if (!defined $pluginName) {
			next;
		}

		$plugins->{$pluginName} = $installManifest;
	}
}

sub _parseInstallManifest {
	my $class = shift;
	my $file  = shift;
	my $moduleType = shift;

	my $installManifest = eval { XMLin($file, SuppressEmpty => undef) };

	if ($@) {

		logWarning("Unable to parse XML in file [$file]: [$@]");

		return undef;
	}

	my $pluginName;

	my $module = $installManifest->{ $moduleType . 'module' };

	if ($module && $module =~ /^Plugins::(.*)::/) {

		$pluginName = $1;

	} elsif ($module && $module =~ /^Slim::Plugin::(.*)::/) {

		$pluginName = $1;

	} else {

		($pluginName) = $file =~ /.*[\/|\\](.*)[\/|\\]install.xml/;
	}

	if ( exists $SKIP{$pluginName} ) {
		# Disabled on SN
		return;
	}

	if (!defined $prefs->get($pluginName)) {

		my $state = delete $installManifest->{'defaultState'};

		if (ref $state eq 'HASH') {

			$state = $state->{ Slim::Utils::OSDetect::OS() } || $state->{ 'other' };
		}

		if ($state && $state eq 'disabled') {

			$prefs->set($pluginName, 'disabled');

		} else {

			$prefs->set($pluginName, 'enabled');
		}
	}

	$installManifest->{'basedir'} = dirname($file);

	if (!defined $module) {
		
		$installManifest->{'error'} = 'INSTALLERROR_NO_MODULE';

	} elsif (!$class->_checkPluginVersion($installManifest)) {

		$installManifest->{'error'} = 'INSTALLERROR_INVALID_VERSION';

	} else {

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
			
			@platforms = @{ $installManifest->{'targetPlatform'} };
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
			
			$installManifest->{'error'} = 'INSTALLERROR_INCOMPATIBLE_PLATFORM';

			$log->warn("plugin $pluginName incompatible with system - disabling");

			$prefs->set($pluginName, 'disabled');
		}
	}

	$installManifest->{'error'} ||= 'INSTALLERROR_SUCCESS';

	main::DEBUGLOG && $log->debug("$pluginName [" . ($module || '') . "] " . Slim::Utils::Strings::getString($installManifest->{error}));

	return ($pluginName, $installManifest);
}

sub _checkPluginVersion {
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

sub _needsEnable {
	my $class = shift;
	my $plugin = shift;

	main::INFOLOG && $log->info("enabling $plugin");

	$prefs->set($plugin, 'enabled');
}

sub _needsDisable {
	my $class = shift;
	my $plugin = shift;

	main::INFOLOG && $log->info("disabling $plugin");

	$prefs->set($plugin, 'disabled');
}

sub _needsUninstall {
	my $class = shift;
	my $plugin = shift;

	if ($plugins->{$plugin}) {

		my $dir = $plugins->{$plugin}->{'basedir'};

		if (-d $dir && $dir =~ /InstalledPlugins/) {

			rmtree $dir;

			main::INFOLOG && $log->info("uninstalling $plugin from $dir");

		} else {

			$log->error("unable to uninstall plugin as not in InstalledPlugins dir - $dir");
		}

	} else {

		$log->error("unable to uninstall plugin $plugin - not in the cache");
	}

	$prefs->remove($plugin);
}

sub _needsInstall {
	my $class = shift;
	my $plugin = shift;

	if ($downloader) {

		$downloader->extract($plugin);

	} else {

		$log->error("unable to install $plugin - downloads disabled");
	}

	$prefs->remove($plugin);
}

1;

