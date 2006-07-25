package Slim::Buttons::Settings;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Buttons::AlarmClock;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Buttons::Information;

# button functions for browse directory
our @defaultSettingsChoices = qw(ALARM VOLUME REPEAT SHUFFLE TITLEFORMAT TEXTSIZE INFORMATION SCREENSAVERS);

our @settingsChoices = ();
our %current = ();
our %menuParams = ();
our %functions = ();

sub arrowFunc {
	return (undef,Slim::Display::Display::symbol('rightarrow'));
};

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
			'overlayRef' => \&arrowFunc,
			'overlayRefArgs' => '',
		},

		'settings/ALARM' => {
			'useMode' => 'alarm'
		},

		'settings/VOLUME' => {
			'useMode' => 'INPUT.Bar',
			'header' => 'VOLUME',
			'stringHeader' => 1,
			'headerValue' => \&volumeValue,
			'onChange' =>  \&executeCommand,
			'command' => 'mixer',
			'subcommand' => 'volume',
			'initialValue' => sub { return $_[0]->volume() },
		},

		'settings/BASS' => {
			'useMode' => 'INPUT.Bar',
			'header' => 'BASS',
			'stringHeader' => 1,
			'headerValue' => 'scaled',
			'mid' => 50,
			'onChange' =>  \&executeCommand,
			'command' => 'mixer',
			'subcommand' => 'bass',
			'initialValue' => sub { return $_[0]->bass() },
		},

		'settings/PITCH' => {
			'useMode' => 'INPUT.Bar',
			'header' => 'PITCH',
			'stringHeader' => 1,
			'headerValue' =>'unscaled',
			'headerValueUnit' => '%',
			'min' => 80,
			'max' => 120,
			'mid' => 100,
			'midIsZero' => 0,
			'increment' => 1,
			'onChange' =>  \&executeCommand,
			'command' => 'mixer',
			'subcommand' => 'pitch',
			'initialValue' => sub { return $_[0]->pitch() },
		},

		'settings/TREBLE' => {
			'useMode' => 'INPUT.Bar',
			'header' => 'TREBLE',
			'stringHeader' => 1,
			'headerValue' => 'scaled',
			'mid' => 50,
			'onChange' =>  \&executeCommand,
			'command' => 'mixer',
			'subcommand' => 'treble',
			'initialValue' => sub { return $_[0]->treble() },
		},

		'settings/REPLAYGAIN' => {
			'useMode' => 'INPUT.List',
			'listRef' => [0,1,2,3],
			'externRef' => [qw(REPLAYGAIN_DISABLED REPLAYGAIN_TRACK_GAIN REPLAYGAIN_ALBUM_GAIN REPLAYGAIN_SMART_GAIN)],
			'stringExternRef' => 1,
			'header' => 'REPLAYGAIN',
			'headerAddCount' => 1,
			'stringHeader' => 1,
			'onChange' =>  \&setPref,
			'pref' => "replayGainMode",
			'initialValue' => sub { return $_[0]->prefGet('replayGainMode') },
		},

		'settings/REPEAT' => {
			'useMode' => 'INPUT.List',
			'listRef' => [0,1,2],
			'externRef' => [qw(REPEAT_OFF REPEAT_ONE REPEAT_ALL)],
			'stringExternRef' => 1,
			'header' => 'REPEAT',
			'stringHeader' => 1,
			'onChange' =>  \&executeCommand,
			'command' => 'playlist',
			'subcommand' => 'repeat',
			'initialValue' => \&Slim::Player::Playlist::repeat,
		},

		'settings/SHUFFLE' => {
			'useMode' => 'INPUT.List',
			'listRef' => [0,1,2],
			'externRef' => [qw(SHUFFLE_OFF SHUFFLE_ON_SONGS SHUFFLE_ON_ALBUMS)],
			'stringExternRef' => 1,
			'header' => 'SHUFFLE',
			'stringHeader' => 1,
			'onChange' => \&executeCommand,
			'command' => 'playlist',
			'subcommand' => 'shuffle',
			'initialValue' => \&Slim::Player::Playlist::shuffle,
		},

		'settings/TITLEFORMAT' => {
			'useMode' => 'INPUT.List',
			'listRef' => undef, # filled before changing modes
			'listIndex' => undef, #filled before changing modes
			'externRef' => undef, #filled before changing modes
			'header' => 'TITLEFORMAT',
			'stringHeader' => 1,
			'onChange' => \&setPref,
			'pref' => "titleFormatCurr",
			'onChangeArgs' => 'CI',
		},

		'settings/TEXTSIZE' => {
			'useMode' => 'INPUT.List',
			'listRef' => undef, #filled before changing modes
			'externRef' => \&_fontExists,
			'header' => 'TEXTSIZE',
			'stringHeader' => 1,
			'onChange' => sub { $_[0]->textSize($_[1], 1) },
			'onChangeArgs' => 'CV',
			'initialValue' => sub { $_[0]->textSize() },
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

		'settings/SETUP_TRANSITIONTYPE' => {
			'useMode' => 'INPUT.List',
			'listRef' => [0,1,2,3,4],
			'externRef' => ['TRANSITION_NONE', 'TRANSITION_CROSSFADE', 'TRANSITION_FADE_IN', 'TRANSITION_FADE_OUT', 'TRANSITION_FADE_IN_OUT'],
			'stringExternRef' => 1,
			'onChange' => \&setPref,
			'headerAddCount' => 1,
			'pref' => "transitionType",
			'header' => 'SETUP_TRANSITIONTYPE',
			'stringHeader' => 1,
			'initialValue' => 'transitionType',
		},
		
		
		# Screensavers submenus
		
		'settings/SCREENSAVERS' => {
			'useMode' => 'INPUT.List',
			'listRef' => ['SETUP_SCREENSAVER', 'SETUP_OFFSAVER', 'SETUP_IDLESAVER'],
			'callback' => \&screensaversExitHandler,
			'stringExternRef' => 1,
			'header' => 'SCREENSAVERS',
			'stringHeader' => 1,
			'headerAddCount' => 1,
			'overlayRef' => \&arrowFunc,
			'overlayRefArgs' => '',
		},

		'settings/SCREENSAVERS/SETUP_SCREENSAVER' => {
			'useMode' => 'INPUT.List',
			'listRef' => undef,
			'externRef' => undef,
			'stringExternRef' => 1,
			'headerAddCount' => 1,
			'onChange' => \&setPref,
			'pref' => "screensaver",
			'header' => 'SETUP_SCREENSAVER',
			'stringHeader' => 1,
			'initialValue' => 'screensaver',
		},
		
		'settings/SCREENSAVERS/SETUP_OFFSAVER' => {
			'useMode' => 'INPUT.List',
			'listRef' => undef,
			'externRef' => undef,
			'stringExternRef' => 1,
			'onChange' => \&setPref,
			'headerAddCount' => 1,
			'pref' => "offsaver",
			'header' => 'SETUP_OFFSAVER',
			'stringHeader' => 1,
			'initialValue' => 'offsaver',
		},

		'settings/SCREENSAVERS/SETUP_IDLESAVER' => {
			'useMode' => 'INPUT.List',
			'listRef' => undef,
			'externRef' => undef,
			'stringExternRef' => 1,
			'onChange' => \&setPref,
			'headerAddCount' => 1,
			'pref' => "idlesaver",
			'header' => 'SETUP_IDLESAVER',
			'stringHeader' => 1,
			'initialValue' => 'idlesaver',
		},

	);
}

sub setPref {
	my $client = shift;
	my $value = shift;
	
	my $pref = $client->param('pref');
	
	$client->prefSet($pref,$value);
}

sub executeCommand {
	my $client = shift;
	my $value = shift;
	
	my $command = $client->param('command');
	my $subcmd  = $client->param('subcommand');
	
	$client->execute([$command, $subcmd, $value]);
}
	
sub _fontExists {
	my $client = shift;
	
	my $fontname;

	if ($client->display->isa( "Slim::Display::Graphics" )) {
		$fontname = $client->display->fonts()->{line}[1];
		$fontname =~ s/(\.2)?//go;
	} else {
		$fontname = $client->textSize() ? 'large' : 'small';
	}

	return Slim::Utils::Strings::stringExists($fontname) ? $client->string($fontname) : $fontname;
}

sub settingsExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
		
	} elsif ($exittype eq 'RIGHT') {
		my $nextmenu = 'settings/' . $client->param('listRef')->[$client->param('listIndex')];
		if (exists($menuParams{$nextmenu})) {
			my %nextParams = %{$menuParams{$nextmenu}};
			
			if (($nextParams{'useMode'} eq 'INPUT.List' || $nextParams{'useMode'} eq 'INPUT.Bar')  && exists($nextParams{'initialValue'})) {
				#set up valueRef for current pref
				my $value;
				if (ref($nextParams{'initialValue'}) eq 'CODE') {
					$value = $nextParams{'initialValue'}->($client);
					
				} else {
					$value = $client->prefGet($nextParams{'initialValue'});
				}
				$nextParams{'valueRef'} = \$value;
				
			} 
			
			if ($nextmenu eq 'settings/TITLEFORMAT') {
				my @titleFormat = $client->prefGetArray('titleFormat');
				$nextParams{'listRef'} = \@titleFormat;
				my @externTF = map {Slim::Utils::Prefs::getInd('titleFormat',$_)} @titleFormat;
				$nextParams{'externRef'} = \@externTF;
				$nextParams{'listIndex'} = $client->prefGet('titleFormatCurr');	
				
			} elsif ($nextmenu eq 'settings/TEXTSIZE') {
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

sub screensaversExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
		
	} elsif ($exittype eq 'RIGHT') {
		my $nextmenu = 'settings/' . $current{$client} . '/' . $client->param('listRef')->[$client->param('listIndex')];
		if (exists($menuParams{$nextmenu})) {
			my %nextParams = %{$menuParams{$nextmenu}};
			
			my $value = $client->prefGet($nextParams{'initialValue'});
			$nextParams{'valueRef'} = \$value;
			
			my %hash = %{&Slim::Buttons::Common::hash_of_savers};
			my @modes = keys %hash;
			my @names = values %hash;
			$nextParams{'listRef'} = \@modes;
			$nextParams{'externRef'} = \@names;

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
	
	if ($client->maxBass() - $client->minBass()) {
		push @settingsChoices, 'BASS';
	}
	
	if ($client->maxTreble() - $client->minTreble()) {
		push @settingsChoices, 'TREBLE';
	}
	
	if ($client->maxPitch() - $client->minPitch()) {
		push @settingsChoices, 'PITCH';
	}
	
	if (Slim::Player::Sync::isSynced($client) || (scalar(Slim::Player::Sync::canSyncWith($client)) > 0)) {
		push @settingsChoices, 'SYNCHRONIZE';
	}
	
	if ($client->isa( "Slim::Player::Squeezebox2" )) {
		push @settingsChoices, 'SETUP_TRANSITIONTYPE';
	}

	if ($client->canDoReplayGain(0)) {
		push @settingsChoices, 'REPLAYGAIN';
	}
	
	@settingsChoices = sort { $client->string($a) cmp $client->string($b) } @settingsChoices;
	
	
	$params{'listRef'} = \@settingsChoices;
	
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
}

sub volumeValue {
	my ($client,$arg) = @_;
	return ' ('.($arg <= 0 ? $client->string('MUTED') : int($arg/100*40+0.5)).')';
}

# this is deprecated, warn and backtrace if anyone calls
sub volumeLines {
	msg("Somebody called volumeLines\n");
	bt();
}

# this is deprecated, warn and backtrace if anyone calls
sub pitchLines {
	msg("Somebody called pitchLines\n");
	bt();
}

# this is deprecated, warn and backtrace if anyone calls
sub bassLines {
	msg("Somebody called bassLines\n");
	bt();
}

# this is deprecated, warn and backtrace if anyone calls
sub trebleLines {
	msg("Somebody called trebleLines\n");
	bt();
}

1;

__END__
