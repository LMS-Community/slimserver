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

use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Unicode;

my $addGroups = 0;
my $plugins_read;
my @pluginDirs = ();
my @pluginRootDirs = ();
my %plugins = ();
my %playerplugins = ();
my %brokenplugins = ();

INIT {

	@pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');

	unshift @INC, @pluginDirs;
}

sub pluginDirs {

	return @pluginDirs;
}

sub init {
	no strict 'refs';
	initPlugins() unless $plugins_read;
	addSetupGroups() unless $addGroups;
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

	my $firstCall = !scalar(@pluginRootDirs); # first call loads @pluginRootDirs

	for my $plugindir (pluginDirs()) {

		opendir(DIR, $plugindir) || next;

		for my $plugin ( sort(readdir(DIR)) ) {

			# Skip loading MoodLogic (saves memory) unless we're on Windows.
			if (Slim::Utils::OSDetect::OS() ne 'win' && $plugin =~ /MoodLogic/) {
				next;
			}

			next if ($plugin =~ m/^\./i);

			if ($plugin =~ s/(.+)\.pm$/$1/i) {

				$pluginlist{$plugin} = exists($plugins{$plugin}) ? $plugins{$plugin}{'name'} : $plugin;

			} elsif (-d catdir($plugindir, $plugin) && -e catdir($plugindir, $plugin, "Plugin.pm")) {

				my $pluginname = $plugin . '::' . "Plugin";

				$pluginlist{$pluginname} = exists($plugins{$pluginname}) ? $plugins{$pluginname}{'name'} : $plugin;
				
				push @pluginRootDirs, catdir($plugindir, $plugin) if $firstCall;
			}
		}

		closedir(DIR);
	}

	return \%pluginlist;
}

sub initPlugins {
	return if $plugins_read || $addGroups;

	my %disabledplugins = map { $_ => 1 } Slim::Utils::Prefs::getArray('disabledplugins');

	for my $plugin (keys %{installedPlugins()}) {

		if (addPlugin($plugin, \%disabledplugins)) {
			addMenus($plugin, \%disabledplugins);
			addScreensavers($plugin, \%disabledplugins);
			addDefaultMaps($plugin, \%disabledplugins);
			addWebPages($plugin, \%disabledplugins);
		}

	}

	$plugins_read = 1 unless Slim::Utils::Prefs::get('plugins-onthefly');
}

sub canPlugin {
	my $plugin = shift;
	
	# don't verify a second time
	return 0 if ($brokenplugins{$plugin});

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
	$::d_plugins && msg("Requiring $fullname plugin.\n");	

	eval "use $fullname";

	if ($@) {
		$::d_plugins && msg("Can't require $fullname for Plugins menu: " . $@);
		$brokenplugins{$plugin} = 1;
		return 0;
	}
	
	if (UNIVERSAL::can("Plugins::${plugin}", "enabled")) {
		return 0 if (not &{"Plugins::${plugin}::enabled"});
	}
	
	# load up the localized strings, if available
	my $strings = eval { &{$fullname . "::strings"}() };

	if (!$@ && $strings) {
		# flag strings as UTF8
		if ($] > 5.007) {
			$strings = pack "U0C*", unpack "C*", $strings;
		} else {
			# for the 5.6 laggers.
			if (Slim::Utils::Unicode::currentLocale() =~ /^iso-8859/) {
				$strings = Slim::Utils::Unicode::utf8toLatin1($strings);
			}
		}

		Slim::Utils::Strings::addStrings(\$strings);
	}

	my $displayName = eval { &{$fullname . "::getDisplayName"}() };
	$displayName = undef if $@;
	
	# Older plugins don't send back the string token - so we don't
	# want to load them.
	if ($displayName && !Slim::Utils::Strings::stringExists($displayName)) {

		$::d_plugins && msg("Can't load plugin $fullname - not 6.0+ compatible. (displayName must return a string token, strings() must not use _DATA_)\n");
		$brokenplugins{$plugin} = 1;

		return 0;

	} elsif ($displayName && Slim::Utils::Strings::stringExists($displayName)) {

		return $displayName;

	} else {

		$::d_plugins && msg("Can't load $fullname for Plugins menu: $@\n");

		$brokenplugins{$plugin} = 1;

		return 0;
	}
}

