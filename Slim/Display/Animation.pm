#!/usr/bin/perl -w
package Slim::Display::Animation;

# $Id: Animation.pm,v 1.20 2004/08/03 17:29:12 vidur Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

# these functions have all been moved into client methods.

sub animating {
	return shift->animating();
}

# find all the queued up animation frames and toss them
sub killAnimation {
	shift->killAnimation();
}

sub endAnimation {
	shift->endAnimation();
}

sub showBriefly {
	my $client = shift;
	my $line1 = shift;
	my $line2 = shift;
	my $duration = shift;
	my $firstLineIfDoubled = shift;

	$client->showBriefly($line1, $line2, $duration, $firstLineIfDoubled);
}

# push the old lines (start1,2) off the left side
sub pushLeft {
	my $client = shift;
	my $start1 = shift;
	my $start2 = shift;
	my $end1 = shift;
	my $end2 = shift;

	$client->pushLeft([$start1, $start2], [$end1, $end2]);
}

# push the old lines (start1,2) off the right side
sub pushRight {
	my $client = shift;
	my $start1 = shift;
	my $start2 = shift;
	my $end1 = shift;
	my $end2 = shift;

	$client->pushRight([$start1, $start2], [$end1, $end2]);
}

sub doEasterEgg {
	shift->doEasterEgg();
}
sub bumpLeft {
	shift->bumpLeft();
}

sub bumpUp {
	shift->bumpUp();
}

sub bumpDown {
	shift->bumpDown();
}

sub bumpRight {
	shift->bumpRight();
}

sub scrollBottom {
	shift->scrollBottom();
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:

