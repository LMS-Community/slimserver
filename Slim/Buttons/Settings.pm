package Slim::Buttons::Settings;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
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
use Slim::Utils::Prefs;
use Slim::Buttons::Information;

# button functions for browse directory
our @defaultSettingsChoices = qw(ALARM VOLUME BASS TREBLE REPEAT SHUFFLE TITLEFORMAT TEXTSIZE OFFDISPLAYSIZE INFORMATION SETUP_SCREENSAVER);

our @settingsChoices = ();
our %current = ();
our %menuParams = ();
our %functions = ();

sub init {
	Slim::Buttons::Common::addMode('settings',Slim::Buttons::Settings::getFunctions(),\&Slim::Buttons::Settings::setMode);

	%functions = (
		'right' => sub  {
			my ($client,$funct,$functarg) = @_;
			if (defined($client->param('useMode'))) {
				#in a submenu of settings, which is passing back a button press
				$client->bumpRight();
			} else {
				#handle passback of button presses
				settingsExitHandler($client,'RIGHT');
			}
		}
	);

	%menuParams = (

		'settings' => {
			'listRef' => \@defaultSettingsChoices,
			'stringExternRef' => 1,
			'header' => 'SETTINGS',
			'stringHeader' => 1,
			'headerAddCount' => 1,
			'callback' => \&settingsExitHandler,
			'overlayRef' => sub { return (undef,Slim::Display::Display::symbol('rightarrow')) },
			'overlayRefArgs' => '',
		},

		'settings/ALARM' => {
			'useMode' => 'alarm'
		},

		'settings/VOLUME' => {
			'useMode' => 'INPUT.Bar',
			'header' => \&volumeHeader,

			'onChange' => sub { 
				my ($subref,$subarg) = Slim::Buttons::Common::getFunction($_[0],'volume_'.$_[1],'Common');
				&$subref($_[0],'volume',$subarg);
			},

			'onChangeArgs' => 'CV',
			'initialValue' => sub { return $_[0]->volume() },
		},

		'settings/BASS' => {
			'useMode' => 'INPUT.Bar',
			'header' => \&bassHeader,
			'mid' => 50,
			'onChange' => sub { Slim::Buttons::Common::mixer($_[0],'bass',$_[1]) },
			'onChangeArgs' => 'CV',
			'initialValue' => sub { return $_[0]->bass() },
		},

		'settings/PITCH' => {
			'useMode' => 'INPUT.Bar',
			'header' => \&pitchHeader,
			'min' => 80,
			'max' => 120,
			'mid' => 100,
			'increment' => 1,
			'onChange' => sub { Slim::Buttons::Common::mixer($_[0],'pitch',$_[1]) },
			'onChangeArgs' => 'CV',
			'initialValue' => sub { return $_[0]->pitch() },
		},

		'settings/TREBLE' => {
			'useMode' => 'INPUT.Bar',
			'header' => \&trebleHeader,
			'mid' => 50,
			'onChange' => sub { Slim::Buttons::Common::mixer($_[0],'treble',$_[1]) },
			'onChangeArgs' => 'CV',
			'initialValue' => sub { return $_[0]->treble() },
		},

		'settings/REPEAT' => {
			'useMode' => 'INPUT.List',
			'listRef' => [0,1,2],
			'externRef' => [qw(REPEAT_OFF REPEAT_ONE REPEAT_ALL)],
			'stringExternRef' => 1,
			'header' => 'REPEAT',
			'stringHeader' => 1,
			'onChange' => sub { Slim::Control::Command::execute($_[0], ["playlist", "repeat", $_[1]]) },
			'onChangeArgs' => 'CV',
			'initialValue' => \&Slim::Player::Playlist::repeat,
		},

		'settings/SHUFFLE' => {
			'useMode' => 'INPUT.List',
			'listRef' => [0,1,2],
			'externRef' => [qw(SHUFFLE_OFF SHUFFLE_ON_SONGS SHUFFLE_ON_ALBUMS)],
			'stringExternRef' => 1,
			'header' => 'SHUFFLE',
			'stringHeader' => 1,
			'onChange' => sub { Slim::Control::Command::execute($_[0], ["playlist", "shuffle", $_[1]]) },
			'onChangeArgs' => 'CV',
			'initialValue' => \&Slim::Player::Playlist::shuffle,
		},

		'settings/TITLEFORMAT' => {
			'useMode' => 'INPUT.List',
			'listRef' => undef, # filled before changing modes
			'listIndex' => undef, #filled before changing modes
			'externRef' => undef, #filled before changing modes
			'header' => 'TITLEFORMAT',
			'stringHeader' => 1,
			'onChange' => sub { Slim::Utils::Prefs::clientSet($_[0],"titleFormatCurr",$_[0]->param('listIndex')) },
			'onChangeArgs' => 'C',
		},

		'settings/TEXTSIZE' => {
			'useMode' => 'INPUT.List',
			'listRef' => undef, #filled before changing modes
			'externRef' => \&_fontExists,
			'header' => 'TEXTSIZE',
			'stringHeader' => 1,
			'onChange' => sub { $_[0]->textSize($_[1]) },
			'onChangeArgs' => 'CV',
			'initialValue' => sub { $_[0]->textSize() },
		},

		'settings/OFFDISPLAYSIZE' => {
			'useMode' => 'INPUT.List',
			'listRef' => undef, #filled before changing modes
			'externRef' => \&_fontExists,
			'header' => 'OFFDISPLAYSIZE',
			'stringHeader' => 1,
			'onChange' => sub { Slim::Utils::Prefs::clientSet($_[0], "offDisplaySize", $_[1]) },
			'onChangeArgs' => 'CV',
			'initialValue' => 'offDisplaySize',
		},

		'settings/INFORMATION' => {
			'useMode' => 'information'
		},

		'settings/SYNCHRONIZE' => {
			'useMode' => 'synchronize'
		},

		#,'settings/PLAYER_NAME' => {
		#	'useMode' => 'INPUT.Text'
			#add more params here after the rest is working
		#}

		'settings/SETUP_SCREENSAVER' => {
			'useMode' => 'INPUT.List',
			'listRef' => undef,
			'externRef' => undef,
			'stringExternRef' => 1,
			'onChange' => sub { Slim::Utils::Prefs::clientSet($_[0], "screensaver", $_[1]) },
			'header' => 'SETUP_SCREENSAVER',
			'stringHeader' => 1,
			'initialValue' => 'screensaver',
		}
	);
}

