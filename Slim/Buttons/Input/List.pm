package Slim::Buttons::Input::List;

# $Id: List.pm,v 1.4 2003/11/25 04:14:15 grotus Exp $
# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Buttons::Common;
use Slim::Utils::Misc;
use Slim::Hardware::VFD;

###########################
#Button mode specific junk#
###########################
my %functions = (
	#change character at cursorPos (both up and down)
	'up' => sub {
			my ($client,$funct,$functarg) = @_;
			changePos($client,-1);
		}
	,'down' => sub {
			my ($client,$funct,$functarg) = @_;
			changePos($client,1);
		}
	,'numberScroll' => sub {
			my ($client,$funct,$functarg) = @_;
			my $isSorted = Slim::Buttons::Common::param($client,'isSorted');
			my $listRef = Slim::Buttons::Common::param($client,'listRef');
			my $numScrollRef;
			if ($isSorted && uc($isSorted) eq 'E') {
				# sorted by the external value
				$numScrollRef = Slim::Buttons::Common::param($client,'externRef');
			} else {
				# not sorted or sorted by the internal value
				$numScrollRef = $listRef;
			}
			my $newIndex = Slim::Buttons::Common::numberScroll($client, $functarg, $numScrollRef, $isSorted ? 1 : 0);
			if (defined $newIndex) {
				Slim::Buttons::Common::param($client,'listIndex',$newIndex);
				my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
				$$valueRef = $listRef->[$newIndex];
				my $onChange = Slim::Buttons::Common::param($client,'onChange');
				if (ref($onChange) eq 'CODE') {
					my $onChangeArgs = Slim::Buttons::Common::param($client,'onChangeArgs');
					my @args;
					push @args, $client if $onChangeArgs =~ /c/i;
					push @args, $$valueRef if $onChangeArgs =~ /v/i;
					$onChange->(@args);
				}
			}
			$client->update;
		}
	#call callback procedure
	,'exit' => sub {
			my ($client,$funct,$functarg) = @_;
			if (!defined($functarg) || $functarg eq '') {
				$functarg = 'exit'
			}
			exitInput($client,$functarg);
		}
	,'passback' => sub {
			my ($client,$funct,$functarg) = @_;
			my $parentMode = Slim::Buttons::Common::param($client,'parentMode');
			if (defined($parentMode)) {
				Slim::Hardware::IR::executeButton($client,$client->lastirbutton,$client->lastirtime,$parentMode);
			}
		}
);

sub changePos {
	my ($client, $dir) = @_;
	my $listRef = Slim::Buttons::Common::param($client,'listRef');
	my $listIndex = Slim::Buttons::Common::param($client,'listIndex');
	if (Slim::Buttons::Common::param($client,'noWrap') 
		&& (($listIndex == 0 && $dir < 0) || ($listIndex == (scalar(@$listRef) - 1) && $dir > 0))) {
			#not wrapping and at end of list
			return;
	}
	my $newposition = Slim::Buttons::Common::scroll($client, $dir, scalar(@$listRef), $listIndex);
	my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
	$$valueRef = $listRef->[$newposition];
	Slim::Buttons::Common::param($client,'listIndex',$newposition);
	my $onChange = Slim::Buttons::Common::param($client,'onChange');
	if (ref($onChange) eq 'CODE') {
		my $onChangeArgs = Slim::Buttons::Common::param($client,'onChangeArgs');
		my @args;
		push @args, $client if $onChangeArgs =~ /c/i;
		push @args, $$valueRef if $onChangeArgs =~ /v/i;
		$onChange->(@args);
	}
	$client->update();
}

sub lines {
	my $client = shift;
	my ($line1, $line2);
	my $listIndex = Slim::Buttons::Common::param($client,'listIndex');
	my $listRef = Slim::Buttons::Common::param($client,'listRef');
	if (!defined($listRef)) { return ('','');}
	$line1 = getExtVal($client,$listRef->[$listIndex],$listIndex,'header');
	$line2 = getExtVal($client,$listRef->[$listIndex],$listIndex,'externRef');
	my @overlay = getExtVal($client,$listRef->[$listIndex],$listIndex,'overlayRef');
	return ($line1,$line2,@overlay);
}

