package Slim::Buttons::Input::Choice;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::Input::Choice

=head1 SYNOPSIS

 my %params = (
	header   => $client->modeParam('header') || ($title . ' {count}'),
	listRef  => \@list,
	url      => $url,
	title    => $title,
	favorite => $favorite ? $favorite->{'num'} : undef,

	# play music when play is pressed
	onPlay => sub {
		;
	},

	onAdd => sub {

	},
	
	onRight => $client->modeParam('onRight'), # passthrough
 );

 Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);;

=head1 DESCRIPTION

L<Slim::Buttons::Input::Choice> is modelled after INPUT.List, but more "electric", in that
most mode params can be either hard values or subroutines to be
invoked at run time.  More documentation coming soon.

The name Choice comes from its original use, creating a mode where
the user could choose amoung several options.  But some top-level
were selectable, while others led to further options.  This required
custom behavior for some of the options.  This mode allows for such
custom behavior.  While the name remains "Choice", this is useful
for creating just about any kind of mode.

=cut

use strict;
use warnings;

use Slim::Buttons::Common;
use Slim::Utils::Misc;
use Slim::Display::Display;

# TODO: move browseCache into Client object, where it will be cleaned up after client is forgotten
our %browseCache = (); # remember where each client is browsing

Slim::Buttons::Common::addMode('INPUT.Choice', getFunctions(), \&setMode);

# get the value the user is currently referencing.
# item could be hash, string or code
sub getItem {
	my $client = shift;
	my $index  = shift;

	if (!defined($index)) {
		$index = $client->modeParam('listIndex') || 0;
	}

	my $listref = $client->modeParam('listRef');

	return $listref->[$index];
}

# Each item in our list has a "name" which will be displayed on the
# Squeezebox.  Usually, name will be found in our listref.  But its
# also possible to define a name subroutine in our mode params, and if
# so that takes priority.
sub getItemName {
	my $client = shift;
	my $index  = shift; # optional

	if (!defined($index)) {

		# if name has been overridden by a function, this code will get that.
		my $name = getParam($client, 'name');
		if ($name) {
			return $name;
		}
	}

	# name not overridden, get it from the item
	my $item = getItem($client, $index);

	if ( ref($item) && $item->{'name'} ) {
		return $item->{'name'};
	}
	
	# use lookupRef to find the item name if available
	if ( my $lookup = $client->modeParam('lookupRef') ) {
		return $lookup->( $client->modeParam('listIndex') || 0 );
	}

	return $item;
}

# each item in our listref has a value
sub getItemValue {
	my $client = shift;
	my $index  = shift; # optional
	my $item   = getItem($client, $index);

	if (ref($item)) {
		return $item->{'value'};
	}

	return $item;
}

# some values can be mode-wide, or overridden at the list item level
sub getParam {
	my $client = shift;
	my $name   = shift;

	my $item = getItem($client);

	if (ref($item)) {

		if ($item->{$name}) {
			return $item->{$name};
		}
	}

	return $client->modeParam($name);
}

# Most of the data required by this mode can be either a hard value,
# or a subroutine which will return a value.  If a subroutine, we pass
# the client and the currently selected item from the listref as
# params.  So whatever data your subroutine needs, be sure to include
# it in the listref (each item in the list can be a hash, or a simple
# string)
sub getExtVal {
	my $client = shift;
	my $value  = shift;

	if (ref $value eq 'CODE') {

		my $ret = eval { $value->($client, getItem($client)) };

		if ($@) {
			errorMsg("INPUT.Choice: getExtVal - couldn't run coderef. [$@]\n");
			return '';
		}

		return $ret;

	} else {

		return $value;
	}
}

