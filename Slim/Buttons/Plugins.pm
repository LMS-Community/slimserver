#
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
# $Id: Plugins.pm,v 1.28 2004/10/27 23:36:15 vidur Exp $
#
package Slim::Buttons::Plugins;
use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Utils::Strings qw (string);
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

use FindBin qw($Bin);

sub pluginDirs {
	my @pluginDirs;
	push @pluginDirs, catdir($Bin, "Plugins");
	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @pluginDirs, $ENV{'HOME'} . "/Library/SlimDevices/Plugins/";
		push @pluginDirs, "/Library/SlimDevices/Plugins/";
	}
	return @pluginDirs;
}

use lib (pluginDirs());

my $read_onfly = Slim::Utils::Prefs::get('plugins-onthefly');	# set to 1 to pick up modules on the fly rather than
			# on the first visit to the plug-ins section
my %plugins = ();
my %curr_plugin = ();
my $plugins_read;
my %playerplugins = ();

sub enabledPlugins {
	my $client = shift;
	my @enabled;
	my %disabledplugins = map {$_ => 1} Slim::Utils::Prefs::getArray('disabledplugins');
	my $pluginlistref = installedPlugins();
	foreach my $item (keys %{$pluginlistref}) {
		next if (exists $disabledplugins{$item});
		next if (!exists $plugins{$item});
		
		no strict 'refs';
		if (exists &{$plugins{$item}->{'module'} . "::enabled"} && 
			! &{$plugins{$item}->{'module'} . "::enabled"}($client) ) {
			next;
		}
		
		push @enabled, $item;
	}
	@enabled = sort { Slim::Utils::Text::ignoreCaseArticles($plugins{$a}->{'name'}) cmp Slim::Utils::Text::ignoreCaseArticles($plugins{$b}->{'name'}) } @enabled;
	return @enabled;
}

sub playerPlugins {
	return \%playerplugins;
}

sub installedPlugins {
	my %pluginlist = ();
	foreach my $plugindir (pluginDirs()) {
		if (opendir(DIR, $plugindir)) {
			no strict 'refs';
			foreach my $plugin ( sort(readdir(DIR)) ) {
				if ($plugin =~ s/(.+)\.pm$/$1/i) {
					$pluginlist{$plugin} = exists($plugins{$plugin}) ? $plugins{$plugin}{'name'} : $plugin;
				}
				elsif (-d catdir($plugindir, $plugin) &&
					   -e catdir($plugindir, $plugin, "Plugin.pm")) {
					my $pluginname = $plugin . '::' . "Plugin";
					$pluginlist{$pluginname} = exists($plugins{$pluginname}) ? $plugins{$pluginname}{'name'} : $plugin;
				}
			}
			closedir(DIR);
		}
	}
	return \%pluginlist;
}

sub read_plugins {
	no strict 'refs';

	foreach my $name (keys %{installedPlugins()}) {
		my $fullname = "Plugins::$name";
		$::d_plugins && msg("Requiring $fullname plugin.\n");	
		eval "require $fullname";
		if ($@) {
			$::d_plugins && msg("Can't require $fullname for Plugins menu: " . $@);
		} else {
			# load up the localized strings, if available
			my $strings;
			eval {$strings = &{$fullname . "::strings"}()};
			if (!$@ && $strings) { Slim::Utils::Strings::addStrings($strings); }
			my $names;
			eval {$names = &{$fullname . "::getDisplayName"}()};
			if (!$@ && $names) {
				Slim::Utils::Strings::addstringRef(uc($name),\&{$fullname . "::getDisplayName"});
				my $ref = {
					module => $fullname,
					name => &{$fullname . "::getDisplayName"}(),
					mode => "PLUGIN.$name",
				};
				$plugins{$name} = $ref;
				my %params = (
					'useMode' => "PLUGIN.$name"
					,'header' => $plugins{$name}->{'name'}
					);
				Slim::Buttons::Home::addSubMenu("PLUGINS",$name,\%params);
			} else {
				$::d_plugins && msg("Can't load $fullname for Plugins menu: " . $@);
			}
			addDefaultMaps();
		}
	}
	addWebPages();
	addScreensavers();
	#addSetupGroups();
	addMenus();
	$plugins_read = 1 unless $read_onfly;
}

