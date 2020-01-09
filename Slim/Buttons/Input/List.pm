package Slim::Buttons::Input::List;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::Input::List

=head1 SYNOPSIS

 my %params = (
	'stringHeader'   => 1,
	'header'         => 'FAVORITES',
	'listRef'        => \@titles,
	'callback'       => \&mainModeCallback,
	'valueRef'       => \$context{$client}->{mainModeIndex},
	'externRef'      => sub {return $_[1] || $_[0]->string('EMPTY')},
	'headerAddCount' => scalar (@urls) ? 1 : 0,
	'urls'           => \@urls,
	'parentMode'     => Slim::Buttons::Common::mode($client),
	'overlayRef'     => sub {
		my $client = shift;
		if (scalar @urls) {
			return (undef, $client->symbols('notesymbol'));
		} else {
			return undef;
		}
	'overlayRefArgs' => 'C',
	},
 );

 Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);

=head1 DESCRIPTION

L<Slim::Buttons::Input::List> is a reusable Logitech Media Server module, creating a 
generic framework UI for navigating through a List of items, with configurable
display parameters and entry/leave points.

=cut

use strict;

use Slim::Buttons::Common;
use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Misc;

my $prefs = preferences('server');

my $log = logger('player.ui');

Slim::Buttons::Common::addMode('INPUT.List', getFunctions(), \&setMode);

###########################
#Button mode specific junk#
###########################
our %functions = (
	#change character at cursorPos (both up and down)
	'up' => sub {
		my ($client, $funct, $functarg) = @_;

		changePos($client, -1, $funct);
	},

	'down' => sub {
		my ($client, $funct, $functarg) = @_;

		changePos($client, 1, $funct);
	},

	'knob' => sub {
		my ($client, $funct, $functarg) = @_;

		my ($newPos, $dir, $pushDir, $wrap) = $client->knobListPos();
		
		changePos($client, $dir, $funct, $pushDir) if $pushDir;
	},

	'numberScroll' => sub {
		my ($client, $funct, $functarg) = @_;

		my $isSorted  = $client->modeParam('isSorted');
		my $lookupRef = $client->modeParam('lookupRef');
		my $listRef   = $client->modeParam('listRef');

		my $numScrollRef;

		if ($isSorted && uc($isSorted) eq 'E') {

			# sorted by the external value
			$numScrollRef = $client->modeParam('externRef');

		} else {

			# not sorted or sorted by the internal value
			$numScrollRef = $listRef;
		}

		my $newIndex = Slim::Buttons::Common::numberScroll($client, $functarg, $numScrollRef, $isSorted ? 1 : 0, $lookupRef);

		if (defined $newIndex) {

			$client->modeParam('listIndex',$newIndex);

			my $valueRef = $client->modeParam('valueRef');

			$$valueRef = $listRef->[$newIndex];

			my $onChange = $client->modeParam('onChange');

			if (ref($onChange) eq 'CODE') {
				my $onChangeArgs = $client->modeParam('onChangeArgs');
				my @args;

				push @args, $client if $onChangeArgs =~ /c/i;
				push @args, $$valueRef if $onChangeArgs =~ /v/i;
				push @args, $newIndex if $onChangeArgs =~ /i/i;
				$onChange->(@args);
			}
		}

		$client->update;
	},
	
	#call callback procedure
	'exit' => sub {
		my ($client, $funct, $functarg) = @_;

		if (!$functarg) {
			$functarg = 'exit'
		}

		exitInput($client, $functarg);
	},
		
	'passback' => sub {
		my ($client, $funct, $functarg) = @_;

		my $parentMode = $client->modeParam('parentMode');

		if (defined($parentMode)) {
			Slim::Hardware::IR::executeButton($client,$client->lastirbutton,$client->lastirtime,$parentMode);
		}
	},
);

