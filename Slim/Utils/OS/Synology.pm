package Slim::Utils::OS::Synology;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.
#
# This module was initially written by Philippe Kehl <phkehl at gmx dot net>

use strict;

use Config;

use base qw(Slim::Utils::OS::Linux);

use constant MAX_LOGSIZE => 1024*1024*1; # maximum log size: 1 MB
use constant MUSIC_DIR   => '/volume1/music';
use constant PHOTOS_DIR  => '/volume1/photo';
use constant VIDEOS_DIR  => '/volume1/video';

sub initDetails {
	my $class = shift;

	$class->{osDetails} = $class->SUPER::initDetails();
	$class->{osDetails}->{osArch} ||= $Config{'archname'};

	$class->{osDetails}->{isDiskStation} = 1;

	if ( !main::RESIZER && !main::SCANNER ) {
		open(my $versionInfo, '<', '/etc/VERSION') or warn "Can't open /etc/VERSION: $!";

		if ($versionInfo) {
			while (<$versionInfo>) {
				if (/productversion="(.*?)"/i) {
					$class->{osDetails}->{osName} = "Synology DSM $1";
					last;
				}
			}

			close $versionInfo;
		};
	}

	return $class->{osDetails};
}

sub localeDetails {
	my $lc_ctype = 'utf8';
	my $lc_time = 'C';

	return ($lc_ctype, $lc_time);
}


sub logRotate {
	my $class   = shift;
	my $dir     = shift || Slim::Utils::OSDetect::dirsFor('log');

	# only keep small log files (1MB) because they are displayed
	# (if at all) in a web interface
	Slim::Utils::OS->logRotate($dir, MAX_LOGSIZE);
}

sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs = $class->SUPER::dirsFor($dir);

	if ($dir =~ /^(?:music|videos|pictures)$/) {
		my $mediaDir;

		if ($dir eq 'music' && -d MUSIC_DIR) {
			$mediaDir = MUSIC_DIR;
		}
		# elsif ($dir eq 'videos' && -d VIDEOS_DIR) {
		# 	$mediaDir = VIDEOS_DIR;
		# }
		# elsif ($dir eq 'pictures' && -d PHOTOS_DIR) {
		# 	$mediaDir = PHOTOS_DIR;
		# }

		push @dirs, $mediaDir if $mediaDir;
	}

	return wantarray() ? @dirs : $dirs[0];
}

# ignore the many @... sub-folders. The static list in ignoredItems() would never be complete.
sub postInitPrefs {
	my ($class, $prefs) = @_;

	# only do this once - if somebody decides to modify the value, so be it!
	if (!$prefs->get('ignoreDirREForSynologySet') && !$prefs->get('ignoreDirRE')) {
		$prefs->set('ignoreDirRE', '^@[a-zA-Z]+');
		$prefs->set('ignoreDirREForSynologySet', 1);
	}
}

sub ignoredItems {
	return (
		'@AntiVirus'   => 1,
		'@appstore'    => 1,   # Synology package manager
		'@autoupdate'  => 1,
		'@clamav'      => 1,
		'@cloudsync'   => 1,
		'@database'    => 1,   # databases store
		'@download'    => 1,
		'@eaDir'       => 1,   # media indexer meta data
		'@img_bkp_cache' => 1,
		'@maillog'     => 1,
		'@MailScanner' => 1,
		'@optware'     => 1,   # NSLU2-Linux Optware system
		'@postfix'     => 1,
		'@quarantine'  => 1,
		'@S2S'         => 1,
		'@sharesnap'   => 1,
		'@spool'       => 1,   # mail/print/.. spool
		'@SynoFinder-log'             => 1,
		'@synodlvolumeche.core'       => 1,
		'@SynologyApplicationService' => 1,
		'@synologydrive'              => 1,
		'@SynologyDriveShareSync'     => 1,
		'@synopkg'     => 1,
		'@synovideostation'           => 1,
		'@tmp'         => 1,   # system temporary files
		'upd@te'       => 1,   # firmware update temporary directory
		'#recycle'     => 1,
		'#snapshot'    => 1,
		# system paths in the fs root which will not contain any music
		'bin'          => '/',
		'config'       => '/',
		'dev'          => '/',
		'etc'          => '/',
		'etc.defaults' => '/',
		'home'         => '/',
		'initrd'       => '/',
		'lib'          => '/',
		'lib32'        => '/',
		'lib64'        => '/',
		'linuxrc'      => '/',
		'lost+found'   => 1,
		'mnt'          => '/',
		'opt'          => '/',
		'proc'         => '/',
		'root'         => '/',
		'run'          => '/',
		'sbin'         => '/',
		'sys'          => '/',
		'tmp'          => '/',
		'tmpRoot'      => '/',
		'usr'          => '/',
		'var'          => '/',
		'var.defaults' => '/',
		# now only the data partition mount points /volume(|USB)[0-9]
		# should remain
	);
}

1;
