package Slim::Utils::OSDetect;

use Slim::Utils::Misc;

# $Id: OSDetect.pm,v 1.3 2003/09/29 22:40:35 dean Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
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
# also sets the global $detectedOS to 'unix' 'win'
#
sub init {
	if (!$detectedOS) {

		$::d_os && Slim::Utils::Misc::msg("Auto-detecting OS: $^O\n");

		if ($^O =~/darwin/i) {
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
#		die "Sorry, the Slim Server runs on MacOS X, but not Mac OS Classic (9.X)"
#	}
	
}

1;

__END__
