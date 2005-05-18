package Slim::Buttons::Input::Choice;

# $Id$

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This mode is modelled after INPUT.List, but more "electric", in that
# most mode params can be either hard values or subroutines to be
# invoked at run time.  More documentation coming soon.

# The name Choice comes from its original use, creating a mode where
# the user could choose amoung several options.  But some top-level
# were selectable, while others led to further options.  This required
# custom behavior for some of the options.  This mode allows for such
# custom behavior.  While the name remains "Choice", this is useful
# for creating just about any kind of mode.

use strict;
use Slim::Buttons::Common;
use Slim::Utils::Misc;
use Slim::Display::Display;

# TODO: move browseCache into Client object, where it will be cleaned up after client is forgotten
our %browseCache = (); # remember where each client is browsing

Slim::Buttons::Common::addMode('INPUT.Choice',getFunctions(),\&setMode);

# get the value the user is currently referencing.
# item could be hash, string or code
sub getItem {
	my $client = shift;
	my $index = shift;

	if (!defined($index)) {
		$index = Slim::Buttons::Common::param($client, 'listIndex') || 0;
	}

	my $listref = Slim::Buttons::Common::param($client, 'listRef');

	my $item = $listref->[$index];
	return $item;
}

# Each item in our list has a "name" which will be displayed on the
# Squeezebox.  Usually, name will be found in our listref.  But its
# also possible to define a name subroutine in our mode params, and if
# so that takes priority.
sub getItemName {
	my $client = shift;
	my $index = shift; # optional

	if (!defined($index)) {
		# if name has been overridden by a function, this code will get that.
		my $name = getParam($client, 'name');
		if ($name) {
			return $name;
		}
	}

	# name not overridden, get it from the item
	my $item = getItem($client, $index);
	if (ref($item)) {
		return $item->{'name'};
	}
	return $item;
}

# each item in our listref has a value
sub getItemValue {
	my $client = shift;
	my $index = shift; # optional
	my $item = getItem($client, $index);

	if (ref($item)) {
		return $item->{'value'};
	}
	return $item;
}

# some values can be mode-wide, or overridden at the list item level
sub getParam {
	my $client = shift;
	my $name = shift;

	my $item = getItem($client);
	if (ref($item)) {
		if ($item->{$name}) {
			return $item->{$name};
		}
	}
	return Slim::Buttons::Common::param($client, $name);
}

# Most of the data required by this mode can be either a hard value,
# or a subroutine which will return a value.  If a subroutine, we pass
# the client and the currently selected item from the listref as
# params.  So whatever data your subroutine needs, be sure to include
# it in the listref (each item in the list can be a hash, or a simple
# string)
sub getExtVal {
	my $client = shift;
	my $value = shift;

	if (!ref($value)) {
		return $value;
	} elsif (ref($value) eq 'CODE') {
		my @args;
		push @args, $client;
		push @args, getItem($client);
		return $value->(@args);
	} else {
		return $value;
	}
}

###########################
#Button mode specific junk#
###########################
my %functions = (
	#change character at cursorPos (both up and down)
	'up' => sub {
		my ($client,$funct,$functarg) = @_;
		changePos($client,-1);
		},
	'down' => sub {
		my ($client,$funct,$functarg) = @_;
		changePos($client,1);
	},
	'numberScroll' => sub {
		my ($client,$funct,$functarg) = @_;
		my $listRef = Slim::Buttons::Common::param($client,'listRef');

		my $newIndex = Slim::Buttons::Common::numberScroll($client, $functarg, $listRef, 0);
		if (defined $newIndex) {
			Slim::Buttons::Common::param($client,'listIndex',$newIndex);
			my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
			$$valueRef = $listRef->[$newIndex];
			my $onChange = getParam($client,'onChange');
			if (ref($onChange) eq 'CODE') {
				$onChange->($client, $valueRef ? ($$valueRef) : undef);
			}
		}
		$client->update;
	},
	#call callback procedure
	'exit' => sub {
		my ($client,$funct,$functarg) = @_;
		if (!defined($functarg) || $functarg eq '') {
			$functarg = 'exit'
		}
		exitInput($client,$functarg);
	},
	'passback' => \&passback,
	'play' => sub {callCallback('onPlay', @_)},
	'add' => sub {callCallback('onAdd', @_)},

	# right and left buttons is handled in exitInput

	# add more explicit callbacks if necessary here.
);

