package Slim::Networking::mDNS;

# SlimServer Copyright (C) 2003-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
 
our %children;

sub advertise {
	my $name = shift;
	my $service = shift;
	my $port = shift;
	
	if ($name) {
		my $mdnsbin = Slim::Utils::Misc::findbin('mDNSResponderPosix');
		
		if (!$mdnsbin) {
			if ($::d_mdns) { msg("can't use mDNS, as $mdnsbin isn't available\n"); }
			return undef;
		}
		
		my $pid = fork;
		
		if (!defined($pid)) {
			return undef;
		} elsif ($pid == 0) {
			my @args = ( "\"$mdnsbin\" -n \"$name\" -t $service -p $port" );
			if ($::d_mdns) { msg("registering $name for $service on port $port using $mdnsbin\n"); }
			exec @args;
			warn "couldn't register register mDNS service $service\n";
			exit;
		} else { 
			$children{ $pid } = $pid;
			return $pid;
		}
	}
}

sub stopAdvertise {
	my $pid = shift;
	
	if (!defined($pid)) {
		foreach $pid (keys %children) {
			kill "TERM", $pid;
		}
		%children = ();
	} else {
		kill "TERM", $pid;
		delete ($children{$pid});
	}
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
