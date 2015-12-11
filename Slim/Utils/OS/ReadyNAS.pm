package Slim::Utils::OS::ReadyNAS;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);

use base qw(Slim::Utils::OS::Debian);

sub dontSetUserAndGroup { 1 }

sub initDetails {
	my $class = shift;

	$class->{osDetails} = $class->SUPER::initDetails();

	$class->{osDetails}->{isReadyNAS} = 1;

	# add Plugins folder to search path
	unshift @INC, '/c/.squeezeboxserver';

	return $class->{osDetails};
}


sub initPrefs {
	my ($class, $prefs) = @_;
	
	# if this is a sparc based ReadyNAS, do some performance tweaks
	if ($class->{osDetails}->{osArch} =~ /sparc/) {	
		$prefs->{scannerPriority}   = 20;
		$prefs->{disableStatistics} = 1;
	}
}


sub initMySQL {
	my ($class, $dbclass) = @_;
	
	$dbclass->confFile( '/etc/mysql/my.cnf' );
	
	if (!$dbclass->dbh) {
		$dbclass->startServer;
	}
}


sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs;

	if ($dir =~ /^(?:music|videos|pictures|playlists)$/) {

		# let's do some optimistic tests
		my $path;
		
		if ($dir =~ /(?:music|playlists)/) {
			$path = catdir('/', 'media', 'Music');
		}
		elsif ($dir eq 'videos') {
			$path = catdir('/', 'media', 'Videos');
		}
		elsif ($dir eq 'pictures') {
			$path = catdir('/', 'media', 'Pictures');
		}
		
		unless ($path && -r $path) {
			$path = $class->SUPER::dirsFor($dir);
		}
		
		push @dirs, $path;
	
	} elsif ($dir eq 'Plugins') {
			
		push @dirs, $class->SUPER::dirsFor($dir);
		push @dirs, "/c/.squeezeboxserver/Plugins";
		
	} elsif ($dir =~ /^(?:prefs)$/) {

		push @dirs, $::prefsdir || "/c/.squeezeboxserver/prefs";

	} elsif ($dir eq 'log') {

		push @dirs, $::logdir || "/c/.squeezeboxserver/log";

	} elsif ($dir eq 'cache') {

		push @dirs, $::cachedir || "/c/.squeezeboxserver/cache";

	} else {
		@dirs = $class->SUPER::dirsFor($dir);
	}

	return wantarray() ? @dirs : $dirs[0];
}


# log rotation on ReadyNAS seems to be broken - let's take care of this
sub logRotate {
	my $class   = shift;
	my $dir     = shift || $class->dirsFor('log');

    Slim::Utils::OS->logRotate($dir);
}


sub ignoredItems {
	return (
		'bin'       => '/',
		'dev'       => '/',
		'etc'       => '/',
		'frontview' => '/',
		'home'      => '/',
		'initrd'    => 1,
		'lib'       => '/',
		'mnt'       => '/',
		'opt'       => '/',
		'proc'      => '/',
		'ramfs'     => '/',
		'root'      => '/',
		'sbin'      => '/',
		'sys'       => '/',
		'tmp'       => '/',
		'USB'       => '/',
		'usr'       => '/',	
		'var'       => '/',
		'lib64'     => '/',
		'lost+found'=> 1,
	);
}

1;