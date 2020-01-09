package Slim::Plugin::MusicMagic::PlayerSettings;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Plugin::MusicMagic::Common;
use Slim::Utils::Prefs;

# button functions for browse directory
our @defaultSettingsChoices = qw(mix_size mix_type mix_style mix_variety mix_filter mix_genre reject_type reject_size);

our @settingsChoices = ();
our %current = ();
our %menuParams = ();
our %functions = ();

my $prefs = preferences('plugin.musicip');

sub init {
	Slim::Buttons::Common::addMode('MMMsettings',getFunctions(),\&setMode);

	%functions = (
		'right' => sub  {
			my ($client,$funct,$functarg) = @_;
			if (defined($client->modeParam('useMode'))) {
				#in a submenu of settings, which is passing back a button press
				Slim::Buttons::Common::popMode($client);
				Slim::Plugin::MusicMagic::Plugin::mixerFunction($client,1);
			} else {
				#handle passback of button presses
				settingsExitHandler($client,'RIGHT');
			}
		},
		'play' => sub {
			my $client = shift;
			my @oldlines = $client->curLines();
			
			Slim::Buttons::Common::popMode($client);
			Slim::Plugin::MusicMagic::Plugin::mixerFunction($client,1);
		},
	);

	%menuParams = (

		'MMMsettings' => {
			'listRef'         => \@defaultSettingsChoices,
			'externRef'      => sub { return 'SETUP_'.$_[1]; },
			'stringExternRef' => 1,
			'header'          => 'SETUP_MMMSETTINGS',
			'stringHeader'    => 1,
			'headerAddCount'  => 1,
			'callback'        => \&settingsExitHandler,
			'overlayRef'      => sub { return (undef,shift->symbols('rightarrow')) },
			'overlayRefArgs'  => 'C',
		},
		
		'MMMsettings/mix_size' => {
			'useMode'        => 'INPUT.Bar',
			'header'         => 'SETUP_MIX_SIZE',
			'stringHeader'   => 1,
			'headerValue'    =>'unscaled',
			'min'            => 0,
			'max'            => 200,
			'increment'      => 1,
			'onChange'       => \&setPref,
			'pref'           => "mix_size",
			'initialValue'   => "mix_size",
			'overlayRef'     => \&settingsOverlay,
			'overlayRefArgs' => 'C',
		},

		'MMMsettings/mix_type' => {
			'useMode'        => 'INPUT.List',
			'header'         => 'SETUP_MIX_TYPE',
			'stringHeader'   => 1,
			'listRef'        => [0,1,2],
			'externRef'      => {
				'0' => Slim::Utils::Strings::string('MMMMIXTYPE_TRACKS'),
				'1' => Slim::Utils::Strings::string('MMMMIXTYPE_MIN'),
				'2' => Slim::Utils::Strings::string('MMMMIXTYPE_MBYTES'),
			},
			'onChange'       => \&setPref,
			'pref'           => "mix_type",
			'initialValue'   => "mix_type",
			'overlayRef'     => \&settingsOverlay,
			'overlayRefArgs' => 'C',
		},

		'MMMsettings/mix_style' => {
			'useMode'        => 'INPUT.Bar',
			'header'         => 'SETUP_MIX_STYLE',
			'stringHeader'   => 1,
			'headerValue'    => 'unscaled',
			'min'            => 0,
			'max'            => 200,
			'increment'      => 1,
			'onChange'       => \&setPref,
			'pref'           => "mix_style",
			'initialValue'   => "mix_style",
			'overlayRef'     => \&settingsOverlay,
			'overlayRefArgs' => 'C',
		},

		'MMMsettings/mix_variety' => {
			'useMode'        => 'INPUT.Bar',
			'header'         => 'SETUP_MIX_VARIETY',
			'stringHeader'   => 1,
			'headerValue'    =>'unscaled',
			'min'            => 0,
			'max'            => 9,
			'increment'      => 1,
			'onChange'       => \&setPref,
			'pref'           => "mix_variety",
			'initialValue'   => "mix_variety",
			'overlayRef'     => \&settingsOverlay,
			'overlayRefArgs' => 'C',
		},

		'MMMsettings/mix_filter' => {
			'useMode'        => 'INPUT.List',
			'header'         => 'SETUP_MIX_FILTER',
			'stringHeader'   => 1,
			'listRef'        => undef,
			'externRef'      => undef,
			'onChange'       => \&setPref,
			'pref'           => "mix_filter",
			'initialValue'   => "mix_filter",
			'overlayRef'     => \&settingsOverlay,
			'overlayRefArgs' => 'C',
		},

		'MMMsettings/mix_genre' => {
			'useMode'        => 'INPUT.List',
			'header'         => 'SETUP_MIX_GENRE',
			'stringHeader'   => 1,
			'listRef'        => [0,1],
			'externRef'      => {
				'0' => Slim::Utils::Strings::string('NO'),
				'1' => Slim::Utils::Strings::string('YES'),
			},
			'onChange'       => \&setPref,
			'pref'           => "mix_genre",
			'initialValue'   => "mix_genre",
			'overlayRef'     => \&settingsOverlay,
			'overlayRefArgs' => 'C',
		},
		
		'MMMsettings/reject_type' => {
			'useMode'        => 'INPUT.List',
			'header'         => 'SETUP_REJECT_TYPE',
			'stringHeader'   => 1,
			'listRef'        => [0,1,2],
			'externRef'      => {
				'0' => Slim::Utils::Strings::string('MMMMIXTYPE_TRACKS'),
				'1' => Slim::Utils::Strings::string('MMMMIXTYPE_MIN'),
				'2' => Slim::Utils::Strings::string('MMMMIXTYPE_MBYTES'),
			},
			'onChange'       => \&setPref,
			'pref'           => "reject_type",
			'initialValue'   => "reject_type",
			'overlayRef'     => \&settingsOverlay,
			'overlayRefArgs' => 'C',
		},
		
		'MMMsettings/reject_size' => {
			'useMode'        => 'INPUT.Bar',
			'header'         => 'SETUP_REJECT_SIZE',
			'stringHeader'   => 1,
			'headerValue'    =>'unscaled',
			'min'            => 0,
			'max'            => 200,
			'increment'      => 1,
			'onChange'       => \&setPref,
			'pref'           => "reject_size",
			'initialValue'   => "reject_size",
			'overlayRef'     => \&settingsOverlay,
			'overlayRefArgs' => 'C',
		},
	);
}

