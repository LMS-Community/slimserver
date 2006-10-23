package Slim::Hardware::IR;

# $Id$

# SlimServer Copyright (c) 2001-2006  Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Hardware::IR

=head1 DESCRIPTION

L<Slim::Hardware::IR>

=cut

use strict;

use File::Basename;
use Path::Class;
use Time::HiRes qw(gettimeofday);

use Slim::Buttons::Common;
use Slim::Utils::Log;
use Slim::Utils::Misc;

my %irCodes = ();
my %irMap   = ();

my @irQueue = ();

my @buttonPressStyles = ('', '.single', '.double', '.repeat', '.hold', '.hold_release');
my $defaultMapFile;

# If time between IR commands is greater than this, then the code is considered a new button press
our $IRMINTIME  = 0.140;

# bumped up to a full second, to help the heavy handed.
our $IRHOLDTIME  = 1.0;

# 256 ms
our $IRSINGLETIME = 0.256;

# Max time an IR key code is queued for before being discarded [if server is busy]
my $maxIRQTime = 3.0;

our $irPerf = Slim::Utils::PerfMon->new('IR Delay', [0.002, 0.005, 0.010, 0.015, 0.025, 0.050, 0.1, 0.5, 1, 5]);

my $log = logger('player.ir');

sub init {

	%irCodes = ();
	%irMap = ();
	
	for my $irfile (keys %{irfiles()}) {
		loadIRFile($irfile);
	}

	for my $mapfile (keys %{mapfiles()}) {
		loadMapFile($mapfile);
	}
}

sub enqueue {
	my $client = shift;
	my $irCodeBytes = shift;
	my $clientTime = shift;

	my $irTime = $clientTime / $client->ticspersec;
	my $now = Time::HiRes::time();

	assert($client);
	assert($irCodeBytes);
	assert($irTime);

	# estimate time of actual key press as $irTime + $ref, $ref = min($now - $irTime) over set of key presses
	# allows estimation of delay for IR key presses queued in slimproto tcp session while server busy/network congested
	# assumes most IR interaction lasts < 60s, reset estimate after this to ensure recovery from clock adjustments
	my $offset = $now - $irTime;
	my $ref    = $client->irRefTime || 0;

	if ($offset < $ref || $offset - $ref + abs($now - ($client->irRefTimeStored || 0)) > 60) {
		$ref = $client->irRefTime($offset);
		$client->irRefTimeStored($now);
	}

	my $entry = {
		'client' => $client,
		'bytes'  => $irCodeBytes,
		'irTime' => $irTime,
		'estTime'=> $irTime + $ref,
	};

	push @irQueue, $entry;
}

sub idle {
	# return 0 only if no IR in queue
	if (!scalar @irQueue) {
		return 0;
	}

	my $entry = shift @irQueue;
	my $client = $entry->{'client'};

	my $now = Time::HiRes::time();
	
	$::perfmon && $irPerf->log($now - $entry->{'estTime'});

	if (($now - $entry->{'estTime'}) < $maxIRQTime) {

		# process IR code
		$client->execute(['ir', $entry->{'bytes'}, $entry->{'irTime'}]);

	} else {

		# discard all queued IR for this client as they are potentially stale
		forgetQueuedIR($client);

		$log->info(sprintf("Discarded stale IR for client: %s", $client->id));

	}
		
	return 1;
}

sub forgetQueuedIR {
	my $client = shift;

	my $i = 0;

	while ( my $entry = $irQueue[$i] ) {

		if ( $entry->{'client'} eq $client ) {
			splice @irQueue, $i, 1;
		} else {
			$i++;
		}
	}

	Slim::Utils::Timers::killTimers($client, \&checkRelease);
}

sub IRFileDirs {

	return Slim::Utils::OSDetect::dirsFor('IR');
}

