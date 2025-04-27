package Slim::Utils::OS::pCP;

# OS file for pCP https://www.picoreplayer.org
#
# Revision 1.1
# 2017-04-16	Removed /proc from a music path
#
# Revision 1.2
# 2017-08-14    Added Manual Plugin directory at Cache/Plugins
#
# Revision 2.0
# 2025-03-23   Packages now being built by Lyrion.org.  Use default Cache/updates folder

use strict;
use warnings;

use base qw(Slim::Utils::OS::Linux);
use File::Spec::Functions qw(catdir);

use constant MAX_LOGSIZE => 1024*1024*1; # maximum log size: 1 MB
use constant UPDATE_DIR => '/tmp/slimupdate';

sub initDetails {
	my $class = shift;

	$class->{osDetails} = $class->SUPER::initDetails();
	$class->{osDetails}->{osName} = 'piCore';
	return $class->{osDetails};
}

sub getSystemLanguage { 'EN' }

sub localeDetails {
	my $lc_ctype = 'utf8';
	my $lc_time = 'C';

	return ($lc_ctype, $lc_time);
}

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the server directories we
need information for.

pCP Uses a update directory in /tmp and a custom manual plugin folder

=cut

sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs;

	if ($dir eq 'updates') {

		mkdir UPDATE_DIR unless -d UPDATE_DIR;
		@dirs = (UPDATE_DIR);
	}
	else {
		@dirs = $class->SUPER::dirsFor($dir);

		if ($dir eq "Plugins") {
			push @dirs, catdir( Slim::Utils::Prefs::preferences('server')->get('cachedir'), 'Plugins' );
			unshift @INC, catdir( Slim::Utils::Prefs::preferences('server')->get('cachedir') );
		}
	}

	return wantarray() ? @dirs : $dirs[0];
}

sub canAutoUpdate { 1 }
sub installerExtension { 'tcz' }
sub installerOS { 'pcp' }

sub getUpdateParams {
	my ($class, $url) = @_;

	if ($url) {
		require File::Slurp;

		my $updateFile = UPDATE_DIR . '/update_url';
		File::Slurp::write_file($updateFile, $url);
	}

	return {
		cb => \&Slim::Utils::OS::Linux::signalUpdateReady
	};
}

sub logRotate {
	# only keep small log files (1MB) because they are in RAM
	Slim::Utils::OS->logRotate($_[1], MAX_LOGSIZE);
}

sub ignoredItems {
	return (
		'bin'	=> '/',
		'dev'	=> '/',
		'etc'	=> '/',
		'opt'	=> '/',
		'init'	=> '/',
		'root'	=> '/',
		'sbin'	=> '/',
		'tmp'	=> '/',
		'var'	=> '/',
		'lib'	=> '/',
		'run'	=> '/',
		'sys'	=> '/',
		'usr'	=> '/',
		'proc'  => '/',
		'lost+found'=> 1,
	);
}

1;

