package Slim::Utils::PluginManager;

# Plugins.pm by Andrew Hedges (andrew@hedges.me.uk) October 2002
# Re-written by Kevin Walsh (kevin@cursor.biz) January 2003
#
# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# $Id$
#

use strict;

use File::Basename qw(dirname);
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Path::Class;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Unicode;

my $plugins_read;
my @pluginDirs = ();
my @pluginRootDirs = ();
my %plugins = ();
my %playerplugins = ();

# Bug: 4082 - Populate brokenplugins with the names of old plugins from
# previous SlimServer releases.
my %brokenplugins = (
	'ShoutcastBrowser' => 1,
	'Live365'          => 1,
	'RadioIO'          => 1,
	'Picks'            => 1,
	'iTunes'           => 1,
	'RandomPlay'       => 1,
	'CLI'              => 1,
	'RPC'              => 1,
	'RssNews'          => 1,
	'Rescan'           => 1,
	'SavePlaylist'     => 1,
	'SlimTris'         => 1,
	'Snow'             => 1,
	'Visualizer'       => 1,
	'xPL'              => 1,
);

my $log = logger('server.plugins');

{
	@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');

	# dirsFor('Plugins') returns a list of paths like this:
	#
	# /usr/share/slimserver/Plugins
	#
	# We need to use the path for both the @INC and reading the plugin
	# directory. @INC needs the path one level up. IE:
	# /usr/share/slimserver, so that modules can be loaded properly
	unshift @INC, (map { dirname($_) } @pluginDirs);

	# Bug 4169
	# Remove non-EN HTML paths for core plugins
	my @corePlugins = qw(Live365 MoodLogic MusicMagic RandomPlay);

	for my $path (@pluginDirs) {

		for my $plugin (@corePlugins) {

			my $htmlDir = catdir($path, $plugin, 'HTML');
			my $okDir   = catdir($path, $plugin, 'HTML', 'EN');

			if (!-d $htmlDir) {
				next;
			}

			my $dir = dir($htmlDir);

			for my $subDir ($dir->children) {

				if ($subDir ne $okDir && $subDir->is_dir && $subDir !~ /\.svn/) {

					$log->debug("Removing old non-EN HTML files from core Plugins: [$subDir]");

					$subDir->rmtree;				
				}
			}
		}
	}
}

sub pluginDirs {

	return @pluginDirs;
}

sub init {
	no strict 'refs';
	initPlugins() unless $plugins_read;
}

sub enabledPlugins {
	my $client = shift;

	my @enabled = ();
	my %disabledplugins = map {$_ => 1} Slim::Utils::Prefs::getArray('disabledplugins');
	my $pluginlistref   = installedPlugins();

	for my $item (keys %{$pluginlistref}) {

		next if (exists $disabledplugins{$item});
		next unless defined $plugins{$item};
		
		no strict 'refs';
		if (exists &{$plugins{$item}->{'module'} . "::enabled"} && 
			! &{$plugins{$item}->{'module'} . "::enabled"}($client) ) {
			next;
		}
		
		push @enabled, $item;
	}

	@enabled = sort { 
		Slim::Utils::Text::ignoreCaseArticles($plugins{$a}->{'name'}) cmp 
		Slim::Utils::Text::ignoreCaseArticles($plugins{$b}->{'name'}) } @enabled;

	return @enabled;
}

sub enabledPlugin {
	my $plugin = shift;
	my $client = shift;

	return grep(/$plugin/, enabledPlugins($client));
}

sub playerPlugins {
	# remove disabled plugins
	foreach (keys %playerplugins) {
		delete $playerplugins{$_} if (not $playerplugins{$_});
	}
	
	return \%playerplugins;
}

