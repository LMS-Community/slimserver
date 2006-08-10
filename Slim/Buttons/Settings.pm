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
our @defaultSettingsChoices = qw(VOLUME REPEAT SHUFFLE TITLEFORMAT TEXTSIZE SCREENSAVERS);

our @settingsChoices = ();
our %current = ();
our %menuParams = ();
our %functions = ();

sub arrowFunc {
	return (undef,Slim::Display::Display::symbol('rightarrow'));
};

sub init {
	#Slim::Buttons::Common::addMode('settings',Slim::Buttons::Settings::getFunctions(),\&Slim::Buttons::Settings::setMode);

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

	# Massive hash for all the Settings
	%menuParams = (

		'SETTINGS'            => {
			'listRef'         => \@defaultSettingsChoices,
			'stringExternRef' => 1,
			'header'          => 'SETTINGS',
			'stringHeader'    => 1,
			'headerAddCount'  => 1,
			'overlayRef'      => \&arrowFunc,
			'overlayRefArgs'  => '',
			'init'            => \&settingsMenu,
			'submenus'        => {
		
				'VOLUME'           => {
					'useMode'      => 'INPUT.Bar',
					'header'       => 'VOLUME',
					'stringHeader' => 1,
					'headerValue'  => \&volumeValue,
					'onChange'     =>  \&executeCommand,
					'command'      => 'mixer',
					'subcommand'   => 'volume',
					'initialValue' => sub { return $_[0]->volume() },
				},
		
				'BASS'             => {
					'useMode'      => 'INPUT.Bar',
					'header'       => 'BASS',
					'stringHeader' => 1,
					'headerValue'  => 'scaled',
					'mid'          => 50,
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
					'headerValue'  => 'scaled',
					'mid'          => 50,
					'onChange'     =>  \&executeCommand,
					'command'      => 'mixer',
					'subcommand'   => 'treble',
					'initialValue' => sub { return $_[0]->treble() },
					'condition'   => sub {
						my $client = shift;
						return $client->maxTreble() - $client->minTreble();
					},
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
					'initialValue'    => sub { return $_[0]->prefGet('replayGainMode') },
					'condition'   => sub {
						my $client = shift;
						return $client->canDoReplayGain(0);
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
					'pref'         => \&Slim::Player::Playlist::repeat,
					'initialValue' => \&Slim::Player::Playlist::repeat,
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
					'pref'         => \&Slim::Player::Playlist::shuffle,
					'initialValue' => \&Slim::Player::Playlist::shuffle,
					'command'      => 'playlist',
					'subcommand'   => 'shuffle',
					'initialValue' => \&Slim::Player::Playlist::shuffle,
				},
		
				'TITLEFORMAT'      => {
					'useMode'      => 'INPUT.Choice',
					'header'       => '{TITLEFORMAT}{count}',
					'onPlay'       => \&setPref,
					'onAdd'        => \&setPref,
					'onRight'      => \&setPref,
					'pref'         => 'titleFormatCurr',
					'initialValue' => sub { shift->prefGet('titleFormatCurr') },
					'init'         => sub {
						my $client = shift;

						my @externTF = ();
						my $i        = 0;

						for my $format ($client->prefGetArray('titleFormat')) {

							push @externTF, {
								'name'  => Slim::Utils::Prefs::getInd('titleFormat', $format),
								'value' => $i++
							};
						}

						$client->param('listRef', \@externTF);
						$client->param('initialValue', $client->prefGet('titleFormatCurr'));
					}
				},
		
				'TEXTSIZE'         => {
					'useMode'      => 'INPUT.List',
					'listRef'      => undef, #filled before changing modes
					'externRef'    => \&_fontExists,
					'header'       => 'TEXTSIZE',
					'stringHeader' => 1,
					'onChange'     => sub { $_[0]->textSize($_[1]) },
					'onChangeArgs' => 'CV',
					'initialValue' => sub { $_[0]->textSize() },
					'init'         => sub {
						my $client = shift;

						my @text   = (0..$client->maxTextSize);

						$client->param('listRef', \@text);
					},
				},
		
				'SYNCHRONIZE' => {
					'useMode'   => 'synchronize',
					'condition' => sub {
						my $client = shift;

						return Slim::Player::Sync::isSynced($client) || 
							(scalar(Slim::Player::Sync::canSyncWith($client)) > 0);
					},
				},
		
				#,'settings/PLAYER_NAME' => {
				#	'useMode' => 'INPUT.Text'
					#add more params here after the rest is working
				#}
		
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
					'initialValue' => sub { return $_[0]->prefGet('transitionType') },
					'condition'    => sub { return $_[0]->isa('Slim::Player::Squeezebox2') },
				},

				# Screensavers submenus
				'SCREENSAVERS'        => {
					'useMode'         => 'INPUT.List',
					'listRef'         => ['SETUP_SCREENSAVER', 'SETUP_OFFSAVER', 'SETUP_IDLESAVER'],
					'stringExternRef' => 1,
					'header'          => 'SCREENSAVERS',
					'stringHeader'    => 1,
					'headerAddCount'  => 1,
					'overlayRef'      => \&arrowFunc,
					'overlayRefArgs'  => '',
					'submenus'        => {
	
						'SETUP_SCREENSAVER' => {
							'useMode'       => 'INPUT.Choice',
							'onPlay'        => \&setPref,
							'onAdd'         => \&setPref,
							'onRight'       => \&setPref,
							'pref'          => "screensaver",
							'header'        => '{SETUP_SCREENSAVER}{count}',
							'initialValue'  => sub { return $_[0]->prefGet('screensaver') },
							'init'          => \&screensaverInit,
						},
						
						'SETUP_OFFSAVER' => {
							'useMode'       => 'INPUT.Choice',
							'onPlay'        => \&setPref,
							'onAdd'         => \&setPref,
							'onRight'       => \&setPref,
							'pref'          => "offsaver",
							'header'        => '{SETUP_OFFSAVER}{count}',
							'initialValue'  => sub { return $_[0]->prefGet('offsaver') },
							'init'          => \&screensaverInit,
						},
				
						'SETUP_IDLESAVER' => {
							'useMode'       => 'INPUT.Choice',
							'onPlay'        => \&setPref,
							'onAdd'         => \&setPref,
							'onRight'       => \&setPref,
							'pref'          => "idlesaver",
							'header'        => '{SETUP_IDLESAVER}{count}',
							'initialValue'  => sub { return $_[0]->prefGet('idlesaver') },
							'init'          => \&screensaverInit,
						},
					},
				},
			
				'DIGITAL_INPUT'       => {
					'useMode'      => 'INPUT.Choice',
					'listRef'      => [
						{
							name   => '{OFF}',
							value  => 0,
						},
						{
							name   => '{DIGITAL_INPUT_BALANCED_AES}',
							value  => 1,
						},
						{
							name   => '{DIGITAL_INPUT_BNC_SPDIF}',
							value  => 2,
						},
						{
							name   => '{DIGITAL_INPUT_RCA_SPDIF}',
							value  => 3,
						},
						{
							name   => '{DIGITAL_INPUT_OPTICAL_SPDIF}',
							value  => 4,
						},
					],
					'onPlay'       => \&updateDigitalInput,
					'onAdd'        => \&updateDigitalInput,
					'onRight'      => \&updateDigitalInput,
					'header'       => '{DIGITAL_INPUT}{count}',
					'pref'         => 'digitalInput',
					'initialValue' => sub { return $_[0]->prefGet('digitalInput') },
					'condition'    => sub { return $_[0]->isa('Slim::Player::Transporter') },
				},
			},
		},
	);
	
	Slim::Buttons::Home::addMenuOption('SETTINGS', $menuParams{'SETTINGS'});
}

