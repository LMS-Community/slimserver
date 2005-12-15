package Slim::Control::Queries;

# $Id: Command.pm 5121 2005-11-09 17:07:36Z dsully $
#
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use Slim::Control::Request;
use Slim::Music::Import;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

sub prefQuery {
	my $request = shift;
	
	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotQuery(['pref'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# use positional parameters as backups
	my $prefName = $request->getParam('prefName') || $request->getParam('_p1');
	
	if (!defined $prefName) {
		$request->setStatusBadParams();
		return;
	}

	my $isValue = Slim::Utils::Prefs::get($prefName);
	
	$request->addResult('isValue', $isValue);
	
	$request->setStatusDone();
}

sub playerprefQuery {
	my $request = shift;
	
	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotQuery(['playerpref'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# use positional parameters as backups
	my $client   = $request->client();
	my $prefName = $request->getParam('prefName') || $request->getParam('_p1');
	
	if (!defined $client || !defined $prefName) {
		$request->setStatusBadParams();
		return;
	}

	my $isValue = $client->prefGet($prefName);
	
	$request->addResult('isValue', $isValue);
	
	$request->setStatusDone();
}

sub rescanQuery {
	my $request = shift;
	
	if ($request->isNotQuery(['rescan'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no params for the rescan query

	my $isValue = Slim::Music::Import::stillScanning() ? 1 : 0;
	
	$request->addResult('isValue', $isValue);
	
	$request->setStatusDone();
}

sub versionQuery {
	my $request = shift;
	
	if ($request->isNotQuery(['version'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no params for the version query

	my $isValue = $::VERSION;
	
	$request->addResult('isValue', $isValue);
	
	$request->setStatusDone();
}

sub debugQuery {
	my $request = shift;
	
	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotQuery(['debug'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# use positional parameters as backups
	my $debugFlag = $request->getParam('debugFlag') || $request->getParam('_p1');
	
	if ( !defined $debugFlag || !($debugFlag =~ /^d_/) ) {
		$request->setStatusBadParams();
		return;
	}
	
	$debugFlag = "::" . $debugFlag;
	no strict 'refs';
	
	my $isValue = $$debugFlag;
	$isValue ||= 0;
	
	$request->addResult('isValue', $isValue);
	
	$request->setStatusDone();
}

sub infototalQuery {
	my $request = shift;
	
	# check this is the correct command.
	if ($request->isNotQuery(['info'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# use positional parameters as backups
	my $total  = $request->getParam('total') || $request->getParam('_p1');
	my $entity = $request->getParam('entity') || $request->getParam('_p2');

	if (!defined $total || $total ne 'total') {
		$request->setStatusBadParams();
		return;
	}		
	
	# get the DB
	my $ds = Slim::Music::Info::getCurrentDataStore();
	
	if (!defined $entity || $entity eq 'genres') {
		$request->addResult('genres', $ds->count('genre'));
	}
	if (!defined $entity || $entity eq 'artists') {
		$request->addResult('artists', $ds->count('contributor'));
	}
	if (!defined $entity || $entity eq 'albums') {
		$request->addResult('albums', $ds->count('album'));
	}
	if (!defined $entity || $entity eq 'songs') {
		$request->addResult('songs', $ds->count('track'));
	}			
	
	$request->setStatusDone();
}

sub sleepQuery {
	my $request = shift;
	
	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotQuery(['sleep'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();
	
	if (!defined $client) {
		$request->setStatusBadParams();
		return;
	}

	my $isValue = $client->sleepTime() - Time::HiRes::time();
	if ($isValue < 0) {
		$isValue = 0;
	}
	
	$request->addResult('isValue', $isValue);
	
	$request->setStatusDone();
}

sub modeQuery {
	my $request = shift;
	
	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotQuery(['mode'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();
	
	if (!defined $client) {
		$request->setStatusBadParams();
		return;
	}

	my $isValue = Slim::Player::Source::playmode($client);
	
	$request->addResult('isValue', $isValue);
	
	$request->setStatusDone();
}

sub connectedQuery {
	my $request = shift;
	
	# check this is the correct command.
	if ($request->isNotQuery(['connected'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();
	
	if (!defined $client) {
		$request->setStatusBadParams();
		return;
	}

	my $isValue = $client->connected() || 0;
	
	$request->addResult('isValue', $isValue);
	
	$request->setStatusDone();
}

sub signalstrengthQuery {
	my $request = shift;
	
	# check this is the correct command.
	if ($request->isNotQuery(['signalstrength'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();
	
	if (!defined $client) {
		$request->setStatusBadParams();
		return;
	}

	my $isValue = $client->signalStrength() || 0;
	
	$request->addResult('isValue', $isValue);
	
	$request->setStatusDone();
}


1;

__END__
