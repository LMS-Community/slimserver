package Slim::Buttons::Settings;

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Buttons::Browse;
use Slim::Buttons::AlarmClock;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw (string);
use Slim::Utils::Prefs;

# button functions for browse directory
my @defaultSettingsChoices = (sort('REPEAT','SHUFFLE','TEXTSIZE','TITLEFORMAT','TREBLE', 'BASS', 'VOLUME', 'ALARM'));
my @settingsChoices;
my %functions = (
	'up' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#settingsChoices + 1), $client->settingsSelection);
		$client->settingsSelection($newposition);
		Slim::Display::Display::update($client);
	},
	'down' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#settingsChoices + 1), $client->settingsSelection);
		$client->settingsSelection($newposition);
		Slim::Display::Display::update($client);
	},
	'left' => sub   {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		if ($settingsChoices[$client->settingsSelection] eq 'SYNCHRONIZE') {
			# reset to the top level of the music
			Slim::Buttons::Common::pushModeLeft($client, 'synchronize');
		} elsif ($settingsChoices[$client->settingsSelection] eq 'REPEAT') {
			Slim::Buttons::Common::pushModeLeft($client, 'repeat');
		} elsif ($settingsChoices[$client->settingsSelection] eq 'TEXTSIZE') {
			Slim::Buttons::Common::pushModeLeft($client, 'textsize');
		} elsif ($settingsChoices[$client->settingsSelection] eq 'TITLEFORMAT') {
			Slim::Buttons::Common::pushModeLeft($client, 'titleformat');
		} elsif ($settingsChoices[$client->settingsSelection] eq 'SHUFFLE') {
			Slim::Buttons::Common::pushModeLeft($client, 'shuffle');
		} elsif ($settingsChoices[$client->settingsSelection] eq 'TREBLE') {
			Slim::Buttons::Common::pushModeLeft($client, 'treble');
		} elsif ($settingsChoices[$client->settingsSelection] eq 'BASS') {
			Slim::Buttons::Common::pushModeLeft($client, 'bass');
		} elsif ($settingsChoices[$client->settingsSelection] eq 'VOLUME') {
			Slim::Buttons::Common::pushModeLeft($client, 'volume');
		} elsif ($settingsChoices[$client->settingsSelection] eq 'ALARM') {
			Slim::Buttons::Common::pushModeLeft($client, 'alarm');
		}
	}
);

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	updateMenu($client);
	if (!defined($client->settingsSelection)) { $client->settingsSelection(0); };
	$client->lines(\&lines);
}

sub updateMenu {
	my $client = shift;
	@settingsChoices = @defaultSettingsChoices;
 	if (Slim::Player::Playlist::isSynced($client) || (scalar(Slim::Player::Playlist::canSyncWith($client)) > 0)) {
		push @settingsChoices, 'SYNCHRONIZE';
	}
}

#
# figure out the lines to be put up to display the directory
#
sub lines {
	my $client = shift;
	my ($line1, $line2);
	$line1 = string('SETTINGS');
	$line2 = string($settingsChoices[$client->settingsSelection]);
	return ($line1, $line2, undef, Slim::Hardware::VFD::symbol('rightarrow'));
}


######################################################################
# settings submodes for: textSize, repeat, titleformat, treble, bass and shuffle

my @repeatSettingsChoices;

my %repeatSettingsFunctions = (
	'up' => sub {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#repeatSettingsChoices + 1), Slim::Player::Playlist::repeat($client) );
		Slim::Control::Command::execute($client, ["playlist", "repeat", $newposition]);
		Slim::Display::Display::update($client);
	},
	'down' => sub {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#repeatSettingsChoices + 1), Slim::Player::Playlist::repeat($client) );
		Slim::Control::Command::execute($client, ["playlist", "repeat", $newposition]);
		Slim::Display::Display::update($client);
	},
	'left' => $functions{'left'},
	'right' => sub { Slim::Display::Animation::bumpRight(shift); },
	'add' => sub { Slim::Display::Animation::bumpRight(shift); },
	'play' => sub { Slim::Display::Animation::bumpRight(shift); },
);

sub getRepeatFunctions {
	return \%repeatSettingsFunctions;
}

sub setRepeatMode {
	my $client = shift;
	$client->lines(\&repeatSettingsLines);
	@repeatSettingsChoices = (string('REPEAT_OFF'),string('REPEAT_ONE'),string('REPEAT_ALL'))
}

