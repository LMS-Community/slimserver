#
# Plugins.pm by Andrew Hedges (andrew@hedges.me.uk) October 2002
# Re-written by Kevin Walsh (kevin@cursor.biz) January 2003
#
# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# $Id: Plugins.pm,v 1.11 2003/12/24 08:35:00 kdf Exp $
#
package Slim::Buttons::Plugins;
use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Utils::Strings qw (string);
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

use FindBin qw($Bin);

my $read_onfly = 0;	# set to 1 to pick up modules on the fly rather than
			# on the first visit to the plug-ins section
my %plugins = ();
my %curr_plugin = ();
my $plugins_read;

my %functions = (
    'left' => sub  {
		Slim::Buttons::Common::popModeRight(shift);
    },
    'right' => sub  {
		my $client = shift;
		my @enabled = enabledPlugins($client);
		my $current = $plugins{$enabled[$curr_plugin{$client}]};
	
		if (pluginCount()) {
					my @oldlines = Slim::Display::Display::curLines($client);
					Slim::Buttons::Common::pushMode(
					$client,
					$current->{mode},
			);
			Slim::Display::Animation::pushLeft(
					$client,
					@oldlines,
					Slim::Display::Display::curLines($client),
			);
		}
		else {
			Slim::Display::Animation::bumpRight($client);
		}
    },
    'up' => sub  {
		my $client = shift;
	
		$curr_plugin{$client} = Slim::Buttons::Common::scroll(
			$client,
			-1,
			pluginCount(),
			$curr_plugin{$client},
		);
		$client->update();
    },
    'down' => sub  {
		my $client = shift;
	
		$curr_plugin{$client} = Slim::Buttons::Common::scroll(
			$client,
			1,
			pluginCount(),
			$curr_plugin{$client},
		);
		$client->update();
    },
);

sub lines {
    my $client = shift;
	my @enabled = enabledPlugins($client);

    unless (scalar(@enabled)) {
		return(string('NO_PLUGINS'),'');
    }

	my $current = $plugins{$enabled[$curr_plugin{$client}]};

 	my @lines = (
		string('PLUGINS') . ' (' . ($curr_plugin{$client} + 1) . ' ' . string('OF') . ' ' . (pluginCount()) . ')',
		$current->{name},
    );
    return (@lines,undef,Slim::Hardware::VFD::symbol('rightarrow'));
}

sub pluginDirs {
	my @pluginDirs;
	push @pluginDirs, catdir($Bin, "Plugins");
	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @pluginDirs, $ENV{'HOME'} . "/Library/SlimDevices/Plugins/";
		push @pluginDirs, "/Library/SlimDevices/Plugins/";
	}
	return @pluginDirs;
}

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
	@enabled = sort { Slim::Music::Info::ignoreCaseArticles($plugins{$a}->{'name'}) cmp Slim::Music::Info::ignoreCaseArticles($plugins{$b}->{'name'}) } @enabled;
	return @enabled;
}

sub installedPlugins {
	my %pluginlist = ();
	foreach my $plugindir (pluginDirs()) {
		if (opendir(DIR, $plugindir)) {
			no strict 'refs';
			unshift @INC,  $plugindir;
			foreach my $plugin ( sort(readdir(DIR)) ) {
				if ($plugin =~ s/(.+)\.pm$/$1/i) {
					my $pluginname;
					$pluginlist{$plugin} = exists($plugins{$plugin}) ? $plugins{$plugin}{'name'} : $plugin;
				}
			}
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
			# load screensaver, if one exists.
			eval { &{$fullname . "::screenSaver"}() };
			if ($@ && !($@ =~ m/\:\:screenSaver/)) { $::d_plugins && msg("No screensaver for $fullname: " . $@);}
			my $names;
			eval {$names = &{$fullname . "::getDisplayName"}()};
			if (!$@ && $names) {
				my $ref = {
					module => $fullname,
					name => &{$fullname . "::getDisplayName"}(),
					mode => "PLUGIN.$name",
				};
				$plugins{$name} = $ref;
			} else {
				$::d_plugins && msg("Can't load $fullname for Plugins menu: " . $@);
			}
			addDefaultMaps();
		}
    }
    $plugins_read = 1 unless $read_onfly;
}

sub addDefaultMaps {
	no strict 'refs';
	foreach my $plugin (keys %{installedPlugins()}) {
		my $defaultMap;
		eval {$defaultMap = &{"Plugins::${plugin}::defaultMap"}()};
		if ($defaultMap && exists($plugins{$plugin})) {
			Slim::Hardware::IR::addModeDefaultMapping($plugins{$plugin}{'mode'},$defaultMap)
		}
	}
}

sub addSetupGroups {
	no strict 'refs';
	foreach my $plugin (enabledPlugins()) {
		my ($groupRef,$prefRef);
		eval {($groupRef,$prefRef) = &{"Plugins::${plugin}::setupGroup"}()};
		if ($@) {
			$::d_plugins && msg("Can't get setup group for plugin $plugin : " . $@);
		} else {
			if ($groupRef && $prefRef && exists($plugins{$plugin})) {
				Slim::Web::Setup::addGroup('plugins',$plugin,$groupRef,undef,$prefRef)
			}
		}
	}
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

sub setMode {
    my $client = shift;
    if (!defined $curr_plugin{$client} || $curr_plugin{$client} >= scalar(enabledPlugins($client))) {
    	$curr_plugin{$client} = 0;
    }
    $client->lines(\&lines);
}

sub getFunctions {
    return \%functions;
}

1;
