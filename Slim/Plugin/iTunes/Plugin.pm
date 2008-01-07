package Slim::Plugin::iTunes::Plugin;

# SqueezeCenter Copyright 2001-2007 Logitech.
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
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.itunes',
	'defaultLevel' => 'ERROR',
});

my $prefs = preferences('plugin.itunes');

sub getDisplayName {
	return 'SETUP_ITUNES';
}

sub initPlugin {
	my $class = shift;

	Slim::Plugin::iTunes::Settings->new;

	return 1 if $class->initialized;

	Slim::Plugin::iTunes::Settings->new;

	if (!$class->canUseiTunesLibrary) {
		return;
	}

	# default to on if not previously set
	$prefs->set('itunes', 1) unless defined $prefs->get('itunes');

	Slim::Player::ProtocolHandlers->registerHandler('itunesplaylist', 0);

	$class->initialized(1);
	$class->checker(1);

	return 1;
}

sub shutdownPlugin {
	my $class = shift;

	# turn off checker
	Slim::Utils::Timers::killTimers(undef, \&checker);

	# disable protocol handler
	Slim::Player::ProtocolHandlers->registerHandler('itunesplaylist', 0);

	$class->initialized(0);

	# set importer to not use
	Slim::Music::Import->useImporter($class, 0);
}

sub checker {
	my $class     = shift;
	my $firstTime = shift || 0;

	if (!$prefs->get('itunes')) {

		return 0;
	}

	if (!$firstTime && !Slim::Music::Import->stillScanning && __PACKAGE__->isMusicLibraryFileChanged) {

		Slim::Control::Request::executeRequest(undef, ['rescan']);
	}

	# make sure we aren't doing this more than once...
	Slim::Utils::Timers::killTimers(undef, \&checker);

	my $interval = $prefs->get('scan_interval') || 3600;

	# the very first time, we do want to scan right away
	if ($firstTime) {
		$interval = 10;
	}

	$log->info("setting checker for $interval seconds from now.");

	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + $interval, \&checker);
}

1;

__END__
