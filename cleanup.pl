#!/usr/bin/perl -w

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

require 5.008_001;
use strict;
use File::Path;
use Getopt::Long;
use Socket;

use constant SLIM_SERVICE => 0;

use Slim::bootstrap;
use Slim::Utils::OSDetect;

my $os;

sub main {
	Slim::Utils::OSDetect::init();
	$os = Slim::Utils::OSDetect->getOS();

	if (checkForSC()) {
		print "\nPlease Stop SqueezeCenter before running the cleanup.\n\n";
		exit;
	}

	my ($all, $cache, $prefs, $logs, $playlists);
	
	GetOptions(
		'all'   => \$all,
		'cache' => \$cache,
		'prefs' => \$prefs,
		'logs'  => \$logs
	);

	my %folders;
	
	$folders{cache} = 'cache' if ($all || $cache);
#	$folders{playlists} = 'playlists' if ($all || $playlists);
	
	if ($all || $prefs) {
		$folders{prefs} = 'preferences';
		$folders{oldprefs} = 'old preferences (SlimServer <= 6.5)';
	}
	
	unless (scalar keys %folders) {
		usage();
		exit;
	}
		
	for my $folder (keys %folders) {
		print "\nDeleting $folders{$folder} files and folders...\n";
		
		foreach ($os->dirsFor($folder)) {
			print "-> $_\n";
			rmtree $_;
		}
	}
	
	print "\nDone. Please restart SqueezeCenter.\n\n";
}


sub usage {
	print <<EOF;
Usage: $0 [--all] [--prefs] [--cache]

Command line options:

	--cache        Clean cache folder, including music database
	--prefs        Delete preference files
	--all          Wipe'em all
	
EOF

}

sub checkForSC {
	my $raddr = '127.0.0.1';
	my $rport = 3483;

	my $iaddr = inet_aton($raddr);
	my $paddr = sockaddr_in($rport, $iaddr);

	socket(SSERVER, PF_INET, SOCK_STREAM, getprotobyname('tcp'));

	if (connect(SSERVER, $paddr)) {

		close(SSERVER);
		return 1;
	}

	return 0;
}

main();

__END__
