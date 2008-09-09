package Slim::Utils::OS::ReadyNAS;

use strict;
use base qw(Slim::Utils::OS::Debian);

sub initDetails {
	my $class = shift;

	$class->{osDetails} = $class->SUPER::initDetails();

	$class->{osDetails}->{osName} = 'Netgear RAIDiator';

	return $class->{osDetails};
}

sub dontSetUserAndGroup { 1 }

sub initPrefs {
	my ($class, $prefs) = @_;

	$prefs->{dbsource}          = 'dbi:mysql:database=slimserver';
	$prefs->{scannerPriority}   = 20;
	$prefs->{resampleArtwork}   = 0;
	$prefs->{disableStatistics} = 1;
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