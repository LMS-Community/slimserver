package Slim::Display::Display;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use Slim::Utils::Misc;
use Slim::Utils::Timers;
use Slim::Buttons::Settings;
use Slim::Utils::Strings qw(string);

our %commandmap = (
	'center' => "\x1ecenter\x1e",
	'cursorpos' => "\x1ecursorpos\x1e",
	'framebuf' => "\x1eframebuf\x1e",
	'/framebuf' => "\x1e/framebuf\x1e",
	'linebreak' => "\x1elinebreak\x1e",
	'repeat' => "\x1erepeat\x1e", 
	'right' => "\x1eright\x1e",
	'scroll' => "\x1escroll\x1e",
	'/scroll' => "\x1e/scroll\x1e", 
	'tight' => "\x1etight\x1e",
	'/tight' => "\x1e/tight\x1e",
);

#depricated, use $client methods
sub update {
	return shift->update();
}

sub renderOverlay {
	return Slim::Player::Player::renderOverlay(undef, @_);
}

sub balanceBar {
	return shift->balanceBar(@_);
}

sub progressBar {
	return shift->progressBar(@_);
}


# display text manipulation routines
sub lineLength {
	my $line = shift;
	return 0 if (!defined($line) || !length($line));

	$line =~ s/\x1f[^\x1f]+\x1f/x/g;
	$line =~ s/(\x1eframebuf\x1e.*\x1e\/framebuf\x1e|\n|\xe1[^\x1e]\x1e)//gs;
	return length($line);
}

sub splitString {
	my $string = shift;
	my @result = ();
	$string =~ s/(\x1f[^\x1f]+\x1f|\x1eframebuf\x1e.*\x1e\/framebuf\x1e|\x1e[^\x1e]+\x1e|.)/push @result, $1;/esg;
	return \@result;
}

sub subString {
	my ($string,$start,$length,$replace) = @_;
	$string =~ s/\x1eframebuf\x1e.*\x1e\/framebuf\x1e//s if ($string);

	my $newstring = '';
	my $oldstring = '';

	if ($start > 32765 || ($length||0) > 32765) {
			msg("substr on string with start or length greater than 32k, returning empty string.\n");
			bt();
			return '';
	}

	if ($string && $string =~ s/^(((?:(\x1e[^\x1e]+\x1e)|)(?:[^\x1e\x1f]|\x1f[^\x1f]+\x1f)){0,$start})//) {
		$oldstring = $1;
	}
	
	if (defined($length)) {
		if ($string =~ s/^(((?:(\x1e[^\x1e]+\x1e)|)([^\x1e\x1f]|\x1f[^\x1f]+\x1f)){0,$length})//) {
			$newstring = $1;
		}
	
		if (defined($replace)) {
			$_[0] = $oldstring . $replace . $string;
		}
	} else {
		$newstring = $string;
	}
	return $newstring;
}

sub command {
	my $symname = shift;
	if (exists($commandmap{$symname})) { return $commandmap{$symname}; }
}

sub symbol {
	my $symname = shift;
	
	if (exists($commandmap{$symname})) { return $commandmap{$symname}; }
	
	return ("\x1f". $symname . "\x1f");
}

# the lines functions return a pair of lines and a pair of overlay strings
# which may need to be overlayed on top of the first pair, right justified.

sub curLines {
	my $client = shift;
	
	if (!defined($client)) { return; }
	
	my $linefunc = $client->lines();

	if (defined $linefunc) {
		return $client->renderOverlay(&$linefunc($client));
	} else {
		$::d_ui && msg("Linefunction for client is undefined!\n");
		$::d_ui && bt();
	}
}

#	FUNCTION:	volumeDisplay
#
#	DESCRIPTION:	Used to display a bar graph of the current volume below a label
#	
#	EXAMPLE OUTPUT:	Volume
#					###############-----------------
#	
#	USAGE:		volumeDisplay($client)
sub volumeDisplay {
	my $client = shift;

	my $volume = $client->volume();
	my $volumestring = $client->string('VOLUME').' ('.($volume <= 0 ? $client->string('MUTED') : int($volume/100*40+0.5)).')';
	my @lines = Slim::Buttons::Input::Bar::lines($client,$volume,$volumestring ,$client->minVolume(), $client->minVolume(), $client->maxVolume());

	$client->showBriefly(@lines);
}
sub pitchDisplay {
	my $client = shift;

	my $pitch = $client->pitch();
	my $pitchstring = $client->string('PITCH').' ('.(int($pitch)).'%)';
	my @lines = Slim::Buttons::Input::Bar::lines($client,$pitch,$pitchstring, $client->minPitch(), ($client->maxPitch() + $client->minPitch() ) / 2, $client->maxPitch());

	$client->showBriefly(@lines);
}
sub bassDisplay {
	my $client = shift;

	my $bass = $client->bass();
	my $bassstring = $client->string('BASS').' ('.(int($bass/100*40 + 0.5) - 20).')';
	my @lines = Slim::Buttons::Input::Bar::lines($client,$bass,$bassstring, $client->minBass(), ($client->maxBass() + $client->minBass() ) / 2, $client->maxBass());

	$client->showBriefly(@lines);
}
sub trebleDisplay {
	my $client = shift;

	my $treble = $client->treble();
	my $treblestring = $client->string('TREBLE').' ('.(int($treble/100*40 + 0.5) - 20).')';
	my @lines = Slim::Buttons::Input::Bar::lines($client,$treble,$treblestring, $client->minTreble(), ($client->maxTreble() + $client->minTreble() ) / 2, $client->maxTreble());

	$client->showBriefly(@lines);
}

sub center {
	my $line = shift;
	return (Slim::Display::Display::symbol('center'). $line);
}

1;
__END__


