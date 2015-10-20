#!/usr/bin/perl
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
use constant SLIM_SERVICE => 0;

use Slim::Utils::Light;
use Slim::Utils::OSDetect;

Slim::Utils::OSDetect::init();

if ( my $installer = Slim::Utils::Light->checkForUpdate() ) {

	# run the preference pane
	require File::Basename;
	my $pwd = File::Basename::dirname($0);
	`osascript $pwd/openprefs.scpt`;
}

1;