sub installedPlugins {
	my %pluginlist = ();

	for my $plugindir (pluginDirs()) {

		opendir(DIR, $plugindir) || next;

		for my $plugin ( sort(readdir(DIR)) ) {

			# Skip loading MoodLogic (saves memory) unless we're on Windows.
			if (Slim::Utils::OSDetect::OS() ne 'win' && $plugin =~ /MoodLogic/) {
				next;
			}

			# Don't load the old Favorites plugin.
			if ($plugin eq 'Favorites') {
				next;
			}

			next if ($plugin =~ m/^\./i);

			if ($plugin =~ s/(.+)\.pm$/$1/i) {

				$pluginlist{$plugin} = exists($plugins{$plugin}) ? $plugins{$plugin}{'name'} : $plugin;

			} elsif (-d catdir($plugindir, $plugin) && -e catdir($plugindir, $plugin, "Plugin.pm")) {

				my $pluginname = $plugin . '::' . "Plugin";

				$pluginlist{$pluginname} = exists($plugins{$pluginname}) ? $plugins{$pluginname}{'name'} : $plugin;

			}
		}

		closedir(DIR);
	}

	return \%pluginlist;
}

sub initPlugins {
	return if $plugins_read;

	my %disabledplugins = map { $_ => 1 } Slim::Utils::Prefs::getArray('disabledplugins');

	for my $plugin (keys %{installedPlugins()}) {

		next if (exists $disabledplugins{$plugin});

		if (addPlugin($plugin, \%disabledplugins)) {

			addMenus($plugin, \%disabledplugins);
			addScreensavers($plugin, \%disabledplugins);
			addDefaultMaps($plugin, \%disabledplugins);
			addWebPages($plugin, \%disabledplugins);

			# Add any template directories.
			my $path = ($plugin =~ /^(.+?)::/) ? $1 : $plugin;

			for my $plugindir (pluginDirs()) {

				my $htmldir = catdir($plugindir, $path, "HTML");

				if (-r $htmldir) {

					Slim::Web::HTTP::addTemplateDirectory($htmldir);
				}
			}
		}
	}

	$plugins_read = 1;
}

sub canPlugin {
	my $plugin = shift;
	
	# don't verify a second time
	if ($brokenplugins{$plugin}) {
		return 0;
	}

	# This shouldn't be here - but I can't think of a better place.
	# Fred: commented out to re-enable xPL waiting for a better solution
	# Done this way xPL is forever disabled.
#	if (!Slim::Utils::Prefs::get('xplsupport') && $plugin =~ /xPL/) {
#		return 0;
#	}

	if ($plugins{$plugin} && defined($plugins{$plugin}{'name'})) {
		# plugin is already initialized
		return $plugins{$plugin}{'name'};
	}

	no strict 'refs';

	my $fullname = "Plugins::$plugin";

	$log->info("Requiring $fullname plugin.");

	eval "use $fullname";

	if ($@) {

		logWarning("Can't require $fullname for Plugins menu: $@");

		$brokenplugins{$plugin} = 1;

		return 0;
	}
	
	if (UNIVERSAL::can("Plugins::${plugin}", "enabled")) {
		return 0 if (not &{"Plugins::${plugin}::enabled"});
	}
	
	my $displayName = eval { &{$fullname . "::getDisplayName"}() };
	$displayName = undef if $@;
	
	# Older plugins don't send back the string token - so we don't
	# want to load them.
	
	my $nameExists = Slim::Utils::Strings::stringExists($displayName);
	
	if ($displayName && !$nameExists) {

		logWarning("Can't load plugin $fullname - not 7.0+ compatible. Strings should be defined in a strings.txt file held in the plugin's root directory & displayName must return a string token which is resolved from this file");

		$brokenplugins{$plugin} = 1;

		return 0;

	} elsif ($displayName && $nameExists) {

		return $displayName;

	} else {

		logWarning("Can't load $fullname for Plugins menu: $@");

		$brokenplugins{$plugin} = 1;

		return 0;
	}
}

