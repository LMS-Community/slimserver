package Slim::Buttons::Settings;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::Settings

=head1 DESCRIPTION

L<Slim::Buttons::Settings> is a wrapper module to handle the UI for the player settings.
Each settings parameters are collected by this module for sending to various INPUT.* modes
to select, set, and read player preferences.

=cut

use strict;
use Slim::Buttons::Common;
use Slim::Buttons::Alarm;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Buttons::Information;
use Slim::Networking::Discovery::Server;

my $prefs = preferences('server');

our @defaultSettingsChoices = qw(SHUFFLE REPEAT ALARM SYNCHRONIZE AUDIO_SETTINGS DISPLAY_SETTINGS);

our %menuParams = ();
our %functions = ();

sub init {
	#Slim::Buttons::Common::addMode('settings',Slim::Buttons::Settings::getFunctions(),\&Slim::Buttons::Settings::setMode);

	%functions = (
		'right' => sub  {
			my ($client,$funct,$functarg) = @_;
			if (defined($client->modeParam('useMode'))) {
				#in a submenu of settings, which is passing back a button press
				$client->bumpRight();
			} else {
				#handle passback of button presses
				settingsExitHandler($client,'RIGHT');
			}
		}
	);

	# Massive hash for all the Settings
	%menuParams = (

		'SETTINGS'            => {
			'listRef'         => \@defaultSettingsChoices,
			'stringExternRef' => 1,
			'header'          => 'SETTINGS',
			'stringHeader'    => 1,
			'headerAddCount'  => 1,
			'overlayRef'      => sub { return (undef, shift->symbols('rightarrow')) },
			'overlayRefArgs'  => 'C',
			'init'            => \&settingsMenu,
			'submenus'        => {
		
				# Brightness submenus
				'AUDIO_SETTINGS'      => {
					'useMode'         => 'INPUT.List',
					'listRef'         => [ 
						'BASS',
						'TREBLE',
						'PITCH',
						'SETUP_TRANSITIONTYPE',
						'VOLUME',
						'REPLAYGAIN',
						'SETUP_ANALOGOUTMODE',
						'LINE_IN_LEVEL',
						'LINE_IN_ALWAYS_ON',
						'STEREOXL',
					],
					'stringExternRef' => 1,
					'header'          => 'AUDIO_SETTINGS',
					'stringHeader'    => 1,
					'headerAddCount'  => 1,
					'overlayRef'      => sub { 
						return (undef, shift->symbols('rightarrow')); 
					},
					'overlayRefArgs'  => 'CV',
					'condition'       => sub { 1 },
					'init'            => sub {
						my $client = shift;
						my @opts;
						
						my @settingsChoices = @{$menuParams{'SETTINGS'}{'submenus'}{'AUDIO_SETTINGS'}{'listRef'}};
						my $menu = $menuParams{'SETTINGS'}{'submenus'}{'AUDIO_SETTINGS'}{'submenus'};

						for my $setting ( @settingsChoices) {
					
							if ($menu->{$setting}->{'condition'} && &{$menu->{$setting}->{'condition'}}($client)) {
					
								push @opts, $setting;
							}
						}

						#@settingsChoices = sort { $client->string($a) cmp $client->string($b) } @settingsChoices;
					
						$client->modeParam('listRef', \@opts);
					},
					'submenus'        => {

						'VOLUME'           => {
							'useMode'      => 'INPUT.Bar',
							'header'       => 'VOLUME',
							'stringHeader' => 1,
							'increment'    => 1,
							'headerValue'  => sub { return $_[0]->volumeString($_[1]) },
							'onChange'     => \&executeCommand,
							'command'      => 'mixer',
							'subcommand'   => 'volume',
							'initialValue' => sub { return $_[0]->volume() },
							'condition'    => sub { 1 },
						},
				
						'BASS'             => {
							'useMode'      => 'INPUT.Bar',
							'header'       => 'BASS',
							'stringHeader' => 1,
							'headerValue'  => 'unscaled',
							'min'          => sub { shift->minBass(); },
							'max'          => sub { shift->maxBass(); },
							'cursor'       => 0,
							'increment'    => 1,
							'onChange'     =>  \&executeCommand,
							'command'      => 'mixer',
							'subcommand'   => 'bass',
							'initialValue' => sub { return $_[0]->bass() },
							'condition'    => sub {
								my $client = shift;
								return $client->maxBass() - $client->minBass();
							},
						},
		
						'PITCH'               => {
							'useMode'         => 'INPUT.Bar',
							'header'          => 'PITCH',
							'stringHeader'    => 1,
							'headerValue'     =>'unscaled',
							'headerValueUnit' => '%',
							'min'             => 80,
							'max'             => 120,
							'mid'             => 100,
							'midIsZero'       => 0,
							'increment'       => 1,
							'onChange'        =>  \&executeCommand,
							'command'         => 'mixer',
							'subcommand'      => 'pitch',
							'initialValue'    => sub { return $_[0]->pitch() },
							'condition'       => sub {
								my $client = shift;
								return $client->maxPitch() - $client->minPitch();
							},
						},
				
						'TREBLE'           => {
							'useMode'      => 'INPUT.Bar',
							'header'       => 'TREBLE',
							'stringHeader' => 1,
							'headerValue'  => 'unscaled',
							'cursor'       => 0,
							'min'          => sub { shift->minTreble(); },
							'max'          => sub { shift->maxTreble(); },
							'increment'    => 1,
							'onChange'     =>  \&executeCommand,
							'command'      => 'mixer',
							'subcommand'   => 'treble',
							'initialValue' => sub { return $_[0]->treble() },
							'condition'   => sub {
								my $client = shift;
								return $client->maxTreble() - $client->minTreble();
							},
						},
				
						'STEREOXL'           => {
							'useMode'      => 'INPUT.Choice',
							'listRef'      => [
								{
									name   => '{CHOICE_OFF}',
									value  => 0,
								},
								{
									name   => '{LOW}',
									value  => 1,
								},
								{
									name   => '{MEDIUM}',
									value  => 2,
								},
								{
									name   => '{HIGH}',
									value  => 3,
								},
							],
							'onPlay'       => \&setPref,
							'onAdd'        => \&setPref,
							'onRight'      => \&setPref,
							'header'       => '{STEREOXL}',
							'headerAddCount' => 1,
							'pref'            => "stereoxl",
							'initialValue' => sub { return $_[0]->stereoxl() },
							'condition'   => sub {
								my $client = shift;
								return $client->maxXL() - $client->minXL();
							},
						},

						'SETUP_ANALOGOUTMODE' => analogOutMenu(),

						'LINE_IN_LEVEL'    => {
							'useMode'      => 'INPUT.Bar',
							'header'       => 'LINE_IN_LEVEL',
							'stringHeader' => 1,
							'headerValue'  => 'unscaled',
							'min'          => 0,
							'max'          => 100,
							'increment'    => 1,
							'onChange'     => sub {
								my ($client, $value) = @_;
								
								$value = $prefs->client($client)->get('lineInLevel') + $value;
								$prefs->client($client)->set('lineInLevel', $value);
							},
							
							'pref'         => "lineInLevel",
							'initialValue' => sub { $prefs->client(shift)->get('lineInLevel') },
							'condition'    => sub {
								my $client = shift;
								return $client->can('setLineIn') && Slim::Utils::PluginManager->isEnabled('Slim::Plugin::LineIn::Plugin');
							},
						},

						'LINE_IN_ALWAYS_ON'=> {
							'useMode'      => 'INPUT.Choice',
							'listRef'      => [
								{
									name   => '{OFF}',
									value  => 0,
								},
								{
									name   => '{ON}',
									value  => 1,
								},
							],
							'onPlay'       => \&setPref,
							'onAdd'        => \&setPref,
							'onRight'      => \&setPref,
							'header'       => '{LINE_IN_ALWAYS_ON}',
							'headerAddCount'=> 1,
							'pref'         => "lineInAlwaysOn",
							'initialValue' => sub { $prefs->client(shift)->get('lineInAlwaysOn') },
							'condition'    => sub {
								my $client = shift;
								return $client->can('setLineIn') && Slim::Utils::PluginManager->isEnabled('Slim::Plugin::LineIn::Plugin');
							},
						},
				
						'SETUP_TRANSITIONTYPE' => {
							'useMode'      => 'INPUT.Choice',
							'listRef'      => [
								{
									name   => '{TRANSITION_NONE}',
									value  => 0,
								},
								{
									name   => '{TRANSITION_CROSSFADE}',
									value  => 1,
								},
								{
									name   => '{TRANSITION_FADE_IN}',
									value  => 2,
								},
								{
									name   => '{TRANSITION_FADE_OUT}',
									value  => 3,
								},
								{
									name   => '{TRANSITION_FADE_IN_OUT}',
									value  => 4,
								},
							],
							'onPlay'       => \&setPref,
							'onAdd'        => \&setPref,
							'onRight'      => \&setPref,
							'header'       => '{SETUP_TRANSITIONTYPE}',
							'headerAddCount' => 1,
							'pref'         => 'transitionType',
							'initialValue' => sub { $prefs->client(shift)->get('transitionType') },
							'condition'    => sub { return $_[0]->isa('Slim::Player::Squeezebox2') },
						},

						'REPLAYGAIN'       => {
							'useMode'      => 'INPUT.Choice',
							'listRef'      => [
								{
									name   => '{REPLAYGAIN_DISABLED}',
									value  => 0,
								},
								{
									name   => '{REPLAYGAIN_TRACK_GAIN}',
									value  => 1,
								},
								{
									name   => '{REPLAYGAIN_ALBUM_GAIN}',
									value  => 2,
								},
								{
									name   => '{REPLAYGAIN_SMART_GAIN}',
									value  => 3,
								},
							],
							'onPlay'       => \&setPref,
							'onAdd'        => \&setPref,
							'onRight'      => \&setPref,
							'header'       => '{REPLAYGAIN}',
							'headerAddCount'  => 1,
							'pref'            => "replayGainMode",
							'initialValue'    => sub { $prefs->client(shift)->get('replayGainMode') },
							'condition'   => sub {
								my $client = shift;
								return $client->canDoReplayGain(0);
							},
						},
					},
				},
				'DISPLAY_SETTINGS'          => {
					'useMode'         => 'INPUT.List',
					'listRef'         => [
						'SETUP_GROUP_BRIGHTNESS',
						'TEXTSIZE',
						'TITLEFORMAT',
						'SETUP_VISUALIZERMODE',
						'SCREENSAVERS',
						'SETUP_PLAYINGDISPLAYMODE',
						'SETUP_SHOWCOUNT',
					],
					'stringExternRef' => 1,
					'header'          => 'DISPLAY_SETTINGS',
					'stringHeader'    => 1,
					'headerAddCount'  => 1,
					'overlayRef'      => sub { 
						return (undef, shift->symbols('rightarrow')); 
					},
					'overlayRefArgs'  => 'CV',
					'condition'       => sub { 1 },
					'init'            => sub {
						my $client = shift;
						my @opts;
						
						my @settingsChoices = @{$menuParams{'SETTINGS'}{'submenus'}{'DISPLAY_SETTINGS'}{'listRef'}};
						my $menu = $menuParams{'SETTINGS'}{'submenus'}{'DISPLAY_SETTINGS'}{'submenus'};
						
						for my $setting ( @settingsChoices) {
						
							if ($menu->{$setting}->{'condition'} && &{$menu->{$setting}->{'condition'}}($client)) {
					
								push @opts, $setting;
							}
						}
					
						#@settingsChoices = sort { $client->string($a) cmp $client->string($b) } @settingsChoices;
					
						$client->modeParam('listRef', \@opts);
					},
					'submenus'        => {
						'TITLEFORMAT'      => {
							'useMode'      => 'INPUT.Choice',
							'header'       => '{TITLEFORMAT}',
							'headerAddCount' => 1,
							'onPlay'       => \&setPref,
							'onAdd'        => \&setPref,
							'onRight'      => \&setPref,
							'pref'         => 'titleFormatCurr',
							'initialValue' => sub { $prefs->client(shift)->get('titleFormatCurr') },
							'condition'    => sub { 1 },
							'init'         => sub {
								my $client = shift;
		
								my @externTF = ();
								my $i        = 0;
		
								for my $format (@{ $prefs->client($client)->get('titleFormat') }) {
		
									push @externTF, {
										'name'  => $prefs->get('titleFormat')->[ $format ],
										'value' => $i++
									};
								}
		
								$client->modeParam('listRef', \@externTF);
							}
						},
		
						'TEXTSIZE'      => {
							'useMode'      => 'INPUT.Choice',
							'header'       => '{TEXTSIZE}',
							'headerAddCount' => 1,
							# to display the font options, we temporarily set the activeFont pref to the current selection and then reset the pref in exit callback
							'onChange'     => sub { $prefs->client($_[0])->set('activeFont_curr', $_[1]->{'value'}) },
							'onPlay'       => sub { $_[0]->modeParam('settextsize', $_[1]->{'value'}) },
							'onAdd'        => sub { $_[0]->modeParam('settextsize', $_[1]->{'value'}) },
							'overlayRef'   => sub { [undef, Slim::Buttons::Common::radioButtonOverlay($_[0], $_[1]->{'value'} eq $_[0]->modeParam('settextsize')) ] },
							'overlayRefArgs' => 'CV',
							'pref'         => 'activeFont_curr',
							'initialValue' => sub { $prefs->client(shift)->get('activeFont_curr') },
							'condition'    => sub { $_[0]->display->isa('Slim::Display::Graphics'); },
							'init'         => sub {
								my $client = shift;
		
								my @fonts = ();
								my $i        = 0;
		
								for my $font (@{ $prefs->client($client)->get('activeFont') }) {
		
									push @fonts, {
										'name'  => Slim::Utils::Strings::getString($font),
										'value' => $i++
									};
								}
		
								$client->modeParam('listRef', \@fonts);
								$client->modeParam('settextsize', $prefs->client($client)->get('activeFont_curr'));
							},
							'callback'      => sub {
								my $client = shift;
								my $action = shift;
								if ($action eq 'right') {
									my $valref = $client->modeParam('valueRef');
									$client->modeParam('settextsize', $$valref->{'value'});
									$client->update;
								}
								if ($action eq 'left') {
									setPref($client, $client->modeParam('settextsize'));
									Slim::Buttons::Common::popModeRight($client);
								}
							},
						},

						# Brightness submenus
						'SETUP_GROUP_BRIGHTNESS'        => {
							'useMode'         => 'INPUT.List',
							'listRef'         => ['SETUP_POWERONBRIGHTNESS', 'SETUP_POWEROFFBRIGHTNESS', 'SETUP_IDLEBRIGHTNESS', 'SETUP_MINAUTOBRIGHTNESS', 'SETUP_SENSAUTOBRIGHTNESS'],
							'stringExternRef' => 1,
							'header'          => 'SETUP_GROUP_BRIGHTNESS',
							'stringHeader'    => 1,
							'headerAddCount'  => 1,
							'overlayRef'      => sub { 
								return (undef, shift->symbols('rightarrow')); 
							},
							'overlayRefArgs'  => 'CV',
							'condition'    => sub { 1 },
							'init'            => sub {
								my $client = shift;
								my @opts;
								
								my @settingsChoices = @{$menuParams{'SETTINGS'}{'submenus'}{'DISPLAY_SETTINGS'}{'submenus'}{'SETUP_GROUP_BRIGHTNESS'}{'listRef'}};
								my $menu = $menuParams{'SETTINGS'}{'submenus'}{'DISPLAY_SETTINGS'}{'submenus'}{'SETUP_GROUP_BRIGHTNESS'}{'submenus'};
								
								for my $setting ( @settingsChoices) {
								
									if ($menu->{$setting}->{'condition'} && &{$menu->{$setting}->{'condition'}}($client)) {
							
										push @opts, $setting;
									}
								}
					
								#@settingsChoices = sort { $client->string($a) cmp $client->string($b) } @settingsChoices;
					
								$client->modeParam('listRef', \@opts);
							},
							'submenus'        => {
			
								'SETUP_POWERONBRIGHTNESS' => {
									'useMode'       => 'INPUT.Choice',
									'onPlay'        => \&setPref,
									'onAdd'         => \&setPref,
									'onRight'       => \&setPref,
									'pref'          => "powerOnBrightness",
									'header'        => '{SETUP_POWERONBRIGHTNESS}',
									'headerAddCount'=> 1,
									'initialValue'  => sub { $prefs->client(shift)->get('powerOnBrightness') },
									'init'          => \&brightnessInit,
									'condition'    => sub { 1 },
								},
								
								'SETUP_POWEROFFBRIGHTNESS' => {
									'useMode'       => 'INPUT.Choice',
									'onPlay'        => \&setPref,
									'onAdd'         => \&setPref,
									'onRight'       => \&setPref,
									'pref'          => "powerOffBrightness",
									'header'        => '{SETUP_POWEROFFBRIGHTNESS}',
									'headerAddCount'=> 1,
									'initialValue'  => sub { $prefs->client(shift)->get('powerOffBrightness') },
									'init'          => \&brightnessInit,
									'condition'    => sub { 1 },
								},
						
								'SETUP_IDLEBRIGHTNESS' => {
									'useMode'       => 'INPUT.Choice',
									'onPlay'        => \&setPref,
									'onAdd'         => \&setPref,
									'onRight'       => \&setPref,
									'pref'          => "idleBrightness",
									'header'        => '{SETUP_IDLEBRIGHTNESS}',
									'headerAddCount'=> 1,
									'initialValue'  => sub { $prefs->client(shift)->get('idleBrightness') },
									'init'          => \&brightnessInit,
									'condition'    => sub { 1 },
								},
								'SETUP_MINAUTOBRIGHTNESS'    => {
									'useMode'      => 'INPUT.Bar',
									'header'       => 'SETUP_MINAUTOBRIGHTNESS',
									'stringHeader' => 1,
									'headerValue'  => 'unscaled',
									'min'          => 1,
									'max'          => 5,
									'increment'    => 1,
									'onChange'     => sub {
										my ($client, $value) = @_;
										
										$value = $prefs->client($client)->get('minAutoBrightness') + $value;
										$prefs->client($client)->set('minAutoBrightness', $value);
									},
									
									'pref'         => "minAutoBrightness",
									'initialValue' => sub { $prefs->client(shift)->get('minAutoBrightness') },
									'condition'    => sub {
										my $client = shift;
										return $client->isa('Slim::Player::Boom');
									},
								},
								'SETUP_SENSAUTOBRIGHTNESS'    => {
									'useMode'      => 'INPUT.Bar',
									'header'       => 'SETUP_SENSAUTOBRIGHTNESS',
									'stringHeader' => 1,
									'headerValue'  => 'unscaled',
									'min'          => 1,
									'max'          => 20,
									'increment'    => 1,
									'onChange'     => sub {
										my ($client, $value) = @_;
										
										$value = $prefs->client($client)->get('sensAutoBrightness') + $value;
										$prefs->client($client)->set('sensAutoBrightness', $value);
									},
									
									'pref'         => "sensAutoBrightness",
									'initialValue' => sub { $prefs->client(shift)->get('sensAutoBrightness') },
									'condition'    => sub {
										my $client = shift;
										return $client->isa('Slim::Player::Boom');
									},
								},
							},
						},
		
						# Screensavers submenus
						'SCREENSAVERS'        => {
							'useMode'         => 'INPUT.List',
							'listRef'         => [
								'SETUP_SCREENSAVER',
								'SETUP_IDLESAVER',
								'SETUP_OFFSAVER',
								'SETUP_ALARMSAVER',
							],
							'stringExternRef' => 1,
							'header'          => 'SCREENSAVERS',
							'stringHeader'    => 1,
							'headerAddCount'  => 1,
							'overlayRef'      => sub { return (undef, shift->symbols('rightarrow')) },
							'overlayRefArgs'  => 'C',
							'condition'    => sub { 1 },
							'submenus'        => {
			
								'SETUP_SCREENSAVER' => {
									'useMode'       => 'INPUT.Choice',
									'onPlay'        => \&setPref,
									'onAdd'         => \&setPref,
									'onRight'       => \&setPref,
									'pref'          => "screensaver",
									'header'        => '{SETUP_SCREENSAVER}',
									'headerAddCount'=> 1,
									'initialValue'  => sub { $prefs->client(shift)->get('screensaver') },
									'init'          => \&screensaverInit,
								},
								
								'SETUP_OFFSAVER' => {
									'useMode'       => 'INPUT.Choice',
									'onPlay'        => \&setPref,
									'onAdd'         => \&setPref,
									'onRight'       => \&setPref,
									'pref'          => "offsaver",
									'header'        => '{SETUP_OFFSAVER}',
									'headerAddCount'=> 1,
									'initialValue'  => sub { $prefs->client(shift)->get('offsaver') },
									'init'          => \&screensaverInit,
								},
						
								'SETUP_IDLESAVER' => {
									'useMode'       => 'INPUT.Choice',
									'onPlay'        => \&setPref,
									'onAdd'         => \&setPref,
									'onRight'       => \&setPref,
									'pref'          => "idlesaver",
									'header'        => '{SETUP_IDLESAVER}',
									'headerAddCount'=> 1,
									'initialValue'  => sub { $prefs->client(shift)->get('idlesaver') },
									'init'          => \&screensaverInit,
								},
						
								'SETUP_ALARMSAVER' => {
									'useMode'       => 'INPUT.Choice',
									'onPlay'        => \&setPref,
									'onAdd'         => \&setPref,
									'onRight'       => \&setPref,
									'pref'          => "alarmsaver",
									'header'        => '{SETUP_ALARMSAVER}',
									'headerAddCount'=> 1,
									'initialValue'  => sub { $prefs->client(shift)->get('alarmsaver') },
									'init'          => \&screensaverInit,
								},
							},
						},
		
						'SETUP_PLAYINGDISPLAYMODE'      => {
							'useMode'      => 'INPUT.Choice',
							'header'       => '{SETUP_PLAYINGDISPLAYMODE}',
							'headerAddCount'=> 1,
							'onPlay'       => \&setPref,
							'onAdd'        => \&setPref,
							'onRight'      => \&setPref,
							'pref'         => 'playingDisplayMode',
							'initialValue' => sub { $prefs->client(shift)->get('playingDisplayMode') },
							'condition'    => sub { 1 },
							'init'         => sub {
								my $client = shift;
		
								my $modes = $client->display->modes;
								my @opts  = ();
								
								my $x     = 0;
		
								for my $mode (@{ $prefs->client($client)->get('playingDisplayModes') }) {
		
									my @desc;
		
									for my $tok (@{ $modes->[$mode]{'desc'} }) {
										push @desc, Slim::Utils::Strings::string($tok);
									}
		
									push @opts, {
										'name'  => join(' ', @desc),
										'value' => $x,
									};
									$x++;
								}
		
								$client->modeParam('listRef', \@opts);
							}
						},
		
						'SETUP_VISUALIZERMODE'         => {
							'useMode'      => 'INPUT.Choice',
							'onPlay'       => \&updateVisualMode,
							'onAdd'        => \&updateVisualMode,
							'onRight'      => \&updateVisualMode,
							'header'       => '{SETUP_VISUALIZERMODE}',
							'headerAddCount'=> 1,
							'pref'         => 'visualMode',
							'initialValue' => sub { $prefs->client(shift)->get('visualMode') },
							'condition'    => sub { return $_[0]->display->isa('Slim::Display::Transporter') },
							'init'         => \&visualInit,
						},

						'SETUP_SHOWCOUNT'              => {
							'useMode'      => 'INPUT.Choice',
							'onPlay'       => \&setPref,
							'onAdd'        => \&setPref,
							'onRight'      => \&setPref,
							'header'       => '{SETUP_SHOWCOUNT}',
							'headerAddCount'=> 1,
							'pref'         => 'alwaysShowCount',
							'initialValue' => sub { $prefs->client(shift)->get('alwaysShowCount') },
							'condition'    => sub { 1 },
							'listRef'      => [
								{
									name   => '{SETUP_SHOWCOUNT_TEMP}',
									value  => 0,
								},
								{
									name   => '{SETUP_SHOWCOUNT_ALWAYS}',
									value  => 1,
								},
							],
						},
					},
				},

				'REPEAT'           => {
					'useMode'      => 'INPUT.Choice',
					'listRef'      => [
						{
							name   => '{REPEAT_OFF}',
							value  => 0,
						},
						{
							name   => '{REPEAT_ONE}',
							value  => 1,
						},
						{
							name   => '{REPEAT_ALL}',
							value  => 2,
						},
					],
					'onPlay'       => \&executeCommand,
					'onAdd'        => \&executeCommand,
					'onRight'      => \&executeCommand,
					'header'       => '{REPEAT}',
					'headerAddCount'=> 1,
					'condition'    => sub { 1 },
					'pref'         => sub { Slim::Player::Playlist::repeat(shift) },
					'initialValue' => sub { Slim::Player::Playlist::repeat(shift) },
					'command'      => 'playlist',
					'subcommand'   => 'repeat',
				},

				'SHUFFLE'          => {
					'useMode'      => 'INPUT.Choice',
					'listRef'      => [
						{
							name   => '{SHUFFLE_OFF}',
							value  => 0,
						},
						{
							name   => '{SHUFFLE_ON_SONGS}',
							value  => 1,
						},
						{
							name   => '{SHUFFLE_ON_ALBUMS}',
							value  => 2,
						},
					],
					'onPlay'       => \&executeCommand,
					'onAdd'        => \&executeCommand,
					'onRight'      => \&executeCommand,
					'header'       => '{SHUFFLE}',
					'headerAddCount'=> 1,
					'condition'    => sub { 1 },
					'pref'         => sub{ return Slim::Player::Playlist::shuffle(shift)},
					'initialValue' => sub{ return Slim::Player::Playlist::shuffle(shift)},
					'command'      => 'playlist',
					'subcommand'   => 'shuffle',
				},
	
				'SYNCHRONIZE' => {
					'useMode'   => 'synchronize',
					'condition' => sub {
						my $client = shift;

						return $client->isSynced() || 
							(scalar(Slim::Player::Sync::canSyncWith($client)) > 0);
					},
				},
		
				'MUSICSOURCE' => {
					'useMode'        => 'INPUT.Choice',
					'onRight'        => \&switchServer,
					'onPlay'         => \&switchServer,
					'onAdd'          => \&switchServer,
					'header'         => '{MUSICSOURCE}',
					'headerAddCount' => 1,
					'init'           => \&serverListInit,
					'initialValue'   => Slim::Utils::Network::serverAddr(),
					'overlayRef'     => sub {
						my ($client, $item) = @_;
						return [undef, 
							Slim::Networking::Discovery::Server::is_self($item->{value})
							? Slim::Buttons::Common::checkBoxOverlay($client, 1)
							: $client->symbols('rightarrow')
						];
					},
					'condition'      => sub { shift->hasServ(); },
				},
			},
		},
	);

	Slim::Buttons::Home::addMenuOption('SETTINGS', $menuParams{'SETTINGS'});
	Slim::Buttons::Home::addMenuOption('MUSICSOURCE', $menuParams{'SETTINGS'}->{'submenus'}->{'MUSICSOURCE'});
}

