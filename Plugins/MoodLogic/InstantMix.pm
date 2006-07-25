package Plugins::MoodLogic::InstantMix;

#$Id: /mirror/slim/branches/split-scanner/Plugins/MoodLogic/InstantMix.pm 4113 2005-08-29T19:51:42.434193Z adrian  $

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Buttons::Common;
use Slim::Music::TitleFormatter;
use Slim::Utils::Timers;

# button functions for browse directory
our @instantMix = ();

our %functions = ();

sub init {

	Slim::Buttons::Common::addMode('moodlogic_instant_mix', getFunctions(), \&setMode);

	%functions = (
		'up' => sub  {
			my $client = shift;
			my $button;
			my $count = scalar @instantMix;
			
			if ($count < 2) {
				$client->bumpUp() if ($button !~ /repeat/);
			} else {
				my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#instantMix + 1), selection($client, 'instant_mix_index'));
				setSelection($client, 'instant_mix_index', $newposition);
				$client->pushUp();
			}
		},
		
		'down' => sub  {
			my $client = shift;
			my $button = shift;
			my $count = scalar @instantMix;

			if ($count < 2) {
				$client->bumpDown() if ($button !~ /repeat/);;
			} else {
				my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#instantMix + 1), selection($client, 'instant_mix_index'));
				setSelection($client, 'instant_mix_index', $newposition);
				$client->pushDown();
			}
		},
		
		'left' => sub  {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},
		
		'right' => sub  {
			my $client = shift;

			Slim::Buttons::Common::pushMode($client, 'trackinfo', {'track' => $instantMix[selection($client, 'instant_mix_index')]});
			$client->pushLeft();
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
			$line2 = $client->string('MOODLOGIC_INSTANT_MIX');
			
			$client->showBriefly( {
				'line1'    => $line1,
				'line2'    => $line2,
				'overlay2' => $client->symbols('notesymbol'),
			});
			
			$client->execute(["playlist", $append ? "append" : "play", $instantMix[0]]);
			
			for (my $i=1; $i<=$#instantMix; $i++) {
				$client->execute(["playlist", "append", $instantMix[$i]]);
			}
		},
	);
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $push = shift;
	
	if ($push eq "push") {
		setSelection($client, 'instant_mix_index', 0);
		
		if (defined $client->param( 'mix')) {
			@instantMix = @{$client->param('mix')};
		}
	}

	$client->lines(\&lines);
}

# figure out the lines to be put up to display
sub lines {
	my $client = shift;

	my $line1 = $client->string('MOODLOGIC_INSTANT_MIX');
	
	$line1 .= sprintf(" (%d ".$client->string('OUT_OF')." %s)", selection($client, 'instant_mix_index') + 1, scalar @instantMix);

	my $line2 = Slim::Music::TitleFormatter::infoFormat($instantMix[selection($client, 'instant_mix_index')], 'TITLE (ARTIST)', 'TITLE');

	return {
		'line1'    => $line1,
		'line2'    => $line2,
		'overlay2' => $client->symbols('rightarrow'),
	};
}

#	get the current selection parameter from the parameter stack
sub selection {
	my $client = shift;
	my $index = shift;

	my $value = $client->param( $index);

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

	$client->param( $index, $value);
}

1;

__END__
