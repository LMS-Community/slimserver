package Slim::Buttons::Block;

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Buttons::Block

=head1 SYNOPSIS

Slim::Buttons::Playlist::block($client,$lineref);

Slim::Buttons::Playlist::unblock($client);

=head1 DESCRIPTION

L<Slim::Buttons::Block> is a mode for locking out further remote control interaction 
until a longer process has compeleted.  It is also used to provide feedback to the user
in the form of an apropriate message and animated display during the wait for a long operation to
complete.

=cut

use strict;
use Slim::Utils::Timers;
use Slim::Utils::Misc;
use Slim::Buttons::Common;

use Storable;

my $ticklength = .2;            # length of each tick, seconds
my $tickdelay  =  1;            # number of updates before animation appears
my @tickchars  = ('|','/','-','\\');

our %functions  = ();

=head1 METHODS

=head2 init( )

The init() function registers the block mode with the server.

Generally only called from L<Slim::Buttons::Common>

=cut

# Don't do this at compile time - not at run time
sub init {
	Slim::Buttons::Common::addMode('block',getFunctions(),\&setMode);
}

# Each button on the remote has a function:
sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	$client->lines(\&lines);
	$client->modeParam('modeUpdateInterval', $ticklength) unless ($client->blocklines()->{'static'});
}

=head2 block( $client, $line1)

Starts the block mode on the specified client.  The required $line argument is a reference to 
a display hash for any information required on the screen while blocking.

=cut
sub block {
	my $client = shift;
	my $line1 = shift;

	my $parts;
	if (ref($line1) eq 'HASH') {
		$parts = $line1;
	} else {
		my $line2 = shift;
		$parts = $client->parseLines([$line1,$line2]);
	}

	my $blockName = shift;  # associate name with blocked mode
	my $static = shift;     # turn off animation

	$client->blocklines( { 'static' => $static, 'parts' => $parts, 'ticks' => 0 } );

	my $screen2mode = $client->param('screen2');

	Slim::Buttons::Common::pushMode($client,'block');
	$client->modeParam('block.name', $blockName);
	$client->modeParam('screen2', $screen2mode);

	if (defined $parts) {
		$client->showBriefly($parts);
	}
}

=head2 unblock( $client)

Releases the provided client from block mode. 

=cut
sub unblock {
	my $client = shift;
	
	Slim::Buttons::ScreenSaver::wakeup($client);
	
	if (Slim::Buttons::Common::mode($client) eq 'block') {
		Slim::Buttons::Common::popMode($client);
	}
}

# Display blocked lines with animation in overlay [unless static display specified]

sub lines {
	my $client = shift;

	my $bdata = $client->blocklines();
	my $parts = $bdata->{'parts'};
	my $screen1;

	if ($bdata->{'static'}) { return $parts };

	if ($bdata->{'ticks'} < $tickdelay) {
		$bdata->{'ticks'}++;
		return $parts;
	}

	# create state for graphics animation if it does not exist - do it here so only done when animation starts
	unless (defined $bdata->{'pos'}) {

		$bdata->{'parts'} = $parts = Storable::dclone($parts);

		$screen1 = $parts->{'screen1'} ? $parts->{'screen1'} : $parts;
		
		if ($client->display->isa('Slim::Display::Graphics')) {
			# For graphics players animation cycles through characters in one of the following fonts:
			# SB2 - blockanimateSB2.1, SBG - blockanimateSBG.1
			my $vfd = $client->display->vfdmodel(); 
			my $model = $vfd eq 'graphic-320x32' ? 'SB2' : 'SBG';
			my $font = "blockanimate$model.1";
			my $chars = Slim::Display::Lib::Fonts::fontchars($font);

			$bdata->{'vfd'} = $vfd;
			$bdata->{'chars'} = $chars ? $chars - 1 : ($font = undef);
			
			if ($screen1->{'fonts'} && $screen1->{'fonts'}->{"$vfd"}) {
				if (ref $screen1->{'fonts'}->{"$vfd"} ne 'HASH') {
					# expand font definition so we can redefine one component only
					my $basefont = $screen1->{'fonts'}->{"$vfd"};
					my $sfonts = $screen1->{'fonts'}->{"$vfd"} = {};
					foreach my $c (qw(line overlay center)) {
						foreach my $l (0..$client->display->renderCache()->{'maxLine'}) {
							$sfonts->{"$c"}[$l] = $basefont . "." . ( $l + 1 );
						}
					}
				}
			} elsif ($client->display->linesPerScreen == 1) {
				# clear overlay so animation is seen
				$screen1->{'overlay'}[1] = undef;
			}
			
			$screen1->{'fonts'}->{"$vfd"}->{'overlay'}[0] = $font;
			
		}
		
		$bdata->{'pos'} = -1;
		
	} else {
		
		$screen1 = $parts->{'screen1'} ? $parts->{'screen1'} : $parts;

	}
	
	if ($bdata->{'chars'}) {
		
		my $pos = ($bdata->{'pos'} + 1) % $bdata->{'chars'};
		my $vfd = $bdata->{'vfd'};
		$bdata->{'pos'} = $pos;
		$screen1->{'overlay'}[0] = chr($pos + 1);
		
	} else {
		
		my $pos = int(Time::HiRes::time() / $ticklength) % (@tickchars);
		
		$screen1->{overlay}[0] = $tickchars[$pos];
		
	}

	return($parts);
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Display::Display>

L<Slim::Display::Graphics>

L<Slim::Utils::Timers>

=cut

1;

__END__
