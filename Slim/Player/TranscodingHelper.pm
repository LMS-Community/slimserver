package Slim::Player::TranscodingHelper;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(catdir);
use Scalar::Util qw(blessed);

use Slim::Player::CapabilitiesHelper;
use Slim::Music::Info;
use Slim::Player::Sync;
use Slim::Utils::DateTime;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;

{
	if (main::ISWINDOWS) {
		require Win32;
	}
}

sub init {
	loadConversionTables();
}

our %commandTable = ();
our %capabilities = ();
our %binaries = ();

sub Conversions {
	return \%commandTable;
}

my $log = logger('player.source');

my $prefs = preferences('server');

sub loadConversionTables {

	my @convertFiles = ();

	main::INFOLOG && $log->info("Loading conversion config files...");

	# custom convert files allowed at server root or root of plugin directories
	for my $baseDir (Slim::Utils::OSDetect::dirsFor('convert')) {

		push @convertFiles, (
			catdir($baseDir, 'convert.conf'),
			catdir($baseDir, 'custom-convert.conf'),
			catdir($baseDir, 'slimserver-convert.conf'),
		);
	}

	foreach my $baseDir (Slim::Utils::PluginManager->dirsFor('convert')) {

		push @convertFiles, catdir($baseDir, 'custom-convert.conf');
	}
	
	foreach my $convertFileName (@convertFiles) {

		# can't read? next.
		next unless -r $convertFileName;

		open(CONVERT, $convertFileName) || next;

		while (my $line = <CONVERT>) {

			# skip comments and whitespace
			next if $line =~ /^\s*#/;
			next if $line =~ /^\s*$/;

			# get rid of comments and leading and trailing white space
			$line =~ s/#.*$//o;
			$line =~ s/^\s*//o;
			$line =~ s/\s*$//o;
	
			if ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$/) {

				my $inputtype  = $1;
				my $outputtype = $2;
				my $clienttype = $3;
				my $clientid   = lc($4);
				my $profile = "$inputtype-$outputtype-$clienttype-$clientid";

				$line = <CONVERT>;
				if ($line =~ /^\s+#\s+(\S.*)/) {
					_getCapabilities($profile, $1);
					$line = <CONVERT>;
				} else {
					$capabilities{$profile} = {I => 'noArgs', F => 'noArgs'};	# default capabilities
				}

				my $command = $line;
				
				$command =~ s/^\s*//o;
				$command =~ s/\s*$//o;

				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug(
						"input: '$inputtype' output: '$outputtype' clienttype: " .
						"'$clienttype': clientid: '$clientid': '$command'"
					);
				}

				next unless defined $command && $command !~ /^\s*$/;

				$commandTable{$profile} = $command;
			}
		}

		close CONVERT;
	}
}

# Capabilities
# I - can transcode from stdin
# F - can transcode from a named file
# R - can transcode from a remote URL (URL types unspecified)
#
# O - can seek to a byte offset in the source stream (not yet implemented)
# T - can seek to a start time offset
# U - can seek to start time offset and finish at end time offset
#
# D - can downsample 
# B - can limit bitrate
#
# default is "IF"

# Substitution strings for variable capabilities
# %f, $FILE$ - file path (local files)
# %F, $URL$  - full URL (remote streams)
#
# %o - stream start byte offset
#
# %S - stream samples start offset (not yet implemented)
# %s - stream seconds start offset
# %t - stream time (m:ss) start offset
# %U - stream samples end offset (not yet implemented)
# %u - stream seconds end offset
# %v - stream time (m:ss) end offset
# %w - stream seconds duration

#
# %b - limit bitrate: b/s
# %B - limit bitrate: kb/s
# %d - samplerate: samples/s
# %D - samplerate: ksamples/s

