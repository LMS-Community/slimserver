package Slim::Music::Import;

# Logitech Media Server Copyright 2001-2011 Logitech.
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
	Slim::Music::Import->useImporter($class, $prefs->get('itunes'));

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
use File::Spec::Functions;
use FindBin qw($Bin);
use Proc::Background;
use Scalar::Util qw(blessed);

use Slim::Music::Artwork;
use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Progress;

{
	if (main::ISWINDOWS) {
		require Win32;
	}
}

{
	my $class = __PACKAGE__;

	for my $accessor (qw(cleanupDatabase scanPlaylistsOnly scanningProcess doQueueScanTasks)) {

		$class->mk_classdata($accessor);
	}
}

# Total of how many file scanners are running
our %importsRunning = ();
our %Importers      = ();

my $log             = logger('scan.import');
my $prefs           = preferences('server');

my %scanQueue;
my $ABORT = 0;

=head2 launchScan( \%args )

Launch the external (forked) scanning process.

\%args can include any of the arguments the scanning process can accept.

=cut

sub launchScan {
	my ($class, $args) = @_;
	
	# Don't launch the scanner unless there is something to scan
	if (!$class->countImporters()) {
		return 1;
	}

	# Pass along the prefsfile & logfile flags to the scanner.
	if (defined $::prefsfile && -r $::prefsfile) {
		$args->{"prefsfile=$::prefsfile"} = 1;
	}

	# Bug 16188 - ensure loaded protocol handlers are known by scanner process by saving in a pref
	$prefs->set('registeredhandlers', [ Slim::Player::ProtocolHandlers->registeredHandlers ]);

	Slim::Utils::Prefs->writeAll;

	my $path = Slim::Utils::OSDetect::getOS->decodeExternalHelperPath(
		Slim::Utils::Prefs->dir
	);
	
	$args->{ "prefsdir=$path" } = 1;

	if ( my $logconfig = Slim::Utils::Log->defaultConfigFile ) {

		$args->{ "logconfig=$logconfig" } = 1;
	}

	if (defined $::logdir && -d $::logdir) {
		$args->{"logdir=$::logdir"} = 1;
	}
	
	$args->{'noimage'} = 1 if !(main::IMAGE && main::MEDIASUPPORT);
	$args->{'novideo'} = 1 if !(main::VIDEO && main::MEDIASUPPORT);

	# Set scanner priority.  Use the current server priority unless 
	# scannerPriority has been specified.

	my $scannerPriority = $prefs->get('scannerPriority');

	unless (defined $scannerPriority && $scannerPriority ne "") {
		$scannerPriority = Slim::Utils::Misc::getPriority();
	}

	if (defined $scannerPriority && $scannerPriority ne "") {
		$args->{"priority=$scannerPriority"} = 1;
	}
	
	# bug 17639 - pass singledir value if defined
	my $singledir = delete $args->{singledir} || '';

	my @scanArgs = map { "--$_" } keys %{$args};

	my $command  = Slim::Utils::OSDetect::getOS->scanner();

	# Bug: 3530 - use the same version of perl we were started with.
	if ($Config{'perlpath'} && -x $Config{'perlpath'} && $command !~ /\.exe$/) {

		unshift @scanArgs, $command;
		$command  = $Config{'perlpath'};
	}
	
	# Pass debug flags to scanner
	my $debugArgs = '';
	my $scannerLogOptions = Slim::Utils::Log->getScannerLogOptions();
	 
	foreach (keys %$scannerLogOptions) {
		$debugArgs .= $_ . '=' . $scannerLogOptions->{$_} . ',' if defined $scannerLogOptions->{$_};
	}
	
	if ( $main::debug ) {
		$debugArgs .= $main::debug;
	}
	
	if ( $debugArgs ) {
		$debugArgs =~ s/,$//;
		push @scanArgs, '--debug', $debugArgs;
	}
	
	if ( $singledir ) {
		push @scanArgs, $singledir;
	}
	
	$class->setIsScanning($args->{wipe} ? 'SETUP_WIPEDB' : 'SETUP_STANDARDRESCAN');
	
	$class->scanningProcess(
		Proc::Background->new($command, @scanArgs)
	);
	
	return 1;
}

=head2 abortScan()

Stop the external (forked) scanning process.

=cut

