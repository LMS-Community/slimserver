package Slim::Player::TranscodingHelper;

# $Id$

# SlimServer Copyright (C) 2001-2004 Logitech.
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

our %commandTable = ();
our %binaries = ();

sub Conversions {
	return \%commandTable;
}

my $log = logger('player.source');

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

				my $command = <CONVERT>;

				$command =~ s/^\s*//o;
				$command =~ s/\s*$//o;

				$log->debug(
					"input: '$inputtype' output: '$outputtype' clienttype: " .
					"'$clienttype': clientid: '$clientid': '$command'"
				);

				next unless defined $command && $command !~ /^\s*$/;

				$commandTable{"$inputtype-$outputtype-$clienttype-$clientid"} = $command;
			}
		}

		close CONVERT;
	}
}

sub enabledFormat {
	my $profile = shift;

	$log->debug("Checking to see if $profile is enabled");

	my $count = Slim::Utils::Prefs::getArrayMax('disabledformats');

	if (!defined($count) || $count < 0) {
		return 1;
	}

	$log->debug("There are $count disabled formats...");

	for (my $i = $count; $i >= 0; $i--) {

		my $disabled = Slim::Utils::Prefs::getInd('disabledformats', $i);

		$log->debug("Testing $disabled vs $profile");

		if ($disabled eq $profile) {

			$log->debug("** $profile Disabled **");

			return 0;
		}
	}

	return 1;
}