# %C, $CHANNELS$   - channel count
# %c, $OCHANNELS$  - output channel count
# %i               - clientid
# %I, $CLIENTID$   - clientid     ( : or . replaced by - )
# %p               - player model
# %P, $PLAYER$     - player model ( SPACE or QOUTE replaced by _ )
# %g               - groupid
# %G, $GROUPID$    - groupid     ( formatted as MAC. if no group is present use CLIENTID )
# %n               - player name
# %N, $NAME$       - player name  ( SPACE or QOUTE replaced by _ )
# %q, $QUALITY$    - quality
# %Q,              - quality ( fractal notation: if = '0' return '01' )
#     ${FILENAME}$ - contents of {FILENAME} (may contain other $*$ substitutions )

# specific combinations match before wildcards

sub _getCapabilities {
	my ($profile, $capabilities) = @_;
	
	$capabilities{$profile} = {};
	unless ($capabilities =~ /^([A-Z](\:\{\w+=[^}]+\})?)+$/) {
		$log->error("Capabilities for $profile: syntax error in $capabilities");
		return;
	}
	
	while ($capabilities) {
		my $can = substr($capabilities, 0, 1, '');
		my $args;
	
		if ($capabilities =~ /^:\{(\w+=[^}]+)\}/) {
			$capabilities = $';
			$args = $1;
		} else {
			if ($can =~ /OTUDB/) {
				$log->error("Capabilities for $profile: missing arguments for '$can'");
			}
			$args = 'noArgs';
		}
	
		$capabilities{$profile}->{$can} = $args;
	}
}

sub isEnabled {
	my $profile = shift;
	
	return (defined $commandTable{$profile}) && enabledFormat($profile);
}

sub enabledFormat {
	my $profile = shift;

	main::DEBUGLOG && $log->debug("Checking to see if $profile is enabled");

	my @disabled = @{ $prefs->get('disabledformats') };

	if (!@disabled) {
		return 1;
	}

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug("There are " . scalar @disabled . " disabled formats...");
	}
	
	for my $format (@disabled) {

		main::DEBUGLOG && $log->debug("Testing $format vs $profile");

		if ($format eq $profile) {

			main::DEBUGLOG && $log->debug("** $profile Disabled **");

			return 0;
		}
	}

	return 1;
}

sub checkBin {
	my $profile            = shift;
	my $ignoreprefsettings = shift;

	my $command;

	main::DEBUGLOG && $log->debug("Checking formats for: $profile");

	# get the command for this profile
	$command = $commandTable{$profile};

	# if the user's disabled the profile, then skip it unless we're changing the prefs...
	return undef unless $command && ( defined($ignoreprefsettings) || enabledFormat($profile) );

	main::DEBUGLOG && $log->debug("   enabled");

	if ($command) {
		main::DEBUGLOG && $log->debug("  Found command: $command");
	}

	# if we don't have one or more of the requisite binaries, then move on.
	while ($command && $command =~ /\[([^]]+)\]/g) {

		my $binary;

		if (!exists $binaries{$1}) {
			$binary = Slim::Utils::Misc::findbin($1);
		}

		if ($binary) {

			$binaries{$1} = $binary;

		} elsif (!exists $binaries{$1}) {

			$command = undef;

			$@ = $1;

			$log->warn("   couldn't find binary for: $1");
		}
	}

	return $command;
}

