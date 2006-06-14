package Slim::Music::Import;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Class::Data::Inheritable);

use Config;
use FindBin qw($Bin);
use Proc::Background;
use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;

{
	my $class = __PACKAGE__;

	for my $accessor (qw(cleanupDatabase scanPlaylistsOnly useFolderImporter scanningProcess)) {

		$class->mk_classdata($accessor);
	}
}

# Total of how many file scanners are running
our %importsRunning = ();
our %Importers      = ();

my $folderScanClass = 'Slim::Music::MusicFolderScan';

sub launchScan {
	my ($class, $args) = @_;

	# Pass along the prefs file - might need to do this for other flags,
	# such as logfile as well.
	if (defined $::prefsfile && -r $::prefsfile) {
		$args->{"prefsfile=$::prefsfile"} = 1;
	}

	# Add in the various importer flags
	for my $importer (qw(itunes musicmagic moodlogic)) {

		if (Slim::Utils::Prefs::get($importer)) {

			$args->{$importer} = 1;
		}
	}

	my @scanArgs = map { "--$_" } keys %{$args};

	my $command  = "$Bin/scanner.pl";

	# Bug: 3530 - use the same version of perl we were started with.
	if ($Config{'perlpath'} && -x $Config{'perlpath'}) {

		unshift @scanArgs, $command;
		$command  = $Config{'perlpath'};
	}

	# Check for different scanner types.
	if (Slim::Utils::OSDetect::OS() eq 'win' && -x "$Bin/scanner.exe") {

		$command  = "$Bin/scanner.exe";

	} elsif (Slim::Utils::OSDetect::isDebian() && -x '/usr/sbin/slimserver-scanner') {

		$command  = '/usr/sbin/slimserver-scanner';
	}

	$class->scanningProcess(
		Proc::Background->new($command, @scanArgs)
	);

	return 1;
}

# Force a rescan of all the importers.
# This is called by the scanner.pl helper program.
sub startScan {
	my $class  = shift;
	my $import = shift;

	# If we are scanning a music folder, do that first - as we'll gather
	# the most information from files that way and subsequent importers
	# need to do less work.
	if ($Importers{$folderScanClass} && !$class->scanPlaylistsOnly) {

		$class->runImporter($folderScanClass, $import);

		$class->useFolderImporter(1);
	}

	# Check Import scanners
	for my $importer (keys %Importers) {

		# Don't rescan the music folder again.
		if ($importer eq $folderScanClass) {
			next;
		}

		# These importers all implement 'playlist only' scanning.
		# See bug: 1892
		if ($class->scanPlaylistsOnly && !$Importers{$importer}->{'playlistOnly'}) {
			next;
		}

		$class->runImporter($importer, $import);
	}

	$class->scanPlaylistsOnly(0);

	# Auto-identify VA/Compilation albums
	$::d_import && msg("Import: Starting mergeVariousArtistsAlbums().\n");

	$importsRunning{'mergeVariousAlbums'} = Time::HiRes::time();

	Slim::Schema->mergeVariousArtistsAlbums;

	# Remove and dangling references.
	if ($class->cleanupDatabase) {

		# Don't re-enter
		$class->cleanupDatabase(0);

		$importsRunning{'cleanupStaleEntries'} = Time::HiRes::time();

		Slim::Schema->cleanupStaleTrackEntries;
	}

	# Reset
	$class->useFolderImporter(0);

	$::d_import && msg("Import: Finished background scanning.\n");

	# This needs to be moved for split-scanner
	# Slim::Control::Request::notifyFromArray(undef, ['rescan', 'done']);
}

sub deleteImporter {
	my ($class, $importer) = @_;

	delete $Importers{$importer};
}

# addImporter takes hash ref of named function refs.
sub addImporter {
	my ($class, $importer, $params) = @_;

	$Importers{$importer} = $params;

	$::d_import && msgf("Import: Adding %s Scan\n", $importer);
}

sub runImporter {
	my ($class, $importer, $import) = @_;

	if ($Importers{$importer}->{'use'}) {

		if (!defined $import || (defined $import && ($importer eq $import))) {

			$importsRunning{$importer} = Time::HiRes::time();

			# rescan each enabled Import, or scan the newly enabled Import
			$::d_import && msgf("Import: Starting %s scan\n", $importer);

			$importer->startScan;
		}
	}
}

sub countImporters {
	my $class = shift;
	my $count = 0;

	for my $importer (keys %Importers) {
		
		# Don't count Folder Scan for this since we use this as a test to see if any other importers are in use
		if ($Importers{$importer}->{'use'} && $importer ne $folderScanClass) {

			$count++;
		}
	}

	return $count;
}

sub resetSetupGroups {
	my $class = shift;

	$class->walkImporterListForFunction('setup');
}

sub resetImporters {
	my $class = shift;

	$class->walkImporterListForFunction('reset');
}

sub walkImporterListForFunction {
	my $class    = shift;
	my $function = shift;

	for my $importer (keys %Importers) {

		if (defined $Importers{$importer}->{$function}) {
			&{$Importers{$importer}->{$function}};
		}
	}
}

sub importers {
	my $class = shift;

	return \%Importers;
}

sub useImporter {
	my ($class, $importer, $newValue) = @_;

	if (!$importer) {
		return 0;
	}

	if (defined $newValue && exists $Importers{$importer}) {

		$Importers{$importer}->{'use'} = $newValue;

	} else {

		return exists $Importers{$importer} ? $Importers{$importer} : 0;
	}
}

# End the main importers, such as Music Dir, iTunes, etc - and call
# post-processing steps in order if required.
sub endImporter {
	my ($class, $importer) = @_;

	if (exists $importsRunning{$importer}) { 

		$::d_import && msgf("Import: Completed %s Scan in %s seconds.\n",
			$importer, int(Time::HiRes::time() - $importsRunning{$importer})
		);

		delete $importsRunning{$importer};
	}
}

sub stillScanning {
	my $class   = shift;
	my $imports = scalar keys %importsRunning;

	if (blessed($class->scanningProcess) && $class->scanningProcess->alive) {
		return 1;
	} else {
		return 0;
	}

	if ($::d_import && $imports) {

		msg("Import: Scanning with $imports import plugins\n");

		while (my ($importer, $started) = each %importsRunning) {

			msgf("\t%s scan started at: %s\n", $importer, (localtime($started) . ''));
		}

		msg("\n");
	}

	return $imports;
}

1;

__END__