sub abortScan {
	my $class = shift || __PACKAGE__;
	
	if ( $class->stillScanning ) {
		# Tell scanner to shut down the next time
		# we get a progress update
		$ABORT = 1;
		
		$class->setIsScanning(0) if !$class->externalScannerRunning;
		$class->clearScanQueue;
		
		Slim::Control::Request::notifyFromArray( undef, [ 'rescan', 'done' ] );
	}
}

sub hasAborted { $ABORT }

sub setAborted { shift; $ABORT = shift; }

sub externalScannerRunning {
	my $class = shift;
	
	return 1 if main::SCANNER;
	
	return (blessed($class->scanningProcess) && $class->scanningProcess->alive) ? 1 : 0;
}

=head2 lastScanTime()

Returns the last time the user ran a scan, or 0.

=cut

sub lastScanTime {
	my $class = shift;
	my $name  = shift || 'lastRescanTime';

	# May not have a DB
	return 0 if !Slim::Schema::hasLibrary();
	
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
	
	# May not have a DB to store this in
	return if !Slim::Schema::hasLibrary();
	
	my $last = Slim::Schema->rs('MetaInformation')->find_or_create( {
		'name' => $name
	} );

	$last->value($value);
	$last->update;
}

=head2 setLastScanTimeIsDST()

Set flag whether a scan happened in DST or not.
We'll need this on Windows, which has a bug handling file's mtime and DST.

=cut

sub setLastScanTimeIsDST {
	my $class = shift;

	# May not have a DB to store this in
	return if !Slim::Schema::hasLibrary();
	
	my $last = Slim::Schema->rs('MetaInformation')->find_or_create( {
		'name' => 'lastRescanTimeIsDST'
	} );

	$last->value( (localtime(time()))[8] ? 1 : 0 );
	$last->update;
}

sub getLastScanTimeIsDST {
	my $class = shift;
	return $class->lastScanTime('lastRescanTimeIsDST');
}

=head2 setIsScanning( )

Set a flag in the DB to true or false if the scanner is running.

=cut

sub setIsScanning {
	my $class = shift;
	my $value = shift;

	# May not have a DB to store this in
	return if !Slim::Schema::hasLibrary();

	my $isScanning = Slim::Schema->rs('MetaInformation')->find_or_create({
		'name' => 'isScanning'
	});

	$isScanning->value($value);
	$isScanning->update;

	if ($@) {
		logError("Failed to update isScanning: [$@]");
	}
}

=head2 clearProgressInfo( )

Clear importer progress info stored in the database.

XXX - only here for backwards compatibility (v7.6). This has been replaced by Slim::Utils::Progress->clear

=cut

sub clearProgressInfo {
	Slim::Utils::Progress->clear();
}

=head2 runScan( )

Start a scan of all used importers.

This is called by the scanner.pl helper program.

=cut

sub runScan {
	my $class  = shift;
	
	my $changes = 0;

	# clear progress info in case scanner.pl is run standalone
	Slim::Utils::Progress->clear;

	# Check Import scanners
	for my $importer ( _sortedImporters() ) {
		# Skip non-file scanners
		if ( !$Importers{$importer}->{type} || $Importers{$importer}->{type} ne 'file' ) {
			next;
		}

		# These importers all implement 'playlist only' scanning.
		# See bug: 1892
		if ($class->scanPlaylistsOnly && !$Importers{$importer}->{'playlistOnly'}) {

			$log->warn("Skipping [$importer] - it doesn't implement playlistOnly scanning!");

			next;
		}

		# XXX tmp var is to avoid a strange "Can't coerce CODE to integer in addition (+)" error/bug
		# even though there is no way this returns a coderef...
		my $tmp = $class->runImporter($importer);
		$changes += $tmp;
	}

	$class->scanPlaylistsOnly(0);

	return $changes;
}

sub _sortedImporters {
	return sort {
		my $wa = exists $Importers{$a}->{weight} ? $Importers{$a}->{weight} : 1000;
		my $wb = exists $Importers{$b}->{weight} ? $Importers{$b}->{weight} : 1000;
		return $wa <=> $wb;
	} keys %Importers;
}

=head2 runScanPostProcessing( )

This is called by the scanner.pl helper program.

Run the post-scan processing. This includes merging Various Artists albums,
finding artwork, cleaning stale db entries, and optimizing the database.

=cut

