package Slim::Buttons::Plugins;

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
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

use FindBin qw($Bin);

my $addGroups = 0;
our @pluginDirs = ();

sub pluginDirs {
	if (!scalar @pluginDirs) {
		if (Slim::Utils::OSDetect::OS() eq 'mac') {
			push @pluginDirs, $ENV{'HOME'} . "/Library/SlimDevices/Plugins/";
			push @pluginDirs, "/Library/SlimDevices/Plugins/";
		}
		push @pluginDirs, catdir($Bin, "Plugins");
	}
		
	return @pluginDirs;
}

use lib (pluginDirs());

# set to 1 to pick up modules on the fly rather than
# on the first visit to the plug-ins section
my $read_onfly;
my $plugins_read;

our %plugins = ();
our %curr_plugin = ();
our %playerplugins = ();

sub init {
	no strict 'refs';

	# Do this at runtime, not compile time.
	$read_onfly = Slim::Utils::Prefs::get('plugins-onthefly');
	
	read_plugins() unless $plugins_read;

	for my $plugin (enabledPlugins()) {
		# We use initPlugin() instead of the more succinct
		# init() because it's less likely to cause backward
		# compatibility problems.
		if (exists &{"Plugins::${plugin}::initPlugin"}) {
			&{"Plugins::${plugin}::initPlugin"}();
		}
	}
}