# Returns a reference to a hash of filenames/external names
sub irfiles {
	my $client = shift;

	my %files = ();

	for my $irDir (IRFileDirs()) {

		if (!-d $irDir) {
			next;
		}

		my $dir = dir($irDir);

		while (my $fileObj = $dir->next) {

			my $file = $fileObj->stringify;

			if ($file !~ /(.+)\.ir$/) {
				next;
			}
			
			# NOTE: client isn't required here, but if it's been sent from setup
			# Don't show front panel ir set for non-transporter clients
			if (defined ($client) && !$client->isa('Slim::Player::Transporter') && ($1 eq 'Front_Panel')) {
				next;
			}

			$log->info("Found IR file $file");

			$files{$file} = $1;
		}
	}

	return \%files;
}

sub irfileName {
	my $file  = shift;
	my %files = %{irfiles()};

	return $files{$file};
}

sub defaultMap {
	return "Default";
}

sub defaultMapFile {

	if (!defined($defaultMapFile)) {
		$defaultMapFile = defaultMap() . '.map';
	}

	return $defaultMapFile;
}

# returns a reference to a hash of filenames/external names
sub mapfiles {
	my %maplist = ();

	for my $irDir (IRFileDirs()) {

		if (!-d $irDir) {
			next;
		}

		my $dir = dir($irDir);

		while (my $fileObj = $dir->next) {

			my $file = $fileObj->stringify;

			if ($file !~ /(.+)\.map$/) {
				next;
			}
			
			$log->info("Found key mapping file: $file");

			if ($1 eq defaultMap()) {

				$maplist{$file} = Slim::Utils::Strings::string('DEFAULT_MAP');
				$defaultMapFile = $file;

			} else {

				$maplist{$file} = $1;
			}
		}
	}

	return \%maplist;
}

sub addModeDefaultMapping {
	my ($mode, $mapRef) = @_;

	if (exists $irMap{$defaultMapFile}{$mode}) {

		# don't overwrite existing mappings
		return;
	}

	if (ref($mapRef) eq 'HASH') {

		$irMap{$defaultMapFile}{$mode} = $mapRef;
	}
}

sub IRPath {
	my $mapFile = shift;

	for my $irDir (IRFileDirs()) {

		my $file = file($irDir, $mapFile);

		if (-r $file) {
			return $file->stringify;
		}
	}
}

sub loadMapFile {
	my $file = shift;
	my $mode;

	$log->info("Key mapping file entry: $file");

	if (!-r $file) {
		$file = IRPath($file);
	}

	$log->info("Opening map file [$file]");

	if (!-r $file) {

		$log->warn("Failed to open $file");
		return;
	}

	my @lines = file($file)->slurp('chomp' => 1);

	$file = basename($file);

	delete $irMap{$file};

	for (@lines) {

		if (/\[(.+)\]/) {
			$mode = $1;
			next;
		}

		# No trailing or leading whitespace.
		# Also no # or = in button names.
		s/^\s+//;
		s/\s+$//;
		s/\s*#.*$//;

		if (!length) {
			next;
		}

		my ($buttonName, $function) = split(/\s*=\s*/, $_, 2);

		if ($buttonName !~ /(.+)\.\*/) {

			$irMap{$file}{$mode}{$buttonName} = $function;
			next;
		}

		for my $style (@buttonPressStyles) {

			if (!exists($irMap{$file}{$mode}{$1 . $style})) {

				$irMap{$file}{$mode}{$1 . $style} = $function;
			}
		}
	}
}

sub loadIRFile {
	my $file = shift;

	if (!-r $file) {
		$file = IRPath($file);
	}

	$log->info("Opening IR file [$file]");

	if (!-r $file) {

		$log->warn("Failed to open $file");
		return;
	}

	delete $irCodes{$file};

	my @lines = file($file)->slurp('chomp' => 1);

	for (@lines) {

		# No trailing or leading whitespace.
		# Also no # or = in button names.
		s/^\s+//;
		s/\s+$//;
		s/\s*#.*$//;

		if (!length) {
			next;
		}

		my ($buttonName, $irCode) = split(/\s*=\s*/, $_, 2);

		$irCodes{$file}{$irCode} = $buttonName;
	}
}	

