package Slim::Plugin::iTunes::Plugin;

# SlimServer Copyright (C) 2001-2005 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::iTunes::Common);

use Slim::Plugin::iTunes::Settings;

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.itunes',
	'defaultLevel' => 'WARN',
});

sub getDisplayName {
	return 'SETUP_ITUNES';
}

sub enabled {
	return ($::VERSION ge '6.1');
}

sub getFunctions {
	return '';
}

sub initPlugin {
	my $class = shift;

	return 1 if $class->initialized;

	if (!$class->canUseiTunesLibrary) {
		return;
	}

	Slim::Player::ProtocolHandlers->registerHandler('itunesplaylist', 0);

	Slim::Music::Import->addImporter($class, { 'use' => 1 });

	Slim::Plugin::iTunes::Settings->new;

	$class->initialized(1);
	$class->checker(1);

	return 1;
}

sub shutdownPlugin {
	my $class = shift;

	# turn off checker
	Slim::Utils::Timers::killTimers(0, \&checker);

	# disable protocol handler
	Slim::Player::ProtocolHandlers->registerHandler('itunesplaylist', 0);

	$class->initialized(0);

	# set importer to not use
	Slim::Music::Import->useImporter($class, 0);
}

sub checker {
	my $class     = shift;
	my $firstTime = shift || 0;

	if (!Slim::Utils::Prefs::get('itunes')) {

		return 0;
	}

	if (!$firstTime && !Slim::Music::Import->stillScanning && __PACKAGE__->isMusicLibraryFileChanged) {

		Slim::Control::Request::executeRequest(undef, ['rescan']);
	}

	# make sure we aren't doing this more than once...
	Slim::Utils::Timers::killTimers(0, \&checker);

	my $interval = Slim::Utils::Prefs::get('itunesscaninterval') || 3600;

	# the very first time, we do want to scan right away
	if ($firstTime) {
		$interval = 10;
	}

	$log->info("setting checker for $interval seconds from now.");

	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $interval, \&checker);
}

1;

__END__