sub addMenus {
	no strict 'refs';
	foreach my $plugin (keys %{installedPlugins()}) {
		my $menu;
		if (UNIVERSAL::can("Plugins::${plugin}","addMenu")) {
			eval { $menu = &{"Plugins::${plugin}::addMenu"}()};
			if (!$@ && defined $menu) {
				my %params = (
					'useMode' => "PLUGIN.$plugin"
					,'header' => $plugins{$plugin}->{'name'}
					);
				$::d_plugins && msg("Adding $plugin to menu: $menu\n");
				Slim::Buttons::Home::addSubMenu($menu,$plugin,\%params);
				Slim::Buttons::Home::delSubMenu("PLUGINS",$plugin);
				Slim::Buttons::Home::addSubMenu("PLUGINS",$menu,&Slim::Buttons::Home::getMenu("-".$menu));
			}
		}
	}
}

sub addScreensavers {
	no strict 'refs';
	foreach my $plugin (keys %{installedPlugins()}) {
		# load screensaver, if one exists.
		if (UNIVERSAL::can("Plugins::${plugin}","screenSaver")) {
			eval { &{"Plugins::${plugin}::screenSaver"}() };
			if ($@) { $::d_plugins && msg("Failed screensaver for $plugin: " . $@);}
			else {
				my %params = (
					'useMode' => "PLUGIN.$plugin"
					,'header' => $plugins{$plugin}->{'name'}
					);
				Slim::Buttons::Home::addSubMenu("SCREENSAVERS",$plugin,\%params);
				Slim::Buttons::Home::delSubMenu("PLUGINS",$plugin);
				Slim::Buttons::Home::addSubMenu("PLUGINS","SCREENSAVERS",&Slim::Buttons::Home::getMenu("-SCREENSAVERS"));
			}
		}
	}
}
			
sub addDefaultMaps {
	no strict 'refs';
	foreach my $plugin (keys %{installedPlugins()}) {
		my $defaultMap;
		if (UNIVERSAL::can("Plugins::${plugin}","defaultMap")) {
			eval {$defaultMap = &{"Plugins::${plugin}::defaultMap"}()};
			if ($defaultMap && exists($plugins{$plugin})) {
				Slim::Hardware::IR::addModeDefaultMapping($plugins{$plugin}{'mode'},$defaultMap)
			}
		}
	}
}

