package Slim::Display::NoDisplay;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# $Id$

=head1 NAME

Slim::Display::NoDisplay

=head1 DESCRIPTION

L<Slim::Display::NoDisplay>
 Display class for clients with no display
  - used to stub out common display methods in Display::Display

=cut

use base qw(Slim::Display::Display);

use strict;
use Slim::Utils::Misc;
use Slim::Utils::Log;

sub showBriefly {
	my $display = shift;

	if (logger('player.display')->is_info) {
		my ($line, $subr) = (caller(1))[2,3];
		($line, $subr) = (caller(2))[2,3] if $subr eq 'Slim::Player::Player::showBriefly';
		logger('player.display')->info(sprintf "caller %s (%d) notifyLevel=%d ", $subr, $line, $display->notifyLevel);
	}

	if ($display->notifyLevel) {
		$display->notify('showbriefly', @_)
	}
}

sub periodicScreenRefresh {}
sub update {}
sub brightness {}
sub prevline1 {}
sub prevline2 {}
sub curDisplay {}
sub curLines {}
sub progressBar {}
sub balanceBar {}
sub scrollInit {}
sub scrollStop {}
sub scrollUpdateBackground {}
sub scrollTickerTimeLeft {}
sub scrollUpdate {}
sub killAnimation {}
sub resetDisplay {}
sub endAnimation {}
sub vfdmodel { 'none' }
sub linesPerScreen { 0 }
sub displayWidth { 0 }
sub maxBrightness {}
sub symbols {return $_[1];}

=head1 SEE ALSO

L<Slim::Display::Display>

=cut

1;