sub repeatSettingsLines {
	my $client = shift;
	my ($line1, $line2);
	$line1 = string('REPEAT');
	$line2 = $repeatSettingsChoices[Slim::Player::Playlist::repeat($client)];
	return ($line1, $line2);
}


my @shuffleSettingsChoices;

my %shuffleSettingsFunctions = (
	'up' => sub {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#shuffleSettingsChoices + 1), Slim::Player::Playlist::shuffle($client));
		Slim::Control::Command::execute($client, ["playlist", "shuffle", $newposition]);
		Slim::Display::Display::update($client);
	},
	'down' => sub {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#shuffleSettingsChoices + 1), Slim::Player::Playlist::shuffle($client));
		Slim::Control::Command::execute($client, ["playlist", "shuffle", $newposition]);
		Slim::Display::Display::update($client);
	},
	'left' => $functions{'left'},
	'right' => sub { Slim::Display::Animation::bumpRight(shift); },
	'add' => sub { Slim::Display::Animation::bumpRight(shift); },
	'play' => sub { Slim::Display::Animation::bumpRight(shift); },
);

sub getShuffleFunctions {
	return \%shuffleSettingsFunctions;
}

sub setShuffleMode {
	my $client = shift;
	@shuffleSettingsChoices = (string('SHUFFLE_OFF'), string('SHUFFLE_ON_SONGS'), , string('SHUFFLE_ON_ALBUMS'));
	$client->lines(\&shuffleSettingsLines);
}

 sub shuffleSettingsLines {
	my $client = shift;
	my ($line1, $line2);
	$line1 = string('SHUFFLE');
	$line2 = $shuffleSettingsChoices[Slim::Player::Playlist::shuffle($client)];
	return ($line1, $line2);
}

#################################################################################
my @textSizeSettingsChoices;

my %textSizeSettingsFunctions = (
	'up' => sub {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#textSizeSettingsChoices + 1), (Slim::Utils::Prefs::clientGet($client, "doublesize")) ? 1 : 0 );
		Slim::Utils::Prefs::clientSet($client, "doublesize", $newposition);
		Slim::Display::Display::update($client);
	},
	'down' => sub {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#textSizeSettingsChoices + 1), (Slim::Utils::Prefs::clientGet($client, "doublesize")) ? 1 : 0 );
		Slim::Utils::Prefs::clientSet($client, "doublesize", $newposition);
		Slim::Display::Display::update($client);
	},
	'left' => $functions{'left'},
	'right' => sub { Slim::Display::Animation::bumpRight(shift); },
	'add' => sub { Slim::Display::Animation::bumpRight(shift); },
	'play' => sub { Slim::Display::Animation::bumpRight(shift); },
);

sub getTextSizeFunctions {
	return \%textSizeSettingsFunctions;
}

sub setTextSizeMode {
	my $client = shift;
	@textSizeSettingsChoices = (string('SMALL'),string('LARGE'));
	$client->lines(\&textSizeSettingsLines);
}

sub textSizeSettingsLines {
	my $client = shift;
	my ($line1, $line2);
	$line1 = string('TEXTSIZE');
	$line2 = $textSizeSettingsChoices[(Slim::Utils::Prefs::clientGet($client, "doublesize")) ? 1 : 0];
	return ($line1, $line2);
}

#################################################################################
my @titleFormatSettingsChoices;

my %titleFormatSettingsFunctions = (
	'up' => sub {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#titleFormatSettingsChoices + 1), Slim::Utils::Prefs::clientGet($client, "titleFormatCurr"));
		Slim::Utils::Prefs::clientSet($client, "titleFormatCurr", $newposition);
		Slim::Display::Display::update($client);
	},
	'down' => sub {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#titleFormatSettingsChoices + 1), Slim::Utils::Prefs::clientGet($client, "titleFormatCurr"));
		Slim::Utils::Prefs::clientSet($client, "titleFormatCurr", $newposition);
		Slim::Display::Display::update($client);
	},
	'left' => $functions{'left'},
	'right' => sub { Slim::Display::Animation::bumpRight(shift); },
);

sub getTitleFormatFunctions {
	return \%titleFormatSettingsFunctions;
}

