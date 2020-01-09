package Slim::Web::Settings::Server::Plugins;


# Logitech Media Server Copyright 2001-2020 Logitech.
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