sub checkBin {
	my $profile = shift;
	my $command;

	$log->debug("Checking formats for: $profile");

	# get the command for this profile
	$command = $commandTable{$profile};

	# if the user's disabled the profile, then skip it...
	return undef unless $command && enabledFormat($profile);

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

sub getConvertCommand {
	my $client = shift;
	my $track  = shift || return;
	my $type   = shift || Slim::Music::Info::contentType($track);

	my $player;
	my $clientid;
	my $command  = undef;
	my $format   = undef;
	my $url      = blessed($track) && $track->can('url') ? $track->url : $track;

	my @supportedformats = ();
	my %formatcounter    = ();
	my $audibleplayers   = 0;

	my $underMax;

	if (defined($client)) {

		my @playergroup = ($client, Slim::Player::Sync::syncedWith($client));

		$player   = $client->model();
		$clientid = $client->id();	
		$underMax = underMax($client, $url, $type);

		$log->debug("undermax = $underMax, type = $type, $player = $clientid");
	
		# make sure we only test formats that are supported.
		foreach my $everyclient (@playergroup) {
			
			next if $everyclient->prefGet('silent');
			
			$audibleplayers++;
			
			foreach my $supported ($everyclient->formats()) {
				$formatcounter{$supported}++;
			}
		}
		
		foreach my $testformat ($client->formats()) {
			
			if ($formatcounter{$testformat} == $audibleplayers) {
				push @supportedformats, $testformat;
			}
		}

	} else {

		$underMax = 1;
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

	foreach my $checkFormat (@supportedformats) {

		my @profiles = ();

		if ($client) {
			push @profiles, (
				"$type-$checkFormat-$player-$clientid",
				"$type-$checkFormat-*-$clientid",
				"$type-$checkFormat-$player-*"
			);
			
			# Bug 4022, support Transporter for WMA by also checking SB2 profiles
			if ( $player eq 'transporter' ) {
				push @profiles, "$type-$checkFormat-squeezebox2-*";
			}
		}

		push @profiles, "$type-$checkFormat-*-*";

		foreach my $profile (@profiles) {

			$command = checkBin($profile);

			last if $command;
		}

		$format = $checkFormat;

		if (defined $command && $command eq "-") {

			# special case for mp3 to mp3 when input is higher than
			# specified max bitrate.
			if (!$underMax && $type eq "mp3") {
				$command = $commandTable{"mp3-mp3-transcode-*"};
			}			

			# special case for FLAC cuesheets for SB2. For now, we
			# let flac do the seeking to the correct point and transcode
			# to a complete stream that we can send to SB2.
			# Yucky, but a stopgap until we get FLAC seeking code into
			# a Perl invokable form.
			elsif (($type eq "flc") && ($url =~ /#([^-]+)-([^-]+)$/)) {
				$command = $commandTable{"flc-flc-transcode-*"};
			}

			$underMax = 1;

			# We can't handle WMA Lossless in firmware. So move to the next format type.
			if ($type eq 'wma' && $checkFormat eq 'wma' && blessed($track) && $track->lossless) {

				next;
			}
		}

		# only finish if the rate isn't over the limit
		if ($command && (!defined($client) || underMax($client, $url, $format))) {
			last;
		}
	}

	if (!defined $command) {

		$log->error("Error: Didn't find any command matches for type: $type format: $format");

		$format = $type;
	} else {

		$log->info("Matched Format: $format Type: $type Command: $command");
	}

	return ($command, $type, $format);
}

sub tokenizeConvertCommand {
	my ($command, $type, $filepath, $fullpath, $sampleRate, $maxRate, $noPipe, $quality) = @_;

	# Check to see if we need to flip the endianess on output
	my $swap = (unpack('n', pack('s', 1)) == 1) ? "" : "-x";

	# Special case for FLAC cuesheets. We pass the start and end
	# of the track within the FLAC file.
	if ($fullpath =~ /#([^-]+)-([^-]+)$/) {

		my ($start, $end) = ($1, $2);

		$command =~ s/\$START\$/Slim::Utils::DateTime::fracSecToMinSec($start)/eg;
		$command =~ s/\$END\$/Slim::Utils::DateTime::fracSecToMinSec($end)/eg;

	} else {

		$command =~ s/\$START\$/0/g;
		$command =~ s/\$END\$/-0/g;
	}

	# This must come above the FILE substitutions, otherwise it will break
	# files with [] in their names.
	$command =~ s/\[([^\]]+)\]/'"' . Slim::Utils::Misc::findbin($1) . '"'/eg;

	# escape $ and * in file names and URLs.
	# Except on Windows where $ and ` shouldn't be escaped and "
	# isn't allowed in filenames.
	if (Slim::Utils::OSDetect::OS() ne 'win') {
		$filepath =~ s/([\$\"\`])/\\$1/g;
		$fullpath =~ s/([\$\"\`])/\\$1/g;
	}
	
	# Bug 3396, mov123 commands for URLs must pass the URL to mov123, instead of using stdin
	if ( $command =~ /mov123/ && $fullpath =~ /^http/ ) {
		$filepath = $fullpath;
	}
	
	$command =~ s/\$FILE\$/"$filepath"/g;
	$command =~ s/\$URL\$/"$fullpath"/g;
	$command =~ s/\$RATE\$/$sampleRate/g;
	$command =~ s/\$QUALITY\$/$quality/g;
	$command =~ s/\$BITRATE\$/$maxRate/g;
	$command =~ s/\$-x\$/$swap/g;

	$command =~ s/\$([^\$\\]+)\$/'"' . Slim::Utils::Misc::findbin($1) . '"'/eg;

	if (!defined($noPipe)) {
		$command .= (Slim::Utils::OSDetect::OS() eq 'win') ? '' : ' &';
		$command .= ' |';
	}

	$log->debug("Using command for conversion: $command");

	return $command;
}

sub underMax {
	my $client   = shift;
	my $fullpath = shift;
	my $type     = shift || Slim::Music::Info::contentType($fullpath);

	my $maxRate  = Slim::Utils::Prefs::maxRate($client);

	# If we're not rate limited, we're under the maximum.
	# If we don't have lame, we can't transcode, so we
	# fall back to saying we're under the maximum.
	return 1 if $maxRate == 0 || (!Slim::Utils::Misc::findbin('lame'));

	# If the input type is mp3, we determine whether the 
	# input bitrate is under the maximum.
	if (defined($type) && $type eq 'mp3') {

		my $track = Slim::Schema->rs('Track')->objectForUrl($fullpath);
		my $rate  = 0;

		if (blessed($track) && $track->can('bitrate')) {

			$rate = ($track->bitrate || 0)/1000;
		}

		return ($maxRate >= $rate);
	}
	
	# For now, we assume the output is raw 44.1Khz, 16 bit, stereo PCM
	# in all other cases. In that case, we're over any set maximum. 
	# In the future, we may want to do finer grained testing here - the 
	# PCM may have different parameters  and we may be able to stream other
	# formats.
	return 0;
}

1;

__END__
