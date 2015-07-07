package Slim::Utils::OS::RedHat;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use FindBin qw($Bin);

use base qw(Slim::Utils::OS::Linux);

sub initDetails {
	my $class = shift;

	$class->{osDetails} = $class->SUPER::initDetails();

	$class->{osDetails}->{isRedHat} = 1;

	return $class->{osDetails};
}

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the Logitech Media Server directories we
need information for.

=cut

sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs = ();
	
	if ($dir =~ /^(?:oldprefs|updates)$/) {

		push @dirs, $class->SUPER::dirsFor($dir);

	} elsif ($dir =~ /^(?:Firmware|Graphics|HTML|IR|MySQL|SQL|lib|Bin)$/) {

		push @dirs, "/usr/share/squeezeboxserver/$dir";

	} elsif ($dir eq 'Plugins') {
			
		push @dirs, $class->SUPER::dirsFor($dir);
		push @dirs, "/usr/share/squeezeboxserver/Plugins";
		push @dirs, "/usr/lib/perl5/vendor_perl/Slim/Plugin";
		
	} elsif ($dir =~ /^(?:strings|revision|repositories)$/) {

		push @dirs, "/usr/share/squeezeboxserver";

	} elsif ($dir eq 'libpath') {

		push @dirs, "/usr/share/squeezeboxserver";

	# Because we use the system MySQL, we need to point to the right
	# directory for the errmsg. files. Default to english.
	} elsif ($dir eq 'mysql-language') {

		push @dirs, "/usr/share/mysql/english";

	} elsif ($dir =~ /^(?:types|convert)$/) {

		push @dirs, "/etc/squeezeboxserver";

	} elsif ($dir eq 'prefs') {

		push @dirs, $::prefsdir || "/var/lib/squeezeboxserver/prefs";

	} elsif ($dir eq 'log') {

		push @dirs, $::logdir || "/var/log/squeezeboxserver";

	} elsif ($dir eq 'cache') {

		push @dirs, $::cachedir || "/var/lib/squeezeboxserver/cache";

	} elsif ($dir =~ /^(?:music|playlists)$/) {

		push @dirs, '';

	} else {

		warn "dirsFor: Didn't find a match request: [$dir]\n";
	}

	return wantarray() ? @dirs : $dirs[0];
}


sub scanner {
	return '/usr/libexec/squeezeboxserver-scanner';
}

sub canAutoUpdate { $_[0]->SUPER::runningFromSource ? 0 : 1 }
sub installerExtension { 'rpm' }; 
sub installerOS { 'rpm' }

sub getUpdateParams {
	my ($class, $url) = @_;
	
	if ($url) {
		Slim::Utils::OS::Linux::signalUpdateReady($url);
	}
	
	return;
}


1;
