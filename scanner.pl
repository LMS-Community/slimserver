#!/usr/bin/perl -w

# SlimServer Copyright (C) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin";
BEGIN {
	use bootstrap;

	bootstrap->loadModules(qw(Time::HiRes DBD::SQLite DBI XML::Parser));
};

use File::Spec::Functions qw(:ALL);

use Slim::Music::Import;
use Slim::Music::Info;
use Slim::Music::MusicFolderScan;
use Slim::Music::PlaylistFolderScan;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner;
use Slim::Utils::Strings qw(string);

use Plugins::iTunes::Importer;
use Plugins::MusicMagic::Importer;

sub main {

	our $d_info = 0;
	our $d_remotestream = 0;
	our $d_parse = 0;
	our $d_import = 1;
	our $d_server = 0;
	our $d_scan = 0;
	our $d_sql = 0;
	our $d_itunes = 0;
	our $LogTimestamp = 1;

	$::d_server && msg("SlimServer OSDetect init...\n");
	Slim::Utils::OSDetect::init();

	$::d_server && msg("SlimServer OS Specific init...\n");

	$SIG{'CHLD'} = 'IGNORE';
	$SIG{'PIPE'} = 'IGNORE';
	$SIG{'TERM'} = \&bootstrap::sigterm;
	$SIG{'INT'}  = \&bootstrap::sigint;
	$SIG{'QUIT'} = \&bootstrap::sigquit;

	# initialize slimserver subsystems
	$::d_server && msg("SlimServer settings init...\n");

	Slim::Utils::Prefs::init();
	Slim::Utils::Prefs::load();

	Slim::Utils::Prefs::set('prefsWriteDelay', 0);

	Slim::Utils::Prefs::checkServerPrefs();

	Slim::Utils::Prefs::makeCacheDir();	

	$::d_server && msg("SlimServer strings init...\n");
	Slim::Utils::Strings::init(catdir($Bin,'strings.txt'), "EN");

	$::d_server && msg("SlimServer Info init...\n");
	Slim::Music::Info::init();

	#
	Slim::Utils::Scanner->init;

	Slim::Music::MusicFolderScan->init;
	Slim::Music::PlaylistFolderScan->init;
	Plugins::iTunes::Importer->initPlugin;
	Plugins::MusicMagic::Importer->initPlugin;

	#$::d_server && msg("SlimServer Plugins init...\n");
	#Slim::Buttons::Plugins::init();

	#$::d_server && msg("SlimServer checkDataSource...\n");
	#checkDataSource();

	$::d_server && msg("SlimServer done init...\n");

	Slim::Music::Info::wipeDBCache();
	Slim::Music::Import->resetImporters;
	Slim::Music::Import->startScan;

	#Slim::Utils::Scanner->scanRemoteURL({
	#	'url' => 'http://www.somafm.com/groovesalad.pls',
	#});
}

sub cleanup {

	$::d_server && msg("SlimServer cleaning up.\n");

	# Make sure to flush anything in the database to disk.
	my $ds = Slim::Music::Info::getCurrentDataStore();

	if ($ds) {
		$ds->forceCommit;
	}
}

main();

__END__
