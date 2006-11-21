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

use FormValidator::Simple;

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

	if ($paramRef->{'validate'}) {

		my $result = FormValidator::Simple->check($paramRef => [
			'webproxy' => [ 'HTTP_URL' ],
		]);

		#$paramRef->{'result'} = $result;
		if ($result->has_error) {
			
			return \"webproxy is invalid!";
		} else {
			return \"";
		}
	}

	my $homeURL = Slim::Utils::Prefs::homeURL();

	# Bug 2724 - only show the mDNS settings if we have a binary for it.
	if (Slim::Utils::Misc::findbin('mDNSResponderPosix')) {

		push @prefs, 'mDNSname';
	}

	# If this is a settings update
	if ($paramRef->{'submit'}) {

		my $result = FormValidator::Simple->check($paramRef => [
			'httpport'            => [ 'NOT_BLANK', 'INT', [ 'BETWEEN', 1025, 65535 ] ],
			'tcpReadMaximum'      => [ 'NOT_BLANK', 'INT', [ 'BETWEEN', 1, 65535 ] ],
			'tcpWriteMaximum'     => [ 'NOT_BLANK', 'INT', [ 'BETWEEN', 1, 65535 ] ],
			'bufferSecs'          => [ 'NOT_BLANK', 'INT', [ 'BETWEEN', 3, 30 ] ],
			'udpChunkSize'        => [ 'NOT_BLANK', 'INT', [ 'BETWEEN', 1, 4096 ] ],
			'remotestreamtimeout' => [ 'NOT_BLANK', 'INT', [ 'BETWEEN', 0, 600 ] ],
			'maxWMArate'          => [ 'NOT_BLANK', 'INT', [ 'BETWEEN', 0, 9999 ] ],
			'webproxy'            => [ 'HTTP_URL' ],
		]);

		$paramRef->{'warning'} = "";

		if ($paramRef->{'httpport'} ne Slim::Utils::Prefs::get('httpport')) {

			Slim::Utils::Prefs::set('httpport', $paramRef->{'httpport'});
		}

		for my $pref (@prefs) {

			if ($paramRef->{$pref}) {

				Slim::Utils::Prefs::set($pref, $paramRef->{$pref});
			}
		}

		#$paramRef->{'result'} = $result;
	}

	for my $pref (@prefs) {

		$paramRef->{$pref} = Slim::Utils::Prefs::get($pref);
	}

	$paramRef->{'HomeURL'} = $homeURL;
	
	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