sub addPlugin {
	my $plugin = shift;
	my $disabledPlugins = shift;
	no strict 'refs';

	my $fullname = "Plugins::$plugin";

	my $displayName = canPlugin($plugin) || return 0;

	$plugins{$plugin} = {
		module => $fullname,
		name   => $displayName,
		mode   => "PLUGIN.$plugin",
		initialized => $plugins{$plugin}{initialized}
	};

	# only run initPlugin() once
	if ((not $plugins{$plugin}{initialized}) && (not $disabledPlugins->{$plugin}) && UNIVERSAL::can("Plugins::${plugin}", "initPlugin")) {

		eval { $fullname->initPlugin };

		if ($@) {

			$log->error("Initialization of $fullname failed: $@");

			$brokenplugins{$plugin} = 1;
			delete $plugins{$plugin};
			return 0;
		}

		$plugins{$plugin}{initialized} = 1;
	}

	if (UNIVERSAL::can("Plugins::${plugin}","setMode") && UNIVERSAL::can("Plugins::${plugin}","getFunctions")) {
		Slim::Buttons::Common::addMode("PLUGIN.$plugin", &{"Plugins::${plugin}::getFunctions"}, \&{"Plugins::${plugin}::setMode"});
	}

	if (UNIVERSAL::can("Plugins::${plugin}","getDisplayDescription")) {
		$plugins{$plugin}->{'desc'} = &{"Plugins::${plugin}::getDisplayDescription"};
	}

	return 1;
}

sub addMenus {
	my $plugin = shift;
	my $disabledPlugins = shift;
	no strict 'refs';
	
	# don't bother if name isn't defined (corrupt/invalid plugin)
	return unless defined $plugins{$plugin}->{'name'};
	
	my %params = (
		'useMode' => "PLUGIN.$plugin",
		'header'  => $plugins{$plugin}->{'name'}
	);
	
	if (exists $disabledPlugins->{$plugin} || 
		!(UNIVERSAL::can("Plugins::${plugin}","setMode") && UNIVERSAL::can("Plugins::${plugin}","getFunctions"))) {

		Slim::Buttons::Home::addSubMenu("PLUGINS", $plugins{$plugin}->{'name'}, undef);
		Slim::Buttons::Home::addMenuOption($plugins{$plugin}->{'name'}, undef);
	}
	else {
		Slim::Buttons::Home::addSubMenu("PLUGINS", $plugins{$plugin}->{'name'}, \%params);
		#add toplevel info for the option of having a plugin at the top level.
		Slim::Buttons::Home::addMenuOption($plugins{$plugin}->{'name'},\%params);
	}
	
	# don't bother going further if there is no addMenu
	return unless UNIVERSAL::can("Plugins::${plugin}","addMenu");
	
	my $menu = eval { &{"Plugins::${plugin}::addMenu"}() };
	
	if (!$@ && defined $menu && $menu && !exists $disabledPlugins->{$plugin}) {

		$log->info("Adding $plugin to menu: $menu");

		Slim::Buttons::Home::addSubMenu($menu, $plugins{$plugin}->{'name'}, \%params);
		
		if ($menu ne "PLUGINS") {
			Slim::Buttons::Home::delSubMenu("PLUGINS", $plugins{$plugin}->{'name'});
			Slim::Buttons::Home::addSubMenu("PLUGINS", $menu, &Slim::Buttons::Home::getMenu("-".$menu));
		}
	
	} else {

		$menu ||= 'PLUGINS';

		$log->info("Removing $plugin from menu: $menu");

		Slim::Buttons::Home::addSubMenu($menu, $plugins{$plugin}->{'name'}, undef);
	}
}

sub addScreensavers {
	my $plugin = shift;
	my $disabledPlugins = shift;
	no strict 'refs';
	
	# load screensaver, if one exists.
	return unless UNIVERSAL::can("Plugins::${plugin}","screenSaver");

	if (exists $disabledPlugins->{$plugin}) {

		Slim::Buttons::Home::addSubMenu("SCREENSAVERS", $plugins{$plugin}->{'name'}, undef);

		return;
	}

	eval { &{"Plugins::${plugin}::screenSaver"}() };

	if ($@) {

		$log->warn("Failed screensaver for $plugin: $@");

	} elsif (!UNIVERSAL::can("Plugins::${plugin}","addMenu")) {

		my %params = (
			'useMode' => "PLUGIN.$plugin",
			'header'  => $plugins{$plugin}->{'name'}
		);

		Slim::Buttons::Home::addSubMenu("SCREENSAVERS", $plugins{$plugin}->{'name'}, exists $disabledPlugins->{$plugin} ? undef : \%params);
		Slim::Buttons::Home::delSubMenu("PLUGINS", $plugins{$plugin}->{'name'});
		Slim::Buttons::Home::addSubMenu("PLUGINS", "SCREENSAVERS", &Slim::Buttons::Home::getMenu("-SCREENSAVERS"));
	}
}
			