sub getExtVal {
	my ($client, $value, $listIndex, $source) = @_;
	my $extref = Slim::Buttons::Common::param($client,$source);
	my $extval;
	if (ref($extref) eq 'ARRAY') {
		$extref = $extref->[$listIndex];
	}

	if (!ref($extref)) {
		return $extref;
	} elsif (ref($extref) eq 'CODE') {
		my @args;
		my $argtype = Slim::Buttons::Common::param($client,$source . 'Args');
		push @args, $client if $argtype =~ /c/i;
		push @args, $value if $argtype =~ /v/i;
		return $extref->(@args);
	} elsif (ref($extref) eq 'HASH') {
		return $extref->{$value};
	} elsif (ref($extref) eq 'ARRAY') {
		return @$extref;
	} else {
		return undef;
	}
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	#my $setMethod = shift;
	#possibly skip the init if we are popping back to this mode
	#if ($setMethod ne 'pop') {
		if (!init($client)) {
			Slim::Buttons::Common::popModeRight($client);
		}
	#}
	$client->lines(\&lines);
}
# set unsupplied parameters to the defaults
# listRef = none # reference to list of internal values, exit mode if not supplied
# header = 'Select item:' # message displayed on top line, can be a scalar, a code ref
	# , or an array ref to a list of scalars or code refs
# headerArgs = CV
# valueRef =  # reference to value to be selected
# callback = undef # function to call to exit mode
# listIndex = 0 or position of valueRef in listRef
# noWrap = undef # whether or not the list wraps at the ends
# externRef = undef
# externRefArgs = CV
# overlayRef = undef
# overlayRefArgs = CV
# onChange = undef
# onChangeArgs = CV

# other parameters used
# isSorted = undef # whether the interal or external list is sorted 
	#(I for internal, E for external, undef or anything else for unsorted)

sub init {
	my $client = shift;
	if (!defined(Slim::Buttons::Common::param($client,'parentMode'))) {
		Slim::Buttons::Common::param($client,'parentMode',$client->modeStack->[-2]);
	}
	if (!defined(Slim::Buttons::Common::param($client,'header'))) {
		Slim::Buttons::Common::param($client,'header','Select item:');
	}
	my $listRef = Slim::Buttons::Common::param($client,'listRef');
	my $externRef = Slim::Buttons::Common::param($client,'externRef');
	if (!defined $listRef && ref($externRef) eq 'ARRAY') {
		$listRef = $externRef;
		Slim::Buttons::Common::param($client,'listRef',$listRef);
	}
	if (!defined $externRef && ref($listRef) eq 'ARRAY') {
		$externRef = $listRef;
		Slim::Buttons::Common::param($client,'externRef',$externRef);
	}
	return undef if !defined($listRef);
	my $isSorted = Slim::Buttons::Common::param($client,'isSorted');
	if ($isSorted && ($isSorted !~ /[iIeE]/ || (uc($isSorted) eq 'E' && ref($externRef) ne 'ARRAY'))) {
		Slim::Buttons::Common::param($client,'isSorted',0);
	}
	my $listIndex = Slim::Buttons::Common::param($client,'listIndex');
	my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
	if (!defined($listIndex)) {
		$listIndex = 0;
	} elsif ($listIndex > $#$listRef) {
		$listIndex = $#$listRef;
	}
	while ($listIndex < 0) {
		$listIndex += scalar(@$listRef);
	}
	if (!defined($valueRef)) {
		$$valueRef = $listRef->[$listIndex];
		Slim::Buttons::Common::param($client,'valueRef',$valueRef);
	} elsif (!ref($valueRef)) {
		$$valueRef = $valueRef;
		Slim::Buttons::Common::param($client,'valueRef',$valueRef);
	}
	if ($$valueRef ne $listRef->[$listIndex]) {
		my $newIndex;
		for ($newIndex = 0; $newIndex < scalar(@$listRef); $newIndex++) {
			last if $$valueRef eq $listRef->[$newIndex];
		}
		if ($newIndex < scalar(@$listRef)) {
			$listIndex = $newIndex;
		} else {
			$$valueRef = $listRef->[$listIndex];
		}
	}
	Slim::Buttons::Common::param($client,'listIndex',$listIndex);
	if (!defined(Slim::Buttons::Common::param($client,'externRefArgs'))) {
		Slim::Buttons::Common::param($client,'externRefArgs','CV');
	}
	if (!defined(Slim::Buttons::Common::param($client,'overlayRefArgs'))) {
		Slim::Buttons::Common::param($client,'overlayRefArgs','CV');
	}
	if (!defined(Slim::Buttons::Common::param($client,'onChangeArgs'))) {
		Slim::Buttons::Common::param($client,'onChangeArgs','CV');
	}
	if (!defined(Slim::Buttons::Common::param($client,'headerArgs'))) {
		Slim::Buttons::Common::param($client,'headerArgs','CV');
	}
	return 1;
}

sub exitInput {
	my ($client,$exitType) = @_;
	my $callbackFunct = Slim::Buttons::Common::param($client,'callback');
	if (!defined($callbackFunct) || !(ref($callbackFunct) eq 'CODE')) {
		if ($exitType eq 'right') {
			Slim::Display::Animation::bumpRight($client);
		} elsif ($exitType eq 'left') {
			Slim::Buttons::Common::popModeRight($client);
		} else {
			Slim::Buttons::Common::popMode($client);
		}
		return;
	}
	$callbackFunct->(@_);
}

1;
