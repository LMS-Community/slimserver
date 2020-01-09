package Slim::Hardware::TriLED;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

=head1 NAME

Slim::Hardware::TriLED

=head1 DESCRIPTION

L<Slim::Hardware::TriLED>

=cut

use strict;

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = logger('player.triled');

my $prefs = preferences('server');

=head2 setTriLED( $client, $color, $transition, $on_time, $off_time, $times )

Sets the tricolor LED
$color is RGB i.e 0x00FF0000 for red, 0x0000FF00 for green, 0x000000FF for blue
$transition = 0 -> change color immediately
$transition = 1 -> change color gradually

$on_time = 0 -> do not blink
$on_time > 0 -> blink on time (in ms)
$off_time > 0 -> blink off time (in ms)
$times = 0 -> blink forever
$times > 0 -> number of blinks

=cut

my $isInitialized = 0;

# ----------------------------------------------------------------------------
sub init {
	Slim::Control::Request::addDispatch( ['triled', 'set', '_color', '_transition', '_ontime', '_offtime', '_times'], [1, 0, 0, \&cliTriLED]);
	$isInitialized = 1;
}


# ----------------------------------------------------------------------------
sub cliTriLED {
	my $request = shift;

	# Check this is the correct query
	if( $request->isNotCommand( [['triled', 'set']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client = $request->client();
	my $color = $request->getParam( '_color');
	my $transition = $request->getParam( '_transition');
	my $on_time = $request->getParam( '_ontime');
	my $off_time = $request->getParam( '_offtime');
	my $times = $request->getParam( '_times');
	
	# Only supported on Receiver
	if( !defined( $client) || !( $client->model() eq 'receiver')) {
		return;
	}

	setTriLED( $client, $color, $transition, $on_time, $off_time, $times);
	$request->setStatusDone();
}


# ----------------------------------------------------------------------------
sub setTriLED {
	init() unless $isInitialized;

	my $client = shift;
	my $color = shift || 0x00000000;	# white
	my $transition = shift || 0x00;		# no transition
	my $on_time = shift || 0x00;		# no blinking
	my $off_time = shift || 0x00;
	my $times = shift || 0x00;

#	$log->info(sprintf("Trying to execute button [%s] for irCode: [%s]",

	my $cmd = pack( 'N', $color);
	$cmd .= pack( 'n', $on_time);	# on time	0 -> do not blink
	$cmd .= pack( 'n', $off_time);	# off time
	$cmd .= pack( 'C', $times);	# times		0 -> blink forever
	$cmd .= pack( 'C', $transition);	# transition
	$client->sendFrame( 'ledc', \$cmd);
}

1;
