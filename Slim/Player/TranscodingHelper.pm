package Slim::Player::TranscodingHelper;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Player::Sync;
use Slim::Utils::DateTime;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Unicode;

{
	if ($^O =~ /Win32/) {
		require Win32;
	}
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

	$log->info("Loading conversion config files...");

	# custom convert files allowed at server root or root of plugin directories
	for my $baseDir (Slim::Utils::OSDetect::dirsFor('convert')) {

		push @convertFiles, (
			catdir($baseDir, 'convert.conf'),
			catdir($baseDir, 'custom-convert.conf'),
			catdir($baseDir, 'slimserver-convert.conf'),
		);
	}

	foreach my $baseDir (Slim::Utils::PluginManager->pluginRootDirs()) {

		push @convertFiles, catdir($baseDir, 'custom-convert.conf');
	}
	
	if ( main::SLIM_SERVICE ) {
		# save time by only including native formats on SN
		@convertFiles = (
			catdir($FindBin::Bin, 'slimservice-convert.conf'),
		);
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

				if ( $log->is_debug ) {
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
# O - can seek to a byte offset in the source stream
# T - can seek to a start time offset
# U - can seek to start time offset and finish at end time offset
#
# D - can downsample 
# B - can limit bitrate
#
# Substitution strings for variable capabilities
# %f - file path (local files)
# %F - full URL (remote streams)
#
# %o - stream start byte offset
# 
# %S - stream samples start offset
# %s - stream seconds start offset
# %t - stream time (m:ss) start offset
# %U - stream samples end offset
# %u - stream seconds end offset
# %v - stream time (m:ss) end offset
# %w - stream seconds duration

#
# %b - limit bitrate: b/s
# %B - limit bitrate: kb/s
# %d - samplerate: samples/s
# %D - samplerate: ksamples/s

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

	$log->debug("Checking to see if $profile is enabled");

	my @disabled = @{ $prefs->get('disabledformats') };

	if (!@disabled) {
		return 1;
	}

	if ( $log->is_debug ) {
		$log->debug("There are " . scalar @disabled . " disabled formats...");
	}
	
	for my $format (@disabled) {

		$log->debug("Testing $format vs $profile");

		if ($format eq $profile) {

			$log->debug("** $profile Disabled **");

			return 0;
		}
	}

	return 1;
}

sub checkBin {
	my $profile            = shift;
	my $ignoreprefsettings = shift;

	my $command;

	$log->debug("Checking formats for: $profile");

	# get the command for this profile
	$command = $commandTable{$profile};

	# if the user's disabled the profile, then skip it unless we're changing the prefs...
	return undef unless $command && ( defined($ignoreprefsettings) || enabledFormat($profile) );

	$log->debug("   enabled");

	if ($command) {
		$log->debug("  Found command: $command");
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
	my ($song, $type, $streamModes, $need, $want) = @_;
	
	my $track  = $song->currentTrack();
	$type ||= Slim::Music::Info::contentType($track);

	my $client = $song->master();
	my $player;
	my $clientid;
	my $transcoder  = undef;
	my $backupTranscoder  = undef;
	my $url      = blessed($track) && $track->can('url') ? $track->url : $track;

	my @supportedformats = ();
	my %formatcounter    = ();
	
	# Check if we need to ratelimit
	my $rateLimit = rateLimit($client, $url, $type);
	RATELIMIT: if ($rateLimit) {
		foreach (@$want) {
			last RATELIMIT if /B/;
		}
		push @$want, 'B';
	}
	
	# Check if we need to downsample
	my $samplerateLimit = samplerateLimit($song);
	SAMPLELIMIT: if ($samplerateLimit) {
		foreach (@$need) {
			last SAMPLELIMIT if /D/;
		}
		push @$need, 'D';
	}
		
	# special case for FLAC cuesheets for SB2. For now, we
	# let flac do the seeking to the correct point and transcode
	# to a complete stream that we can send to SB2.
	# Yucky, but a stopgap until we get FLAC seeking code into
	# a Perl invokable form.
	if (($type eq "flc") && ($url =~ /#([^-]+)-([^-]+)$/)) {
		my ($foundU, $foundT);
		foreach (@$need) {
			$foundT = 1 if /T/;
			$foundU = 1 if /U/;
		}
		push @$need, 'T' if ! $foundT;
		push @$need, 'U' if ! $foundU;
	}
	
	if (defined($client)) {

		my @playergroup = $client->syncGroupActiveMembers();

		$player   = $client->model();
		$clientid = $client->id();	

		$log->debug("rateLimit = $rateLimit, type = $type, $player = $clientid");
	
		# make sure we only test formats that are supported.
		foreach my $everyclient (@playergroup) {
								
			foreach my $supported ($everyclient->formats()) {
				$formatcounter{$supported}++;
			}
		}
		
		foreach my $testformat ($client->formats()) {
			
			if ($formatcounter{$testformat} == @playergroup) {
				push @supportedformats, $testformat;
			}
		}

	} else {

		$rateLimit = 0;
		@supportedformats = qw(aif wav mp3);
	}
	
	# Switch Apple Lossless files from a CT of 'mov' to 'alc' for
	# conversion purposes, so we can use 'alac' if it's available.
	# 
	# Bug: 2095
	if ($type eq 'mov' && blessed($track) && $track->lossless) {
		$log->debug("Track is alac - updating type!");
		$type = 'alc';
	}

	# Build the full list of possible profiles
	my @profiles = ();
	foreach my $checkFormat (@supportedformats) {

		if ($client) {
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
		next PROFILE if ! $streamMode;
		
		# Check for mandatory capabilities
		foreach (@$need) {
			next PROFILE if ! $caps->{$_};
		}

		# We can't handle WMA Lossless in firmware.
		if ($command eq "-"
			&& $type eq 'wma' && blessed($track) && $track->lossless) {
				next PROFILE;
		}

		$transcoder = {
			command => $command,
			profile => $profile,
			usedCapabilities => [@$need, @$want],
			streamMode => $streamMode,
			streamformat => ((split (/-/, $profile))[1]),
			rateLimit => $rateLimit,
			samplerateLimit => $samplerateLimit,
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
		$log->info("Error: Didn't find any command matches for type: $type");
	} else {
		$log->is_info && $log->info("Matched: $type->", $transcoder->{'streamformat'}, " via: ", $transcoder->{'command'});
	}

	return $transcoder;
}

sub tokenizeConvertCommand2 {
	my ($transcoder, $filepath, $fullpath, $noPipe, $quality) = @_;
	
	my $command = $transcoder->{'command'};
	
	# This must come above the FILE substitutions, otherwise it will break
	# files with [] in their names.
	$command =~ s/\[([^\]]+)\]/'"' . Slim::Utils::Misc::findbin($1) . '"'/eg;

	my ($start, $end);
	# Special case for FLAC cuesheets. We pass the start and end
	# of the track within the FLAC file.
	if ($fullpath =~ /#([^-]+)-([^-]+)$/) {
		 ($start, $end) = ($1, $2);
	}
	
	if ($transcoder->{'start'}) {
		$start += $transcoder->{'start'};
	}
		
	my %subs;
	my %vars;
	
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
	if (!Slim::Utils::OSDetect::isWindows()) {
		$filepath =~ s/([\$\"\`])/\\$1/g;
		$fullpath =~ s/([\$\"\`])/\\$1/g;
	}

	if (Slim::Music::Info::isFile($filepath)) {
		$filepath = Slim::Utils::OSDetect::getOS->decodeExternalHelperPath($filepath);
	}
	
	foreach my $v (keys %vars) {
		my $value;
		
		if ($v eq 's') {$value = "$start";}
		elsif ($v eq 'u') {$value = "$end";}
		elsif ($v eq 't') {$value = Slim::Utils::DateTime::fracSecToMinSec($start);}
		elsif ($v eq 'v') {$value = Slim::Utils::DateTime::fracSecToMinSec($end);}
		elsif ($v eq 'w') {$value = $start - $end;}

		elsif ($v eq 'b') {$value = ($transcoder->{'rateLimit'} || 320) * 1000;}
		elsif ($v eq 'B') {$value = ($transcoder->{'rateLimit'} || 320);}
		
		elsif ($v eq 'd') {$value = ($transcoder->{'samplerateLimit'} || 44100);}
		elsif ($v eq 'D') {$value = ($transcoder->{'samplerateLimit'} || 44100) / 1000;}
		
		elsif ($v eq 'f') {$value = '"' . $filepath . '"';}
		elsif ($v eq 'F') {$value = '"' . $fullpath . '"';}
		
		foreach (values %subs) {
			s/%$v/$value/ge;
		}
	}

	
	# Check to see if we need to flip the endianess on output
	$subs{'-x'} = (unpack('n', pack('s', 1)) == 1) ? "" : "-x";
	
	$subs{'FILE'} = '"' . $filepath . '"';
	$subs{'URL'} = '"' . $fullpath . '"';
	$subs{'QUALITY'} = $quality;
	
	foreach (keys %subs) {
		$command =~ s/\$$_\$/$subs{$_}/;
	}

	# XXX What was this for?
	# $command =~ s/\$([^\$\\]+)\$/'"' . Slim::Utils::Misc::findbin($1) . '"'/eg;
	
	$command =~ s/\s+\$\w+\$//g;
	
	if (!defined($noPipe)) {
		$command .= (Slim::Utils::OSDetect::isWindows()) ? '' : ' &';
		$command .= ' |';
	}

	$log->debug("Using command for conversion: $command");

	return $command;
}

sub rateLimit {
	my $client     = shift;
	my $fullpath   = shift;
	my $type       = shift || Slim::Music::Info::contentType($fullpath);

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

		my $track = Slim::Schema->rs('Track')->objectForUrl($fullpath);
		my $rate  = 0;

		if (blessed($track) && $track->can('bitrate')) {
			$rate = ($track->bitrate || 0)/1000;
		}

		return 0 if ($maxRate >= $rate);
	}
	
	return $maxRate;
}

sub samplerateLimit {
	my $song     = shift;
	
	return undef if ! $song->currentTrack()->samplerate;

	my $maxRate = 0;
	
	foreach ($song->{'owner'}->activePlayers()) {
		my $rate = $_->maxSupportedSamplerate();
		if ($rate && ($maxRate && $maxRate > $rate || !$maxRate)) {
			$maxRate = $rate;
		}
	}
	
	if ($maxRate && $maxRate < $song->currentTrack()->samplerate) {
		if (($maxRate % 12000) == 0 && ($song->currentTrack()->samplerate % 11025) == 0) {
			$maxRate = int($maxRate * 11025 / 12000);
		}
		return $maxRate;
	}
	
	return undef;
}

1;

__END__
