#!/usr/bin/perl -w -ICPAN

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
use utf8;

use constant SLIM_SERVICE => 0;
use constant SCANNER => 0;
use constant DEBUG => 1;

use Slim::Utils::OSDetect;
use Slim::Utils::Light;

BEGIN {
	if ($^O =~ /win/i) {
		eval { require Wx::Perl::Packager; }
	}
}

my $useWx = eval {
	require Wx;
	require Wx::Event;
	require Slim::GUI::ControlPanel;

	# don't use Wx, if script is run using perl on OSX
	# it needs to be run using wxperl
	return $^O !~ /darwin/ || $^X =~ /wxPerl/i;
};

if (DEBUG && $@) {
	print "GUI can't be loaded: $@\n";
}

my ($os);

sub main {
	Slim::Utils::OSDetect::init();
	$os = Slim::Utils::OSDetect->getOS();
	
	if (checkForSC() && !$useWx) {
		print sprintf("\n%s\n\n", string('CLEANUP_PLEASE_STOP_SC'));
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
			
			my $app = Slim::GUI::ControlPanel->new({
				folderCB => \&getFolderList,
				cleanCB  => \&cleanup,
				options  => options(),
			});
			
			$app->MainLoop;
			exit;
		}

		else {		
			usage();
			exit;
		}
	}

	cleanup($folders);
	
	print sprintf("\n%s\n\n", string('CLEANUP_PLEASE_RESTART_SC'));
}

sub usage {
	my $usage = <<EOF;
%s: $0 [--all] [--prefs] [--cache]

%s

	--mysql        %s
	--filecache    %s
	--prefs        %s
	--logs         %s

	--cache   (!)  %s

	--all     (!!) %s
	
EOF
	print sprintf($usage, 
		string('CLEANUP_USAGE'), 
		string('CLEANUP_COMMAND_LINE'),
		string('CLEANUP_MYSQL'),
		string('CLEANUP_FILECACHE'),
		string('CLEANUP_PREFS'),
		string('CLEANUP_LOGS'),
		string('CLEANUP_CACHE'),
		string('CLEANUP_ALL'),
	);
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
			title    => string('CLEANUP_PREFS'),
			position => [30, 20],
		},
	
		{
			name     => 'filecache',
			title    => string('CLEANUP_FILECACHE'),
			position => [30, 40],
		},
	
		{
	
			name     => 'mysql',
			title    => string('CLEANUP_MYSQL'),
			position => [30, 60],
		},
	
		{
	
			name     => 'logs',
			title    => string('CLEANUP_LOGS'),
			position => [30, 80],
		},
	
		{
	
			name     => 'cache',
			margin   => 20,
			title    => '(!) ' . string('CLEANUP_CACHE'),
			position => [30, 120],
		},
	
		{
	
			name     => 'all',
			title    => '(!!) ' . string('CLEANUP_ALL'),
			position => [30, 160],
		},
	];

	return $options;
}

sub checkForSC {
	my $iaddr = inet_aton('127.0.0.1');
	my $paddr = sockaddr_in(3483, $iaddr);

	socket(SSERVER, PF_INET, SOCK_STREAM, getprotobyname('tcp'));

	if (connect(SSERVER, $paddr)) {

		close(SSERVER);
		return 1;
	}

	return 0;
}

sub cleanup {
	my $folders = shift;

	my $fallbackFolder = $os->dirsFor('');
		
	for my $item (@$folders) {
		print sprintf("\n%s %s...\n", string('CLEANUP_DELETING'), $item->{label}) unless $useWx;
		
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

main();

__END__