# returns the code for a CodeByte
# for now copycat of lookup for detecting unknown codes
# result of this investigation should be reused, but too delicate operation now
sub lookupCodeBytes {
	my $client = shift;
	my $irCodeBytes = shift;
		
	if (defined $irCodeBytes) {
	
		my %enabled = %irCodes;

		if ($client) {

			map { delete $enabled{$_} } $client->prefGetArray('disabledirsets');
		}

		for my $irset (keys %enabled) {

			if (defined (my $code = $irCodes{$irset}{$irCodeBytes})) {

				$log->info("$irCodeBytes -> code: $code");

				return $code;
			}
		}
	}
	
	$log->info("$irCodeBytes -> unknown");

	return undef;
}

# Look up an IR code by hex value for enabled remotes, then look up the function for the current
# mode, and return the name of the function, eg "play"
sub lookup {
	my $client = shift;
	my $code = shift;
	my $modifier = shift;

	if (!defined $code) {

		$log->warn("irCode not present");
		return '';
	}
	
	my %enabled = %irCodes;

	for ($client->prefGetArray('disabledirsets')) {
		delete $enabled{$_};
	}

	for my $irset (keys %enabled) {

		if (defined $irCodes{$irset}{$code}) {

			$log->info("Found button $irCodes{$irset}{$code} for $code");

			$code = $irCodes{$irset}{$code};

			last;
		}
	}
	
	if (defined $modifier) {
		$code .= '.' . $modifier;
	}

	$client->lastirbutton($code);

	return lookupFunction($client, $code);
}

sub lookupFunction {
	my ($client, $code, $mode) = @_;

	if (!defined $mode) {
		$mode = Slim::Buttons::Common::mode($client);
	}

	my $map      = $client->prefGet('irmap');
	my $function = '';

	assert($client);
	assert($map);
	assert($mode);
#	assert($code); # FIXME: somhow we keep getting here with no $code.

	if ($function = $irMap{$map}{$mode}{$code}) {

		$log->info("Found function: $function for button $code in mode $mode from map $map");

	} elsif ($function = $irMap{$defaultMapFile}{$mode}{$code}) {

		$log->info("Found function: $function for button $code in mode $mode from map $defaultMapFile");
	
	} elsif ($mode =~ /^(.+)\..+/ && $irMap{$map}{lc($1)}{$code}) {

		$function = $irMap{$map}{lc($1)}{$code};

		$log->info("Found function: $function for button $code in mode class \L$1 from map $map");

	} elsif ($mode =~ /^(.+)\..+/ && $irMap{$defaultMapFile}{lc($1)}{$code}) {

		$function = $irMap{$defaultMapFile}{lc($1)}{$code};

		$log->info("Found function: $function for button $code in mode class \L$1 from map $defaultMapFile");

	} elsif ($function = $irMap{$map}{'common'}{$code}) {

		$log->info("Found function: $function for button $code in mode common from map $map");
	
	} elsif ($function = $irMap{$defaultMapFile}{'common'}{$code}) {

		$log->info("Found function: $function for button $code in mode common from map $defaultMapFile");
	}

	if (!$function) {
		$log->info("irCode not defined: [$code] for map: [$map] and mode: [$mode]");
	}

	return $function;
}

