package Slim::Web::Settings::Server::Plugins;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::PluginManager;
use Slim::Utils::OSDetect;

my $os = Slim::Utils::OSDetect->getOS();

sub name {
	return Slim::Web::HTTP::protectName('SETUP_PLUGINS');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/server/plugins.html');
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my @changed = ();

	my $plugins = Slim::Utils::PluginManager->allPlugins;
	my $pluginState = preferences('plugin.state')->all();
	
	for my $plugin (keys %{$plugins}) {

		my $name     = $plugins->{$plugin}->{'name'};
		my $module   = $plugins->{$plugin}->{'module'};

		$plugins->{$plugin}->{errorDesc} = Slim::Utils::PluginManager->getErrorString($plugin);

		# XXXX - handle install / uninstall / enable / disable
		if ( $paramRef->{'saveSettings'} ) {
			# don't handle enforced plugins
			next if $plugins->{$plugin}->{'enforce'} || $plugins->{$plugin}->{error} < 0;

			if (!$paramRef->{$name} && $pluginState->{$plugin}) {
				push @changed, Slim::Utils::Strings::string($name);
				Slim::Utils::PluginManager->disablePlugin($module);
			}
	
			if ($paramRef->{$name} && !$pluginState->{$plugin}) {
				push @changed, Slim::Utils::Strings::string($name);
				Slim::Utils::PluginManager->enablePlugin($module);
			}
		}

	}

	if (@changed) {
		
		#Slim::Utils::PluginManager->runPendingOperations;
		Slim::Utils::PluginManager->writePluginCache;

		# show a link/button to restart SC if this is supported by this platform
		if ($os->canRestartServer()) {
					
			$paramRef->{'warning'} = '<span id="restartWarning">'
				. Slim::Utils::Strings::string('PLUGINS_CHANGED_NEED_RESTART')
				. '</span>';
	
		}
		
		else {
		
			$paramRef->{'warning'} .= '<span id="popupWarning">'
				. Slim::Utils::Strings::string('PLUGINS_CHANGED') . '<br>' . join('<br>',@changed)
				. '</span>';
			
		}
	}


	if ($paramRef->{restart} && $os->canRestartServer()) {
		
		$paramRef->{'warning'} = '<span id="popupWarning">'
			. Slim::Utils::Strings::string('RESTARTING_PLEASE_WAIT')
			. '</span>';
		
		# delay the restart a few seconds to return the page to the client first
		Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 2, sub {
			$os->restartServer();
		});
				
	}

	$paramRef->{plugins}     = $plugins;
	$paramRef->{pluginState} = preferences('plugin.state')->all();

	# only show plugins with perl modules
	my @keys = ();
	for my $key (keys %$plugins) {
		push @keys, $key if $plugins->{$key}->{module};
	};

	my @sortedPlugins = 
		map { $_->[1] }
		sort { $a->[0] cmp $b->[0] }
		map { [ uc( Slim::Utils::Strings::string($plugins->{$_}->{name}) ), $_ ] } 
		@keys;

	$paramRef->{sortedPlugins} = \@sortedPlugins;

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