sub setPref {
	my $client = shift;
	my $value = shift;

	# See the hash defines above. 
	if (ref $value eq 'HASH') {
		$value = $value->{'value'};
	}

	my $pref = $client->modeParam('pref');
	
	$prefs->client($client)->set($pref,$value);
	if ($pref eq 'playername') {
		$client->execute(['name', $value]);
	}
}

sub executeCommand {
	my $client = shift;
	my $value = shift;

	# See the hash defines above. 
	if (ref $value eq 'HASH') {
		$value = $value->{'value'};
	}

	my $command = $client->modeParam('command');
	my $subcmd  = $client->modeParam('subcommand');

	$client->execute([$command, $subcmd, $value]);
}

sub screensaverInit {
	my $client = shift;
	my $pref = $client->modeParam('pref');
	
	my %hash = %{ Slim::Buttons::Common::validSavers($client)->{$pref} };
	my @savers;
	
	for (sort {$client->string($hash{$a}) cmp $client->string($hash{$b})} keys %hash) {
	
		push @savers, {
			'name'  => "{".$hash{$_}."}",
			'value' => $_,
		};

	}
	
	$client->modeParam('listRef', \@savers);
}

sub brightnessInit {
	my $client = shift;
	
	my $hash  = $client->display->getBrightnessOptions();
	my @options;
	
	for (sort keys %$hash) {
	
		unshift @options, {
			'name'  => $hash->{$_},
			'value' => $_,
		};

	}
	
	$client->modeParam('listRef', \@options);
}