sub getConvertCommand2 {
	my ($songOrTrack, $type, $streamModes, $need, $want, $formatOverride, $rateOverride) = @_;
	
	my $track;
	my $song;
	my $client;
	
	if ( ref $songOrTrack eq 'Slim::Player::Song' ) {
		$song   = $songOrTrack;
		$track  = $song->currentTrack();
		$client = $song->master();
	}
	else {
		$track = $songOrTrack;
	}
	
	$type ||= Slim::Music::Info::contentType($track);
	
	my $player     = $client ? $client->model() : undef;
	my $clientid   = $client ? $client->id() : undef;
	my $clientprefs= $client ? $prefs->client($client) : undef;
	my $transcoder = undef;
	my $error;
	my $backupTranscoder = undef;
	my $url = $track->url;

	my @supportedformats = ();
	
	# Check if we need to ratelimit
	my $rateLimit 
		= $rateOverride ? $rateOverride
		: $client ? _rateLimit($client, $type, $track->bitrate) : 0;
	RATELIMIT: if ($rateLimit) {
		foreach (@$want) {
			last RATELIMIT if /B/;
		}
		push @$want, 'B';
	}
	
	# Check if we need to downsample
	my $samplerateLimit = $song ? Slim::Player::CapabilitiesHelper::samplerateLimit($song) : 0;
	SAMPLELIMIT: if ($samplerateLimit) {
		foreach (@$need) {
			last SAMPLELIMIT if /D/;
		}
		push @$need, 'D';
	}
	
	# make sure we only test formats that are supported.
	if ( $formatOverride ) {
		@supportedformats = ($formatOverride);
	}
	elsif ( $client ) {
		@supportedformats = Slim::Player::CapabilitiesHelper::supportedFormats($client);
	}

	# Build the full list of possible profiles
	my @profiles = ();
	foreach my $checkFormat (@supportedformats) {

		if ( $clientid && $player ) {
			push @profiles, (
				"$type-$checkFormat-$player-$clientid",
				"$type-$checkFormat-*-$clientid",
				"$type-$checkFormat-$player-*"
			);
		}

		push @profiles, "$type-$checkFormat-*-*";
		
		if ($type eq $checkFormat && enabledFormat("$type-$checkFormat-*-*")) {
			push @profiles, "$type-$checkFormat-transcode-*";
		}
	}
	
	# Test each profile in turn
	PROFILE: foreach my $profile (@profiles) {
		my $command = checkBin($profile);
		next PROFILE if !$command;

		my $streamMode = undef;
		my $caps = $capabilities{$profile};
		
		# Find a profile supporting available stream modes
		foreach (@$streamModes) {
			if ($caps->{$_}) {
				$streamMode = $_;
				last;
			}
		}
		if (! $streamMode) {
			main::DEBUGLOG && $log->is_debug
				&& $log->debug("Rejecting $command because no available stream mode supported: ",
							(join(',', @$streamModes)));
			next PROFILE;
		}
		
		# Check for mandatory capabilities
		foreach (@$need) {
			if (! $caps->{$_}) {
				main::DEBUGLOG && $log->is_debug
					&& $log->debug("Rejecting $command because required capability $_ not supported: ");
				if ($_ eq 'D') {
					$error ||= 'UNSUPPORTED_SAMPLE_RATE';
				}
				next PROFILE;
			}
		}

		# We can't handle WMA Lossless in firmware.
		if ($command eq "-"
			&& $type eq 'wma' && blessed($track) && $track->lossless) {
				next PROFILE;
		}

		$transcoder = {
			command          => $command,
			profile          => $profile,
			usedCapabilities => [@$need, @$want],
			streamMode       => $streamMode,
			streamformat     => (split (/-/, $profile))[1],
			rateLimit        => $rateLimit || 320,
			samplerateLimit  => $samplerateLimit || 44100,
			clientid         => $clientid || 'undefined',
			groupid          => $clientprefs ? ($clientprefs->get('syncgroupid') || 0) : 0,
			name             => $client ? $client->name : 'undefined',
			player           => $player || 'undefined',
			channels         => $track->channels() || 2,
			outputChannels   => $clientprefs ? ($clientprefs->get('outputChannels') || 2) : 2,
		};
		
		# Check for optional profiles
		my $wanted = 0;
		my @got = ();
		foreach (@$want) {
			if (! $caps->{$_}) {
				$wanted++;
			} else {
				push @got, $_;
			}
		}
		
		if ($wanted) {
			# Save this - maybe we get a better offer later
			if (!$backupTranscoder || $backupTranscoder->{'wanted'} > $wanted) {
				$backupTranscoder = $transcoder;
				$transcoder = undef;
				$backupTranscoder->{'wanted'} = $wanted;
				$backupTranscoder->{'usedCapabilities'} = [@$need, @got];
			}
			next PROFILE;
		}
		
		last;
	}

	if (!$transcoder && $backupTranscoder) {
		# Use the backup option
		$transcoder = $backupTranscoder;
	}

	if (! $transcoder) {
		main::INFOLOG && $log->info("Error: Didn't find any command matches for type: $type");
	} else {
		main::INFOLOG && $log->is_info && $log->info("Matched: $type->", $transcoder->{'streamformat'}, " via: ", $transcoder->{'command'});
	}

	return wantarray ? ($transcoder, $error) : $transcoder;
}

