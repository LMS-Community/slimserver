package Slim::Hardware::IR;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Hardware::IR

=head1 DESCRIPTION

L<Slim::Hardware::IR>

Example Processing Pathway for an IR 'up' button command:
    Slimproto.pm receives a BUTN slimproto packet and dispatches to Slimproto::_button_handler
    It enqueue's an even to to Slim::Hardware::IR::enqueue with the button command, and time as reported by the player.
    Slim::Hardware::IR::enque calculates the time difference between the server time and the time the IR command was sent. The IR Event is pushed onto an even stack.
    Slim::Hardware::IR::idle    pulls events off the IR stack.  If it's been too long between the IR event and its processing, the whole IR queue is cleared.  Otherwise, idle() looks up the event handler and runs Client::execute('ir', <ircode>, <irtimefromclient>)
    This calls Slim::Control::Request::execute, which looks up 'ir' in its dispatch table, and executes Slim::Control::Commands::irCommand as a result.
    Slim::Control::Commands::irCommand calls Slim::Hardware::IR::processIR
    Slim::Hardware::IR::processIR does a little work, then looks up the client function to call with lookupFunction, then executes it with processCode.
    processCode calls $client->execute with the 'button' command, which once again goes back to Slim::Control::Request and looks up the 'button' function, and then calls Slim::Control::Commands::buttonCommand
    Slim::Control::Commands::buttonCommand calls Slim::Hardware::IR::executeButton with the client, button and time
    Slim::Hardware::IR::executeButton calls lookupFunction which finds the IR handler function to call.  It looks this up in Default.map under 'common'
    For knob_right or knob_left (and others), this currently calls 'up' or 'down'
    executeButton then calls Slim::Buttons::Common::getFunction, which looks up INPUT.List, up, which is defined in Slim::Buttons::Input::List.pm
    Slim::Buttons::Input::List, up calls Slim::Buttons::Input::List::changePos 
    Slim::Buttons::Input::List::changePos calls Slim::Buttons::Common::scroll.  This is where the acceleration algorithm takes place.

=cut

use strict;

use File::Basename;
use Path::Class;
use Time::HiRes qw(gettimeofday);

use Slim::Buttons::Common;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

my %irCodes = ();
my %irMap   = ();

my @irQueue = ();

my @buttonPressStyles = ('', '.single', '.double', '.repeat', '.hold', '.hold_release');
my $defaultMapFile;

# If time between IR commands is greater than this, then the code is considered a new button press
our $IRMINTIME  = 0.140;

# bumped up to a full second, to help the heavy handed.
our $IRHOLDTIME  = 0.9;

# 256 ms
our $IRSINGLETIME = 0.256;

# Max time an IR key code is queued for before being discarded [if server is busy]
my $maxIRQTime = 3.0;

my $log = logger('player.ir');