# use the parent mode's function...
sub passback {
	my ($client,$funct,$functarg) = @_;
	my $parentMode = Slim::Buttons::Common::param($client,'parentMode');
	if (defined($parentMode)) {
		Slim::Hardware::IR::executeButton($client,$client->lastirbutton,$client->lastirtime,$parentMode);
	}
}

# call callback if defined.  Otherwise, passback.  This
# preserves the behavior expected by most INPUT.list modes, while
# allowing newer modes to take advantage of the explicit callback.
sub callCallback {
	my $callbackName = shift;
	my $client = shift;
	my $funct = shift;
	my $functarg = shift;

	my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
	my $cb = getParam($client, $callbackName);
	if (ref($cb) eq 'CODE') {
		my @args = ($client, $valueRef ? ($$valueRef) : undef);
		$cb->(@args);
	} else {
		passback($client, $funct, $functarg);
	}
}

sub changePos {
	my ($client, $dir) = @_;
	my $listRef = Slim::Buttons::Common::param($client,'listRef');
	my $listIndex = Slim::Buttons::Common::param($client,'listIndex');
	if (getParam($client,'noWrap') 
		&& (($listIndex == 0 && $dir < 0) || ($listIndex == (scalar(@$listRef) - 1) && $dir > 0))) {
			#not wrapping and at end of list
			return;
	}
	my $newposition = Slim::Buttons::Common::scroll($client, $dir, scalar(@$listRef), $listIndex);
	my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
	$$valueRef = $listRef->[$newposition];
	Slim::Buttons::Common::param($client,'listIndex',$newposition);
	my $onChange = getParam($client,'onChange');

	if (ref($onChange) eq 'CODE') {
		$onChange->($client, $valueRef ? ($$valueRef) : undef);
	}
	if ($newposition != $listIndex) {
		if ($dir < 0) {
			$client->pushUp();
		} else {
			$client->pushDown();
		}
	}

	# if unique mode name supplied, remember where client was browsing
	if ($client->param("modeName") && $$valueRef) {
		my $value = $$valueRef;
		if (ref($value) eq 'HASH' && $value->{'value'}) {
			$value = $value->{'value'};
		}
		$browseCache{$client}{$client->param("modeName")} = $value;
	}
}

# callers can specify strings (i.e. header) as a string like this...
# text text text {STRING1} text {count} text {STRING2}
# and the behavior will be 
# 'text' will go through unchanged
# '{STRING}' will be replaced with STRING translated
# '{count}' will be replaced with (m of N) (i.e. like addHeaderCount in List mode)
sub formatString {
	my $client = shift;
	my $string = shift;
	my $listIndex = shift;
	my $listRef = shift;

	while ($string =~ /(.*?)\{(.*?)\}(.*)/) {
		if ($2 eq 'count') {
			# replace {count} with (n of M)
			$string = $1 . ' (' . ($listIndex + 1) . ' ' . $client->string('OF') .' ' . scalar(@$listRef) . ')' . $3;
		} else {
			# translate {STRING}
			$string = $1 . $client->string($2) . $3;
		}
	}
	return $string;
}