sub addDefaultMaps {
	my $plugin = shift;
	no strict 'refs';

	return unless UNIVERSAL::can("Plugins::${plugin}","defaultMap");

	my $defaultMap = eval { &{"Plugins::${plugin}::defaultMap"}() };

	if ($defaultMap && exists($plugins{$plugin})) {
		Slim::Hardware::IR::addModeDefaultMapping($plugins{$plugin}{'mode'}, $defaultMap)
	}
}

sub addWebPages {
	my $plugin = shift;
	my $disabledPlugins = shift;
	no strict 'refs';

	if (exists($plugins{$plugin}) && UNIVERSAL::can("Plugins::${plugin}","webPages")) {

		# Get the page function map and index URL from the plugin
		my ($pagesref, $index) = eval { &{"Plugins::${plugin}::webPages"}() };

		if ($@ || (exists $disabledPlugins->{$plugin})) {

			if ($@) {
				$log->warn("Can't get web page handlers for plugin $plugin : $@");
			}

			if ($plugins{$plugin}->{'name'}) {

				Slim::Web::Pages->addPageLinks("plugins", {
					$plugins{$plugin}->{'name'} => undef
				});
			}

		} elsif ($pagesref) {

			my $path = ($plugin =~ /^(.+?)::/) ? $1 : $plugin;
			my $urlbase = 'plugins/' . $path . '/';

			# Add the page handlers
			for my $page (keys %$pagesref) {
				Slim::Web::HTTP::addPageFunction($urlbase . $page, $pagesref->{$page});
			}

			if ($index) {
				Slim::Web::Pages->addPageLinks("plugins", { $plugins{$plugin}->{'name'} => $urlbase . $index });
			}
		}
	}
}

sub clearGroups {

	$log->info("Resetting plugins.");

	$plugins_read = 0;
}

sub clearPlugins {
	%plugins = {};
	clearGroups();
}

sub shutdownPlugins {

	$log->info("Shutting down plugins...");

	for my $plugin (enabledPlugins()) {

		shutdownPlugin($plugin, 1);
	}
}

sub shutdownPlugin {
	my $plugin  = shift;
	my $exiting = shift || 0;

	no strict 'refs';

	# We use shutdownPlugin() instead of the more succinct
	# shutdown() because it's less likely to cause backward
	# compatibility problems.
	if (UNIVERSAL::can("Plugins::$plugin", "shutdownPlugin")) {

		# Exiting is passed along if the entire server is being shut down.
		eval { &{"Plugins::${plugin}::shutdownPlugin"}($exiting) };
	}

	if (defined $plugins{$plugin}) {

		$plugins{$plugin}{'initialized'} = 0;
	}
}

sub unusedPluginOptions {
	my $client = shift;
	
	my %menuChoices = ();

	my %disabledplugins = map { $_ => 1 } Slim::Utils::Prefs::getArray('disabledplugins');
	my %homeplugins     = map { $_ => 1 } @{Slim::Buttons::Home::getHomeChoices($client)};

	my $pluginsRef = \%plugins;

	for my $menuOption (keys %{$pluginsRef}) {

		next unless $pluginsRef->{$menuOption};
		next if exists $disabledplugins{$menuOption};
		next if exists $homeplugins{$pluginsRef->{$menuOption}->{'name'}};

		next if (!UNIVERSAL::can("$pluginsRef->{$menuOption}->{'module'}","setMode"));
		next if (!UNIVERSAL::can("$pluginsRef->{$menuOption}->{'module'}","getFunctions"));
		
		no strict 'refs';

		if (exists &{"Plugins::" . $menuOption . "::enabled"} && $client &&
			! &{"Plugins::" . $menuOption . "::enabled"}($client) ) {
			next;
		}

		$menuChoices{$menuOption} = $client->string($pluginsRef->{$menuOption}->{'name'});

	}
	return sort { $menuChoices{$a} cmp $menuChoices{$b} } keys %menuChoices;
}

sub pluginCount {
	return scalar(enabledPlugins(shift));
}

sub pluginRootDirs {
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

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
