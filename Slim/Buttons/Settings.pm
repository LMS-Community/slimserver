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
use Slim::Buttons::AlarmClock;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Buttons::Information;
use Slim::Buttons::SqueezeNetwork;

if ( !main::SLIM_SERVICE ) {
	require Slim::Networking::Discovery::Server;
}

my $prefs = preferences('server');

# button functions for browse directory
our @defaultSettingsChoices = qw(VOLUME REPEAT SHUFFLE TITLEFORMAT TEXTSIZE SCREENSAVERS);

if ( main::SLIM_SERVICE ) {
	@defaultSettingsChoices = qw(
		LANGUAGE
		TIMEZONE
		SETUP_TIMEFORMAT
		SETUP_LONGDATEFORMAT
		VOLUME
		REPEAT
		SHUFFLE
		TEXTSIZE
		SCREENSAVERS
		SETUP_PLAYER_CODE
	);
	
	require YAML::Syck;
}

our @settingsChoices = ();
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
				},
		
				'BASS'             => {
					'useMode'      => 'INPUT.Bar',
					'header'       => 'BASS',
					'stringHeader' => 1,
					'headerValue'  => 'scaled',
					'mid'          => 50,
					'onChange'     => \&executeCommand,
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
					'initialValue'    => sub { $prefs->client(shift)->get('replayGainMode') },
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
					'pref'         => sub{ return Slim::Player::Playlist::shuffle(shift)},
					'initialValue' => sub{ return Slim::Player::Playlist::shuffle(shift)},
					'command'      => 'playlist',
					'subcommand'   => 'shuffle',
				},
		
				'TITLEFORMAT'      => {
					'useMode'      => 'INPUT.Choice',
					'header'       => '{TITLEFORMAT}{count}',
					'onPlay'       => \&setPref,
					'onAdd'        => \&setPref,
					'onRight'      => \&setPref,
					'pref'         => 'titleFormatCurr',
					'initialValue' => sub { $prefs->client(shift)->get('titleFormatCurr') },
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
					'init'         => sub {
						my $client = shift;

						my @fonts = ();
						my $i        = 0;

						for my $font (@{ $prefs->client($client)->get('activeFont') }) {

							push @fonts, {
								'name'  => $font,
								'value' => $i++
							};
						}

						$client->modeParam('listRef', \@fonts);
					}
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
					'initialValue' => sub { $prefs->client(shift)->get('transitionType') },
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
					'overlayRef'      => sub { return (undef, shift->symbols('rightarrow')) },
					'overlayRefArgs'  => 'C',
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
	
	if ( main::SLIM_SERVICE ) {
		
		# language choices
		my $languageHash       = Slim::Utils::Strings::languageOptions(); # all langs
		my @languageChoices    = ();

		# build array of name value pairs for INPUT.Choice
		for my $key ( sort keys %{$languageHash} ) {

			push @languageChoices, {
				value => $key, 
				name  => $languageHash->{$key}
			};
		}
	
		$menuParams{'SETTINGS'}->{'submenus'}->{'LANGUAGE'} = {
			'useMode'        => 'INPUT.Choice',
			'listRef'        => \@languageChoices,
			'headerArgs'     => 'C',
			'header'         => '{SETUP_LANGUAGE}{count}',
			'pref'           => 'language',
			'initialValue'   => sub { $prefs->client($_[0])->get('language') },
			'onRight'        => sub {
				my ($client, $item) = @_;
				$prefs->client($client)->set('language', $item->{value});
				# Refresh string cache
				$client->display->displayStrings( Slim::Utils::Strings::clientStrings($client) );
			},
		};
		
		my $timezones = YAML::Syck::LoadFile( $main::SN_PATH . "/config/timezones.yml" );
		
		$menuParams{'SETTINGS'}->{'submenus'}->{'TIMEZONE'} = {
			'useMode' => 'INPUT.Choice',
			'listRef' => $timezones,
			'header'  => '{TIMEZONE}{count}',
			'onRight' => sub {
				my ($client, $item) = @_;
				$prefs->client($client)->set('timezone', $item->value);
			},
			'initialValue' => sub {
				my $client = shift;
				
				my $timezone
					=  $prefs->client($client)->get('timezone') 
					|| $client->playerData->userid->timezone;
				
				return $timezone;
			},
			'pref'       => 'timezone',
			'overlayRef' => sub {
				my ($client, $item) = @_;
				my $timezone = $item->value;
				my $returnMe = $client->formatTime($timezone);
				
				my $user_timezone
					=  $prefs->client($client)->get('timezone') 
					|| $client->playerData->userid->timezone;
				
				$returnMe   .= ' ' . Slim::Buttons::Common::checkBoxOverlay( 
					$client, 
					$user_timezone eq $timezone
				);
				return [undef, $returnMe];
			},
		};
		
		# time format choices
		# list copied from Slim::Web::Setup.
		# choices showing seconds removed
		my %timeFormatDetail = (
			q(%H:%M)    => 'hh:mm (24h)',
			q(%H.%M)    => 'hh.mm (24h)',
			q(%H,%M)    => 'hh,mm (24h)',
			q(%Hh%M)    => "hh'h'mm (24h)",
			q(%l:%M %p) => 'h:mm pm (12h)',
			q(%k:%M)    => 'h:mm (24h)',
			q(%k.%M)    => 'h.mm (24h)',
			q(%k,%M)    => 'h,mm (24h)',
			q(%kh%M)    => "h'h'mm (24h)",
		);

		my @timeFormatChoices = keys %timeFormatDetail;
		
		$menuParams{'SETTINGS'}->{'submenus'}->{'SETUP_TIMEFORMAT'} = {
			'useMode'      => 'INPUT.Choice',
			'listRef'      => \@timeFormatChoices,
			'header'       => "{SETUP_TIMEFORMAT}{count}",
			'name'         => sub {
				my ($client, $item) = @_;
				# format current time in current format option
				return $client->timeF(undef, undef, $item) . ' - ' . $timeFormatDetail{$item};
			},
			'onRight'      => sub {
				my ($client, $item) = @_;
				$prefs->client($client)->set('timeFormat',$item);
			},
			'initialValue' => sub { $prefs->client($_[0])->get('timeFormat') },
			'pref'         => 'timeFormat',
		};
		
		my @dateFormatChoices = (
			q(%A, %B %e, %Y),
			q(%a, %b %e, %Y),
			q(%a, %b %e, '%y),
			q(%A, %e %B %Y),
			q(%A, %e. %B %Y),
			q(%a, %e %b %Y),
			q(%a, %e. %b %Y),
			q(%A %e %B %Y),
			q(%A %e. %B %Y),
			q(%a %e %b %Y),
			q(%a %e. %b %Y),
		);
		
		$menuParams{'SETTINGS'}->{'submenus'}->{'SETUP_LONGDATEFORMAT'} = {
			'useMode'     => 'INPUT.Choice',
			'listRef'     => \@dateFormatChoices,
			'header'      => "{SETUP_LONGDATEFORMAT}{count}",
			'name'        => sub {
				my ($client, $item) = @_;
				# format current time in current format option
				return $client->longDateF(undef, undef, $item);
			},
			'onRight'     => sub {
				my ($client, $item) = @_;
				$prefs->client($client)->set('longdateFormat', $item);
			},
			'initialValue' => sub { $prefs->client($_[0])->get('longdateFormat') },
			'pref'         => 'longdateFormat',
		};
		
		
		$menuParams{'SETTINGS'}->{'submenus'}->{'SETUP_PLAYER_CODE'} = {
			'useMode'      => 'INPUT.Choice',
			'listRef'      => [ 'foo' ],
			'name'         => sub {
				my ($client, $item) = @_;
				return sprintf($client->string('SQUEEZENETWORK_PIN'), $client->pin);
			},
			'header'       => '{SQUEEZENETWORK_SIGNUP}',
		};
		
		# Delete menu items we don't want on SN
		delete $menuParams{'SETTINGS'}->{'submenus'}->{'TITLEFORMAT'};
		delete $menuParams{'SETTINGS'}->{'submenus'}->{'REPLAYGAIN'};
	}

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

	my @servers;

	if ( main::SLIM_SERVICE ) {
		@servers = ('SqueezeCenter');
	}
	else {
	 	@servers = keys %{Slim::Networking::Discovery::Server::getServerList()};
		unshift @servers, 'SQUEEZENETWORK';
	}

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

					if ( main::SLIM_SERVICE ) {
						# Connect player back to their last SC
						$client->execute( [ 'connect', 0 ] );
					}
					else {
						$client->execute( [ 'connect', Slim::Networking::Discovery::Server::getServerAddress($server) ] );
					}

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
