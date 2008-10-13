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
use File::Spec::Functions;
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

	my ($all, $cache, $filecache, $mysql, $prefs, $logs);
	
	GetOptions(
		'all'       => \$all,
		'cache'     => \$cache,
		'filecache' => \$filecache,
		'prefs'     => \$prefs,
		'logs'      => \$logs,
		'mysql'     => \$mysql,
	);

	my @folders;
	
	my $cacheFolder = $os->dirsFor('cache');

	push @folders, _target('cache', 'cache') if ($all || $cache);
	
	if ($filecache) {
		push @folders, {
			label   => 'file cache (artwork, templates etc.)',
			folders => [
				catdir($cacheFolder, 'Artwork'),
				catdir($cacheFolder, 'iTunesArtwork'),
				catdir($cacheFolder, 'FileCache'),
				catdir($cacheFolder, 'fonts.bin'),
				catdir($cacheFolder, 'strings.bin'),
				catdir($cacheFolder, 'cookies.dat'),
				catdir($cacheFolder, 'plugin-data.yaml'),
			],
		};
	}
		
	if ($mysql) {
		push @folders, {
			label   => 'MySQL data',
			folders => [
				catdir($cacheFolder, 'MySQL'),
				catdir($cacheFolder, 'my.cnf'),
				catdir($cacheFolder, 'squeezecenter-mysql.pid'),
				catdir($cacheFolder, 'squeezecenter-mysql.sock'),
				catdir($cacheFolder, 'mysql-error-log.txt'),
			],
		};
	}
		
	if ($all || $prefs) {
		push @folders, _target('prefs', 'preferences');
		push @folders, _target('oldprefs', 'old preferences (SlimServer <= 6.5)');
	}
	
	push @folders, _target('log', 'logs') if ($all || $logs);
	
	unless (scalar @folders) {
		usage();
		exit;
	}

	my $fallbackFolder = $os->dirsFor('');
		
	for my $item (@folders) {
		print "\nDeleting $item->{label}...\n";
		
		foreach ( @{$item->{folders}} ) {
			print "-> $_\n" if (-e $_);

			if (-d $_) {
				rmtree $_;
			}
			
			elsif (-f $_) {
				unlink $_;
			}
		}
	}
	
	print "\nDone. Please restart SqueezeCenter.\n\n";
}

sub usage {
	print <<EOF;
Usage: $0 [--all] [--prefs] [--cache]

Command line options:

	--mysql        Delete MySQL data (music database)
	--filecache    Delete file cache for artwork, templates etc.
	--prefs        Delete preference files
	--logs         Delete log files

	--cache   (!)  Clean cache folder, including music database, artwork cache
	               and favorites files (if no playlist folder is defined)

	--all     (!!) Wipe'em all
	
EOF

}

sub _target {
	my ($value, $label) = @_;
	
	my $f = $os->dirsFor($value);
	
	return {
		label   => $label,
		folders => [ $f ],
	};
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