sub enabledPlugins {
	my $client = shift;

	my @enabled = ();
	my %disabledplugins = map {$_ => 1} Slim::Utils::Prefs::getArray('disabledplugins');
	my $pluginlistref   = installedPlugins();

	for my $item (keys %{$pluginlistref}) {

		next if (exists $disabledplugins{$item});
		next if (!exists $plugins{$item});
		
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

sub playerPlugins {
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

sub read_plugins {
	no strict 'refs';

	for my $plugin (keys %{installedPlugins()}) {

		my $fullname = "Plugins::$plugin";
		$::d_plugins && msg("Requiring $fullname plugin.\n");	

		eval "require $fullname";

		if ($@) {
			$::d_plugins && msg("Can't require $fullname for Plugins menu: " . $@);
			next;
		}

		# load up the localized strings, if available
		my $strings = eval { &{$fullname . "::strings"}() };

		if (!$@ && $strings) {

			# flag strings as UTF8
			$strings = pack "U0C*", unpack "C*", $strings;

			Slim::Utils::Strings::addStrings(\$strings);
		}

		my $displayName = eval { &{$fullname . "::getDisplayName"}() };

		# Older plugins don't send back the string token - so we don't
		# want to load them.
		if ($displayName && !Slim::Utils::Strings::stringExists($displayName)) {

			$::d_plugins && msg("Can't load plugin $fullname - not 6.0+ compatible.\n");
			Slim::Utils::Prefs::push('disabledplugins',$plugin);

		} elsif (!$@ && $displayName) {

			#Slim::Utils::Strings::addStringPointer(uc($plugin), $displayName);

			$plugins{$plugin} = {
				module => $fullname,
				name   => $displayName,
				mode   => "PLUGIN.$plugin",
			};

			my %params = (
				'useMode' => "PLUGIN.$plugin",
				'header'  => $plugins{$plugin}->{'name'},
			);

			if (UNIVERSAL::can("Plugins::${plugin}","setMode") && UNIVERSAL::can("Plugins::${plugin}","getFunctions")) {
				Slim::Buttons::Home::addSubMenu("PLUGINS", $plugins{$plugin}->{'name'}, \%params);
				Slim::Buttons::Common::addMode("PLUGIN.$plugin",&{"Plugins::${plugin}::getFunctions"},\&{"Plugins::${plugin}::setMode"});
			}
			
			#add toplevel info for the option of having a plugin at the top level.
			Slim::Buttons::Home::addMenuOption($plugins{$plugin}->{'name'},\%params);

		} else {

			$::d_plugins && msg("Can't load $fullname for Plugins menu: $@\n");
		}

		addDefaultMaps();
	}

	addWebPages();
	addMenus();
	addScreensavers();
	$plugins_read = 1 unless $read_onfly;
}

sub addMenus {
	no strict 'refs';
	my %disabledplugins = map { $_ => 1 } Slim::Utils::Prefs::getArray('disabledplugins');
	
	for my $plugin (keys %{installedPlugins()}) {

		next unless UNIVERSAL::can("Plugins::${plugin}","addMenu");
		next if exists $disabledplugins{$plugin};
		
		my $menu = eval { &{"Plugins::${plugin}::addMenu"}() };

		if (!$@ && defined $menu) {

			my %params = (
				'useMode' => "PLUGIN.$plugin",
				'header'  => $plugins{$plugin}->{'name'}
			);

			$::d_plugins && msg("Adding $plugin to menu: $menu\n");

			Slim::Buttons::Home::addSubMenu($menu, $plugins{$plugin}->{'name'}, \%params);

			if ($menu ne "PLUGINS") {
				Slim::Buttons::Home::delSubMenu("PLUGINS", $plugins{$plugin}->{'name'});
				Slim::Buttons::Home::addSubMenu("PLUGINS", $menu, &Slim::Buttons::Home::getMenu("-".$menu));
			}
		}
	}
}

sub addScreensavers {
	no strict 'refs';
	my %disabledplugins = map { $_ => 1 } Slim::Utils::Prefs::getArray('disabledplugins');
	
	for my $plugin (keys %{installedPlugins()}) {

		# load screensaver, if one exists.
		next unless UNIVERSAL::can("Plugins::${plugin}","screenSaver");
		next if exists $disabledplugins{$plugin};

		eval { &{"Plugins::${plugin}::screenSaver"}() };

		if ($@) {

			$::d_plugins && msg("Failed screensaver for $plugin: " . $@);

		} elsif (!UNIVERSAL::can("Plugins::${plugin}","addMenu")) {

			my %params = (
				'useMode' => "PLUGIN.$plugin",
				'header'  => $plugins{$plugin}->{'name'}
			);

			Slim::Buttons::Home::addSubMenu("SCREENSAVERS", $plugins{$plugin}->{'name'}, \%params);
			Slim::Buttons::Home::delSubMenu("PLUGINS", $plugins{$plugin}->{'name'});
			Slim::Buttons::Home::addSubMenu("PLUGINS", "SCREENSAVERS", &Slim::Buttons::Home::getMenu("-SCREENSAVERS"));
		}
	}
}
			
sub addDefaultMaps {
	no strict 'refs';

	for my $plugin (keys %{installedPlugins()}) {

		next unless UNIVERSAL::can("Plugins::${plugin}","defaultMap");

		my $defaultMap = eval { &{"Plugins::${plugin}::defaultMap"}() };

		if ($defaultMap && exists($plugins{$plugin})) {
			Slim::Hardware::IR::addModeDefaultMapping($plugins{$plugin}{'mode'}, $defaultMap)
		}
	}
}

sub addWebPages {
	no strict 'refs';
	my %disabledplugins = map { $_ => 1 } Slim::Utils::Prefs::getArray('disabledplugins');
	
	for my $plugin (keys %{installedPlugins()}) {

		next if exists $disabledplugins{$plugin};

		if (exists($plugins{$plugin}) && UNIVERSAL::can("Plugins::${plugin}","webPages")) {

			# Get the page function map and index URL from the plugin
			my ($pagesref, $index) = eval { &{"Plugins::${plugin}::webPages"}() };

			if ($@) {

				$::d_plugins && msg("Can't get web page handlers for plugin $plugin : " . $@);

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
					Slim::Web::Pages::addLinks("plugins", {
						$plugins{$plugin}->{'name'} => $urlbase . $index,
					});
				}
			}
		}
	}
}

sub clearGroups {
	$addGroups = 0;
}

sub addSetupGroups {
	no strict 'refs';
	my %disabledplugins = map { $_ => 1 } Slim::Utils::Prefs::getArray('disabledplugins');
	
	return if $addGroups && !Slim::Utils::Prefs::get('plugins-onthefly');

	for my $plugin (keys %{installedPlugins()}) {

		next unless UNIVERSAL::can("Plugins::${plugin}","setupGroup");
		next if exists $disabledplugins{$plugin};

		my ($groupRef, $prefRef, $isClient) = eval { &{"Plugins::${plugin}::setupGroup"}() };

		if ($@) {
			$::d_plugins && msg("Can't get setup group for plugin $plugin : " . $@);
			next;
		}

		if ($groupRef && $prefRef && exists($plugins{$plugin})) {

			my %params =  (
				title      => $plugins{$plugin}->{'name'},
				Groups     => { 'Default' => $groupRef },
				GroupOrder => ['Default'],
				Prefs      => $prefRef
			);

			if (defined $isClient) {

				$playerplugins{$plugins{$plugin}->{'name'}} = 1;

				Slim::Web::Setup::addGroup('player_plugins', $plugin, $groupRef, undef, $prefRef);

			} else {

				Slim::Web::Setup::addGroup('plugins', $plugin, $groupRef, undef, $prefRef);

				Slim::Web::Setup::addCategory("PLUGINS.${plugin}", \%params);

				if (UNIVERSAL::can("Plugins::${plugin}","addMenu")) {

					my $menu = eval { &{"Plugins::${plugin}::addMenu"}() };

					if (!$@ && defined $menu && $menu eq "RADIO") {
						Slim::Web::Setup::addGroup('radio', $plugin, $groupRef, undef, $prefRef);
					}
				}
			}
		}
	}
	$addGroups = 1;
}

sub shutdownPlugins {
	no strict 'refs';
	for my $plugin (enabledPlugins()) {
		# We use shutdownPlugin() instead of the more succinct
		# shutdown() because it's less likely to cause backward
		# compatibility problems.
		if (exists &{"Plugins::${plugin}::shutdownPlugin"}) {
			&{"Plugins::${plugin}::shutdownPlugin"}();
		}
	}
}

sub unusedPluginOptions {
	my $client = shift;
	
	my %menuChoices = ();

	my %disabledplugins = map { $_ => 1 } Slim::Utils::Prefs::getArray('disabledplugins');
	my %homeplugins = map { $_ => 1 } @{Slim::Buttons::Home::getHomeChoices($client)};

	my $pluginsRef = \%plugins;

	for my $menuOption (keys %{$pluginsRef}) {

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

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
