package Slim::Networking::Select;

# $Id: Select.pm,v 1.8 2004/01/20 20:30:58 dean Exp $

# SlimServer Copyright (c) 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use IO::Select;

use Slim::Utils::Misc;

my %readSockets;
my %readCallbacks;

my %writeSockets;
my %writeCallbacks;

my $readSelects = IO::Select->new();
my $writeSelects = IO::Select->new();

sub addRead {
	my $r = shift;
	my $callback = shift;
	if (!$callback) {
		delete $readSockets{"$r"};
		delete $readCallbacks{"$r"};
		$::d_select && msg("removing select write $r\n");
	} else {
		$readSockets{"$r"} = $r;
		$readCallbacks{"$r"} = $callback;
		$::d_select && msg("adding select read $r $callback\n");
	}
	$readSelects = IO::Select->new(map {$readSockets{$_}} (keys %readSockets));
}

sub addWrite {
	my $w = shift;
	my $callback = shift;
	
	$::d_select && msg("before: " . scalar(keys %writeSockets) . "/" . $writeSelects->count . "\n");
	if (!$callback) {
		delete $writeSockets{"$w"};
		delete $writeCallbacks{"$w"};	
		$::d_select && msg("removing select write $w\n");
	} else {
		$writeSockets{"$w"} = $w;
		$writeCallbacks{"$w"} = $callback;
		$::d_select && msg("adding select write $w $callback\n");
	}
	$writeSelects = IO::Select->new(map {$writeSockets{$_}} (keys %writeSockets));

	$::d_select && msg("now: " . scalar(keys %writeSockets) . "/" . $writeSelects->count . "\n");
}

sub select {
	my $select_time = shift;
	
	my ($r, $w, $e) = IO::Select->select($readSelects,$writeSelects,undef,$select_time);

	$::d_select && msg("select returns ($select_time): reads: " . (defined($r) && scalar(@$r)) . " of " . $readSelects->count .
					" writes: " . (defined($w) && scalar(@$w)) . " of " . $writeSelects->count .
					" err: " . (defined($e) && scalar(@$e)) . "\n");
					
	my $sock;		
	my $count = 0;
	foreach $sock (@$r) {
		my $readsub = $readCallbacks{"$sock"};
		$readsub->($sock) if $readsub;
		$count++;
		# this is totally overkill...
		Slim::Networking::Protocol::readUDP();
	}
	
	foreach $sock (@$w) {
		my $writesub = $writeCallbacks{"$sock"};
		$writesub->($sock) if $writesub;
		$count++;
		# this is totally overkill...
		Slim::Networking::Protocol::readUDP();
	}
	return $count;
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
