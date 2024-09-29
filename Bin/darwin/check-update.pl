#!/usr/bin/env perl
#
# This script checks whether we have an update ready to be installed

use strict;
use FindBin qw($Bin);

BEGIN {
	my $libPath = "$Bin/../..";

	# This works like 'use lib'
	# prepend our directories to @INC so we look there first.
	unshift @INC, $libPath, "$libPath/CPAN";
}

use constant RESIZER => 0;
use constant SCANNER => 0;

use Slim::Utils::Light;
use Slim::Utils::OSDetect;

Slim::Utils::OSDetect::init();

if ( my $installer = Slim::Utils::Light->checkForUpdate() ) {
	require File::Basename;
	my $pwd = File::Basename::dirname($0);

	# new Menubar Item would pass localized strings for a notification
	if ($ENV{LMS_NOTIFICATION_TITLE} && $ENV{LMS_NOTIFICATION_CONTENT}) {
		`open $pwd/lms-notify.app`;
	}
	# legacy: run the preference pane
	else {
		`osascript $pwd/openprefs.scpt`;
	}
}

1;
