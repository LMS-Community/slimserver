package Slim::Utils::OS::ReadyNAS;

use strict;
use File::Spec::Functions qw(:ALL);

use base qw(Slim::Utils::OS::Debian);

sub dontSetUserAndGroup { 1 }

sub initDetails {
	my $class = shift;

	$class->{osDetails} = $class->SUPER::initDetails();

	$class->{osDetails}->{isReadyNAS} = 1;

	return $class->{osDetails};
}


sub initPrefs {
	my ($class, $prefs) = @_;
	
	$prefs->{dbsource} = 'dbi:mysql:database=slimserver';
	
	# if this is a sparc based ReadyNAS, do some performance tweaks
	if ($class->{osDetails}->{osArch} =~ /sparc/) {	
		$prefs->{scannerPriority}   = 20;
		$prefs->{resampleArtwork}   = 0;
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

	if ($dir =~ /^(?:music|playlists)$/) {

		# let's do some optimistic tests
		my $path = catdir('/', 'media', 'Music');
		
		unless ($path && -r $path) {
			$path = $class->SUPER::dirsFor($dir);
		}
		
		push @dirs, $path;
	}
	else {
		@dirs = $class->SUPER::dirsFor($dir);
	}

	return wantarray() ? @dirs : $dirs[0];
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
		'lost+found'=> 1,
	);
}

#sub scanner {
#	return the path to the C based scanner
#	return '/usr/sbin/sc-scanner';
#}

1;