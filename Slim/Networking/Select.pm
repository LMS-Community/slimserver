package Slim::Networking::Select;

# $Id: Select.pm,v 1.1 2003/10/31 22:09:04 dean Exp $

# Slim Server Copyright (c) 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use IO::Select;
use Tie::RefHash;

use Slim::Utils::Misc;

my %readSockets;
my %writeSockets;
my $readSelects;
my $writeSelects;

tie %readSockets, "Tie::RefHash";
tie %writeSockets, "Tie::RefHash";

sub addRead {
	my $r = shift;
	my $callback = shift;
	if (!defined($callback)) {
		delete $readSockets{$r};
		$::d_select && msg("removing select write $r\n");
	} else {
		$readSockets{$r} = $callback;
		$::d_select && msg("adding select read $r $callback\n");
	}
	$readSelects = IO::Select->new(keys %readSockets); 
}

sub addWrite {
	my $w = shift;
	my $callback = shift;
	
	if (!defined($callback)) {
		delete $writeSockets{$w};
		$::d_select && msg("removing select write $w\n");
	} else {
		$writeSockets{$w} = $callback;
		$::d_select && msg("adding select write $w $callback\n");
	}
	$writeSelects = IO::Select->new(keys %writeSockets);
}

sub select {
	my $select_time = shift;

	my ($r, $w, $e) = IO::Select->select($readSelects,$writeSelects,undef,$select_time);

	$::d_select && msg("select returns: reads: " . (defined($r) && scalar(@$r)) . " of " . $readSelects->count .
					" writes: " . (defined($w) && scalar(@$w)) . " of " . $writeSelects->count .
					" err: " . (defined($e) && scalar(@$e)) . "\n");
					
	my $sock;		
	my $count = 0;
	foreach $sock (@$r) {
		my $readsub = $readSockets{$sock};
		$readsub->($sock) if $readsub;
		$count++;
	}
	
	foreach $sock (@$w) {
		my $writesub = $writeSockets{$sock};
		$writesub->($sock) if $writesub;
		$count++;
	}
	return $count;
}


1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
