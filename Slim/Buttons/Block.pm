package Slim::Buttons::Block;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Slim::Utils::Timers;
use Slim::Utils::Misc;
use Slim::Buttons::Common;

my $ticklength = .2;            # length of each tick, seconds
my $tickdelay  =  2;            # number of updates before animation appears
my @tickchars  = ('|','/','-','\\');

our %functions  = ();

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

	Slim::Buttons::Common::pushMode($client,'block');
	$client->modeParam('block.name', $blockName);

	if (defined $parts) {
		$client->showBriefly($parts);
	}
}

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

	if ($bdata->{'static'}) { return $parts };

	if ($bdata->{'ticks'} < $tickdelay) {
		$bdata->{'ticks'}++;
		return $parts;
	}

	# create state for graphics animation if it does not exist - do it here so only done when animation starts
	unless (defined $bdata->{'pos'}) {
		
		if ($client->display->isa('Slim::Display::Graphics')) {
			# For graphics players animation cycles through characters in one of the following fonts:
			# SB2 - blockanimateSB2.1, SBG - blockanimateSBG.1
			my $vfd = $client->display->vfdmodel(); 
			my $model = $vfd eq 'graphic-320x32' ? 'SB2' : 'SBG';
			my $font = "blockanimate$model.1";
			my $chars = Slim::Display::Lib::Fonts::fontchars($font);

			$bdata->{'vfd'} = $vfd;
			$bdata->{'chars'} = $chars ? $chars - 1 : ($font = undef);
			
			if ($parts->{'fonts'} && $parts->{'fonts'}->{"$vfd"} && ref $parts->{'fonts'}->{"$vfd"} ne 'HASH') {
				# expand font definition so we can redefine one component only
				my $basefont = $parts->{'fonts'}->{"$vfd"};
				my $sfonts = $parts->{'fonts'}->{"$vfd"} = {};
				foreach my $c (qw(line overlay center)) {
					foreach my $l (0..$client->display->renderCache()->{'maxLine'}) {
						$sfonts->{"$c"}[$l] = $basefont . "." . ( $l + 1 );
					}
				}
			}
			
			$parts->{'fonts'}->{"$vfd"}->{'overlay'}[0] = $font;
			
		}
		
		$bdata->{'pos'} = -1;
		
	}
	
	if ($bdata->{'chars'}) {
		
		my $pos = ($bdata->{'pos'} + 1) % $bdata->{'chars'};
		my $vfd = $bdata->{'vfd'};
		$bdata->{'pos'} = $pos;
		$parts->{'overlay'}[0] = chr($pos + 1);
		
	} else {
		
		my $pos = int(Time::HiRes::time() / $ticklength) % (@tickchars);
		
		$parts->{overlay}[0] = $tickchars[$pos];
		
	}

	return($parts);
}

1;

__END__