sub _fontExists {
	my $fontname = (@{$_[0]->fonts})[1];
	   $fontname =~ s/(\.2)?//go;

	return Slim::Utils::Strings::stringExists($fontname) ? $_[0]->string($fontname) : $fontname;
}

sub settingsExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} elsif ($exittype eq 'RIGHT') {
		my $nextmenu = 'settings/'.$current{$client};
		if (exists($menuParams{$nextmenu})) {
			my %nextParams = %{$menuParams{$nextmenu}};
			if (($nextParams{'useMode'} eq 'INPUT.List' || $nextParams{'useMode'} eq 'INPUT.Bar')  && exists($nextParams{'initialValue'})) {
				#set up valueRef for current pref
				my $value;
				if (ref($nextParams{'initialValue'}) eq 'CODE') {
					$value = $nextParams{'initialValue'}->($client);
				} else {
					$value = Slim::Utils::Prefs::clientGet($client,$nextParams{'initialValue'});
				}
				$nextParams{'valueRef'} = \$value;
			}
			if ($nextmenu eq 'settings/TITLEFORMAT') {
				my @titleFormat = Slim::Utils::Prefs::clientGetArray($client,'titleFormat');
				$nextParams{'listRef'} = \@titleFormat;
				my @externTF = map {Slim::Utils::Prefs::getInd('titleFormat',$_)} @titleFormat;
				$nextParams{'externRef'} = \@externTF;
				$nextParams{'listIndex'} = Slim::Utils::Prefs::clientGet($client,'titleFormatCurr');	
			}
			if ($nextmenu eq 'settings/SETUP_SCREENSAVER') {
				my %hash = %{&Slim::Buttons::Common::hash_of_savers};
				my @modes = keys %hash;
				my @names = values %hash;
				$nextParams{'listRef'} = \@modes;
				$nextParams{'externRef'} = \@names;
			}
			if ($nextmenu eq 'settings/TEXTSIZE' || $nextmenu eq 'settings/OFFDISPLAYSIZE') {
				my @text = (0..$client->maxTextSize);
				$nextParams{'listRef'} = \@text;
			}
			Slim::Buttons::Common::pushModeLeft(
				$client
				,$nextParams{'useMode'}
				,\%nextParams
			);
		} else {
			$client->bumpRight();
		}
	} else {
		return;
	}
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $method = shift;
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	$current{$client} = $defaultSettingsChoices[0] unless exists($current{$client});
	my %params = %{$menuParams{'settings'}};
	$params{'valueRef'} = \$current{$client};
	
	my @settingsChoices = @defaultSettingsChoices;
	
	if ($client->maxPitch() - $client->minPitch()) {
		push @settingsChoices, 'PITCH';
	}
	
	if (Slim::Player::Sync::isSynced($client) || (scalar(Slim::Player::Sync::canSyncWith($client)) > 0)) {
		push @settingsChoices, 'SYNCHRONIZE';
	}
	
	$params{'listRef'} = \@settingsChoices;
	
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
	$client->update();
}

sub volumeHeader {
	my ($client,$arg) = @_;
	return $client->string('VOLUME').' ('.($arg <= 0 ? $client->string('MUTED') : int($arg/100*40+0.5)).')';
}

sub bassHeader {
	my ($client,$arg) = @_;
	return $client->string('BASS').' ('.(int($arg/100*40 + 0.5) - 20).')';
}

sub trebleHeader {
	my ($client,$arg) = @_;
	return $client->string('TREBLE').' ('.(int($arg/100*40 + 0.5) - 20).')';
}

sub pitchHeader {
	my ($client,$arg) = @_;
	return $client->string('PITCH').' ('.(int($arg)).'%)';
}

sub volumeLines {
	my $client = shift;

	my $volume = $client->volume();
	my $volumestring = volumeHeader($client,$volume);
	return Slim::Buttons::Input::Bar::lines($client,$volume,$volumestring ,$client->minVolume(), $client->minVolume(), $client->maxVolume());
}

sub pitchLines {
	my $client = shift;
	my $pitch = $client->pitch();
	my $pitchstring = pitchHeader($client,$pitch);
	return Slim::Buttons::Input::Bar::lines($client,$pitch,$pitchstring, $client->minPitch(), ($client->maxPitch() + $client->minPitch() ) / 2, $client->maxPitch());
}

sub bassLines {
	my $client = shift;

	my $bass = $client->bass();
	my $bassstring = bassHeader($client,$bass);
	return Slim::Buttons::Input::Bar::lines($client,$bass,$bassstring, $client->minBass(), ($client->maxBass() + $client->minBass() ) / 2, $client->maxBass());
}

sub trebleLines {
	my $client = shift;

	my $treble = $client->treble();
	my $treblestring = trebleHeader($client,$treble);
	return Slim::Buttons::Input::Bar::lines($client,$treble,$treblestring, $client->minTreble(), ($client->maxTreble() + $client->minTreble() ) / 2, $client->maxTreble());
}

1;

__END__
