package Slim::Utils::OSDetect;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::OSDetect

=head1 DESCRIPTION

L<Slim::Utils::OSDetect> handles Operating System Specific details.

=head1 SYNOPSIS

	if (Slim::Utils::OSDetect::isWindows()) {

=cut

use strict;
use FindBin qw($Bin);

my ($os, $isWindows, $isMac, $isLinux);

=head1 METHODS

=head2 OS( )

returns a string to indicate the detected operating system currently running Logitech Media Server.

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
		#print STDOUT "Found custom OS support file for " . $os->name . "\n";
	};

	if ( $@ && $@ !~ m{^Can't locate Slim/Utils/OS/Custom.pm} ) {
		warn $@;
	}

	if (!$os) {		

		if ($^O =~/darwin/i) {
			
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
			} elsif ($os =~ /debian/i && $0 =~ m{^/usr/sbin/squeezeboxserver}) {
		
				require Slim::Utils::OS::Debian;
				$os = Slim::Utils::OS::Debian->new();
		
			} elsif ($os =~ /red hat/i && $0 =~ m{^/usr/libexec/squeezeboxserver}) {
		
				require Slim::Utils::OS::RedHat;
				$os = Slim::Utils::OS::RedHat->new();
		
			} elsif ($os =~ /suse/i && $0 =~ m{^/usr/libexec/squeezeboxserver}) {
				
				require Slim::Utils::OS::Suse;
				$os = Slim::Utils::OS::Suse->new();

            } elsif ($os =~ /Synology/i) {

                require Slim::Utils::OS::Synology;
                $os = Slim::Utils::OS::Synology->new();

			} elsif ($os =~ /squeezeos/i) {
				
				require Slim::Utils::OS::SqueezeOS;
				$os = Slim::Utils::OS::SqueezeOS->new();
				
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
	$isLinux   = $os->get('os') eq 'Linux';
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

sub skipPlugins {
	return $os->skipPlugins();
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

sub isSqueezeOS {
	return $os->get('isSqueezeOS');
}

sub isWindows {
	return $isWindows;
}

sub isMac {
	return $isMac;
}

sub isLinux {
	return $isLinux;
}

1;

__END__