sub setTitleFormatMode {
	my $client = shift;
	@titleFormatSettingsChoices = ();
	foreach my $tf (Slim::Utils::Prefs::clientGetArray($client,'titleFormat')) {
		push @titleFormatSettingsChoices , Slim::Utils::Prefs::getInd('titleFormat',$tf);
	}
	$client->lines(\&titleFormatSettingsLines);
}

sub titleFormatSettingsLines {
	my $client = shift;
	my ($line1, $line2);
	$line1 = string('TITLEFORMAT');
	$line2 = $titleFormatSettingsChoices[Slim::Utils::Prefs::clientGet($client, "titleFormatCurr")];
	return ($line1, $line2);
}

#################################################################################
my %trebleSettingsFunctions = (
	'up' => sub {
		my $client = shift;
		Slim::Buttons::Common::mixer($client,'treble','up');
	},
	'down' => sub {
		my $client = shift;
		Slim::Buttons::Common::mixer($client,'treble','down');
	},
	'left' => $functions{'left'},
	'right' => sub { Slim::Display::Animation::bumpRight(shift); },
	'add' => sub { Slim::Display::Animation::bumpRight(shift); },
	'play' => sub { Slim::Display::Animation::bumpRight(shift); },
);

sub getTrebleFunctions {
	return \%trebleSettingsFunctions;
}

sub setTrebleMode {
	my $client = shift;
	$client->lines(\&trebleSettingsLines);
}

 sub trebleSettingsLines {
	my $client = shift;
	my ($line1, $line2);
	my $level = int(Slim::Utils::Prefs::clientGet($client, "treble")/100*40 + 0.5) - 20;
	$line1 = string('TREBLE') . " ($level)";

	$line2 = Slim::Display::Display::balanceBar($client, 40, Slim::Utils::Prefs::clientGet($client, "treble"));	
	if (Slim::Utils::Prefs::clientGet($client,'doublesize')) { $line2 = $line1; }
	
	return ($line1, $line2);
}

#################################################################################
my %bassSettingsFunctions = (
	'up' => sub {
		my $client = shift;
		Slim::Buttons::Common::mixer($client,'bass','up');
	},
	'down' => sub {
		my $client = shift;
		Slim::Buttons::Common::mixer($client,'bass','down');
	},
	'left' => $functions{'left'},
	'right' => sub { Slim::Display::Animation::bumpRight(shift); },
	'add' => sub { Slim::Display::Animation::bumpRight(shift); },
	'play' => sub { Slim::Display::Animation::bumpRight(shift); },
);

sub getBassFunctions {
	return \%bassSettingsFunctions;
}

sub setBassMode {
	my $client = shift;
	$client->lines(\&bassSettingsLines);
}

 sub bassSettingsLines {
	my $client = shift;
	my ($line1, $line2);
	
	my $level = int(Slim::Utils::Prefs::clientGet($client, "bass")/100*40 + 0.5) - 20;
	$line1 = string('BASS') . " ($level)";

	$line2 = Slim::Display::Display::balanceBar($client, 40, Slim::Utils::Prefs::clientGet($client, "bass"));	
	if (Slim::Utils::Prefs::clientGet($client,'doublesize')) { $line2 = $line1; }
	return ($line1, $line2);
}

#################################################################################
my %volumeSettingsFunctions = (
	'left' => $functions{'left'},
	'right' => sub { Slim::Display::Animation::bumpRight(shift); },
	'add' => sub { Slim::Display::Animation::bumpRight(shift); },
	'play' => sub { Slim::Display::Animation::bumpRight(shift); },
);

sub getVolumeFunctions {
	return \%volumeSettingsFunctions;
}

sub setVolumeMode {
	my $client = shift;
	$client->lines(\&volumeLines);
}

 sub volumeLines {
	my $client = shift;

	my $level = int(Slim::Utils::Prefs::clientGet($client, "volume") / $Slim::Player::Control::maxVolume * 40);

	my $line1;
	my $line2;
	
	if ($level < 0) {
		$line1 = string('VOLUME')."  (". string('MUTED') . ")";
		$level = 0;
	} else {
		$line1 = string('VOLUME')." (".$level.")";
	}

	$line2 = Slim::Display::Display::progressBar($client, 40, $level / 40);	
	
	if (Slim::Utils::Prefs::clientGet($client,'doublesize')) { $line2 = $line1; }
	return ($line1, $line2);
}

1;

__END__