sub addPlugin {
	my $plugin = shift;
	my $disabledPlugins = shift;
	no strict 'refs';

	my $fullname = "Plugins::$plugin";

	my $displayName = canPlugin($plugin);
	return 0 if (not $displayName);

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
			$::d_plugins && msg("Initialization of $fullname failed: $@\n");
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
	
	if (exists $disabledPlugins->{$plugin} || !(UNIVERSAL::can("Plugins::${plugin}","setMode") && UNIVERSAL::can("Plugins::${plugin}","getFunctions"))) {
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

		$::d_plugins && msg("Adding $plugin to menu: $menu\n");
		Slim::Buttons::Home::addSubMenu($menu, $plugins{$plugin}->{'name'}, \%params);
		
		if ($menu ne "PLUGINS") {
			Slim::Buttons::Home::delSubMenu("PLUGINS", $plugins{$plugin}->{'name'});
			Slim::Buttons::Home::addSubMenu("PLUGINS", $menu, &Slim::Buttons::Home::getMenu("-".$menu));
		}
	
	} else {
		$menu ||= 'PLUGINS';
		$::d_plugins && msg("Removing $plugin from menu: $menu\n");
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
		$::d_plugins && msg("Failed screensaver for $plugin: " . $@);

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
			$@ && $::d_plugins && msg("Can't get web page handlers for plugin $plugin : " . $@);
			Slim::Web::Pages->addPageLinks("plugins", {$plugins{$plugin}->{'name'} => undef}) if $plugins{$plugin}->{'name'};

		} elsif ($pagesref) {

			my $path = ($plugin =~ /^(.+?)::/) ? $1 : $plugin;
			my $urlbase = 'plugins/' . $path . '/';

			# Add the page handlers
			for my $page (keys %$pagesref) {
				Slim::Web::HTTP::addPageFunction($urlbase . $page, $pagesref->{$page});
			}
			
			# Add any template directories that may exist for the plugin
			for my $plugindir (pluginDirs()) {
				my $htmldir = catdir($plugindir, $path, "HTML");

				if (-r $htmldir) {
					Slim::Web::HTTP::addTemplateDirectory($htmldir);
				}
			}

			if ($index) {
				Slim::Web::Pages->addPageLinks("plugins", { $plugins{$plugin}->{'name'} => $urlbase . $index });
			}
		}
	}
}

sub clearGroups {
	$::d_plugins && msg("Resetting plugins\n");
	$addGroups = 0;
	$plugins_read = 0;
}

sub clearPlugins {
	%plugins = {};
	clearGroups();
}

sub addSetupGroups {
	no strict 'refs';
	
	my %disabledplugins = map { $_ => 1 } Slim::Utils::Prefs::getArray('disabledplugins');

	return if $addGroups;

	for my $plugin (keys %{installedPlugins()}) {
		my ($groupRef, $prefRef, $isClient, $noSetupGroup);

		if (UNIVERSAL::can("Plugins::${plugin}","setupGroup")) {
			($groupRef, $prefRef, $isClient) = eval { &{"Plugins::${plugin}::setupGroup"}() };
			$noSetupGroup = $@;
		}

		if ($noSetupGroup) {
			$::d_plugins && msg("Can't get setup group for plugin $plugin : " . $noSetupGroup);
			next;
		}

		if ($groupRef && $prefRef && exists($plugins{$plugin})) {
			my %params = (
				'title'      => $plugins{$plugin}->{'name'},
				'parent'     => 'SERVER_SETTINGS',
				'Groups'     => { 'Default' => $groupRef },
				'GroupOrder' => ['Default'],
				'Prefs'      => $prefRef
			);

			my $menu = 'PLUGINS';
			if (UNIVERSAL::can("Plugins::${plugin}","addMenu")) {
				$menu = eval { &{"Plugins::${plugin}::addMenu"}() };
				$menu = 'PLUGINS' if (not $menu || $@);
			}
	
			if (defined $isClient && $isClient) {
				if ($menu eq 'PLUGINS') {
					$menu = 'PLAYER_PLUGINS';
					$params{'parent'} = 'PLAYER_SETTINGS';
					#Slim::Web::Pages->addPageLinks("playerplugin",{"$plugins{$plugin}->{'name'}"  => "setup.html?page=$plugins{$plugin}->{'name'}"});
				}
				$playerplugins{$plugins{$plugin}->{'name'}} = not exists $disabledplugins{$plugin};
			}
	
			if (exists $disabledplugins{$plugin}) {
				Slim::Web::Setup::delGroup($menu, $plugin);
			}
			else {
				Slim::Web::Setup::addGroup($menu, $plugin, $groupRef, undef, $prefRef);
				Slim::Web::Setup::addCategory("PLUGINS.${plugin}", \%params);
				#Slim::Web::Pages->addPageLinks("plugin",{"$plugins{$plugin}->{'name'}"  => "setup.html?page=$plugins{$plugin}->{'name'}"});
			}
		}
		
		if (exists $disabledplugins{$plugin}) {
			shutdownPlugin($plugin);
		}
	}
	$addGroups = 1 unless Slim::Utils::Prefs::get('plugins-onthefly');
}

sub shutdownPlugins {
	$::d_plugins && msg("Shutting down plugins...\n");
	for my $plugin (enabledPlugins()) {
		shutdownPlugin($plugin);
	}
}

sub shutdownPlugin {
	my $plugin = shift;
	no strict 'refs';

	if (UNIVERSAL::can("Plugins::$plugin", "disablePlugin")) {
		msg("disablePlugin() is deprecated! Please use shutdownPlugin() instead. (Plugins::$plugin)\n");
		eval { &{"Plugins::${plugin}::disablePlugin"}() };
	}

	# We use shutdownPlugin() instead of the more succinct
	# shutdown() because it's less likely to cause backward
	# compatibility problems.
	if (UNIVERSAL::can("Plugins::$plugin", "shutdownPlugin")) {
		eval { &{"Plugins::${plugin}::shutdownPlugin"}() };
	}
	$plugins{$plugin}{'initialized'} = 0 if (defined $plugins{$plugin});
}

sub unusedPluginOptions {
	my $client = shift;
	
	my %menuChoices = ();

	my %disabledplugins = map { $_ => 1 } Slim::Utils::Prefs::getArray('disabledplugins');
	my %homeplugins = map { $_ => 1 } @{Slim::Buttons::Home::getHomeChoices($client)};

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
	# returns root directory of installed plugins with their own directory 
	# not expected to be called until after initPlugins
	return @pluginRootDirs;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