sub settingsMenu {
	my $client = shift;
	
	my %temp;
	my @settingsChoices;
	my $menu = $menuParams{'SETTINGS'}{'submenus'};

	for my $setting ( @defaultSettingsChoices ) {

		if ($menu->{$setting}->{'condition'} && &{$menu->{$setting}->{'condition'}}($client)) {

			push @settingsChoices, $setting;
		}
	}

	for my $setting ( keys %{$menu}) {

		if (!grep(/$setting/, @settingsChoices) && $menu->{$setting}->{'condition'} && &{$menu->{$setting}->{'condition'}}($client)) {

			push @settingsChoices, $setting;
		}
	}

	$client->modeParam('listRef', \@settingsChoices);
}

sub analogOutMenu {
	return {
		'useMode'      => 'INPUT.Choice',
		'listRef'      => [
			{
				name   => '{ANALOGOUTMODE_HEADPHONE}',
				value  => 0,
			},
			{
				name   => '{ANALOGOUTMODE_SUBOUT}',
				value  => 1,
			},
			{
				name   => '{ANALOGOUTMODE_ALWAYS_ON}',
				value  => 2,
			},
			{
				name   => '{ANALOGOUTMODE_ALWAYS_OFF}',
				value  => 3,
			},
		],
		'onPlay'       => \&setPref,
		'onAdd'        => \&setPref,
		'onRight'      => \&setPref,
		'header'       => '{SETUP_ANALOGOUTMODE}',
		'headerAddCount' => 1,
		'pref'            => "analogOutMode",
		'initialValue'    => sub { $prefs->client(shift)->get('analogOutMode') },
		'condition'   => sub {
			my $client = shift;
			return $client->hasHeadSubOut();
		},
	};
}

