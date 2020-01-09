package Slim::Display::NoDisplay;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.


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

	if (main::INFOLOG && logger('player.display')->is_info) {
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


sub notify {
	my ($display, $type, $info, $duration) = @_;
	
	# Squeezeplay is expecting duration in milliseconds - we're going to assume any value < 1000 to be seconds
	$duration *= 1000 if $duration && $duration < 1000;

	$display->SUPER::notify($type, $info, $duration)
}

=head1 SEE ALSO

L<Slim::Display::Display>

=cut

1;