# Checks to see if a button has been released, this sub is executed through timers
sub checkRelease {
	my ($client, $releaseType, $startIRTime, $startIRCodeBytes, $estIRTime) = @_;

	my $now = Time::HiRes::time();
	
	if ($startIRCodeBytes ne $client->lastircodebytes) {

		# a different button was pressed, so the original must have been released
		if ($releaseType ne 'hold_check') {

			releaseCode($client, $startIRCodeBytes, $releaseType, $estIRTime);

			# XXX - should check for single press release
			return 0;
		}

	} elsif ($startIRTime != $client->startirhold) {

		# a double press possibly occurred
		if ($releaseType && $releaseType eq 'hold_check') {

			# not really a double press
			return 0;

		} elsif ($releaseType && $releaseType eq 'hold_release') {

			releaseCode($client, $startIRCodeBytes, $releaseType, $estIRTime);

			return 0;

		} else {

			releaseCode($client, $startIRCodeBytes, 'double', $estIRTime);

			# reschedule to check for whether to fire hold_release
			Slim::Utils::Timers::setTimer(
				$client,
				$now + $IRHOLDTIME,
				\&checkRelease,
				'hold_check',
				$client->startirhold,
				$startIRCodeBytes,
				$client->startirhold + $IRHOLDTIME,
			);

			# don't check for single press release
			return 1;
		}

	} elsif ($estIRTime - $client->lastirtime < $IRMINTIME) {

		# still holding button down, so reschedule
		my $nexttime;

		if ($estIRTime >= ($startIRTime + $IRHOLDTIME)) {

			$releaseType = 'hold_release';

			# check for hold release every 1/2 hold time
			$nexttime = $IRHOLDTIME / 2;

		} elsif (($estIRTime + $IRSINGLETIME) > ($startIRTime + $IRHOLDTIME)) {

			$nexttime = $startIRTime + $IRHOLDTIME - $estIRTime;

		} else {

			$nexttime = $IRSINGLETIME;
		}

		Slim::Utils::Timers::setTimer(
			$client,
			$now + $nexttime,
			\&checkRelease,
			$releaseType,
			$startIRTime,
			$startIRCodeBytes,
			$estIRTime + $nexttime
		);

		return 1;

	} else {

		# button released
		if ($releaseType ne 'hold_check') {

			releaseCode($client, $startIRCodeBytes, $releaseType, $estIRTime);
		}

		return 0;
	}
}

sub processIR {
	my ($client, $irCodeBytes, $irTime) = @_;

	if ($irCodeBytes eq '00000000') {

		$log->warn("Ignoring spurious null repeat code.");
		return;
	}

	# lookup the bytes, if we don't know them no point in continuing
	my $code = lookupCodeBytes($client, $irCodeBytes);
	
	if (!defined $code) {

		Slim::Control::Request::notifyFromArray($client, ['unknownir', $irCodeBytes, $irTime]);

		return;
	}

	my $timediff = $irTime - $client->lastirtime();

	if ($timediff < 0) {
		$timediff += (0xffffffff / $client->ticspersec);
	}

	if (($code !~ /(.*?)\.(up|down)$/) && ($timediff < $IRMINTIME) && ($irCodeBytes ne $client->lastircodebytes)) {

		# received oddball code in middle of repeat sequence, drop it
		$log->warn("Received $irCodeBytes while expecting " . $client->lastircodebytes . ", dropping code");

		return;
	}
	
	if ($timediff == 0) { 

		$log->warn("Received duplicate IR timestamp: $irTime - ignoringo");

		return;
	}

	$client->irtimediff($timediff);
	$client->lastirtime($irTime);

	$log->info("$irCodeBytes\t$irTime\t" . Time::HiRes::time());

	if ($code =~ /(.*?)\.(up|down)$/) {

		$log->info("Front panel code detected, processing $code");

		$client->startirhold($irTime);
		$client->lastircodebytes($irCodeBytes);
		$client->irrepeattime(0);

		processFrontPanel($client, $1, $2, $irTime);

	} elsif (($irCodeBytes eq $client->lastircodebytes) # same button press as last one
		&& ( ($client->irtimediff < $IRMINTIME) # within the minimum time to be considered a repeat
			|| (($client->irtimediff < $client->irrepeattime * 2.02) # or within 2% of twice the repeat time
				&& ($client->irtimediff > $client->irrepeattime * 1.98))) # indicating that a repeat code was missed
		) {

		holdCode($client,$irCodeBytes);
		repeatCode($client,$irCodeBytes);

		if (!$client->irrepeattime || ($client->irtimediff > 0 && $client->irtimediff < $client->irrepeattime)) {

			# repeat time not yet set or last time diff less than
			# current estimate of repeat time (excluding time
			# diffs less than 0, from out of order packets)
			$client->irrepeattime($client->irtimediff)
		}

	} else {

		$client->startirhold($irTime);
		$client->lastircodebytes($irCodeBytes);
		$client->irrepeattime(0);

		my $noTimer = Slim::Utils::Timers::firePendingTimer($client,\&checkRelease);

		if (!$noTimer) {

			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time() + $IRSINGLETIME,
				\&checkRelease,
				'single',
				$irTime,
				$irCodeBytes,
				$irTime + $IRSINGLETIME
			)
		}

		my $irCode = lookup($client, $irCodeBytes);

		$log->info(sprintf("irCode = [%s] timer = [%s] timediff = [%s] last = [%s]",
			(defined $irCode ? $irCode : 'undef'), 
			$irTime,
			$client->irtimediff,
			$client->lastircode,
		));

		if (defined $irCode) {

			processCode($client, $irCode, $irTime);
		}
	}
}

