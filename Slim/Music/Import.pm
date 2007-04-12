package Slim::Music::Import;

# SlimServer Copyright (c) 2001-2006  Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Music::Import

=head1 SYNOPSIS

	my $class = 'Slim::Plugin::iTunes::Importer';

	# Make an importer available for use.
	Slim::Music::Import->addImporter($class);

	# Turn the importer on or off
	Slim::Music::Import->useImporter($class, Slim::Utils::Prefs::get('itunes'));

	# Start a serial scan of all importers.
	Slim::Music::Import->runScan;
	Slim::Music::Import->runScanPostProcessing;

	if (Slim::Music::Import->stillScanning) {
		...
	}

=head1 DESCRIPTION

This class controls the actual running of the Importers as defined by a
caller. The process is serial, and is run via the L<scanner.pl> program.

=head1 METHODS

=cut

use strict;

use base qw(Class::Data::Inheritable);

use Config;
use FindBin qw($Bin);
use Proc::Background;
use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Utils::Log;
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
my $log             = logger('scan.import');

=head2 launchScan( \%args )

Launch the external (forked) scanning process.

\%args can include any of the arguments the scanning process can accept.

=cut

sub launchScan {
	my ($class, $args) = @_;

	# Pass along the prefsfile & logfile flags to the scanner.
	if (defined $::prefsfile && -r $::prefsfile) {
		$args->{"prefsfile=$::prefsfile"} = 1;
	}

	$args->{ "prefsdir=" . Slim::Utils::Prefs->dir } = 1;

	if (Slim::Utils::Log->writeConfig) {

		$args->{sprintf("logconfig=%s", Slim::Utils::Log->defaultConfigFile)} = 1;
	}

	if (defined $::logdir && -d $::logdir) {
		$args->{"logdir=$::logdir"} = 1;
	}

	# Add in the various importer flags
	for my $importer (qw(itunes musicmagic)) {

		if (Slim::Utils::Prefs::get($importer)) {

			$args->{$importer} = 1;
		}
	}

	# Set scanner priority.  Use the current server priority unless 
	# scannerPriority has been specified.

	my $scannerPriority = Slim::Utils::Prefs::get("scannerPriority");

	unless (defined $scannerPriority && $scannerPriority ne "") {
		$scannerPriority = Slim::Utils::Misc::getPriority();
	}

	if (defined $scannerPriority && $scannerPriority ne "") {
		$args->{"priority=$scannerPriority"} = 1;
	}

	my @scanArgs = map { "--$_" } keys %{$args};

	my $command  = "$Bin/scanner.pl";

	# Check for different scanner types.
	if (Slim::Utils::OSDetect::OS() eq 'win' && -x "$Bin/scanner.exe") {

		$command  = "$Bin/scanner.exe";

	} elsif (-x '/usr/sbin/slimserver-scanner') {

		$command  = '/usr/sbin/slimserver-scanner';
	}

	# Bug: 3530 - use the same version of perl we were started with.
	if ($Config{'perlpath'} && -x $Config{'perlpath'} && $command !~ /\.exe$/) {

		unshift @scanArgs, $command;
		$command  = $Config{'perlpath'};
	}

	$class->scanningProcess(
		Proc::Background->new($command, @scanArgs)
	);

	# Clear progress info so scan progress displays are blank
	$class->clearProgressInfo;

	# Update a DB flag, so the server knows we're scanning.
	$class->setIsScanning(1);

	# Set a timer to check on the scanning process.
	Slim::Utils::Timers::setTimer(0, (Time::HiRes::time() + 5), \&checkScanningStatus);

	return 1;
}

=head2 checkScanningStatus( )

If we're still scanning, start a timer process to notify any subscribers of a
'rescan done' status.

=cut

sub checkScanningStatus {
	my $class = shift || __PACKAGE__;

	Slim::Utils::Timers::killTimers(0, \&checkScanningStatus);

	# Run again if we're still scanning.
	if ($class->stillScanning) {

		Slim::Utils::Timers::setTimer(0, (Time::HiRes::time() + 5), \&checkScanningStatus);

	} else {

		# Clear caches, like the vaObj, etc after scanning has been finished.
		Slim::Schema->wipeCaches;

		Slim::Control::Request::notifyFromArray(undef, [qw(rescan done)]);
	}
}