sub visualInit {
	my $client = shift;
	my $modes = $prefs->client($client)->get('visualModes');
	my $modeDefs = $client->display->visualizerModes();

	my @visualModes;
	my $i = 0;	

	foreach my $mode (@$modes) {

		my $desc = $modeDefs->[$mode]{'desc'};
		my $name = '';

		foreach my $j (0..$#{$desc}){
			$name .= ' ' if ($j > 0);
			$name .= Slim::Utils::Strings::string(@{$desc}[$j]);
		}

		push @visualModes, {
			name  => $name,
			value => $i++,
		};
	}
	
	$client->modeParam('listRef', \@visualModes);
}

sub updateVisualMode {
	my $client = shift;
	my $value = shift;

	$prefs->client($client)->set('visualMode', $value->{'value'});
	Slim::Buttons::Common::updateScreen2Mode($client);
};

sub serverListInit {
	my $client = shift;

	my @servers;

	my $servers = Slim::Networking::Discovery::Server::getServerList();

	foreach (sort keys %$servers) {
		push @servers, {
			name => Slim::Utils::Strings::getString($_),
			value => Slim::Networking::Discovery::Server::getServerAddress($_)
		};
	}	

	push @servers, {
		name => $client->string('SQUEEZENETWORK'),
		value => 'SQUEEZENETWORK'
	};

	$client->modeParam('listRef', \@servers);
}

