package Slim::Utils::OSDetect;

use Slim::Utils::Misc;

# $Id: OSDetect.pm,v 1.1 2003/07/18 19:42:15 dean Exp $

# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

my $detectedOS = undef;

sub OS {
	if (!$detectedOS) { init(); }
	return $detectedOS;
}

#
# Figures out where the preferences file should be on our platform, and loads it.
# also sets the global $detectedOS to 'unix' 'win' or 'mac'
#
sub init {
	if (!$detectedOS) {

		$::d_os && Slim::Utils::Misc::msg("Auto-detecting OS: $^O\n");

		if ($^O =~/^macos/i) {
			$detectedOS = 'mac';

		} elsif ($^O =~ /^m?s?win/i) {
			$detectedOS = 'win';

		} else {
			$detectedOS = 'unix';
		}

		$::d_os && Slim::Utils::Misc::msg("I think it's \"$detectedOS\".\n");

	} else {
		$::d_os && Slim::Utils::Misc::msg("OS detection skipped, using \"$detectedOS\".\n");
	}

	# figure out where the prefs file should be on this platform:
#	if ($detectedOS eq 'mac') {
#
#		die "Sorry, the SliMP3 server runs on MacOS X, but not Mac OS Classic (9.X)"
#	}
	
}

1;

__END__
