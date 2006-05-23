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

use Slim::Utils::Misc;

use Slim::Control::Request;


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

sub rescanQuery {
	my $request = shift;
	
	if ($request->isNotQuery(['rescan'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no params for the rescan query

	my $isValue = Slim::Utils::Misc::stillScanning() ? 1 : 0;
	
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


1;