=head2 lastScanTime()

Returns the last time the user ran a scan, or 0.

=cut

sub lastScanTime {
	my $class = shift;
	my $name  = shift || 'lastRescanTime';

	my $last  = Slim::Schema->single('MetaInformation', { 'name' => $name });

	return blessed($last) ? $last->value : 0;
}

=head2 setLastScanTime()

Set the last scan time.

=cut

sub setLastScanTime {
	my $class = shift;
	my $name  = shift || 'lastRescanTime';
	my $value = shift || time;

	eval { Slim::Schema->txn_do(sub {

		my $last = Slim::Schema->rs('MetaInformation')->find_or_create({
			'name' => $name
		});

		$last->value($value);
		$last->update;
	}) };
}

=head2 setIsScanning( )

Set a flag in the DB to true or false if the scanner is running.

=cut

sub setIsScanning {
	my $class = shift;
	my $value = shift;

	my $autoCommit = Slim::Schema->storage->dbh->{'AutoCommit'};

	if ($autoCommit) {
		Slim::Schema->storage->dbh->{'AutoCommit'} = 0;
	}

	eval { Slim::Schema->txn_do(sub {

		my $isScanning = Slim::Schema->rs('MetaInformation')->find_or_create({
			'name' => 'isScanning'
		});

		$isScanning->value($value);
		$isScanning->update;
	}) };

	if ($@) {

		logError("Failed to update isScanning: [$@]");
	}

	Slim::Schema->storage->dbh->{'AutoCommit'} = $autoCommit;
}

=head2 clearProgressInfo( )

Clear importer progress info stored in the database.

=cut

sub clearProgressInfo {
	my $class = shift;

	for my $prog (Slim::Schema->rs('Progress')->search({ 'type' => 'importer' })->all) {
		$prog->delete;
		$prog->update;
	}
}

=head2 runScan( )

Start a scan of all used importers.

This is called by the scanner.pl helper program.

=cut

sub runScan {
	my $class  = shift;

	# clear progress info in case scanner.pl is run standalone
	$class->clearProgressInfo;

	# If we are scanning a music folder, do that first - as we'll gather
	# the most information from files that way and subsequent importers
	# need to do less work.
	if ($Importers{$folderScanClass} && !$class->scanPlaylistsOnly) {

		$class->runImporter($folderScanClass);

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

			$log->warn("Skipping [$importer] - it doesn't implement playlistOnly scanning!");

			next;
		}

		$class->runImporter($importer);
	}

	$class->scanPlaylistsOnly(0);

	return 1;
}

=head2 runScanPostProcessing( )

This is called by the scanner.pl helper program.

Run the post-scan processing. This includes merging Various Artists albums,
finding artwork, cleaning stale db entries, and optimizing the database.

=cut

sub runScanPostProcessing {
	my $class  = shift;

	# Auto-identify VA/Compilation albums
	$log->info("Starting mergeVariousArtistsAlbums().");

	$importsRunning{'mergeVariousAlbums'} = Time::HiRes::time();

	Slim::Schema->mergeVariousArtistsAlbums;

	# Post-process artwork, so we can use title formats, and use a generic
	# image to speed up artwork loading.
	$log->info("Starting findArtwork().");

	$importsRunning{'findArtwork'} = Time::HiRes::time();

	Slim::Music::Artwork->findArtwork;

	# Remove and dangling references.
	if ($class->cleanupDatabase) {

		# Don't re-enter
		$class->cleanupDatabase(0);

		$importsRunning{'cleanupStaleEntries'} = Time::HiRes::time();

		Slim::Schema->cleanupStaleTrackEntries;
	}

	# Reset
	$class->useFolderImporter(0);

	# Always run an optimization pass at the end of our scan.
	$log->info("Starting Database optimization.");

	$importsRunning{'dbOptimize'} = Time::HiRes::time();

	Slim::Schema->optimizeDB;

	$class->endImporter('dbOptimize');

	$log->info("Finished background scanning.");

	return 1;
}