sub changePos {
	my ($client, $dir, $funct, $pushDir) = @_;

	my $listRef   = $client->modeParam('listRef');
	my $listIndex = $client->modeParam('listIndex');

	if ($client->modeParam('noWrap')) {

		# not wrapping and at end of list
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

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug(
			"newpos: $newposition = scroll dir:$dir listIndex: $listIndex listLen: ", scalar(@$listRef)
		);
	}

	my $valueRef = $client->modeParam('valueRef');

	$$valueRef = $listRef->[$newposition];

	$client->modeParam('listIndex', $newposition);

	my $onChange = $client->modeParam('onChange');

	$client->updateKnob();

	if (ref($onChange) eq 'CODE') {
		my $onChangeArgs = $client->modeParam('onChangeArgs');
		my @args;

		push @args, $client if $onChangeArgs =~ /c/i;
		push @args, $$valueRef if $onChangeArgs =~ /v/i;
		push @args, $client->modeParam('listIndex') if $onChangeArgs =~ /i/i;

		$onChange->(@args);
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
}

sub lines {
	my $client = shift;
	my $args   = shift;

	my ($line1, $line2);
	my $listIndex = $client->modeParam('listIndex');
	my $listRef = $client->modeParam('listRef');

	if (!defined($listRef)) { return {} }

	if ($listIndex && ($listIndex == scalar(@$listRef))) {
		$client->modeParam('listIndex',$listIndex-1);
		$listIndex--;
	}
	
	$line1 = getExtVal($client,$listRef->[$listIndex],$listIndex,'header');

	if ($client->modeParam('stringHeader') && Slim::Utils::Strings::stringExists($line1)) {
		$line1 = $client->string($line1);
	}

	if (scalar(@$listRef) == 0) {
		$line2 = $client->string('EMPTY');

	} else {

		$line2 = getExtVal($client,$listRef->[$listIndex],$listIndex,'externRef');

		if ($client->modeParam('stringExternRef') && Slim::Utils::Strings::stringExists($line2)) {
			$line2 = $client->linesPerScreen() == 1 ? $client->doubleString($line2) : $client->string($line2);
		}
	}

	my ($overlay1, $overlay2) = getExtVal($client,$listRef->[$listIndex],$listIndex,'overlayRef');

	# show count if we are the new screen of a push transition or pref is set
	if (($args->{'trans'} || $prefs->client($client)->get('alwaysShowCount')) && $client->modeParam('headerAddCount')) {
		$overlay1 .= ' ' . ($listIndex + 1) . ' ' . $client->string('OF') .' ' . scalar(@$listRef);
	}

	# truncate long strings in the header with '...'
	my $len   = $client->measureText($line1, 1);
	my $width = $client->displayWidth;
	my $trunc = '...';

	if ($len > $width) {
		$width -= $client->measureText($trunc, 1);
		while ($len > $width) {
			$line1 = substr $line1, 0, -1;
			$len = $client->measureText($line1, 1);
		}
		$line1 .= $trunc;
	}

	my $parts = {
		'line'    => [ $line1, $line2 ],
		'overlay' => [ $overlay1, $overlay2 ]
	};

	if ($client->modeParam('fonts')) {
		$parts->{'fonts'} = $client->modeParam('fonts');
	}

	return $parts;
}

sub getExtVal {
	my ($client, $value, $listIndex, $source) = @_;

	my $extref = $client->modeParam($source);
	my $extval;

	if (ref($extref) eq 'ARRAY') {
		$extref = $extref->[$listIndex];
	}

	if (!ref($extref)) {

		return $extref;
	
	} elsif (ref($extref) eq 'CODE') {

		my @args = ();

		my $argtype = $client->modeParam($source . 'Args');
	
		push @args, $client    if $argtype =~ /c/i;
		push @args, $value     if $argtype =~ /v/i;
		push @args, $listIndex if $argtype =~ /i/i;
	
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
	my $client    = shift;
	my $setMethod = shift;

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
# headerArgs = CV # accepts C, V and I (I is the 1-based index)
# stringHeader = undef # if true, put the value of header through the string function
	# before displaying it.
# headerAddCount = undef # if true add (I of T) to end of header
	# where I is the 1 based index and T is the total # of items
# valueRef =  # reference to value to be selected
# callback = undef # function to call to exit mode
# listIndex = 0 or position of valueRef in listRef
# init = undef # function to init any number of params at calltime, accepts client as arg
# noWrap = undef # whether or not the list wraps at the ends
# externRef = undef
# externRefArgs = CV # accepts C, V and I
# stringExternRef = undef # same as with stringHeader, but for the value of externRef
# overlayRef = undef
# overlayRefArgs = CV # accepts C, V and I
# onChange = undef
# onChangeArgs = CV # accepts C, V and I
# for the *Args parameters, the letters indicate what values to send to the code ref
#  (C for client object, V for current value, I for list index)

# other parameters used
# isSorted = undef # whether the interal or external list is sorted 
	#(I for internal, E for external, L for lookup, undef or anything else for unsorted)
# lookupRef = undef # function that returns the sortable version of item

sub init {
	my $client = shift;

	my $init = $client->modeParam('init');

	if ($init && (ref($init) eq 'CODE')) {
		$init->($client);
	}

	if (!defined($client->modeParam('parentMode'))) {
		my $i = -2;

		while ($client->modeStack->[$i] =~ /^INPUT./) { $i--; }

		$client->modeParam('parentMode',$client->modeStack->[$i]);
	}

	if (!defined($client->modeParam('header'))) {
		$client->modeParam('header',$client->string('SELECT_ITEM'));
	}

	my $listRef   = $client->modeParam('listRef');
	my $externRef = $client->modeParam('externRef');

	if (!defined $listRef && ref($externRef) eq 'ARRAY') {
		$listRef = $externRef;
		$client->modeParam('listRef',$listRef);
	}

	if (!defined $externRef && ref($listRef) eq 'ARRAY') {
		$externRef = $listRef;
		$client->modeParam('externRef',$externRef);
	}

	return undef if !defined($listRef);

	my $isSorted = $client->modeParam('isSorted');
	my $lookupRef = $client->modeParam('lookupRef');

	if ($isSorted && ($isSorted !~ /[iIeElL]/ || (uc($isSorted) eq 'E' && ref($externRef) ne 'ARRAY') || (uc($isSorted) eq 'L' && ref($lookupRef) ne 'CODE'))) {
		$client->modeParam('isSorted',0);
	}

	my $listIndex = $client->modeParam('listIndex');
	my $valueRef = $client->modeParam('valueRef');

	if (!defined($listIndex) || (scalar(@$listRef) == 0)) {

		$listIndex = 0;

	} elsif ($listIndex > $#$listRef) {

		$listIndex = $#$listRef;
	}

	while ($listIndex < 0) {
		$listIndex += scalar(@$listRef);
	}

	if (!defined($valueRef) || (ref($valueRef) && !defined($$valueRef))) {

		$$valueRef = $listRef->[$listIndex];
		$client->modeParam('valueRef',$valueRef);

	} elsif (!ref($valueRef)) {
		my $value = $valueRef;

		$valueRef = \$value;
		$client->modeParam('valueRef',$valueRef);
	}

	if ((scalar(@$listRef) != 0) && $$valueRef ne $listRef->[$listIndex]) {
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

	$client->modeParam('listIndex',$listIndex);

	if (!defined($client->modeParam('externRefArgs'))) {
		$client->modeParam('externRefArgs','CV');
	}

	if (!defined($client->modeParam('overlayRefArgs'))) {
		$client->modeParam('overlayRefArgs','CV');
	}

	if (!defined($client->modeParam('onChangeArgs'))) {
		$client->modeParam('onChangeArgs','CV');
	}

	if (!defined($client->modeParam('headerArgs'))) {
		$client->modeParam('headerArgs','CV');
	}

	return 1;
}

sub exitInput {
	my ($client,$exitType) = @_;

	my $callbackFunct = $client->modeParam('callback');

	if (!defined($callbackFunct) || !(ref($callbackFunct) eq 'CODE')) {

		if ($exitType eq 'right') {
			$client->bumpRight();

		} elsif ($exitType eq 'left') {
			Slim::Buttons::Common::popModeRight($client);

		} else {
			Slim::Buttons::Common::popMode($client);
		}

		return;
	}

	$callbackFunct->(@_);
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Utils::Timers>

L<Slim::Buttons::Settings>

=cut

1;