#sub _dump_string {
#	use bytes;
#	my $res = '';
#	my $string = shift;
#	
#	for (my $i = 0; $i < length($string); $i++) {
#		my $c = substr($string, $i, 1);
#		my $o = ord($c);
#		if ($o > 127) {
#			$res .= sprintf("\\x%02X", $o);
#		} else {
#			$res .= $c;
#		}
#	}
#	return $res;
#}

sub tokenizeConvertCommand2 {
	my ($transcoder, $filepath, $fullpath, $noPipe, $quality) = @_;
	
	# Bug 10199 - make sure we do not promote any strings to decoded ones (8859-1 => UFT-8)
	use bytes;
	
	my $command = $transcoder->{'command'};
	
	# This must come above the FILE substitutions, otherwise it will break
	# files with [] in their names.
	
	while ( $command =~ /\[([^\]]+)\]/g ) {
		$binaries{$1} = Slim::Utils::Misc::findbin($1) unless $binaries{$1};
	}
	$command =~ s/\[([^\]]+)\]/'"' . $binaries{$1} . '"'/eg;
	
	my ($start, $end);
	
	my %subs;
	my %vars;

	# Special case for cuesheets. We pass the start and end
	# of the track within the file.
	if ($fullpath =~ /#([^-]+)-([^-]+)$/) {
		 ($start, $end) = ($1, $2);
	}
	
	if ($transcoder->{'start'}) {
		$start += $transcoder->{'start'};
	}
	
	if ($start) {
		push @{$transcoder->{'usedCapabilities'}}, 'T';
	}
	
	if ($end) {
		push @{$transcoder->{'usedCapabilities'}}, 'U';
	}
	
	# Start with some legacy ones
	
	my $profile = $transcoder->{'profile'};
	my $capabilities = $capabilities{$profile};
	
	# Find what substitutions we need to make
	foreach my $cap ($transcoder->{'streamMode'}, @{$transcoder->{'usedCapabilities'}}) {
		my ($arg, $value) = $capabilities->{$cap} =~ /(\w+)=(.+)/;
		next unless defined $value;
		$subs{$arg} = $value;
		
		# and find what variables they contain
		foreach ($value =~ m/%(.)/g) {
			$vars{$_} = 1;
		}
	}
	
	# escape $ and * in file names and URLs.
	# Except on Windows where $ and ` shouldn't be escaped and "
	# isn't allowed in filenames.
	if (!main::ISWINDOWS) {
		$filepath =~ s/([\$\"\`])/\\$1/g;
		$fullpath =~ s/([\$\"\`])/\\$1/g;
	}

	# Check to see if we need to flip the endianess on output
	$subs{'-x'}        = (unpack('n', pack('s', 1)) == 1) ? "" : "-x";

	$subs{'FILE'}      = ($filepath eq '-' ? $filepath : '"' . $filepath . '"');
	$subs{'URL'}       = '"' . $fullpath . '"';
	$subs{'QUALITY'}   = $quality;
	$subs{'CHANNELS'}  = $transcoder->{'channels'};
	$subs{'OCHANNELS'} = $transcoder->{'outputChannels'};
	$subs{'CLIENTID'}  = do { (my $tmp = $transcoder->{'clientid'}) =~ tr/.:/-/;  $tmp };
	$subs{'PLAYER'}    = do { (my $tmp = $transcoder->{'player'}  ) =~ tr/\" /_/; $tmp };
	$subs{'NAME'}      = do { (my $tmp = $transcoder->{'name'}    ) =~ tr/\" /_/; $tmp };
	$subs{'GROUPID'}   = $transcoder->{'groupid'} eq 0 ? $subs{'CLIENTID'} : do { (my $tmp = sprintf ( "g%011x", $transcoder->{'groupid'}) ) =~ s/..\K(?=.)/-/g; $tmp};

	foreach my $v (keys %vars) {
		my $value;
		
		if ($v eq 's') {$value = "$start";}
		elsif ($v eq 'u') {$value = "$end";}
		elsif ($v eq 't') {$value = Slim::Utils::DateTime::fracSecToMinSec($start);}
		elsif ($v eq 'v') {$value = Slim::Utils::DateTime::fracSecToMinSec($end);}
		elsif ($v eq 'w') {$value = $end - $start;}

		elsif ($v eq 'b') {$value = $transcoder->{'rateLimit'} * 1000;}
		elsif ($v eq 'B') {$value = $transcoder->{'rateLimit'};}

		elsif ($v eq 'd') {$value = $transcoder->{'samplerateLimit'};}
		elsif ($v eq 'D') {$value = $transcoder->{'samplerateLimit'} / 1000;}

		elsif ($v eq 'f') {$value = $subs{'FILE'};}
		elsif ($v eq 'F') {$value = '"' . $fullpath . '"';}

		elsif ($v eq 'i') {$value = $transcoder->{'clientid'};}
		elsif ($v eq 'I') {$value = $subs{'CLIENTID'};}
		elsif ($v eq 'p') {$value = $transcoder->{'player'};}
		elsif ($v eq 'P') {$value = $subs{'PLAYER'};}
		elsif ($v eq 'n') {$value = $transcoder->{'clientname'};}
		elsif ($v eq 'N') {$value = $subs{'NAME'};}
		elsif ($v eq 'C') {$value = $transcoder->{'channels'};}
		elsif ($v eq 'c') {$value = $transcoder->{'outputChannels'};}
		elsif ($v eq 'q') {$value = $quality;}
		elsif ($v eq 'Q') {$value = ($quality eq '0' ? '01' : $quality . '0');}
		elsif ($v eq 'g') {$value = $transcoder->{'groupid'};}
		elsif ($v eq 'G') {$value = $subs{'GROUPID'};}

		foreach (values %subs) {
			s/%$v/$value/ge;
		}
	}

	# replace subs
	foreach (keys %subs) {
		$command =~ s/\$$_\$/$subs{$_}/g;
	}

	# Try to read parameters from file referenced in the command's placeholder '${PREF-FILE.KEY}$' 
	while ($command && $command =~ /\$\{(.*?)\}\$/g) {
		my $placeholder = $1;
		my $transcoder  = $binaries{$placeholder} || '';
		
		if (!exists $binaries{$placeholder}) {
			my ($file, $pref) = $placeholder =~ /(.*)\.([^\.]+)$/;
			
			if ($file && $pref) {
				$transcoder = preferences($file)->get($pref) || '';
				$transcoder =~ s/\s+/ /;
			} 
			else {
				$log->warn("couldn't find file preferences for: $placeholder");
			}

			$binaries{$placeholder} = $transcoder;
		}
		
		$command =~ s/\${$placeholder}\$/$transcoder/g;
	}

	# clean all remaining '$*$'
	$command =~ s/\s+\$\w+\$//g;
	
	if (!defined($noPipe)) {
		$command .= (main::ISWINDOWS) ? '' : ' &';
		$command .= ' |';
	}

	main::INFOLOG && $log->is_info && $log->info("Using command for conversion: ", Slim::Utils::Unicode::utf8decode_locale($command));

	return $command;
}

sub _rateLimit {
	my ($client, $type, $bitrate) = @_;

	my $maxRate = 0;
	
	foreach ($client->syncGroupActiveMembers()) {
		my $rate = Slim::Utils::Prefs::maxRate($_);
		if ($rate && ($maxRate && $maxRate > $rate || !$maxRate)) {
			$maxRate = $rate;
		}
	}
	
	return 0 unless $maxRate;
	
	# If the input type is mp3 or wma (bug 9641), we determine whether the 
	# input bitrate is under the maximum.
	# We presume that we won't choose an output format that violates the rate limit.
	if (defined($type) && ($type eq 'mp3' || $type eq 'wma')) {
		return 0 if ($maxRate >= ($bitrate || 0)/1000);
	}
	
	return $maxRate;
}

1;

__END__