###########################
#Button mode specific junk#
###########################
my %functions = (

	# change character at cursorPos (both up and down)
	'up' => sub {
		my ($client, $funct, $functarg) = @_;

		changePos($client, -1, $funct);
	},

	'down' => sub {
		my ($client, $funct, $functarg) = @_;

		changePos($client, 1, $funct);
	},
	'knob' => sub {
		my ($client,$funct,$functarg) = @_;

		my ($newPos, $dir, $pushDir, $wrap) = $client->knobListPos();
		
		changePos($client, $dir, $funct, $pushDir) if $pushDir;
	},
	'numberScroll' => sub {
		my ($client, $funct, $functarg) = @_;

		my $listRef = $client->modeParam('listRef');

		my $newIndex = Slim::Buttons::Common::numberScroll(
			$client,
			$functarg,
			$listRef,
			$client->modeParam('isSorted') ? 1 : 0,
			$client->modeParam('lookupRef'),
		);

		if (defined $newIndex) {

			$client->modeParam('listIndex', $newIndex);

			my $valueRef = $client->modeParam('valueRef');
			  $$valueRef = $listRef->[$newIndex];

			my $onChange = getParam($client, 'onChange');

			if (ref($onChange) eq 'CODE') {

				eval { $onChange->($client, $valueRef ? ($$valueRef) : undef) };

				if ($@) {
					errorMsg("INPUT.Choice: numberScroll caught error: [$@]\n");
				}
			}
		}

		$client->update;
	},

	# call callback procedure
	'exit' => sub {
		my ($client,$funct,$functarg) = @_;

		if (!defined($functarg) || $functarg eq '') {
			$functarg = 'exit'
		}

		exitInput($client,$functarg);
	},

	'passback' => \&passback,
	'play'     => sub { callCallback('onPlay', @_) },
	'add'      => sub { callCallback('onAdd', @_)  },
	
	# right and left buttons is handled in exitInput

	# add more explicit callbacks if necessary here.
);

# use the parent mode's function...
sub passback {
	my ($client, $funct, $functarg) = @_;

	my $parentMode = $client->modeParam('parentMode');

	if (defined($parentMode)) {

		Slim::Hardware::IR::executeButton(
			$client,
			$client->lastirbutton,
			$client->lastirtime,
			$parentMode
		);
	}
}

# call callback if defined.  Otherwise, passback.  This
# preserves the behavior expected by most INPUT.list modes, while
# allowing newer modes to take advantage of the explicit callback.
sub callCallback {
	my $callbackName = shift;
	my $client       = shift;
	my $funct        = shift;
	my $functarg     = shift;

	my $valueRef = $client->modeParam('valueRef');
	my $callback = getParam($client, $callbackName);

	if (ref($callback) eq 'CODE') {

		my @args = ($client, $valueRef ? ($$valueRef) : undef);

		eval { $callback->(@args) };

		if ($@) {
			errorMsg("INPUT.Choice: Couldn't run callback: [$callbackName] : $@\n");
		
		} elsif (getParam($client,'pref')) {
		
			$client->update;
		}


	} else {

		passback($client, $funct, $functarg);
	}
}

sub changePos {
	my ($client, $dir, $funct, $pushDir) = @_;

	my $listRef   = $client->modeParam('listRef');
	my $listIndex = $client->modeParam('listIndex');
	
	if ($client->modeParam('noWrap')) {
		
		#not wrapping and at end of list
		if ($listIndex == 0 && $dir < 0) {
			$client->bumpUp() if ($funct !~ /repeat/);
			return;
		}
		
		if ($listIndex >= (scalar(@$listRef) - 1) && $dir > 0) {
			$client->bumpDown() if ($funct !~ /repeat/);
			return;
		}
	}

	my $newposition = Slim::Buttons::Common::scroll($client, $dir, scalar(@$listRef), $listIndex);
	
	$::d_ui && msgf("changepos: newpos: $newposition = scroll dir:$dir listIndex: $listIndex listLen: %d\n", scalar(@$listRef));
	
	my $valueRef = $client->modeParam('valueRef');

	$$valueRef = $listRef->[$newposition];
	$client->modeParam('listIndex',$newposition);

	$client->updateKnob();

	my $onChange = getParam($client,'onChange');

	if (ref($onChange) eq 'CODE') {
		$onChange->($client, $valueRef ? ($$valueRef) : undef);
	}

	if (scalar(@$listRef) < 2) {

		if ($dir < 0) {
			$client->bumpUp() if ($funct !~ /repeat/);
		} else {
			$client->bumpDown() if ($funct !~ /repeat/);
		}

	} elsif ($newposition != $listIndex) {
		
		$pushDir ||= '';
		
		if ($pushDir eq 'up')  {
			
			$client->pushUp();
		} elsif ($pushDir eq 'down') {
			
			$client->pushDown();
		} elsif ($dir < 0)  {
			
			$client->pushUp();
		} else {
			
			$client->pushDown();
		}

	}

	# if unique mode name supplied, remember where client was browsing
	if ($client->modeParam("modeName") && $$valueRef) {

		my $value = $$valueRef;

		if (ref($value) eq 'HASH' && $value->{'value'}) {
			$value = $value->{'value'};
		}

		$browseCache{$client}{$client->modeParam("modeName")} = $value;
	}
}

