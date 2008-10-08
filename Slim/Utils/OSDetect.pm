package Slim::Utils::OSDetect;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::OSDetect

=head1 DESCRIPTION

L<Slim::Utils::OSDetect> handles Operating System Specific details.

=head1 SYNOPSIS

	for my $baseDir (Slim::Utils::OSDetect::dirsFor('types')) {

		push @typesFiles, catdir($baseDir, 'types.conf');
		push @typesFiles, catdir($baseDir, 'custom-types.conf');
	}
	
	if (Slim::Utils::OSDetect::isWindows()) {

=cut

use strict;
use Config;
use File::Path;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

my ($os, $isWindows, $isMac);

=head1 METHODS

=head2 OS( )

returns a string to indicate the detected operating system currently running SqueezeCenter.

=cut

sub OS {
	return $os->name;
}

=head2 init( $newBin)

 Figures out where the preferences file should be on our platform, and loads it.

=cut

sub init {
	my $newBin = shift;
	
	if ($os) {
		return;
	}

	# Allow the caller to pass in a new base dir (for test cases);
	if (defined $newBin && -d $newBin) {
		$Bin = $newBin;
	}
	
	# Let's see whether there's a custom OS file (to be used by 3rd party NAS vendors etc.)
	eval {
		require Slim::Utils::OS::Custom;
		$os = Slim::Utils::OS::Custom->new();
		print STDOUT "Found custom OS support file for " . $os->name . "\n";
	};


	if (!$os) {		

		if ( main::SLIM_SERVICE ) {
	
			require Slim::Utils::OS::SlimService;
			$os = Slim::Utils::OS::SlimService->new();
	
		} elsif ($^O =~/darwin/i) {
			
			require Slim::Utils::OS::OSX;
			$os = Slim::Utils::OS::OSX->new();
	
		} elsif ($^O =~ /^m?s?win/i) {
	
			require Slim::Utils::OS::Win32;
			$os = Slim::Utils::OS::Win32->new();
	
		} elsif ($^O =~ /linux/i) {
			
			require Slim::Utils::OS::Linux;
			$os = Slim::Utils::OS::Linux->getFlavor();
	
			if ($os =~ /RAIDiator/i) {
	
				require Slim::Utils::OS::ReadyNAS;
				$os = Slim::Utils::OS::ReadyNAS->new();
				
			# we only differentiate Debian/Suse/Red Hat if they've been installed from a package
			} elsif ($os =~ /debian/i && $0 =~ m{^/usr/sbin/squeezecenter}) {
		
				require Slim::Utils::OS::Debian;
				$os = Slim::Utils::OS::Debian->new();
		
			} elsif ($os =~ /red hat/i && $0 =~ m{^/usr/libexec/squeezecenter}) {
		
				require Slim::Utils::OS::RedHat;
				$os = Slim::Utils::OS::RedHat->new();
		
			} elsif ($os =~ /suse/i && $0 =~ m{^/usr/libexec/squeezecenter}) {
				
				require Slim::Utils::OS::Suse;
				$os = Slim::Utils::OS::Suse->new();
				
			} else {
	
				$os = Slim::Utils::OS::Linux->new();
			}
	
		} else {
	
			require Slim::Utils::OS::Unix;
			$os = Slim::Utils::OS::Unix->new();
	
		}
	}
	
	$os->initDetails();
	$isWindows = $os->name eq 'win';
	$isMac     = $os->name eq 'mac';
}

sub getOS {
	return $os;
}

=head2 Backwards compatibility

 Keep some helper functions for backwards compatibility.

=cut

sub dirsFor {
	return $os->dirsFor(shift);
}

sub details {
	return $os->details();
}

sub getProxy {
	return $os->getProxy();
}

=head2 isDebian( )

 The Debian package has some specific differences for file locations.
 This routine needs no args, and returns 1 if Debian distro is detected, with
 a clear sign that the .deb package has been installed, 0 if not.

=cut

sub isDebian {
	return $os->get('isDebian');
}

sub isRHorSUSE {
	return $os->get('isRedHat', 'isSuse');
}

sub isWindows {
	return $isWindows;
}

sub isMac {
	return $isMac;
}

1;

__END__