sub addWebPages {
	no strict 'refs';
	foreach my $plugin (keys %{installedPlugins()}) {
		if (exists($plugins{$plugin}) &&
			UNIVERSAL::can("Plugins::${plugin}","webPages")) {
			no strict 'refs';

			# Get the page function map and index URL from the plugin
			my ($pagesref, $index);
			eval {($pagesref, $index) = &{"Plugins::${plugin}::webPages"}()};
			
			if ($@) {
				$::d_plugins && msg("Can't get web page handlers for plugin $plugin : " . $@);
			}
			elsif ($pagesref) {
				my $path = ($plugin =~ /^(.+?)::/) ? $1 : $plugin;
				my $urlbase = 'plugins/' . $path . '/';

				# Add the page handlers
				foreach my $page (keys %$pagesref) {
					Slim::Web::HTTP::addPageFunction($urlbase . $page,
													 $pagesref->{$page});
				}
				
				# Add any template directories that may exist for the plugin
				foreach my $plugindir (pluginDirs()) {
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

sub addSetupGroups {
	no strict 'refs';
	foreach my $plugin (keys %{installedPlugins()}) {
		my ($groupRef,$prefRef,$isClient);
		if (UNIVERSAL::can("Plugins::${plugin}","setupGroup")) {
			eval {($groupRef,$prefRef,$isClient) = &{"Plugins::${plugin}::setupGroup"}()};
			if ($@) {
				$::d_plugins && msg("Can't get setup group for plugin $plugin : " . $@);
			} else {
				if ($groupRef && $prefRef && exists($plugins{$plugin})) {
					my %params =  ( title => $plugins{$plugin}->{'name'},
						Groups => { 'Default' => $groupRef },
						GroupOrder => ['Default'],
						Prefs => $prefRef
						);
					if (defined $isClient) {
						$playerplugins{$plugins{$plugin}->{'name'}} = 1;
						Slim::Web::Setup::addGroup('player_plugins',$plugin,$groupRef,undef,$prefRef);
					} else {
						Slim::Web::Setup::addGroup('plugins',$plugin,$groupRef,undef,$prefRef);
						Slim::Web::Setup::addCategory("PLUGINS.${plugin}",\%params);
						if (UNIVERSAL::can("Plugins::${plugin}","addMenu")) {
							my $menu;
							eval { $menu = &{"Plugins::${plugin}::addMenu"}()};
							if (!$@ && defined $menu && $menu eq "RADIO") {
								Slim::Web::Setup::addGroup('radio',$plugin,$groupRef,undef,$prefRef);
							}
						}
					}
				}
			}
		}
	}
}

sub init {
	no strict 'refs';
	foreach my $plugindir (pluginDirs()) {
		unshift @INC,  $plugindir;
	}
	foreach my $plugin (enabledPlugins()) {
		# We use initPlugin() instead of the more succinct
		# init() because it's less likely to cause backward
		# compatibility problems.
		if (exists &{"Plugins::${plugin}::initPlugin"}) {
			&{"Plugins::${plugin}::initPlugin"}();
		}
	}
}

sub shutdownPlugins {
	no strict 'refs';
	foreach my $plugin (enabledPlugins()) {
		# We use shutdownPlugin() instead of the more succinct
		# shutdown() because it's less likely to cause backward
		# compatibility problems.
		if (exists &{"Plugins::${plugin}::shutdownPlugin"}) {
			&{"Plugins::${plugin}::shutdownPlugin"}();
		}
	}
}

sub pluginOptions {
	my $client = shift;
	
	my %menuChoices = ();
	$menuChoices{""} = "";
	my %disabledplugins = map {$_ => 1} Slim::Utils::Prefs::getArray('disabledplugins');
	my $pluginsRef = Slim::Buttons::Plugins::installedPlugins();
	
	foreach my $menuOption (keys %{$pluginsRef}) {
		next if (exists $disabledplugins{$menuOption});
		no strict 'refs';
		if (exists &{"Plugins::" . $menuOption . "::enabled"} && $client &&
			! &{"Plugins::" . $menuOption . "::enabled"}($client) ) {
			next;
		}
		$menuChoices{$menuOption} = string($menuOption);
	}
	return %menuChoices;
}

sub unusedPluginOptions {
	my $client = shift;
	my %menuChoices = pluginOptions($client);
	
	delete $menuChoices{""};
	foreach my $usedOption (@{Slim::Buttons::Home::getHomeChoices($client)}) {
		delete $menuChoices{$usedOption};
	}
	return sort { $menuChoices{$a} cmp $menuChoices{$b} } keys %menuChoices;
}

sub getPluginModes {
	my $mode = shift;

	read_plugins() unless $plugins_read;

	foreach (keys %plugins){
		$mode->{$plugins{$_}->{mode}} = \&{$plugins{$_}->{module} . "::setMode"}
	}
}

sub getPluginFunctions {
	my $function = shift;

	read_plugins() unless $plugins_read;

	foreach (keys %plugins){
		no strict 'refs';
		$function->{$plugins{$_}->{mode}} = &{$plugins{$_}->{module} . "::getFunctions"}
	}
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