# callers can specify strings (i.e. header) as a string like this...
# text text text {STRING1} text {count} text {STRING2}
# and the behavior will be 
# 'text' will go through unchanged
# '{STRING}' will be replaced with STRING translated
# '{count}' will be replaced with (m of N) (i.e. like addHeaderCount in List mode)
sub formatString {
	my $client    = shift;
	my $string    = shift;
	my $listIndex = shift;
	my $listRef   = shift;

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

	my $listIndex = $client->modeParam('listIndex');
	my $listRef   = $client->modeParam('listRef');

	if (!defined($listRef)) {

		return ({});
	}

	if ($listIndex == scalar(@$listRef)) {
		$client->modeParam('listIndex',$listIndex-1);
		$listIndex--;
	}

	my $header = getExtVal($client, getParam($client, 'header'));

	$line1 = formatString($client, $header, $listIndex, $listRef);

	# deprecated.
	# callers should insert {STRING} into their header
	if (getParam($client,'stringHeader') && Slim::Utils::Strings::stringExists($line1)) {

		$line1 = $client->string($line1);
	}

	if (scalar(@$listRef) == 0) {

		$line2 = $client->string('EMPTY');

	} else {

		# deprecated
		# callers should include {count} in header
		if (getParam($client,'headerAddCount')) {
			msg("INPUT.Choice: headerAddCount is deprecated. " .
				$client->modeParam('headerAddCount'));
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

	my ($overlay1, $overlay2);

	my $overlayref = getExtVal($client, getParam($client, 'overlayRef'));

	if (ref($overlayref) eq 'ARRAY') {

		($overlay1, $overlay2) = @$overlayref;
		$overlay1 = $client->symbols($overlay1) if (defined($overlay1));
		$overlay2 = $client->symbols($overlay2) if (defined($overlay2));
		
	} elsif (my $pref = getParam($client,'pref')) {
		
		# assume a single non-descending list of items, 'pref' item must be given in the params
		my $val = ref $pref eq 'CODE' ? $pref->($client) : $client->prefGet($pref);
		$overlay2 = Slim::Buttons::Common::checkBoxOverlay($client, $val eq getItemValue($client));
	}

	my $parts = {
		'line'    => [ $line1, $line2 ],
		'overlay' => [ $overlay1, $overlay2 ],
	};

	return $parts;
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client    = shift;
	my $setMethod = shift;

	if (!init($client, $setMethod)) {
		Slim::Buttons::Common::popModeRight($client);
	}

	$client->lines(\&lines);
}

# set unsupplied values to defaults.
sub init {
	my $client    = shift;
	my $setMethod = shift;

	my $init = $client->modeParam('init');

	if ($init && (ref($init) eq 'CODE')) {
		$init->($client);
	}

	if (!defined($client->modeParam('parentMode'))) {

		my $i = -2;

		while ($client->modeStack->[$i] =~ /^INPUT./) {
			$i--;
		}

		$client->modeParam('parentMode', $client->modeStack->[$i]);
	}

	if (!defined($client->modeParam('header'))) {

		$client->modeParam('header',$client->string('SELECT_ITEM'));
	}

	my $listRef = $client->modeParam('listRef');

	return undef if !defined($listRef);

	# observe initial value only if pushing modes, not popping.
	my $listIndex = $client->modeParam('listIndex') || 0;

	if ($setMethod eq 'push') {

		my $initialValue = getExtVal($client, getParam($client, 'initialValue'));
		
		# if initialValue not provided, use the one we saved
		if (!$initialValue && $client->modeParam("modeName")) {

			$initialValue = $browseCache{$client}{$client->modeParam("modeName")};
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
	$client->modeParam('listIndex', $listIndex);

	# Take a copy of the current value;
	my $valueRef = $listRef->[$listIndex];
	$client->modeParam('valueRef', \$valueRef);

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

				$valueRef = $client->modeParam('valueRef');

				my $lines = $onRight->($client, (defined($valueRef) ? ($$valueRef) : undef));

				if (defined($lines) && (ref($lines) eq 'ARRAY')) {

					# if onRight returns lines, show them.
					$client->showBriefly($lines->[0], $lines->[1], undef, 1);

				} elsif (getParam($client,'pref')) {
		
					$client->update;
				}

			} else {
				$client->bumpRight();
			}

		} elsif ($exitType eq 'left') {

			Slim::Buttons::Common::popModeRight($client);

		} else {

			Slim::Buttons::Common::popMode($client);
		}

	} else {

		$callbackFunct->(@_);
	}
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Player::Client>

L<Slim::Buttons::Settings>

=cut

1;