sub runScanPostProcessing {
	my $class  = shift;

	# May not have a DB to store this in
	return 1 if !Slim::Schema::hasLibrary();
	
	if (main::STATISTICS) {
		# Look for and import persistent data migrated from MySQL
		my ($dir) = Slim::Utils::OSDetect::dirsFor('prefs');
		my $json = catfile( $dir, 'tracks_persistent.json' );
		if ( -e $json ) {
			$log->error('Migrating persistent track information from MySQL');
			
			if ( Slim::Schema::TrackPersistent->import_json($json) ) {
				unlink $json;
			}
		}
	}
	
	# Run any post-scan importers
	for my $importer ( _sortedImporters() ) {		
		# Skip non-post scanners
		if ( !$Importers{$importer}->{type} || $Importers{$importer}->{type} ne 'post' ) {
			next;
		}
		
		$class->runImporter($importer);
	}
	
	# Run any artwork importers
	for my $importer ( _sortedImporters() ) {		
		# Skip non-artwork scanners
		if ( !$Importers{$importer}->{type} || $Importers{$importer}->{type} ne 'artwork' ) {
			next;
		}
		
		$class->runArtworkImporter($importer);
	}

	# If we ever find an artwork provider...
	#Slim::Music::Artwork->downloadArtwork();

	# update standalone artwork if it's been changed without the music file being changed (don't run on a wipe & rescan)
	Slim::Music::Artwork->updateStandaloneArtwork() unless $class->stillScanning =~ /wipe/i;
	
	# Pre-cache resized artwork
	$importsRunning{'precacheArtwork'} = Time::HiRes::time();
	Slim::Music::Artwork->precacheAllArtwork;
		
	# Always run an optimization pass at the end of our scan.
	$log->error("Starting Database optimization.");

	$importsRunning{'dbOptimize'} = Time::HiRes::time();

	Slim::Schema->optimizeDB;

	$class->endImporter('dbOptimize');

	main::INFOLOG && $log->info("Finished background scanning.");

	return 1;
}

=head2 deleteImporter( $importer )

Removes a importer from the list of available importers.

=cut

sub deleteImporter {
	my ($class, $importer) = @_;

	delete $Importers{$importer};
	
	$class->_checkLibraryStatus();
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

	main::INFOLOG && $log->info("Adding $importer Scan");
	
	$class->_checkLibraryStatus();
}

=head2 runImporter( $importer )

Calls the importer's startScan() method, and adds a start time to the list of
running importers.

=cut

sub runImporter {
	my ($class, $importer) = @_;
	
	my $changes = 0;

	if ($Importers{$importer}->{'use'}) {

		$importsRunning{$importer} = Time::HiRes::time();

		# rescan each enabled Import, or scan the newly enabled Import
		$log->error("Starting $importer scan");

		$changes = $importer->startScan;
	}

	return $changes;
}

=head2 runArtworkImporter( $importer )

Calls the importer's startArtworkScan() method, and adds a start time to the list of
running importers.

=cut

sub runArtworkImporter {
	my ($class, $importer) = @_;

	if ($Importers{$importer}->{'use'}) {

		$importsRunning{$importer} = Time::HiRes::time();

		# rescan each enabled Import, or scan the newly enabled Import
		$log->error("Starting $importer artwork scan");
		
		$importer->startArtworkScan;

		return 1;
	}

	return 0;
}

=head2 countImporters( )

Returns a count of all added and available importers.

=cut

