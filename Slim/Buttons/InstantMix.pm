package Slim::Buttons::InstantMix;

#$Id: InstantMix.pm,v 1.9 2004/12/17 10:09:29 kdf Exp $

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Buttons::Common;
use Slim::Utils::Timers;
use Slim::Hardware::VFD;

Slim::Buttons::Common::addMode('instant_mix',getFunctions(),\&setMode);

# button functions for browse directory
my @instantMix = ();

my %functions = (
	'up' => sub  {
		my $client = shift;
		my $count = scalar @instantMix;
		
		if ($count < 2) {
			$client->bumpUp();
		} else {
			my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#instantMix + 1), selection($client, 'instant_mix_index'));
			setSelection($client, 'instant_mix_index', $newposition);
			$client->update();
		}
	},
	
	'down' => sub  {
		my $client = shift;
		my $count = scalar @instantMix;

		if ($count < 2) {
			$client->bumpDown();
		} else {
			my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#instantMix + 1), selection($client, 'instant_mix_index'));
			setSelection($client, 'instant_mix_index', $newposition);
			$client->update();
		}
	},
	
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	
	'right' => sub  {
		my $client = shift;

		my @oldlines = Slim::Display::Display::curLines($client);
		Slim::Buttons::Common::pushMode($client, 'trackinfo', {'track' => $instantMix[selection($client, 'instant_mix_index')]});
		$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
	},
	'play' => sub  {
		my $client = shift;
		my $button = shift;
		my $append = shift;
		my $line1;
		my $line2;
		
		if ($append) {
			$line1 = $client->string('ADDING_TO_PLAYLIST')
		} elsif (Slim::Player::Playlist::shuffle($client)) {
			$line1 = $client->string('PLAYING_RANDOMLY_FROM');
		} else {
			$line1 = $client->string('NOW_PLAYING_FROM')
		}
		$line2 = $client->string('INSTANT_MIX');
		
		$client->showBriefly($client->renderOverlay($line1, $line2, undef, Slim::Display::Display::symbol('notesymbol')));
		
		Slim::Control::Command::execute($client, ["playlist", $append ? "append" : "play", $instantMix[0]]);
		
		for (my $i=1; $i<=$#instantMix; $i++) {
			Slim::Control::Command::execute($client, ["playlist", "append", $instantMix[$i]]);
		}
	},
);

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $push = shift;
	
	if ($push eq "push") {
		setSelection($client, 'instant_mix_index', 0);
		
		if (defined Slim::Buttons::Common::param($client, 'mix')) {
				@instantMix = @{Slim::Buttons::Common::param($client,'mix')};
		} else {
				die 'no/unknown type specified for instant mix';
		}
	}
	$client->lines(\&lines);

}


#
# figure out the lines to be put up to display
#
sub lines {
	my $client = shift;
	my ($line1, $line2);

	$line1 = $client->string('INSTANT_MIX');
	
	$line1 .= sprintf(" (%d ".$client->string('OUT_OF')." %s)", selection($client, 'instant_mix_index') + 1, scalar @instantMix);

	$line2 = Slim::Music::Info::infoFormat($instantMix[selection($client, 'instant_mix_index')], 'TITLE (ARTIST)', 'TITLE');

	return ($line1, $line2, undef, Slim::Display::Display::symbol('rightarrow'));
}

#	get the current selection parameter from the parameter stack
sub selection {
	my $client = shift;
	my $index = shift;

	my $value = Slim::Buttons::Common::param($client, $index);

	if (defined $value  && $value eq '__undefined') {
		undef $value;
	}

	return $value;
}

#	set the current selection parameter from the parameter stack
sub setSelection {
	my $client = shift;
	my $index = shift;
	my $value = shift;

	if (!defined $value) {
		$value = '__undefined';
	}

	Slim::Buttons::Common::param($client, $index, $value);
}

1;

__END__