sub processFrontPanel {
	my $client = shift;
	my $code   = shift;
	my $dir    = shift;
	my $irTime = shift;

	if ($dir eq 'down') {

		$log->info("IR: Front panel button press: $code");

		my $irCode  = lookupFunction($client,$code);

		$client->lastirbutton($code);

		processCode($client, $irCode, $irTime);

		# start timing for hold time, preparing the .hold event for later.
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + $IRHOLDTIME,
			\&fireHold,
			"$code.hold",
			$client->lastirtime
		);

	} else {

		my $timediff = $irTime - $client->lastirtime;

		$log->info("IR: Front panel button release after $timediff: $code");
		
		my $irCode;

		# When the button is held longer than the time needed for a
		# .hold event, we also follow up with a .hold_release when the
		# button is released.
		if ($timediff > $IRHOLDTIME) {

			$irCode = lookupFunction($client, "$code.hold_release");

			$client->lastirbutton("$code.hold_release");

			processCode($client, $irCode, $client->lastirtime);

		} else {

			# When releasing before the hold time, fire the event
			# with the .single modifier.
			$irCode = lookupFunction($client, "$code.single");

			$client->lastirbutton("$code.single");

			processCode($client, $irCode, $irTime);

		}
	}
}

sub fireHold {
	my $client = shift;
	my $irCode = shift;
	my $irTime = shift;

	my $last = lookupCodeBytes($client, $client->lastircodebytes);

	# block the .hold event if we know that the button has been released already.
	if ($last =~ /\.up$/) {
		return;
	}

	$log->info("Hold Time Expired - irCode = [$irCode] timer = [$irTime] timediff = [" . $client->irtimediff . "] last = [$last]");

	# must set lastirbutton so that button functions like 'passback' will work.
	$client->lastirbutton($irCode);

	processCode($client, $irCode, $irTime);
}

# utility functions used externally
sub resetHoldStart {
	my $client = shift;
	
	$client->startirhold($client->lastirtime);
}

sub resendButton {
	my $client = shift;
	my $ircode = lookup($client, $client->lastircodebytes);

	if (defined $ircode) {
		processCode($client, $ircode, $client->lastirtime);
	}
}

sub lastIRTime {
	my $client = shift;

	return $client->epochirtime;
}

sub setLastIRTime {
	my $client = shift;

	$client->epochirtime(shift);
}

sub releaseCode {
	my ($client, $irCodeBytes, $releaseType, $irtime) = @_;

	my $ircode = lookup($client, $irCodeBytes, $releaseType);

	if ($ircode) {
		processCode($client, $ircode, $irtime);
	}
}

# Some buttons should be handled once when held for a period of time
sub holdCode {
	my ($client, $irCodeBytes) = @_;

	my $holdtime = holdTime($client);

	if ($holdtime >= $IRHOLDTIME && ($holdtime - $IRHOLDTIME) < $client->irtimediff) {

		# the time for the hold firing took place within the last ir interval
		my $ircode = lookup($client, $irCodeBytes, 'hold');

		if ($ircode) {
			processCode($client, $ircode, $client->lastirtime);
		}
	}
}

