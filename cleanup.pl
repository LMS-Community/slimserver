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

my $useWx = eval {
	require Wx;
	require Wx::Event;

	return $^O !~ /darwin/ || $^X =~ /wxPerl/i;
};

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
	
	my $folders = getFolderList({
		'all'       => $all,
		'cache'     => $cache,
		'filecache' => $filecache,
		'prefs'     => $prefs,
		'logs'      => $logs,
		'mysql'     => $mysql,
	});
	
	unless (scalar @$folders) {

		# show simple GUI if possible
		if ($useWx) {
			require Slim::Utils::CleanupGUI;
			my $app = Slim::Utils::CleanupGUI->new({
				running  => checkForSC(),
				title    => 'SqueezeCenter Cleanup',
				cancel   => 'Cancel',
				cleanup  => 'Run Cleanup',
				options  => options(),
				folderCB => \&getFolderList,
				cleanCB  => \&cleanup,
				msgCap   => "Cleanup successfully run",
				msg      => 'Please restart SqueezeCenter for the changes to take effect.'
			});
			$app->MainLoop;
		}

		else {		
			usage();
			exit;
		}
	}

	cleanup($folders);
	
	print "\nDone. Please restart SqueezeCenter.\n\n" unless $useWx;
}

sub usage {
	print <<EOF;
Usage: $0 [--all] [--prefs] [--cache]

Command line options:

	--mysql        Delete MySQL data (music information database)
	--filecache    Delete file cache for artwork, templates etc.
	--prefs        Delete preference files
	--logs         Delete log files

	--cache   (!)  Clean cache folder, including music database, artwork cache
	               and favorites files (if no playlist folder is defined)

	--all     (!!) Wipe'em all
	
EOF

}

sub getFolderList {
	my $args = shift;
	
	my @folders;
	my $cacheFolder = $os->dirsFor('cache');

	push @folders, _target('cache', 'cache') if ($args->{all} || $args->{cache});
	
	if ($args->{filecache}) {
		push @folders, {
			label   => 'file cache (artwork, templates etc.)',
			folders => [
				catdir($cacheFolder, 'Artwork'),
				catdir($cacheFolder, 'iTunesArtwork'),
				catdir($cacheFolder, 'FileCache'),
				catdir($cacheFolder, 'fonts.bin'),
				catdir($cacheFolder, 'strings.bin'),
				catdir($cacheFolder, 'templates'),
				catdir($cacheFolder, 'cookies.dat'),
				catdir($cacheFolder, 'plugin-data.yaml'),
			],
		};
	}
		
	if ($args->{mysql}) {
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
		
	if ($args->{all} || $args->{prefs}) {
		push @folders, _target('prefs', 'preferences');
		push @folders, _target('oldprefs', 'old preferences (SlimServer <= 6.5)');
	}
	
	push @folders, _target('log', 'logs') if ($args->{all} || $args->{logs});

	return \@folders;
}

sub _target {
	my ($value, $label) = @_;
	
	my $f = $os->dirsFor($value);
	
	return {
		label   => $label,
		folders => [ $f ],
	};
}

sub options {
	
	my $options = [
		{
			name     => 'prefs',
			title    => 'Preference files',
			position => [30, 20],
		},
	
		{
			name     => 'filecache',
			title    => 'File cache (artwork, templates etc.)',
			position => [30, 40],
		},
	
		{
	
			name     => 'mysql',
			title    => 'MySQL data (music information database)',
			position => [30, 60],
		},
	
		{
	
			name     => 'logs',
			title    => 'Log files',
			position => [30, 80],
		},
	
		{
	
			name     => 'cache',
			margin   => 20,
			title    => "(!) Clean cache folder, including music database, artwork cache \nand favorites files (if no playlist folder is defined)",
			position => [30, 120],
		},
	
		{
	
			name     => 'all',
			title    => '(!!) Wipe\'em all - don\'t do this unless told!',
			position => [30, 160],
		},
	];

	return $options;
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


sub cleanup {
	my $folders = shift;

	my $fallbackFolder = $os->dirsFor('');
		
	for my $item (@$folders) {
		print "\nDeleting $item->{label}...\n" unless $useWx;
		
		foreach ( @{$item->{folders}} ) {
			next unless $_;
			
			print "-> $_\n" if (-e $_ && !$useWx);

			if (-d $_) {
				rmtree $_;
			}
			
			elsif (-f $_) {
				unlink $_;
			}
		}
	}
}

__END__