sub settingsOverlay {
	my $client = shift;

	my $overlay1;

	if ($client->linesPerScreen == 2) {
		# Use icons for MIXRIGHT as text is too long in some languages
		$overlay1 = $client->symbols('mixable') . $client->symbols('rightarrow');
	}

	return ( $overlay1, undef );
}

sub setPref {
	my $client = shift;
	my $value = shift;
	
	my $pref = $client->modeParam('pref');
	
	my $newvalue = $prefs->client($client)->get($pref) + $value;
	
	$prefs->client($client)->set($pref, $newvalue);
}

sub executeCommand {
	my $client = shift;
	my $value = shift;
	
	my $command = $client->modeParam('command');
	my $subcmd  = $client->modeParam('subcommand');
	
	$client->execute([$command, $subcmd, $value]);
}
	
sub settingsExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {
		my $nextmenu = 'MMMsettings/'.$current{$client};

		if (defined($client->modeParam('useMode'))) {
			#in a submenu of settings and exiting right.
			Slim::Plugin::MusicMagic::Plugin::mixerFunction($client,1);

		} elsif (exists($menuParams{$nextmenu})) {
			my %nextParams = %{$menuParams{$nextmenu}};

			$nextParams{'callback'} = \&settingsExitHandler;
			$nextParams{'parentParams'} = $client->modeParam('parentParams');

			if (($nextParams{'useMode'} eq 'INPUT.List' || $nextParams{'useMode'} eq 'INPUT.Bar')  && exists($nextParams{'initialValue'})) {
				#set up valueRef for current pref
				my $value;

				if (ref($nextParams{'initialValue'}) eq 'CODE') {
					$value = $nextParams{'initialValue'}->($client);
				} else {
				
					# grab client pref, or fall back to server pref if not defined
					$value = $prefs->client($client)->get($nextParams{'initialValue'}) || $prefs->get($nextParams{'initialValue'});
				}

				$nextParams{'valueRef'} = \$value;
			}

			if ($nextmenu eq 'MMMsettings/mix_filter') {
				my $filters = Slim::Plugin::MusicMagic::Common->getFilterList();
				
				$nextParams{'listRef'} = [keys %{$filters}];
				$nextParams{'externRef'} = $filters;
				$nextParams{'listIndex'} = $prefs->client($client)->get('mix_filter');
				
			}
			
			Slim::Buttons::Common::pushModeLeft(
				$client
				,$nextParams{'useMode'}
				,\%nextParams
			);

		} else {
			Slim::Plugin::MusicMagic::Plugin::mixerFunction($client,1);
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

	$current{$client}       = $defaultSettingsChoices[0] unless exists($current{$client});
	my %params              = %{$menuParams{'MMMsettings'}};
	$params{'valueRef'}     = \$current{$client};
	$params{'parentParams'} = $client->modeParam('parentParams');
	
	my @settingsChoices     = @defaultSettingsChoices;
	
	$params{'listRef'}      = \@settingsChoices;
	
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
}

1;

__END__
