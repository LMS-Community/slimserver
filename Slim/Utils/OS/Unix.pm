package Slim::Utils::OS::Unix;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Config;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

use base qw(Slim::Utils::OS);

sub name {
	return 'unix';
}

sub initDetails {
	my $class = shift;

	$class->{osDetails}->{'os'}     = 'Unix';
	$class->{osDetails}->{'osName'} = $Config{'osname'} || 'Unix';
	$class->{osDetails}->{'uid'}    = getpwuid($>);
	$class->{osDetails}->{'osArch'} = $Config{'myarchname'};

	return $class->{osDetails};
}

sub initSearchPath {
	my $class = shift;

	$class->SUPER::initSearchPath(@_);

	my @paths = (split(/:/, ($ENV{'PATH'} || '/sbin:/usr/sbin:/bin:/usr/bin')), qw(/usr/bin /usr/local/bin /usr/libexec /sw/bin /usr/sbin /opt/bin));
	
	Slim::Utils::Misc::addFindBinPaths(@paths);
}

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the server directories we
need information for.

=cut

sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs = $class->SUPER::dirsFor($dir);
	
	# some defaults
	if ($dir =~ /^(?:strings|revision|convert|types|repositories)$/) {

		push @dirs, $Bin;

	} elsif ($dir eq 'log') {

		push @dirs, $::logdir || catdir($Bin, 'Logs');

	} elsif ($dir eq 'cache') {

		push @dirs, $::cachedir || catdir($Bin, 'Cache');

	} elsif ($dir =~ /^(?:music|playlists)$/) {

		push @dirs, '';

	# we don't want these values to return a(nother) value
	} elsif ($dir =~ /^(?:libpath|mysql-language)$/) {

	} elsif ($dir eq 'prefs' && $::prefsdir) {
		
		push @dirs, $::prefsdir;
		
	# SqueezeCenter <= 7.3 prefs
	} elsif ($dir eq 'scprefs') {

		my $oldpath = $class->dirsFor('prefs');
		$oldpath =~ s/squeezebox(?:server)?/squeezecenter/i;

		@dirs = ( $oldpath );

	} elsif ($dir eq 'oldprefs') {
	
		if ($::prefsfile && -r $::prefsfile) {
	
			push @dirs, $::prefsfile;
		
		} elsif (-r '/etc/slimserver.conf') {
	
			push @dirs, '/etc/slimserver.conf';
	
		} elsif (-r catdir($class->dirsFor('prefs'), 'slimserver.pref')) {
	
			push @dirs, catdir($class->dirsFor('prefs'), 'slimserver.pref');
	
		} elsif (-r catdir($ENV{'HOME'}, 'slimserver.pref')) {
	
			push @dirs, catdir($ENV{'HOME'}, 'slimserver.pref');
	
		}

	} else {

		push @dirs, catdir($Bin, $dir);
	}

	return wantarray() ? @dirs : $dirs[0];
}

sub migratePrefsFolder {
	my ($class, $newdir) = @_;

	return if -d $newdir && -f catdir($newdir, 'server.prefs');
	
	# we only care about SqueezeCenter -> Squeezebox Server for now
	my $olddir = $class->dirsFor('scprefs');	

	return unless -d $olddir && -r _;

	require File::Copy::Recursive;
	File::Copy::Recursive::dircopy($olddir, $newdir);
}

# leave log rotation to the system
sub logRotate {}

sub canRestartServer { 1 }

sub restartServer {

	my $class = shift;
	my ($progFile, $progArgs)  = @_;

	# Prefer to execute the script directly if possible, otherwise
	# invoke the interpreter to start the script.
	#
	# The difference between the two approaches is visible on
	# some systems in the process title. See the process name
	# in /proc/$$/stat on Linux as an example.

	my $execProg = (-x $progFile) ? $progFile : $^X;

	return exec($execProg, $progFile, @$progArgs);
}

1;