sub lines {
	my $client = shift;
	my ($line1, $line2);

	my $listIndex = Slim::Buttons::Common::param($client,'listIndex');
	my $listRef = Slim::Buttons::Common::param($client,'listRef');
	if (!defined($listRef)) { return ('','');}
	if ($listIndex == scalar(@$listRef)) {
		Slim::Buttons::Common::param($client,'listIndex',$listIndex-1);
		$listIndex--;
	}

	my $header = getExtVal($client, getParam($client, 'header'));

	$line1 = formatString($client, $header, $listIndex, $listRef);

	# deprecated.
	# callers should insert {STRING} into their header
	if (getParam($client,'stringHeader') && 
		Slim::Utils::Strings::stringExists($line1)) {
		$line1 = $client->string($line1);
	}

	if (scalar(@$listRef) == 0) {
		$line2 = $client->string('EMPTY');
	} else {

		# deprecated
		# callers should include {count} in header
		if (getParam($client,'headerAddCount')) {
			msg("INPUT.Choice: headerAddCount is deprecated. " .
				$client->param('headerAddCount'));
			bt();
			$line1 .= ' (' . ($listIndex + 1)
			. ' ' . $client->string('OF') .' ' . scalar(@$listRef) . ')';
		}

		$line2 = getExtVal($client, getItemName($client));

		# deprecated. don't set stringName or stringHeader, put strings
		# to be translated within curly brackets instead
		if (getParam($client,'stringName') && 
			Slim::Utils::Strings::stringExists($line2)) {
			$line2 = $client->linesPerScreen() == 1 ? $client->doubleString($line2) : $client->string($line2);
		} else {
			$line2 = formatString($client, $line2, $listIndex, $listRef);
		}
	}
	# overlayRef must refer to 2 element array, overlays for both lines
	my $overlayref = getExtVal($client, getParam($client, 'overlayRef'));
	return ($line1, $line2, defined($overlayref) ? @$overlayref : undef);
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $setMethod = shift;

	if (!init($client, $setMethod)) {
		Slim::Buttons::Common::popModeRight($client);
	}

	$client->lines(\&lines);
}

# set unsupplied values to defaults.
sub init {
	my $client = shift;
	my $setMethod = shift;

	my $init = Slim::Buttons::Common::param($client,'init');
	if ($init && (ref($init) eq 'CODE')) {
		$init->($client);
	}
	if (!defined(Slim::Buttons::Common::param($client,'parentMode'))) {
		my $i = -2;
		while ($client->modeStack->[$i] =~ /^INPUT./) { $i--; }
		Slim::Buttons::Common::param($client,'parentMode',$client->modeStack->[$i]);
	}
	if (!defined(Slim::Buttons::Common::param($client,'header'))) {
		# TODO: l10n
		# really, this is deprecated.  Define a header for your mode.
		Slim::Buttons::Common::param($client,'header','Select item:');
	}
	my $listRef = Slim::Buttons::Common::param($client,'listRef');

	return undef if !defined($listRef);

	# observe initial value only if pushing modes, not popping.
	my $listIndex = Slim::Buttons::Common::param($client,'listIndex') || 0;
	if ($setMethod eq 'push') {
		my $initialValue = getExtVal($client, getParam($client, 'initialValue'));
		# if initialValue not provided, use the one we saved
		if (!$initialValue && $client->param("modeName")) {
			$initialValue = $browseCache{$client}{$client->param("modeName")};
		}
		if ($initialValue) {
			my $newIndex;
			for ($newIndex = 0; $newIndex < scalar(@$listRef); $newIndex++) {
				last if $initialValue eq getItemValue($client, $newIndex);
			}
			if ($newIndex < scalar(@$listRef)) {
				$listIndex = $newIndex;
			}
		}
	}

	# valueRef stuff copied from INPUT.List.  Is it really necessary?
	Slim::Buttons::Common::param($client,'listIndex',$listIndex);
	my $valueRef;
	$$valueRef = $listRef->[$listIndex];
	$client->param('valueRef', $valueRef);
	return 1;
}

# copied from INPUT.List.
# Why is pressing right handled here, instead of in our function callbacks???
sub exitInput {
	my ($client,$exitType) = @_;
	my $callbackFunct = getParam($client,'callback');
	my $onRight;
	my $valueRef;

	if (!defined($callbackFunct) || !(ref($callbackFunct) eq 'CODE')) {
		if ($exitType eq 'right') {
			# if user has requested a callback when right is pressed, give it to 'em
			$onRight = getParam($client,'onRight');
			if (defined($onRight) && (ref($onRight) eq 'CODE')) {
				$valueRef = Slim::Buttons::Common::param($client,'valueRef');
				my $lines = $onRight->($client, (defined($valueRef) ? ($$valueRef) : undef));
				if (defined($lines) && (ref($lines) eq 'ARRAY')) {
					# if onRight returns lines, show them.
					$client->showBriefly($lines->[0], $lines->[1], undef, 1);
				}
			} else {
				$client->bumpRight();
			}
		} elsif ($exitType eq 'left') {
			Slim::Buttons::Common::popModeRight($client);
		} else {
			Slim::Buttons::Common::popMode($client);
		}
		return;
	} else {
		$callbackFunct->(@_);
	}
}

1;