sub switchServer {
	my ($client, $server) = @_;
	
	if ($server->{value} eq 'SQUEEZENETWORK') {
		Slim::Buttons::Common::pushModeLeft($client, 'squeezenetwork.connect');
	} 

	elsif ( Slim::Networking::Discovery::Server::is_self($server->{value}) ) {
		$client->bumpRight();
	}
	else {

		$client->showBriefly({
			'line' => [
				$client->string('MUSICSOURCE'),
				$client->string('SQUEEZEBOX_SERVER_CONNECTING', $server->{name}) 
			]
		});

		# we want to disconnect, but not immediately, because that
		# makes the UI jerky.  Postpone disconnect for a short while
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1,
			sub {
				my ($client, $server) = @_;
					
				# don't disconnect unless we're still in this mode.
				return unless ($client->modeParam('server.switch'));

				$client->execute([ 'stop' ]);

				# ensure client has disconnected before forgetting him
				Slim::Control::Request::subscribe(
					\&_forgetPlayer, 
					[['client'],['disconnect']], 
					$client
				);

				$client->execute( [ 'connect', $server ] );

			}, $server->{value});
		
		# this flag prevents disconnect if user has popped out of this mode
		$client->modeParam('server.switch', 1);
	}
}

sub _forgetPlayer {
	my $request = shift;
	my $client  = $request->client;
	
	Slim::Control::Request::unsubscribe(\&_forgetPlayer, $client);

	Slim::Control::Request::executeRequest(
		$client,
		['client', 'forget']);	
}


=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Buttons::Input::Choice>

L<Slim::Buttons::Input::List>

L<Slim::Buttons::Input::Bar>

L<Slim::Utils::Prefs>

=cut

1;

__END__
