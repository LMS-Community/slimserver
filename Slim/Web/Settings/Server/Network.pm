package Slim::Web::Settings::Server::Network;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub name {
	return 'NETWORK_SETTINGS';
}

sub page {
	return 'settings/server/networking.html';
}

sub prefs {
	my @prefs = qw(webproxy httpport bufferSecs remotestreamtimeout maxWMArate);

	# Bug 2724 - only show the mDNS settings if we have a binary for it.
	if (Slim::Utils::Misc::findbin('mDNSResponderPosix')) {
		push @prefs, 'mDNSname';
	}

	# only show following for SLIMP3
	if ($Slim::Player::SLIMP3::SLIMP3Connected) {
		push @prefs, 'udpChunkSize';
	}

	return ($prefs, @prefs);
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	if ($paramRef->{'saveSettings'} && $paramRef->{'httpport'} ne $prefs->get('httpport')) {

		my (undef, $ok) = $prefs->set('httpport', $paramRef->{'httpport'});

		if ($ok) {
			my $homeURL = Slim::Utils::Prefs::homeURL();

			$paramRef->{'warning'} .= join('',
				string("SETUP_HTTPPORT_OK"),
				'<blockquote><a target="_top" href="',
				$homeURL,
				'">',
				$homeURL,
				"</a></blockquote><br>"
			);
		}
		# warning for invalid value created by base class
	}

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
