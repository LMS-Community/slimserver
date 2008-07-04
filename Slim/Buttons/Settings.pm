package Slim::Buttons::Settings;

# SqueezeCenter Copyright 2001-2007 Logitech.
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
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Buttons::Alarm;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Buttons::Information;
use Slim::Networking::Discovery::Server;
use Slim::Buttons::SqueezeNetwork;

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
					'listRef'         => ['BASS','TREBLE','PITCH', 'VOLUME', 'REPLAYGAIN','SETUP_TRANSITIONTYPE', 'SETUP_ANALOGOUTMODE', 'STEREOXL'],
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
							'useMode'      => 'INPUT.Bar',
							'header'       => 'STEREOXL',
							'stringHeader' => 1,
							'headerValue'  => 'unscaled',
							'min'          => sub { shift->minXL(); },
							'max'          => sub { shift->maxXL(); },
							'increment'    => 1,
							'cursor'       => 0,
							'onChange'     =>  \&executeCommand,
							'command'      => 'mixer',
							'subcommand'   => 'stereoxl',
							'initialValue' => sub { return $_[0]->stereoXL() },
							'condition'   => sub {
								my $client = shift;
								return $client->can('maxXL') ? $client->maxXL() - $client->minXL() : 0;
							},
						},

						'SETUP_ANALOGOUTMODE'       => {
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
							],
							'onPlay'       => \&setPref,
							'onAdd'        => \&setPref,
							'onRight'      => \&setPref,
							'header'       => '{SETUP_ANALOGOUTMODE}{count}',
							'pref'            => "analogOutMode",
							'initialValue'    => sub { $prefs->client(shift)->get('analogOutMode') },
							'condition'   => sub {
								my $client = shift;
								return $client->isa('Slim::Player::Boom');
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
							'header'       => '{SETUP_TRANSITIONTYPE}{count}',
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
							'header'       => '{REPLAYGAIN}{count}',
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
					'listRef'         => ['SETUP_GROUP_BRIGHTNESS', 'TEXTSIZE', 'TITLEFORMAT', 'SCREENSAVERS', 'SETUP_PLAYINGDISPLAYMODE', 'SETUP_VISUALIZERMODE'],
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
							'header'       => '{TITLEFORMAT}{count}',
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
							'header'       => '{TEXTSIZE}{count}',
							'onPlay'       => sub { 
								$_[0]->textSize($_[1]->{'value'})
							},
							'onAdd'        => sub { 
								$_[0]->textSize($_[1]->{'value'})
							},
							'onRight'      => sub { 
								$_[0]->textSize($_[1]->{'value'})
							},
							'pref'         => 'activeFont_curr',
							'initialValue' => sub { $prefs->client(shift)->get('activeFont_curr') },
							'condition'    => sub { 1 },
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
							}
						},

						# Brightness submenus
						'SETUP_GROUP_BRIGHTNESS'        => {
							'useMode'         => 'INPUT.List',
							'listRef'         => ['SETUP_POWERONBRIGHTNESS', 'SETUP_POWEROFFBRIGHTNESS', 'SETUP_IDLEBRIGHTNESS'],
							'stringExternRef' => 1,
							'header'          => 'BRIGHTNESS',
							'stringHeader'    => 1,
							'headerAddCount'  => 1,
							'overlayRef'      => sub { 
								return (undef, shift->symbols('rightarrow')); 
							},
							'overlayRefArgs'  => 'CV',
							'condition'    => sub { 1 },
							'submenus'        => {
			
								'SETUP_POWERONBRIGHTNESS' => {
									'useMode'       => 'INPUT.Choice',
									'onPlay'        => \&setPref,
									'onAdd'         => \&setPref,
									'onRight'       => \&setPref,
									'pref'          => "powerOnBrightness",
									'header'        => '{SETUP_POWERONBRIGHTNESS}{count}',
									'initialValue'  => sub { $prefs->client(shift)->get('powerOnBrightness') },
									'init'          => \&brightnessInit,
								},
								
								'SETUP_POWEROFFBRIGHTNESS' => {
									'useMode'       => 'INPUT.Choice',
									'onPlay'        => \&setPref,
									'onAdd'         => \&setPref,
									'onRight'       => \&setPref,
									'pref'          => "powerOffBrightness",
									'header'        => '{SETUP_POWEROFFBRIGHTNESS}{count}',
									'initialValue'  => sub { $prefs->client(shift)->get('powerOffBrightness') },
									'init'          => \&brightnessInit,
								},
						
								'SETUP_IDLEBRIGHTNESS' => {
									'useMode'       => 'INPUT.Choice',
									'onPlay'        => \&setPref,
									'onAdd'         => \&setPref,
									'onRight'       => \&setPref,
									'pref'          => "idleBrightness",
									'header'        => '{SETUP_IDLEBRIGHTNESS}{count}',
									'initialValue'  => sub { $prefs->client(shift)->get('idleBrightness') },
									'init'          => \&brightnessInit,
								},
							},
						},
		
						# Screensavers submenus
						'SCREENSAVERS'        => {
							'useMode'         => 'INPUT.List',
							'listRef'         => ['SETUP_SCREENSAVER', 'SETUP_OFFSAVER', 'SETUP_IDLESAVER'],
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
									'header'        => '{SETUP_SCREENSAVER}{count}',
									'initialValue'  => sub { $prefs->client(shift)->get('screensaver') },
									'init'          => \&screensaverInit,
								},
								
								'SETUP_OFFSAVER' => {
									'useMode'       => 'INPUT.Choice',
									'onPlay'        => \&setPref,
									'onAdd'         => \&setPref,
									'onRight'       => \&setPref,
									'pref'          => "offsaver",
									'header'        => '{SETUP_OFFSAVER}{count}',
									'initialValue'  => sub { $prefs->client(shift)->get('offsaver') },
									'init'          => \&screensaverInit,
								},
						
								'SETUP_IDLESAVER' => {
									'useMode'       => 'INPUT.Choice',
									'onPlay'        => \&setPref,
									'onAdd'         => \&setPref,
									'onRight'       => \&setPref,
									'pref'          => "idlesaver",
									'header'        => '{SETUP_IDLESAVER}{count}',
									'initialValue'  => sub { $prefs->client(shift)->get('idlesaver') },
									'init'          => \&screensaverInit,
								},
							},
						},
		
						'SETUP_PLAYINGDISPLAYMODE'      => {
							'useMode'      => 'INPUT.Choice',
							'header'       => '{SETUP_PLAYINGDISPLAYMODE}{count}',
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
		
								for my $mode (@{ $prefs->client($client)->get('playingDisplayModes') }) {
		
									my @desc;
		
									for my $tok (@{ $modes->[$mode]{'desc'} }) {
										push @desc, Slim::Utils::Strings::string($tok);
									}
		
									push @opts, {
										'name'  => join(' ', @desc),
										'value' => $mode,
									};
								}
		
								$client->modeParam('listRef', \@opts);
							}
						},
		
						'SETUP_VISUALIZERMODE'         => {
							'useMode'      => 'INPUT.Choice',
							'onPlay'       => \&updateVisualMode,
							'onAdd'        => \&updateVisualMode,
							'onRight'      => \&updateVisualMode,
							'header'       => '{SETUP_VISUALIZERMODE}{count}',
							'pref'         => 'visualMode',
							'initialValue' => sub { $prefs->client(shift)->get('visualMode') },
							'condition'    => sub { return $_[0]->display->isa('Slim::Display::Transporter') },
							'init'         => \&visualInit,
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
					'header'       => '{REPEAT}{count}',
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
					'header'       => '{SHUFFLE}{count}',
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

						return Slim::Player::Sync::isSynced($client) || 
							(scalar(Slim::Player::Sync::canSyncWith($client)) > 0);
					},
				},
		
				'MUSICSOURCE' => {
					'useMode'        => 'INPUT.List',
					'callback'       => \&switchServer,
					'header'         => 'MUSICSOURCE',
					'stringHeader'   => 1,
					'headerAddCount' => 1,
					'externRef'      => sub { $_[1] eq 'SQUEEZENETWORK' ? $_[0]->string($_[1]) : $_[1] },
					'overlayRef'     => sub { return (undef, shift->symbols('rightarrow')) },
					'init'           => \&serverListInit,
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
	
	my %hash  = %{&Slim::Buttons::Common::hash_of_savers};
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

	@settingsChoices = sort { $client->string($a) cmp $client->string($b) } @settingsChoices;

	$client->modeParam('listRef', \@settingsChoices);
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

	my @servers = keys %{Slim::Networking::Discovery::Server::getServerList()};
	unshift @servers, 'SQUEEZENETWORK';

	$client->modeParam('listRef', \@servers);
}

sub switchServer {
	my ($client, $exittype) = @_;

	$exittype = uc($exittype);
					
	if ($exittype eq 'LEFT') {
					
		Slim::Buttons::Common::popModeRight($client);
					
	} elsif ($exittype eq 'RIGHT') {

		my $server = ${$client->modeParam('valueRef')}; 

		if ($server eq 'SQUEEZENETWORK') {

			Slim::Buttons::Common::pushModeLeft($client, 'squeezenetwork.connect');

		} elsif ($server) {

			$client->showBriefly({
				'line' => [
					$client->string('MUSICSOURCE'),
					$client->string('SQUEEZECENTER_CONNECTING', $server) 
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

					$client->execute( [ 'connect', Slim::Networking::Discovery::Server::getServerAddress($server) ] );

				}, $server);
		
			# this flag prevents disconnect if user has popped out of this mode
			$client->modeParam('server.switch', 1);
		} else {

			$client->bumpRight();
		}
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
