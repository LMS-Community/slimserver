package Slim::Utils::OS::Linux;

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
			
	} elsif (-f '/etc/debian_version') {
	
		return 'Debian';
	
	} elsif (-f '/etc/redhat_release' || -f '/etc/redhat-release') {
		
		return 'Red Hat';
	
	} elsif (-f '/etc/SuSE-release') {
			
		return 'SuSE';
	}

	return 'Linux';
}

1;