sub countImporters {
	my $class = shift;
	my $count = 0;

	for my $importer (keys %Importers) {
		
		if ($Importers{$importer}->{'use'}) {

			main::INFOLOG && $log->info("Found importer: $importer");

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

		if ( $newValue ) {
			$class->_checkLibraryStatus();
		}

		return $newValue;

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

		$log->error(sprintf("Completed %s Scan in %s seconds.",
			$importer, int(Time::HiRes::time() - $importsRunning{$importer})
		));

		delete $importsRunning{$importer};
		
		Slim::Schema->forceCommit;

		return 1;
	}

	return 0;
}

=head2 stillScanning( )

Returns scan type string token if the server is still scanning your library. False otherwise.

=cut

sub stillScanning {
	my $class = __PACKAGE__;
	
	return 0 if main::SLIM_SERVICE;
	return 0 if !Slim::Schema::hasLibrary();
	
	# clean up progress etc. in case the external scanner crashed
	if (blessed($class->scanningProcess) && !$class->scanningProcess->alive) {
		$class->scanningProcess(undef);
		$class->setIsScanning(0);
		
		Slim::Utils::Progress->cleanup('importer');
		Slim::Control::Request::notifyFromArray( undef, [ 'rescan', 'done' ] );
		
		return 0;
	}
	
	my $sth = Slim::Schema->dbh->prepare_cached(
		"SELECT value FROM metainformation WHERE name = 'isScanning'"
	);
	$sth->execute;
	my ($value) = $sth->fetchrow_array;
	$sth->finish;
	
	return $value || 0;
}

sub _checkLibraryStatus {
	my $class = shift;
	
	if ($class->countImporters()) {
		Slim::Schema->init() if !Slim::Schema::hasLibrary();
	} else {
		Slim::Schema->disconnect() if Slim::Schema::hasLibrary();
	}
	
	return if main::SCANNER;
	
	# Tell everyone who needs to know
	Slim::Control::Request::notifyFromArray(undef, ['library', 'changed', Slim::Schema::hasLibrary() ? 1 : 0]);
}

# create queue of scan tasks - trigger next queued scan once a scan has finished
sub initScanQueue {
	my $class = shift;

	if ( %scanQueue || main::SLIM_SERVICE || main::SCANNER ) {
		main::DEBUGLOG && $log->debug("don't initialize queue - we're slimservice or scanner or already initialized");
		return;
	}
	
	require Tie::IxHash;
	
	tie (%scanQueue, "Tie::IxHash");

	main::DEBUGLOG && $log->debug("initialize scan queue");

	Slim::Control::Request::subscribe( \&nextScanTask, [['rescan'], ['done']] );
}

sub nextScanTask {
	return if main::SLIM_SERVICE || main::SCANNER || __PACKAGE__->stillScanning;
	
	my @keys = keys %scanQueue;
	
	my $k    = shift @keys;
	my $next = delete $scanQueue{$k};
	
	main::DEBUGLOG && $log->debug('triggering next scan: ' . $k) if $k && $next;

	$next->execute() if $next;

	main::DEBUGLOG && $log->is_debug && $log->debug('remaining scans in queue:' . Data::Dump::dump(%scanQueue));
}

sub queueScanTask {
	my ($class, $request) = @_;
	
	if ( main::SLIM_SERVICE || main::SCANNER || !$request || $request->isNotCommand([['wipecache', 'rescan']]) ) {
		$log->error('do not add scan, we are slimservice or scanner or there is no valid request');
		return;
	}

	$class->initScanQueue();

	# no need to queue anything if a wipecache or full rescan is already in the pipeline
	if ( $scanQueue{wipecache} || ($request->isCommand([['rescan']]) && $scanQueue{'rescan||'}) ) {
		main::DEBUGLOG && $log->debug(($scanQueue{wipecache} ? 'wipecache' : 'full rescan') . ' is in queue - nothing to do!');
		return;
	}

	if ( $request->isCommand([['rescan']]) ) {
		my $type      = 'rescan';
		my $mode      = $request->getParam('_mode') || '';
		my $singledir = $request->getParam('_singledir') || '';

		# rescan of everything - remove existing scans
		if ($mode eq '' && $singledir eq '') {
			main::DEBUGLOG && $log->debug('full rescan requested, wipe queue');
			$class->clearScanQueue;
		}

		my $k = "$type|$mode|$singledir";
		
		# no need to add duplicate scan
		if ( $scanQueue{$k} ) {
			main::DEBUGLOG && $log->debug("scan $k is already in queue - skip it");
			return;
		}

		main::DEBUGLOG && $log->debug("adding scan $k to queue");
		$scanQueue{$k} = $request->virginCopy();
	}
	elsif ( $request->isCommand([['wipecache']]) ) {
		main::DEBUGLOG && $log->debug('full wipecache requested, wipe queue');

		# wipecache removes all existing rescans from the queue
		$class->clearScanQueue;

		$scanQueue{wipecache} = $request->virginCopy();
	}
	else {
		$log->error('No scan request - we should not get here: ' . Data::Dump::dump($request));
	}
}

sub clearScanQueue {
	main::DEBUGLOG && $log->is_debug && $log->debug('clearing queue:' . Data::Dump::dump(%scanQueue));
	%scanQueue = () if %scanQueue;
}

=head1 SEE ALSO

L<Slim::Media::MediaFolderScan>

L<Slim::Music::PlaylistFolderScan>

L<Slim::Plugin::iTunes::Importer>

L<Slim::Plugin::MusicMagic::Importer>

L<Proc::Background>

=cut

1;

__END__