my $prefs = preferences('server');

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
	my $entry = shift @irQueue || return 0;
	my $client = $entry->{'client'};

	my $now = Time::HiRes::time();
	
	main::PERFMON && Slim::Utils::PerfMon->check('ir', $now - $entry->{'estTime'});

	if (($now - $entry->{'estTime'}) < $maxIRQTime) {

		# process IR code
		$client->execute(['ir', $entry->{'bytes'}, $entry->{'irTime'}]);

	} else {

		# discard all queued IR for this client as they are potentially stale
		forgetQueuedIR($client);

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf("Discarded stale IR for client: %s", $client->id));
		}

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

			if (basename($file) !~ /(.+)\.ir$/) {
				next;
			}
			
			# NOTE: client isn't required here, but if it's been sent from setup
			# Don't show front panel ir set for clients without a front panel
			if (defined ($client) && !$client->hasFrontPanel() && ($1 eq 'Front_Panel')) {
				next;
			}

			main::INFOLOG && $log->info("Found IR file $file");

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
		my @dirs = IRFileDirs();
		$defaultMapFile = file($dirs[0],defaultMap() . '.map')->stringify;
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

			if (basename($file) !~ /(.+)\.map$/) {
				next;
			}

			main::INFOLOG && $log->info("Found key mapping file: $file");

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
	my ($mode, $mapRef, $force) = @_;

	if ( exists $irMap{$defaultMapFile}{$mode} ) {
		while ( my ($key, $value) = each %{$mapRef} ) {
			if ( !$force && exists $irMap{$defaultMapFile}{$mode}->{$key} ) {
				# future enhancement - make a menu of options if a key action is duplicated
				$log->warn("ignoring [$mode] $key => $value");
			}
			else {
				main::INFOLOG && $log->info("mapping [$mode] $key => $value");
				$irMap{$defaultMapFile}{$mode}->{$key} = $value;
			}
		}
		return;
	}

	if ( ref $mapRef eq 'HASH' ) {
		if ( main::INFOLOG && $log->is_info ) {
			while ( my ($key, $value) = each %{$mapRef} ) {
				$log->info("mapping [$mode] $key => $value");
			}
		}
		
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

	main::INFOLOG && $log->info("Key mapping file entry: $file");

	if (!-r $file) {
		$file = IRPath($file);
	}

	main::INFOLOG && $log->info("Opening map file [$file]");

	if (!-r $file) {

		$log->warn("Failed to open $file");
		return;
	}

	my @lines = file($file)->slurp('chomp' => 1);

	#$file = basename($file);

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

	main::INFOLOG && $log->info("Opening IR file [$file]");

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

# init lookup state for new client so this is not done per ir lookup
sub initClient {
	my $client = shift;

	my @codes;
	my %disabled = map { $_ => 1 } @{ $prefs->client($client)->get('disabledirsets') || [] };

	for my $code (keys %irCodes) {
		if (!$disabled{$code}) {
			main::INFOLOG && $log->info("Client: " . $client->id . " IR code set: $code");
			push @codes, \%{ $irCodes{$code} };
		}
	}

	$client->ircodes(\@codes);

	my $map = $prefs->client($client)->get('irmap');

	if ( $map && !-e $map ) {
		# older prefs didn't track pathname
		# resave the pref with path also stripping to basename as a way to try to fix an invalid path
		my @dirs = IRFileDirs();
		$map = file($dirs[0], basename($map))->stringify;
		$prefs->client($client)->set('irmap', $map);
	}

	my @maps = ( \%{ $irMap{$defaultMapFile} } );

	if ( $map && $map ne $defaultMapFile ) {
		main::INFOLOG && $log->info("Client: " . $client->id . " Using mapfile: $map");
		unshift @maps, \%{ $irMap{$map} };
	}

	$client->irmaps(\@maps);
}

# returns the code for a CodeByte
# for now copycat of lookup for detecting unknown codes
# result of this investigation should be reused, but too delicate operation now
sub lookupCodeBytes {
	my $client = shift;
	my $irCodeBytes = shift;
		
	if (defined $irCodeBytes) {
	
		for my $irset (@{$client->ircodes}) {

			if (defined (my $code = $irset->{$irCodeBytes})) {

				main::INFOLOG && $log->info("$irCodeBytes -> code: $code");

				return $code;
			}
		}
	}
	
	main::INFOLOG && $log->info("$irCodeBytes -> unknown");

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
	
	for my $irset (@{$client->ircodes}) {

		if (defined (my $found = $irset->{$code})) {

			main::INFOLOG && $log->info("Found button $found for $code");

			$code = $found;

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
	my ($client, $code, $mode, $haveFunction) = @_;

	if (!defined $mode) {
		# find the current mode
		$mode = $client->modeStack->[-1];
	}

	my @maps  = @{$client->irmaps};
	my @order = ( $mode, 'common' );

	if ($mode =~ /^(.+)\..+/) {
		if ($1 eq 'INPUT') {
			# add the previous mode so we can provide specific mappings for callers of INPUT.*
			splice @order, 1, 0, $client->modeStack->[-2];
		} else {
			# add the class name so modes of the form class.name can share maps entries
			splice @order, 1, 0, lc($1);
		}
	}

	for my $search (@order) {

		for my $map (@maps) {

			if (my $function = $map->{$search}{$code}) {

				main::INFOLOG && $log->info("Found function: $function for button $code in mode $search (current mode: $mode)");

				return $function;
			}
		}
	}

	main::INFOLOG && $log->info("irCode not defined: [$code] for mode: [$mode]");

	return undef;
}

# Checks to see if a button has been released, this sub is executed through timers
sub checkRelease {
	my ($client, $releaseType, $startIRTime, $startIRCodeBytes, $estIRTime, $origMode) = @_;

	my $now = Time::HiRes::time();

	if ($client->modeStack->[-1] ne $origMode) {

		main::INFOLOG && $log->info("ignoring checkRelease mode has changed");

		return 0;
	}
	
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
				$origMode,
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
			$estIRTime + $nexttime,
			$origMode,
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

		main::DEBUGLOG && $log->debug("Ignoring spurious null repeat code.");
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
		if ( $log->is_warn ) {
			$log->warn("Received $irCodeBytes while expecting " . $client->lastircodebytes . ", dropping code");
		}

		return;
	}
	
	if ($timediff == 0) { 

		$log->warn("Received duplicate IR timestamp: $irTime - ignoringo");

		return;
	}

	$client->irtimediff($timediff);
	$client->lastirtime($irTime);
	
	my $knobData = $client->knobData;

	if (!($code =~ /^knob/)) {
		## Any button other than knob resets the knob state
		$knobData->{'_velocity'} = 0;
		$knobData->{'_acceleration'} = 0;
		$knobData->{'_knobEvent'} = 0;
	}
	if ( main::INFOLOG && $log->is_info ) {
		$log->info("$irCodeBytes\t$irTime\t" . Time::HiRes::time());
	}

	if ($code =~ /(.*?)\.(up|down)$/) {

		my $dir = $2;

		main::INFOLOG && $log->info("Front panel code detected, processing $code");

		if ($dir eq 'down' && $irCodeBytes eq $client->lastircodebytes) {
			$dir = 'repeat';
		}

		$client->lastircodebytes($irCodeBytes);
		$client->irrepeattime(0);

		processFrontPanel($client, $1, $dir, $irTime);

	} elsif ($code =~ /^knob/) {

		main::INFOLOG && $log->info("Knob code detected, processing $code");
		$knobData->{'_knobEvent'} = 1;
		$knobData->{'_time'} = $irTime;
		$knobData->{'_lasttime'} = $client->lastirtime();
		$knobData->{'_deltatime'} = $timediff;
		if ($irCodeBytes eq $client->lastircodebytes && $timediff < 0.5) {
			# The knob is spinning.  We can make useful calculations of speed and acceleration.
			my $velocity = 1/$timediff;
			if ($code =~ m:knob_left:) {
				$velocity = -$velocity;
			}
			my $acceleration = ($velocity - $knobData->{'_velocity'}) / $timediff;
			$knobData->{'_acceleration'} = $acceleration;
			$knobData->{'_velocity'} = $velocity;
			$code .= ".repeat";

		} else {

			$client->lastircodebytes($irCodeBytes);
			$client->irrepeattime(0);
			$knobData->{'_velocity'} = 0;
			$knobData->{'_acceleration'} = 0;
		}

		# The S:B:C:scroll code rate limits scrolling unless this is reset for every update
		$client->startirhold($irTime);

		$client->lastirbutton($code);

		my $irCode = lookupFunction($client, $code);
		
		processCode($client, $irCode, $irTime);

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
				$irTime + $IRSINGLETIME,
				$client->modeStack->[-1], # current mode
			)
		}

		my $irCode = lookup($client, $irCodeBytes);

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf("irCode = [%s] timer = [%s] timediff = [%s] last = [%s]",
				(defined $irCode ? $irCode : 'undef'), 
				$irTime,
				$client->irtimediff,
				$client->lastircode,
			));
		}

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

	if ($dir eq 'repeat') {

		$code .= '.repeat';

		main::INFOLOG && $log->info("IR: Front panel button press: $code");

		# we don't restart the hold timers as we also want to generate .hold events

		my $irCode = lookupFunction($client, $code);

		$client->lastirbutton($code);

		processCode($client, $irCode, $irTime);

	} elsif ($dir eq 'down') {

		main::INFOLOG && $log->info("IR: Front panel button press: $code");
		
		# kill any previous hold timers
		Slim::Utils::Timers::killTimers($client, \&fireHold);

		my $irCode  = lookupFunction($client,$code);

		$client->lastirbutton($code);

		$client->startirhold($irTime);

		processCode($client, $irCode, $irTime);

		# start timing for hold time, preparing the .hold event for later.
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + $IRHOLDTIME,
			\&fireHold,
			"$code.hold",
			$client->lastirtime,
			$client->lastircodebytes
		);

	} else { # dir is up

		my $timediff = $irTime - $client->startirhold;

		main::INFOLOG && $log->info("IR: Front panel button release after $timediff: $code");

		# kill any previous hold timers
		Slim::Utils::Timers::killTimers($client, \&fireHold);
		
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
	my $startIRCodeBytes = shift;

	# block the .hold event if the last ir code was not the one which started the timer
	if ($startIRCodeBytes ne $client->lastircodebytes) {
		return;
	}

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("Hold Time Expired - irCode = [$irCode] timer = [$irTime] timediff = [" . $client->irtimediff . "]");
	}

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

	my $ircode = $client->lastirbutton;

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("Resending $ircode");
	}

	if (defined $ircode) {

		# strip off down and up modifiers from front panel buttons
		$ircode =~ s/\.down|\.up//;
		$ircode = lookupFunction($client, $ircode);

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

	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("irCode = [%s] timer = [%s] timediff = [%s] last = [%s]",
			($irCode || 'undef'),
			($client->lastirtime || 'undef'),
			($client->irtimediff || 'undef'),
			($client->lastircode || 'undef'),
		));
	}

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

	my $irCode = lookupFunction($client, $button, $mode, $orFunction);

	if ($orFunction && !$irCode) {

		$irCode = $button;
	}

	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("Trying to execute button [%s] for irCode: [%s]",
			$button, defined $irCode ? $irCode : 'undef',
		));
	}

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

			$log->is_warn && $log->warn("Warning: Subroutine for irCode: [$irCode] mode: [$mode] does not exist!");

			return;
		}

		Slim::Buttons::ScreenSaver::wakeup($client, $client->lastircode);

		no strict 'refs';

		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug(sprintf("Executing button [%s] for irCode: [%s] %s",
				$button, defined $irCode ? $irCode : 'undef',
				Slim::Utils::PerlRunTime::realNameForCodeRef($subref),
			));
		}

		&$subref($client, $irCode, $subarg);

	} else {

		if ( $log->is_warn ) {
			$log->warn(sprintf("Button [%s] with irCode: [%s] not implemented in mode: [%s]",
				$button, defined $irCode ? $irCode : 'undef', $mode,
			));
		}
	}
}

sub processCode {
	my ($client, $irCode, $irTime) = @_;

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("irCode: $irCode, " . $client->id);
	}

	$client->lastircode($irCode);

	$client->execute(['button', $irCode, $irTime, 1]);
}

=head1 SEE ALSO

L<Time::HiRes>

L<Slim::Buttons::Common>

L<Slim::Player::Client>

=cut

1;