# Some buttons should be handled repeatedly if held down. This function is called
# when IR codes that are received repeatedly - we decide how to handle it.
sub repeatCode {
	my ($client, $irCodeBytes) = @_;

	my $irCode = lookup($client, $irCodeBytes, 'repeat');

	$log->info(sprintf("irCode = [%s] timer = [%s] timediff = [%s] last = [%s]",
		($irCode || 'undef'),
		($client->lastirtime || 'undef'),
		($client->irtimediff || 'undef'),
		($client->lastircode || 'undef'),
	));

	if ($irCode) {

		processCode($client, $irCode, $client->lastirtime);
	}
}

sub repeatCount {
	my $client    = shift;
	# my $minrate = shift; # not used currently, could be added for more complex behavior
	my $maxrate   = shift;
	my $accel     = shift;
	my $holdtime  = holdTime($client);

	# nothing on the initial time through
	if (!$holdtime) {
		return 0;
	}

	if ($accel) {

		# calculate the number of repetitions we should have made by this time
		if ($maxrate && $maxrate < $holdtime * $accel) {

			# done accelerating, so number of repeats during the
			# acceleration plus the max repeat rate times the time
			# since acceleration was finished
			my $flattime = $holdtime - $maxrate / $accel;

			return int($maxrate * $flattime) - int($maxrate * ($flattime - $client->irtimediff));

		} else {

			# number of repeats is the expected integer number of
			# repeats for the current time minus the expected
			# integer number of repeats for the last ir time.
			return int(accelCount($holdtime,$accel)) - int(accelCount($holdtime - $client->irtimediff,$accel));
		}
	}

	return int($maxrate * $holdtime) - int($maxrate * ($holdtime - $client->irtimediff));
}

sub accelCount {
	my $time  = shift;
	my $accel = shift;
	
	return 0.5 * $accel * $time * $time;
}

sub holdTime {
	my $client = shift;

	if ($client->lastirtime ==  0) {
		return 0;
	}

	my $holdtime = $client->lastirtime - $client->startirhold;

	if ($holdtime < 0) {
		$holdtime += 0xffffffff / $client->ticspersec;
	}

	return $holdtime;
}

=head2 executeButton( $client, $button, $time, $mode, $orFunction )

Calls the appropriate handler for the specified button.

=cut

sub executeButton {
	my $client     = shift;
	my $button     = shift;
	my $time       = shift;
	my $mode       = shift;
	my $orFunction = shift; # allow function names as $button

	my $irCode = lookupFunction($client, $button, $mode);

	if ($orFunction && !$irCode) {

		$irCode = $button;
	}

	$log->info(sprintf("Trying to execute button [%s] for irCode: [%s]",
		$button, defined $irCode ? $irCode : 'undef',
	));

	if (defined $irCode) {

		if ($irCode !~ /brightness/ && $irCode ne 'dead' && ($irCode ne 0 || !defined $time)) {

			setLastIRTime($client, Time::HiRes::time());
		}
	}

	if (!defined $time) {
		$client->lastirtime(0);
	}

	if (my ($subref, $subarg) = Slim::Buttons::Common::getFunction($client, $irCode, $mode)) {

		if (!defined $subref || ref($subref) ne 'CODE') {

			$log->error("Error: Subroutine for irCode: [$irCode] does not exist!");

			return;
		}

		Slim::Buttons::ScreenSaver::wakeup($client, $client->lastircode);

		no strict 'refs';

		$log->info(sprintf("Executing button [%s] for irCode: [%s]",
			$button, defined $irCode ? $irCode : 'undef',
		));

		&$subref($client, $irCode, $subarg);

	} else {

		$log->warn(sprintf("Button [%s] with irCode: [%s] not implemented in mode: [%s]",
			$button, defined $irCode ? $irCode : 'undef', $mode,
		));
	}
}

sub processCode {
	my ($client, $irCode, $irTime) = @_;

	$log->info("irCode: $irCode, " . $client->id);

	$client->lastircode($irCode);

	$client->execute(['button', $irCode, $irTime, 1]);
}

=head1 SEE ALSO

L<Time::HiRes>

L<Slim::Buttons::Common>

L<Slim::Player::Client>

=cut

1;