sub updateDigitalInput {
	my $client = shift;
	my $input = shift;

	my $data = pack('C', $input->{'value'});
	$client->prefSet('digitalInput', $input->{'value'});
	$client->sendFrame('audp', \$data);
};

sub setPref {
	my $client = shift;
	my $value = shift;

	# See the hash defines above. 
	if (ref $value eq 'HASH') {
		$value = $value->{'value'};
	}

	my $pref = $client->param('pref');
	
	$client->prefSet($pref,$value);
}

sub executeCommand {
	my $client = shift;
	my $value = shift;

	# See the hash defines above. 
	if (ref $value eq 'HASH') {
		$value = $value->{'value'};
	}

	my $command = $client->param('command');
	my $subcmd  = $client->param('subcommand');

	$client->execute([$command, $subcmd, $value]);
}

sub _fontExists {
	my $client = shift;
	my $index  = shift;

	my $fontname;

	if ($client->display->isa('Slim::Display::Graphics')) {

		$fontname = $client->display->fonts->{'line'}[1];
		$fontname =~ s/(\.2)?//go;

	} else {

		$fontname = $client->textSize ? 'large' : 'small';
	}

	return Slim::Utils::Strings::stringExists($fontname) ? $client->string($fontname) : $fontname;
}

sub screensaverInit {
	my $client = shift;
	
	my %hash  = %{&Slim::Buttons::Common::hash_of_savers};
	my @savers;
	
	for (sort keys %hash) {
	
		push @savers, {
			'name'  => "{".$hash{$_}."}",
			'value' => $_,
		};

	}
	
	$client->param('listRef', \@savers);
}

sub settingsMenu {
	my $client = shift;
	
	my @settingsChoices = @defaultSettingsChoices;
	my $menu = $menuParams{'SETTINGS'}{'submenus'};

	for my $setting ( keys %{$menu}) {

		if ($menu->{$setting}->{'condition'} && &{$menu->{$setting}->{'condition'}}($client)) {
			push @settingsChoices, $setting;
		}
	}

	@settingsChoices = sort { $client->string($a) cmp $client->string($b) } @settingsChoices;

	$client->param('listRef', \@settingsChoices);
}

sub volumeValue {
	my ($client,$arg) = @_;
	return ' ('.($arg <= 0 ? $client->string('MUTED') : int($arg/100*40+0.5)).')';
}

1;

__END__
