package Slim::Web::Settings::Server::Network;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

sub name {
	return 'NETWORK_SETTINGS';
}

sub page {
	return 'settings/server/networking.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	my @prefs = qw(
		webproxy
		httpport
		bufferSecs
		remotestreamtimeout
		maxWMArate
		tcpReadMaximum
		tcpWriteMaximum
		udpChunkSize
	);

	my $homeURL = Slim::Utils::Prefs::homeURL();

	# Bug 2724 - only show the mDNS settings if we have a binary for it.
	if (Slim::Utils::Misc::findbin('mDNSResponderPosix')) {

		push @prefs, 'mDNSname';
	}

	# If this is a settings update
	if ($paramRef->{'submit'}) {

		$paramRef->{'warning'} = "";

		if ($paramRef->{'httpport'} ne Slim::Utils::Prefs::get('httpport')) {
		
			if ($paramRef->{'httpport'} < 1025)  { $paramRef->{'httpport'}  = 1025 };
			if ($paramRef->{'httpport'} > 65535) { $paramRef->{'httpport'} = 65535 };
		
			Slim::Utils::Prefs::set('httpport', $paramRef->{'httpport'});

			$paramRef->{'warning'} .= join('',
				string("SETUP_HTTPPORT_OK"),
				'<blockquote><a target="_top" href="',
				$homeURL,
				'">',
				$homeURL,
				"</a></blockquote><br>"
			);
		}

		for my $pref (@prefs) {

			if ($pref =~ /^tcp/ || $pref eq 'validate') {

				if ($paramRef->{$pref} < 1) {

					$paramRef->{$pref} = 1
				}
			}

			if ($pref eq 'bufferSecs') {

				if ($paramRef->{'bufferSecs'} > 30) {

					$paramRef->{'bufferSecs'} = 30
				}

				if ($paramRef->{'bufferSecs'} < 3) {

					$paramRef->{'bufferSecs'} = 3
				}
			}

			if ($pref eq 'udpChunkSize') {

				if ($paramRef->{'udpChunkSize'} < 1) {

					$paramRef->{'udpChunkSize'} = 1
				}

				if ($paramRef->{'udpChunkSize'} > 4096) {

					$paramRef->{'udpChunkSize'} = 4096
				}
			}

			if ($paramRef->{$pref}) {

				Slim::Utils::Prefs::set($pref, $paramRef->{$pref});
			}
		}
	}

	for my $pref (@prefs) {

		$paramRef->{$pref} = Slim::Utils::Prefs::get($pref);
	}

	$paramRef->{'HomeURL'} = $homeURL;
	
	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
