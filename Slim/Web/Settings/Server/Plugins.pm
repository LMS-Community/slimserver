package Slim::Web::Settings::Server::Plugins;

# $Id$

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::PluginManager;

sub name {
	return Slim::Web::HTTP::protectName('PLUGINS');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/server/plugins.html');
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

	$paramRef->{plugins}  = $plugins;
	$paramRef->{nosubmit} = 1;

	my @sortedPlugins = 
		map { $_->[1] }
		sort { $a->[0] cmp $b->[0] }
		map { [ uc( Slim::Utils::Strings::string($plugins->{$_}->{name}) ), $_ ] } 
		keys %{$plugins};

	$paramRef->{sortedPlugins} = \@sortedPlugins;

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
