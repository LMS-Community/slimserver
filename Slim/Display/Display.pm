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

	if ($start && $length && ($start > 32765 || ($length || 0) > 32765)) {
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

#	FUNCTION:	mixerDisplay
#
#	DESCRIPTION:	Used to display a bar graph of the current mixer feature below a label
#	
#	EXAMPLE OUTPUT:	Volume
#					###############-----------------
#	
#	USAGE:		mixerDisplay($client,'volume')
#
#   AVAILABLE FEATURES: 'volume','pitch','bass','treble'

sub mixerDisplay {
	my $client = shift;
	my $feature = shift;
	
	return unless $feature =~ /(?:volume|pitch|bass|treble)/;

	my $featureValue = Slim::Utils::Prefs::clientGet($client,$feature);
	return unless defined $featureValue;

	my $featureHeader;
	my $mid   = $client->mixerConstant($feature,'mid');
	my $scale = $client->mixerConstant($feature,'scale');
	
	my $headerValue = $client->mixerConstant($feature,'balanced') ? 
							int( ( ($featureValue - $mid) * $scale) + 0.5) :
							int( ( $featureValue * $scale) + 0.5);


	if ($feature eq 'volume' && $featureValue <= 0) {
		$headerValue = $client->string('MUTED');
	} elsif ($feature eq 'pitch') {
		$headerValue .= '%';
	}
	
	$featureHeader = $client->string(uc($feature)) . " ($headerValue)";

	# hack attack: turn off visualizer when showing volume, etc.
	my $oldvisu = $client->modeParam('visu');
	$client->modeParam('visu', [0]);

	my @lines = Slim::Buttons::Input::Bar::lines($client, $featureValue, $featureHeader,
													{
														'min' => $client->mixerConstant($feature,'min'),
														'mid' => $mid,
														'max' => $client->mixerConstant($feature,'max'),
														'noOverlay' => 1,
													}
												);
	# trim off any overlay for showBriefly
	$client->showBriefly(@lines[0,1]);

	$client->modeParam('visu', $oldvisu);	
}
	
		
#	These *Display functions are all deprecated and should not be used
#   Use mixerDisplay instead.
#######################################################################
sub volumeDisplay {
	my $client = shift;

	mixerDisplay($client,'volume');
}

sub pitchDisplay {
	my $client = shift;

	mixerDisplay($client,'pitch');
}

sub bassDisplay {
	my $client = shift;

	mixerDisplay($client,'bass');
}

sub trebleDisplay {
	my $client = shift;

	mixerDisplay($client,'treble');
}
#######################################################################


sub center {
	my $line = shift;
	return (Slim::Display::Display::symbol('center'). $line);
}

1;
__END__


