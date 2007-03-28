package Slim::Web::Settings::Server::Plugins;

# $Id$

# SlimServer Copyright (c) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::PluginManager;

sub name {
	return 'PLUGINS';
}

sub page {
	return 'settings/server/plugins.html';
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my @changed = ();
	
	my $plugins = Slim::Utils::PluginManager->allPlugins;
	
	for my $plugin (keys %{$plugins}) {

		my $name   = $plugins->{$plugin}->{'name'};
		my $module = $plugins->{$plugin}->{'module'};
		
		# XXXX - handle install / uninstall / enable / disable
		if ($paramRef->{$name.'.disable'}) {
			push @changed, Slim::Utils::Strings::string($name);
			Slim::Utils::PluginManager->disablePlugin($module);
		}
		
		if ($paramRef->{$name.'.enable'}) {
			push @changed, Slim::Utils::Strings::string($name);
			Slim::Utils::PluginManager->enablePlugin($module);
		}
		
		if ($paramRef->{$name.'.uninstall'}) {
			push @changed, Slim::Utils::Strings::string($name);
		}

	}

	if (@changed) {
		
		#Slim::Utils::PluginManager->runPendingOperations;
		Slim::Utils::PluginManager->writePluginCache;
		$paramRef->{'warning'} .= Slim::Utils::Strings::string('PLUGINS_CHANGED').'<br>'.join('<br>',@changed);
	}

	$paramRef->{'plugins'}  = $plugins;
	$paramRef->{'nosubmit'} = 1;

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
