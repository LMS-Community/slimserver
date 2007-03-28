package Slim::Plugin::MusicMagic::PlayerSettings;

# SlimServer Copyright (c) 2001-2004 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

# button functions for browse directory
our @defaultSettingsChoices = qw(MMMSize MMMMixType MMMStyle MMMVariety MMMFilter MMMMixGenre MMMRejectType MMMRejectSize);

our @settingsChoices = ();
our %current = ();
our %menuParams = ();
our %functions = ();

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
			my @oldlines = Slim::Display::Display::curLines($client);
			
			Slim::Buttons::Common::popMode($client);
			Slim::Plugin::MusicMagic::Plugin::mixerFunction($client,1);
		},
	);

	%menuParams = (

		'MMMsettings' => {
			'listRef'         => \@defaultSettingsChoices,
			'stringExternRef' => 1,
			'header'          => 'SETUP_MMMSETTINGS',
			'stringHeader'    => 1,
			'headerAddCount'  => 1,
			'callback'        => \&settingsExitHandler,
			'overlayRef'      => sub { return (undef,shift->symbols('rightarrow')) },
			'overlayRefArgs'  => 'C',
		},
		
		'MMMsettings/MMMSize' => {
			'useMode'        => 'INPUT.Bar',
			'header'         => 'SETUP_MMMSIZE',
			'stringHeader'   => 1,
			'headerValue'    =>'unscaled',
			'min'            => 0,
			'max'            => 200,
			'increment'      => 1,
			'onChange'       => \&setPref,
			'pref'           => "MMMSize",
			'initialValue'   => "MMMSize",
			'overlayRef'     => sub { return ($_[0]->string('MUSICMAGIC_MIXRIGHT'),undef) },
			'overlayRefArgs' => 'C',
		},

		'MMMsettings/MMMMixType' => {
			'useMode'        => 'INPUT.List',
			'header'         => 'SETUP_MMMMIXTYPE',
			'stringHeader'   => 1,
			'listRef'        => [0,1,2],
			'externRef'      => {
				'0' => Slim::Utils::Strings::string('MMMMIXTYPE_TRACKS'),
				'1' => Slim::Utils::Strings::string('MMMMIXTYPE_MIN'),
				'2' => Slim::Utils::Strings::string('MMMMIXTYPE_MBYTES'),
			},
			'onChange'       => \&setPref,
			'pref'           => "MMMMixType",
			'initialValue'   => "MMMStyle",
			'overlayRef'     => sub { return ($_[0]->string('MUSICMAGIC_MIXRIGHT'),undef) },
			'overlayRefArgs' => 'C',
		},

		'MMMsettings/MMMStyle' => {
			'useMode'        => 'INPUT.Bar',
			'header'         => 'SETUP_MMMSTYLE',
			'stringHeader'   => 1,
			'headerValue'    => 'unscaled',
			'min'            => 0,
			'max'            => 200,
			'onChange'       => \&setPref,
			'pref'           => "MMMStyle",
			'initialValue'   => "MMMStyle",
			'overlayRef'     => sub { return ($_[0]->string('MUSICMAGIC_MIXRIGHT'),undef) },
			'overlayRefArgs' => 'C',
		},

		'MMMsettings/MMMVariety' => {
			'useMode'        => 'INPUT.Bar',
			'header'         => 'SETUP_MMMVARIETY',
			'stringHeader'   => 1,
			'headerValue'    =>'unscaled',
			'min'            => 0,
			'max'            => 9,
			'increment'      => 1,
			'onChange'       => \&setPref,
			'pref'           => "MMMVariety",
			'initialValue'   => "MMMVariety",
			'overlayRef'     => sub { return ($_[0]->string('MUSICMAGIC_MIXRIGHT'),undef) },
			'overlayRefArgs' => 'C',
		},

		'MMMsettings/MMMFilter' => {
			'useMode'        => 'INPUT.List',
			'header'         => 'SETUP_MMMFILTER',
			'stringHeader'   => 1,
			'listRef'        => undef,
			'externRef'      => undef,
			'onChange'       => \&setPref,
			'pref'           => "MMMFilter",
			'initialValue'   => "MMMFilter",
			'overlayRef'     => sub { return ($_[0]->string('MUSICMAGIC_MIXRIGHT'),undef) },
			'overlayRefArgs' => 'C',
		},

		'MMMsettings/MMMMixGenre' => {
			'useMode'        => 'INPUT.List',
			'header'         => 'SETUP_MMMMIXGENRE',
			'stringHeader'   => 1,
			'listRef'        => [0,1],
			'externRef'      => {
				'0' => Slim::Utils::Strings::string('NO'),
				'1' => Slim::Utils::Strings::string('YES'),
			},
			'onChange'       => \&setPref,
			'pref'           => "MMMMixGenre",
			'initialValue'   => "MMMMixGenre",
			'overlayRef'     => sub { return ($_[0]->string('MUSICMAGIC_MIXRIGHT'),undef) },
			'overlayRefArgs' => 'C',
		},
		
		'MMMsettings/MMMRejectType' => {
			'useMode'        => 'INPUT.List',
			'header'         => 'SETUP_MMMREJECTTYPE',
			'stringHeader'   => 1,
			'listRef'        => [0,1,2],
			'externRef'      => {
				'0' => Slim::Utils::Strings::string('MMMMIXTYPE_TRACKS'),
				'1' => Slim::Utils::Strings::string('MMMMIXTYPE_MIN'),
				'2' => Slim::Utils::Strings::string('MMMMIXTYPE_MBYTES'),
			},
			'onChange'       => \&setPref,
			'pref'           => "MMMRejectType",
			'initialValue'   => "MMMRejectType",
			'overlayRef'     => sub { return ($_[0]->string('MUSICMAGIC_MIXRIGHT'),undef) },
			'overlayRefArgs' => 'C',
		},
		
		'MMMsettings/MMMRejectSize' => {
			'useMode'        => 'INPUT.Bar',
			'header'         => 'SETUP_MMMREJECTSIZE',
			'stringHeader'   => 1,
			'headerValue'    =>'unscaled',
			'min'            => 0,
			'max'            => 200,
			'increment'      => 1,
			'onChange'       => \&setPref,
			'pref'           => "MMMRejectSize",
			'initialValue'   => "MMMRejectSize",
			'overlayRef'     => sub { return ($_[0]->string('MUSICMAGIC_MIXRIGHT'),undef) },
			'overlayRefArgs' => 'C',
		},
	);
}

sub setPref {
	my $client = shift;
	my $value = shift;
	
	my $pref = $client->modeParam('pref');
	
	$client->prefSet($pref,$value);
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
					$value = $client->prefGet($nextParams{'initialValue'});
				}
				$nextParams{'valueRef'} = \$value;
			}
			if ($nextmenu eq 'MMMsettings/MMMFilter') {
				my %filters = Slim::Plugin::MusicMagic::Plugin::grabFilters();
				
				$nextParams{'listRef'} = [keys %filters];
				$nextParams{'externRef'} = {Slim::Plugin::MusicMagic::Plugin::grabFilters()};
				$nextParams{'listIndex'} = $client->prefGet('MMMFilter');
				
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
