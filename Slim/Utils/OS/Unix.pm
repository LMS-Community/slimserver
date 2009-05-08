package Slim::Utils::OS::Unix;

# SqueezeCenter Copyright 2001-2009 Logitech.
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

	$class->SUPER::initSearchPath();

	my @paths = (split(/:/, $ENV{'PATH'} || ''), qw(/usr/bin /usr/local/bin /usr/libexec /sw/bin /usr/sbin));
	
	Slim::Utils::Misc::addFindBinPaths(@paths);
}

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the SqueezeCenter directories we
need information for.

=cut

sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs = $class->SUPER::dirsFor($dir);
	
	# some defaults
	if ($dir =~ /^(?:strings|revision|convert|types)$/) {

		push @dirs, $Bin;

	} elsif ($dir eq 'log') {

		push @dirs, $::logdir || catdir($Bin, 'Logs');

	} elsif ($dir eq 'cache') {

		push @dirs, $::cachedir || catdir($Bin, 'Cache');

	} elsif ($dir =~ /^(?:music|playlists)$/) {

		push @dirs, '';

	# we don't want these values to return a value
	} elsif ($dir =~ /^(?:libpath|mysql-language)$/) {

	} elsif ($dir eq 'prefs' && $::prefsdir) {
		
		push @dirs, $::prefsdir;
		
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

# leave log rotation to the system
sub logRotate {}

1;