=head2 deleteImporter( $importer )

Removes a importer from the list of available importers.

=cut

sub deleteImporter {
	my ($class, $importer) = @_;

	delete $Importers{$importer};
}

=head2 addImporter( $importer, \%params )

Add an importer to the system. Valid params are:

=over 4

=item * use => 1 | 0

Shortcut to use / not use an importer. Same functionality as L<useImporter>.

=item * reset => \&code

Code reference to reset the state of the importer.

=item * playlistOnly => 1 | 0

True if the importer supports scanning playlists only.

=item * mixer => \&mixerFunction

Generate a mix using criteria from the client's parentParams or
modeParamStack.

=item * mixerlink => \&mixerlink

Generate an HTML link for invoking the mixer.

=back

=cut

sub addImporter {
	my ($class, $importer, $params) = @_;

	$Importers{$importer} = $params;

	$log->info("Adding $importer Scan");
}

=head2 runImporter( $importer )

Calls the importer's startScan() method, and adds a start time to the list of
running importers.

=cut

sub runImporter {
	my ($class, $importer) = @_;

	if ($Importers{$importer}->{'use'}) {

		$importsRunning{$importer} = Time::HiRes::time();

		# rescan each enabled Import, or scan the newly enabled Import
		$log->info("Starting $importer scan");

		$importer->startScan;

		return 1;
	}

	return 0;
}

=head2 countImporters( )

Returns a count of all added and available importers. Excludes
L<Slim::Music::MusicFolderScan>, as it is our base importer.

=cut

sub countImporters {
	my $class = shift;
	my $count = 0;

	for my $importer (keys %Importers) {
		
		# Don't count Folder Scan for this since we use this as a test to see if any other importers are in use
		if ($Importers{$importer}->{'use'} && $importer ne $folderScanClass) {

			$log->info("Found importer: $importer");

			$count++;
		}
	}

	return $count;
}

=head2 resetImporters( )

Run the 'reset' function as defined by each importer.

=cut

sub resetImporters {
	my $class = shift;

	$class->_walkImporterListForFunction('reset');
}

sub _walkImporterListForFunction {
	my $class    = shift;
	my $function = shift;

	for my $importer (keys %Importers) {

		if (defined $Importers{$importer}->{$function}) {
			&{$Importers{$importer}->{$function}};
		}
	}
}

=head2 importers( )

Return a hash reference to the list of added importers.

=cut

sub importers {
	my $class = shift;

	return \%Importers;
}

=head2 useImporter( $importer, $trueOrFalse )

Tell the server to use / not use a previously added importer.

=cut

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

=head2 endImporter( $importer )

Removes the given importer from the running importers list.

=cut

sub endImporter {
	my ($class, $importer) = @_;

	if (exists $importsRunning{$importer}) { 

		$log->info(sprintf("Completed %s Scan in %s seconds.",
			$importer, int(Time::HiRes::time() - $importsRunning{$importer})
		));

		delete $importsRunning{$importer};

		return 1;
	}

	return 0;
}

=head2 stillScanning( )

Returns true if the server is still scanning your library. False otherwise.

=cut

sub stillScanning {
	my $class    = shift;
	my $imports  = scalar keys %importsRunning;

	# NB: Some plugins call this, but haven't updated to use class based calling.
	if (!$class) {

		$class = __PACKAGE__;

		logBacktrace("Caller needs to be updated to use ->stillScanning, not ::stillScanning()!");
	}

	# Check and see if there is a flag in the database, and the process is alive.
	my $scanRS   = Slim::Schema->single('MetaInformation', { 'name' => 'isScanning' });
	my $scanning = blessed($scanRS) ? $scanRS->value : 0;

	my $running  = blessed($class->scanningProcess) && $class->scanningProcess->alive ? 1 : 0;

	if ($running && $scanning) {
		return 1;
	}

	return 0;
}

=head1 SEE ALSO

L<Slim::Music::MusicFolderScan>

L<Slim::Music::PlaylistFolderScan>

L<Slim::Plugin::iTunes::Importer>

L<Slim::Plugin::MusicMagic::Importer>

L<Proc::Background>

=cut

1;

__END__
