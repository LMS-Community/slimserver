package Slim::Utils::OS::Linux;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Utils::OS::Unix);

use Config;

sub initDetails {
	my $class = shift;

	$class->{osDetails}->{'os'} = 'Linux';

	$class->{osDetails}->{osName} = getFlavor();
	$class->{osDetails}->{uid}    = getpwuid($>);
	$class->{osDetails}->{osArch} = $Config{'myarchname'};

	return $class->{osDetails};
}

sub getFlavor {
	if (-f '/etc/raidiator_version') {

		return 'Netgear RAIDiator';
			
	} elsif (-f '/etc/squeezeos.version') {
	
		return 'SqueezeOS';
	
	} elsif (-f '/etc/debian_version') {
	
		return 'Debian';
	
	} elsif (-f '/etc/redhat_release' || -f '/etc/redhat-release' || -f '/etc/fedora-release') {
		
		return 'Red Hat';
	
	} elsif (-f '/etc/SuSE-release') {
			
		return 'SuSE';

	} elsif (-f '/etc/synoinfo.conf' || -f '/etc.defaults/synoinfo.conf') {

		return 'Synology DiskStation';
	}

	return 'Linux';
}

1;
