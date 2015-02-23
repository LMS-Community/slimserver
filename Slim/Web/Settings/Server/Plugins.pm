package Slim::Web::Settings::Server::Plugins;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::PluginManager;
use Slim::Utils::OSDetect;

sub name {
	return Slim::Web::HTTP::CSRF->protectName('SETUP_PLUGINS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/server/plugins.html');
}

=pod
# XXX - don't need this any more, as the Extensions plugin is enforced?
sub handler {
	my ($class, $client, $paramRef) = @_;

	my $plugins = Slim::Utils::PluginManager->allPlugins;
	my $pluginState = preferences('plugin.state')->all();
	
	for my $plugin (keys %{$plugins}) {

		my $name = $plugins->{$plugin}->{'name'};

		$plugins->{$plugin}->{errorDesc} = Slim::Utils::PluginManager->getErrorString($plugin);

		if ( $paramRef->{'saveSettings'} ) {

			next if $plugins->{$plugin}->{'enforce'};

			if (!$paramRef->{$name} && $pluginState->{$plugin} eq 'enabled') {
				Slim::Utils::PluginManager->disablePlugin($plugin);
			}
	
			if ($paramRef->{$name} && $pluginState->{$plugin} eq 'disabled') {
				Slim::Utils::PluginManager->enablePlugin($plugin);
			}
		}

	}

	if (Slim::Utils::PluginManager->needsRestart) {
		
		$paramRef = $class->getRestartMessage($paramRef, Slim::Utils::Strings::string('PLUGINS_CHANGED'));
	}

	$paramRef = $class->restartServer($paramRef, Slim::Utils::PluginManager->needsRestart);

	$paramRef->{plugins}     = $plugins;
	$paramRef->{failsafe}    = $main::failsafe;

	$paramRef->{pluginState} = preferences('plugin.state')->all();

	# FIXME: temp remap new states to binary value:
	for my $plugin (keys %{$paramRef->{pluginState}}) {
		$paramRef->{pluginState}->{$plugin} = $paramRef->{pluginState}->{$plugin} =~ /enabled/;
	}

	my @sortedPlugins = 
		map { $_->[1] }
		sort { $a->[0] cmp $b->[0] }
		map { [ uc( Slim::Utils::Strings::getString($plugins->{$_}->{name}) ), $_ ] } 
		keys %$plugins;

	$paramRef->{sortedPlugins} = \@sortedPlugins;

	return $class->SUPER::handler($client, $paramRef);
}
=cut

sub getRestartMessage {
	my ($class, $paramRef, $noRestartMsg) = @_;
	
	# show a link/button to restart SC if this is supported by this platform
	if (main::canRestartServer()) {
				
		$paramRef->{'restartUrl'} = $paramRef->{webroot} . $paramRef->{path} . '?restart=1';
		$paramRef->{'restartUrl'} .= '&rand=' . $paramRef->{'rand'} if $paramRef->{'rand'};

		$paramRef->{'warning'} = '<span id="restartWarning">'
			. Slim::Utils::Strings::string('PLUGINS_CHANGED_NEED_RESTART', $paramRef->{'restartUrl'})
			. '</span>';

	}
	
	else {
	
		$paramRef->{'warning'} .= '<span id="popupWarning">'
			. $noRestartMsg
			. '</span>';
		
	}
	
	return $paramRef;	
}

sub restartServer {
	my ($class, $paramRef, $needsRestart) = @_;
	
	if ($needsRestart && $paramRef->{restart} && main::canRestartServer()) {
		
		$paramRef->{'warning'} = '<span id="popupWarning">'
			. Slim::Utils::Strings::string('RESTARTING_PLEASE_WAIT')
			. '</span>';
		
		# delay the restart a few seconds to return the page to the client first
		Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 2, \&_restartServer);
	}
	
	return $paramRef;
}

sub _restartServer {

	if (Slim::Utils::PluginDownloader->downloading) {

		Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 2, \&_restartServer);

	} else {

		main::restartServer();
	}
}

1;

__END__
