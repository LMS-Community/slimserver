package Slim::Utils::Prefs;

# $Id$

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::Prefs

=head1 SYNOPSIS

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.demo');

$prefs->set('pref1', 1); or $prefs->pref1(1);

$prefs->get('pref1'); or $prefs->pref1;

$prefs->client($client)->set('clientpref1', 1); or $prefs->client($client)->clientpref1(1);

$prefs->client($client)->get('clientpref1'); or $prefs->client($client)->clientpref1;

$prefs->init({ 'pref1' => 1, 'pref2' => 2 });

$pref->remove( 'pref1' );

$prefs->migrate(1, sub {
	$prefs->set('skin', Slim::Utils::Prefs::OldPrefs->get('skin') );
	1;
});

$prefs->setValidate('int', 'pref1');

$prefs->setChange(\&myCallback, 'pref1');

=head1 DESCRIPTION

Object based preferences supporing multiple namespaces so the server and
each plugin can have their own preference namespace.
Supports both global and client preferences within a namespace.

This implementation stores preferences in YAML files with one YAML file per namespace.
Namespaces of the form 'dir.name' are saved as filename 'name.prefs' in sub directory 'dir'.
Preferences for plugins are expected to be stored in namespaces prefixed by 'plugin.'

=head2 Each preference may be associated with:

=over 4

=item validation function to verify the new value for a preference before setting it

=item on change callback to execute when a preference is set

=back 

=head2 Each namespace supports:

=over 4

=item migration functions to update preferences to a new version number
(each namespace has a global and per client version number)

=back

=head1 METHODS

=cut

use strict;

use Exporter::Lite;
use File::Path qw(mkpath);
use Getopt::Long qw(:config pass_through);
use Storable;

use Slim::Utils::Prefs::Namespace;
use Slim::Utils::Prefs::OldPrefs;
use Slim::Utils::Log;

our @EXPORT = qw(preferences);

my $log   = logger('prefs');

my $path; # path to directory where preferences are stored

my %namespaces;

# we need to check for prefsdir being set on cmdline as we are run before the server parses options
Getopt::Long::GetOptions('prefsdir=s' => \$path);
$::prefsdir = $path;

$path ||= Slim::Utils::OSDetect::dirsFor('prefs');

Slim::Utils::OSDetect->getOS()->migratePrefsFolder($path);

my $prefs = preferences('server');

# File paths need to be prepared in order to correctly read the file system
$prefs->setFilepaths(qw(mediadirs ignoreInAudioScan ignoreInVideoScan ignoreInImageScan playlistdir cachedir librarycachedir coverArt));


=head2 preferences( $namespace )

Returns a prefs object for the namespace $namespace.

It is usual to prefix plugin namespaces with "plugin.", e.g. preferences('plugin.demo').

=cut

sub preferences {
	my $namespace = shift;

	return $namespaces{$namespace} ||= Slim::Utils::Prefs::Namespace->new($namespace, $path);
}

=head2 namespaces( )

Returns an array of all active preference namespaces.

=cut

sub namespaces {
	return [ keys %namespaces ];
}

sub init {
	my $sqlHelperClass = Slim::Utils::OSDetect->getOS()->sqlHelperClass();
	my $default_dbsource = $sqlHelperClass->default_dbsource();
	
	my %defaults = (
		# Server Prefs not settable from web pages
		'bindAddress'           => '127.0.0.1',            # Default MySQL bind address
		'dbsource'              => $default_dbsource,
		'dbusername'            => 'slimserver',
		'dbpassword'            => '',
		'dbhighmem'             => 0,
		'cachedir'              => \&defaultCacheDir,
		'librarycachedir'       => \&defaultCacheDir,
		'securitySecret'        => \&makeSecuritySecret,
		'ignoreDirRE'           => '',
		# My Music menu ordering
		'rank-BROWSE_BY_ARTIST'    => 35,
		'rank-BROWSE_BY_ALBUM'     => 30,
		'rank-BROWSE_BY_GENRE'     => 25,
		'rank-BROWSE_BY_YEAR'      => 20,
		'rank-BROWSE_NEW_MUSIC'    => 15,
		'rank-PLUGIN_RANDOMPLAY'   => 13,
		'rank-BROWSE_MUSIC_FOLDER' => 10,
		'rank-SAVED_PLAYLISTS'     => 5,
		'rank-SEARCH'              => 3,
		# Extras menu ordering
		'rank-PLUGIN_PODCAST'            => 35,
		'rank-PLUGIN_RSSNEWS'            => 30,
		'rank-PLUGIN_SOUNDS_MODULE_NAME' => 25,
		'rank-GAMES'                     => 20,
		# Server Settings - Basic
		'language'              => \&defaultLanguage,
		'mediadirs'             => \&defaultMediaDirs,
		'playlistdir'           => \&defaultPlaylistDir,
		'autorescan'            => 0,
		'autorescan_stat_interval' => 10,
		# Server Settings - Behaviour
		'displaytexttimeout'    => 1,
		'checkVersion'          => 1,
		'checkVersionInterval'	=> 60*60*24,
		# enable auto download of SC updates on Windows only (for now)
		'autoDownloadUpdate'    => sub { Slim::Utils::OSDetect::getOS->canAutoUpdate() },
		'noGenreFilter'         => 0,
		'searchSubString'       => 0,
		'ignoredarticles'       => "The El La Los Las Le Les",
		'splitList'             => ';',
		'browseagelimit'        => 100,
		'groupdiscs'            => 1,
		'persistPlaylists'      => 1,
		'playtrackalbum'        => 1,
		'reshuffleOnRepeat'     => 0,
		'saveShuffled'          => 0,
		'composerInArtists'     => 0,
		'conductorInArtists'    => 0,
		'bandInArtists'         => 0,
		'variousArtistAutoIdentification' => 1,
		'useBandAsAlbumArtist'  => 0,
		'useTPE2AsAlbumArtist'  => 0,
		'variousArtistsString'  => undef,
		'ratingImplementation'  => 'LOCAL_RATING_STORAGE',
		# Server Settings - FileTypes
		'disabledextensionsaudio'    => '',
		'disabledextensionsvideo'    => '',
		'disabledextensionsimages'   => '',
		'disabledextensionsplaylist' => '',
		'disabledformats'       => [],
		'ignoreInAudioScan'     => [],
		'ignoreInVideoScan'     => [],
		'ignoreInImageScan'     => [],
		# Server Settings - Networking
		'webproxy'              => \&Slim::Utils::OSDetect::getProxy,
		'httpport'              => 9000,
		'bufferSecs'            => 3,
		'remotestreamtimeout'   => 15,
		'maxWMArate'            => 9999,
		'tcpConnectMaximum'	    => 30,             # not on web page
		'udpChunkSize'          => 1400,           # only used for Slimp3
		# Server Settings - Performance
		'disableStatistics'     => 0,
		'serverPriority'        => '',
		'scannerPriority'       => 0,
		'precacheArtwork'       => 1,
		'customArtSpecs'        => {},
		'maxPlaylistLength'     => 500,
		# Server Settings - Security
		'filterHosts'           => 0,
		'allowedHosts'          => sub {
			require Slim::Utils::Network;
			return join(',', Slim::Utils::Network::hostAddr());
		},
		'csrfProtectionLevel'   => 0,
		'authorize'             => 0,
		'username'              => '',
		'password'              => '',
		# Server Settings - TextFormatting
		'longdateFormat'        => q(%A, %B |%d, %Y),
		'shortdateFormat'       => q(%m/%d/%Y),
		'timeFormat'            => q(|%I:%M %p),
		'showArtist'            => 0,
		'showYear'              => 0,
		'guessFileFormats'	    => [
									'(ARTIST - ALBUM) TRACKNUM - TITLE',
									'/ARTIST/ALBUM/TRACKNUM - TITLE',
									'/ARTIST/ALBUM/TRACKNUM TITLE',
									'/ARTIST/ALBUM/TRACKNUM. TITLE'
								   ],
		'titleFormat'		    => [
									'TITLE',
									'DISC-TRACKNUM. TITLE',
									'TRACKNUM. TITLE',
									'TRACKNUM. ARTIST - TITLE',
									'TRACKNUM. TITLE (ARTIST)',
									'TRACKNUM. TITLE - ARTIST - ALBUM',
									'TRACKNUM. TITLE from ALBUM by ARTIST',
									'TITLE (ARTIST)',
									'ARTIST - TITLE'
								   ],
		'titleFormatWeb'        => 0,
		# Server Settings - UserInterface
		'skin'                  => 'Default',
		'itemsPerPage'          => 50,
		'refreshRate'           => 30,
		'coverArt'              => '',
		'artfolder'             => '',
		'thumbSize'             => 100,
		# Server Settings - jive UI
		'jivealbumsort'		=> 'album',
		'defeatDestructiveTouchToPlay' => 4, # 4 => defeat only if playing and current item not a radio stream
		# Server Settings - mysqueezebox.com
		'sn_sync'               => 1,
		'sn_disable_stats'		=> 1,
		# Bug 5557, disable UPnP support by default
		'noupnp'                => 1,
	);

	# we can have different defaults depending on the OS 
	Slim::Utils::OSDetect::getOS->initPrefs(\%defaults);
	
	# add entry to dispatch table if it is loaded (it isn't in scanner.pl) as migration may call notify for this
	# this is required as Slim::Control::Request::init will not have run at this point
	if (exists &Slim::Control::Request::addDispatch) {
		Slim::Control::Request::addDispatch(['prefset', '_namespace', '_prefname', '_newvalue'], [0, 0, 1, undef]);
	}

	if ( !main::SLIM_SERVICE ) {
		# migrate old prefs across
		$prefs->migrate(1, sub {
			unless (-d $path) { mkdir $path; }
			unless (-d $path) { logError("can't create new preferences directory at $path"); }

			for my $pref (keys %defaults) {
				my $old = Slim::Utils::Prefs::OldPrefs->get($pref);

				# bug 7237: don't migrate dbsource if we're upgrading from SS6.3
				next if $pref eq 'dbsource' && $old && $old =~ /SQLite/i;

				$prefs->set($pref, $old) if !$prefs->exists($pref) && defined $old;
			}

			1;
		});
	}
	
	unless (-d $path && -w $path) {
		logError("unable to write to preferences directory $path");
	}
	
	# rank of Staff Picks has changed
	$prefs->migrate( 2, sub {
		$prefs->set( 'rank-PLUGIN_PICKS_MODULE_NAME' => 25 );
	} );

	if ( !main::SLIM_SERVICE ) {
		# migrate old preferences to new client preferences
		$prefs->migrateClient(1, sub {
			my ($clientprefs, $client) = @_;

			my @migrate = qw(
							 alarmfadeseconds alarm alarmtime alarmvolume alarmplaylist
							 powerOnresume lame maxBitrate lameQuality
							 synchronize syncVolume syncPower powerOffDac disableDac transitionType transitionDuration digitalVolumeControl
							 mp3SilencePrelude preampVolumeControl digitalOutputEncoding clockSource polarityInversion wordClockOutput
							 replayGainMode mp3StreamingMethod
							 playername titleFormat titleFormatCurr playingDisplayMode playingDisplayModes
							 screensaver alarmsaver idlesaver offsaver screensavertimeout visualMode visualModes
							 powerOnBrightness powerOffBrightness idleBrightness autobrightness
							 scrollMode scrollPause scrollPauseDouble scrollRate scrollRateDouble scrollPixels scrollPixelsDouble
							 activeFont idleFont activeFont_curr idleFont_curr doublesize offDisplaySize largeTextFont
							 irmap disabledirsets
							 power mute volume bass treble pitch repeat shuffle currentSong
							);

			my $toMigrate;

			for my $pref (@migrate) {
				my $old = Slim::Utils::Prefs::OldPrefs->clientGet($client, $pref);
				$toMigrate->{$pref} = $old if defined $old;
			}

			# create migrated version using init as will not call the onchange callbacks
			$clientprefs->init($toMigrate);
		
			1;
		});

		$prefs->migrate( 3, sub {
			
			if ($prefs->exists('cachedir') && $prefs->get('cachedir') =~ /SqueezeCenter/i) {
				
				$prefs->set('cachedir', defaultCacheDir());
				makeCacheDir();
				
			}
			
			1;
		} );
		
		$prefs->migrate( 4, sub {
			$prefs->set('librarycachedir', $prefs->get('cachedir'));
			1;
		} );

		# on Windows we don't provide a means to disable the autoprefs value any longer
		# disable automatic scanning automatically, in case user had been using an earlier beta where it was enabled
		$prefs->migrate( 8, sub {
			if (main::ISWINDOWS && $prefs->get('autorescan')) {
				$prefs->set( autorescan => 0 );
			}
			1;
		} );
	}

	# migrate client prefs to version 2 - sync prefs changed
	$prefs->migrateClient(2, sub {
		my $cprefs = shift;
		my $defaults = $Slim::Player::Player::defaultPrefs;
		$cprefs->set( minSyncAdjust       => $defaults->{'minSyncAdjust'}      ) if (defined $cprefs->get('minSyncAdjust') && $cprefs->get('minSyncAdjust') < 1);
		$cprefs->set( packetLatency       => $defaults->{'packetLatency'}      ) if (defined $cprefs->get('packetLatency') && $cprefs->get('packetLatency') < 1);
		1;
	});

	# migrate menuItem pref so everyone gets the correct menu structure
	$prefs->migrateClient( 3, sub {
		my ( $cprefs, $client ) = @_;
		my $defaults = $Slim::Player::Player::defaultPrefs;
	
		if ( $client->hasDigitalIn ) {
			$defaults = $Slim::Player::Transporter::defaultPrefs;
		}
	
		if ( $client->isa('Slim::Player::Boom') ) {
			$defaults = $Slim::Player::Boom::defaultPrefs;
		}

		if ($defaults && defined $defaults->{menuItem}) {
			# clone for each client
			$cprefs->set( menuItem => Storable::dclone($defaults->{menuItem}) );
		}
		1;
	} );

	# migrate 'play other songs' pref from server to per-player
	$prefs->migrateClient( 4, sub {
		my ( $cprefs, $client ) = @_;
		my $playtrackalbum = preferences('server')->get('playtrackalbum');
	
		# copy server pref as a default client pref
		unless (defined $cprefs->get( 'playtrackalbum' )) {
			$cprefs->set( 'playtrackalbum', $playtrackalbum );
		}
		1;
	} );
	
	# Bug 8690, reset fixed digital volume pref because it now affects analog outputs
	$prefs->migrateClient( 5, sub {
		my ( $cprefs, $client ) = @_;
		my $dvc = $cprefs->get('digitalVolumeControl');
		if ( defined $dvc && $dvc == 0 ) {
			$cprefs->set( digitalVolumeControl => 1 );
			if ( $cprefs->get('volume') > 50 ) {
				$cprefs->set( volume => 50 );
			}
		}
		
		return 1;
	} );

	# migrate old alarm clock prefs into new alarms
	$prefs->migrateClient( 6, sub {
		my ( $cprefs, $client ) = @_;
		
		# Don't migrate if new 'alarms' pref is already here
		if ( $cprefs->get('alarms') ) {
			$cprefs->remove('alarm');
			$cprefs->remove('alarmtime');
			$cprefs->remove('alarmplaylist');
			$cprefs->remove('alarmvolume');
			
			return 1;
		}

		my $alarm    = $cprefs->get('alarm');
		my $time     = $cprefs->get('alarmtime');
		my $playlist = $cprefs->get('alarmplaylist');
		my $volume   = $cprefs->get('alarmvolume');
		
		my @newAlarms;

		my %playlistMap = (
			CURRENT_PLAYLIST => undef,
			'' => undef,
			PLUGIN_RANDOM_TRACK => 'randomplay://track',
			PLUGIN_RANDOM_ALBUM => 'randomplay://album',
			PLUGIN_RANDOM_CONTRIBUTOR => 'randomplay://contributor',
		);

		# Old alarms: day 0 is every day, days 1..7 are mon..sun
		# New alarms: days 0..6 are sun..sat

		# Migrate any alarm that is enabled or has a time that isn't 0
		for (my $day = 0; $day < 8; $day++) {
			if ($alarm->[$day] || $time->[$day]) {
				my $duplicate = 0;
				foreach my $newAlarm (@newAlarms) {
					# Won't get here for day 0
					if ($newAlarm->time == $time->[$day]) {
						if ($newAlarm->day($day % 7)) {
							# Alarm has same time as an everyday alarm.  Ignore.
							$duplicate = 1;
							last;
						} else {
							if (
								(defined $newAlarm->playlist
								&& (defined $playlistMap{$playlist->[$day]} && $newAlarm->playlist eq $playlistMap{$playlist->[$day]})
								|| $newAlarm->playlist eq $playlist->[$day]
								)

								||

								(! defined $newAlarm->playlist
								&& ($playlist->[$day] eq 'CURRENT_PLAYLIST' || $playlist->[$day] eq ''))
							)  {
								# Same as an existing alarm - just add the day to it
								if ($alarm->[$day]) {
									$newAlarm->day($day % 7, 1);
								}
								$duplicate = 1;
								last;
							}
						}
					}
				}

				if (! $duplicate) {
					my $newAlarm = Slim::Utils::Alarm->new($client, $time->[$day]);
					$newAlarm->enabled($alarm->[$day]);
					$newAlarm->everyDay(0);
					if ($day == 0) {
						$newAlarm->everyDay(1);
					} else {
						$newAlarm->day($day % 7, 1);
					}
					if (exists $playlistMap{$playlist->[$day]}) {
						$newAlarm->playlist($playlistMap{$playlist->[$day]});
					} else {
						$newAlarm->playlist($playlist->[$day]);
					}
					push @newAlarms, $newAlarm;
				}
			}
		}

		# Save the new alarms in one batch to avoid calling $alarm->save, which would create an infinite
		# loop when it tried to read prefs (thus causing them to migrate)
		my $prefAlarms = {};
		foreach my $newAlarm (@newAlarms) {
			$prefAlarms->{$newAlarm->id} = $newAlarm->_createSaveable;
		}

		$cprefs->set('alarms', $prefAlarms);
		
		# Remove old alarm prefs
		$cprefs->remove('alarm');
		$cprefs->remove('alarmtime');
		$cprefs->remove('alarmplaylist');
		$cprefs->remove('alarmvolume');

		return 1;
	} );

	if ( !main::SLIM_SERVICE ) {
		# Bug 8555, add Clock as an option to the Boom display options if it currently the previous default
		$prefs->migrateClient( 7, sub {
			my ( $cprefs, $client ) = @_;
			if ( $client->isa('Slim::Player::Boom') ) {
				if ( my $existing = $cprefs->get('playingDisplayModes') ) {
					if (scalar @$existing == 10 && $existing->[0] == 0 && $existing->[-1] == 9) {
						$cprefs->set('playingDisplayModes', [0..10]);
					}
				}
			}
			1;
		} );
		
		# Add Music Stores menu item after Music Services
		$prefs->migrateClient( 8, sub {
			my ( $cprefs, $client ) = @_;
			my $menuItem = $cprefs->get('menuItem');
			
			# Ignore if MUSIC_STORES is already present
			return 1 if grep /MUSIC_STORES/, @{$menuItem};
			
			my $done = 0;
			my $i = 0;
			for my $item ( @{$menuItem} ) {
				$i++;
				if ( $item eq 'MUSIC_SERVICES' ) {
					splice @{$menuItem}, $i, 0, 'MUSIC_STORES';
					$done = 1;
					last;
				}
			}
			
			if ( !$done ) {
				# Just add the item at the end
				push @{$menuItem}, 'MUSIC_STORES';
			}
		
			$cprefs->set( menuItem => $menuItem );
			
			1;
		} );
	}
	
	# migrateClient 9 is in Slim::Player::Player
	
	# Bug 13248, migrate global presets to per-player presets
	# Note this has a bug and does not migrate presets that defaulted from favorites
	# That is handled below in #12
	$prefs->migrateClient( 10, sub {
		my ( $cprefs, $client ) = @_;

		if ( Slim::Utils::Favorites->enabled ) {
			my $fav = Slim::Utils::Favorites->new($client);

			my $uuid    = main::SLIM_SERVICE ? undef : $prefs->get('server_uuid');
			my $presets = [];

			for my $hotkey ( @{ $fav->hotkeys } ) {
				my $preset;
				if ( $hotkey->{used} ) {
					my $item = $fav->entry( $hotkey->{index} );

					my $isRemote = Slim::Music::Info::isRemoteURL( $item->{URL} );

					$preset = {
						URL    => $item->{URL},
						text   => $item->{text},
						type   => $item->{type},
						server => $isRemote ? undef : $uuid,
					};
					$preset->{parser} = $item->{parser} if $item->{parser};
				}
				push @{$presets}, $preset;
			}
			$prefs->client($client)->set( presets => $presets );
		}
		
		1;
	} );
	
	if ( !main::SLIM_SERVICE ) {
		# Bug 13229, migrate menuItem pref so everyone gets the correct menu structure for 7.4
		$prefs->migrateClient( 11, sub {
			my ( $cprefs, $client ) = @_;
			my $defaults = $Slim::Player::Player::defaultPrefs;

			if ( $client->hasDigitalIn ) {
				$defaults = $Slim::Player::Transporter::defaultPrefs;
			}

			if ( $client->isa('Slim::Player::Boom') ) {
				$defaults = $Slim::Player::Boom::defaultPrefs;
			}

			if ($defaults && defined $defaults->{menuItem}) {
				# clone for each client
				$cprefs->set( menuItem => Storable::dclone($defaults->{menuItem}) );
			}
			1;
		} );
	}
	
	# Bug 14406, fill out missing presets from favorites, if necessary
	$prefs->migrateClient( 12, sub {
		my ( $cprefs, $client ) = @_;
		
		if ( Slim::Utils::Favorites->enabled ) {
			my $fav = Slim::Utils::Favorites->new($client);

			my $uuid    = main::SLIM_SERVICE ? undef : $prefs->get('server_uuid');
			my $presets = $cprefs->get('presets') || [];
			
			my $index = 0;
			for my $preset ( @{$presets} ) {
				if ( !$preset ) {
					# Fill in empty preset slot from favorites
					my $item = $fav->entry( $index );
					if ( $item && $item->{URL} ) {
						my $isRemote = Slim::Music::Info::isRemoteURL( $item->{URL} );

						$preset = {
							URL    => $item->{URL},
							text   => $item->{text},
							type   => $item->{type},
							server => $isRemote ? undef : $uuid,
						};
						$preset->{parser} = $item->{parser} if $item->{parser};
					}
				}
				$index++;
			}
			
			$cprefs->set( presets => $presets );
		}
		
		1;
	} );
	
	# add global search to menu if client is still using default menu items
	if ( !main::SLIM_SERVICE ) {
		$prefs->migrateClient( 13, sub {
			my ( $cprefs, $client ) = @_;
			
			my $defaults = $Slim::Player::Player::defaultPrefs;
		
			if ( $client->hasDigitalIn ) {
				$defaults = $Slim::Player::Transporter::defaultPrefs;
			}
		
			if ( $client->isa('Slim::Player::Boom') ) {
				$defaults = $Slim::Player::Boom::defaultPrefs;
			}
	
			if ($defaults && defined $defaults->{menuItem}) {
				
				my @oldDefaults  = grep { $_ !~ /GLOBAL_SEARCH/ } @{ $defaults->{menuItem} };
				my @currentPrefs = @{ $cprefs->get('menuItem') };

				# only replace menu if user didn't customize it
				if ("@oldDefaults" eq "@currentPrefs") {
					$cprefs->set( menuItem => Storable::dclone($defaults->{menuItem}) );
				}
			}
			1;
		} );
	}
	
	# Update scrolling prefs for client-side scrolling
	$prefs->migrateClient( 14, sub {
		my ( $cprefs, $client ) = @_;
		
		if ( $client->isa('Slim::Player::Squeezebox2') ) {
			$cprefs->set( scrollRate         => 0.033 );
			$cprefs->set( scrollRateDouble   => 0.033 );
			$cprefs->set( scrollPixels       => 2 );
			$cprefs->set( scrollPixelsDouble => 3 );
		}
		
		1;
	} );	

	# migrateClient 15 is in Slim::Plugin::DateTime::Plugin

	# initialise any new prefs
	$prefs->init(\%defaults);
	
	# perform OS-specific post-init steps
	Slim::Utils::OSDetect::getOS->postInitPrefs($prefs);

	# set validation functions
	$prefs->setValidate( 'num',   qw(displaytexttimeout browseagelimit remotestreamtimeout screensavertimeout 
									 itemsPerPage refreshRate thumbSize httpport bufferSecs remotestreamtimeout) );
	$prefs->setValidate( 'dir',   qw(cachedir librarycachedir playlistdir artfolder) );
	$prefs->setValidate( 'array', qw(guessFileFormats titleFormat disabledformats) );

	# allow users to set a port below 1024 on windows which does not require admin for this
	my $minP = main::ISWINDOWS ? 1 : 1024;
	$prefs->setValidate({ 'validator' => 'intlimit', 'low' => $minP,'high'=>  65535 }, 'httpport'    );
	
	$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    3, 'high' =>    30 }, 'bufferSecs'  );
	$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    1, 'high' =>  4096 }, 'udpChunkSize');
	$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    1,                 }, 'itemsPerPage');
	$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    2,                 }, 'refreshRate' );
	$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>   25, 'high' =>   250 }, 'thumbSize'   );
	$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    0,                 }, 'startDelay'  );
	$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    0,                 }, 'playDelay'   );
	$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    0, 'high' =>  1000 }, 'packetLatency');
	$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>   10, 'high' =>  1000 }, 'minSyncAdjust');

	$prefs->setValidate({ 'validator' => sub { $_[1] ne '' } }, 'playername');

	$prefs->setValidate({ 'validator' => sub {
											!$_[1]				# covers undefined, 0 or '' cases
											|| ($_[1] =~ /^\d+$/ && $_[1] >= 10)
										}
						}, 'maxPlaylistLength');

	$prefs->setValidate({
		validator => sub {
			foreach (split (/,/, $_[1])) {
				s/\s*//g; 

				next if Slim::Utils::Network::ip_is_ipv4($_);

				# allow ranges à la "192.168.0.1-50"
				if (/(.+)-(\d+)$/) {
					next if Slim::Utils::Network::ip_is_ipv4($1);
				}

				# 192.168.0.*
				s/\*/0/g;
				next if Slim::Utils::Network::ip_is_ipv4($_);
							
				return 0;
			}

			return 1;
		}
	}, 'allowedHosts');

	$prefs->setValidate({ 'validator' => 'intlimit', 'low' => 0, 'high' => 100 }, 'alarmDefaultVolume');
	$prefs->setValidate({ 'validator' => 'intlimit', 'low' => 1                }, 'alarmSnoozeSeconds');
	$prefs->setValidate({ 'validator' => 'intlimit', 'low' => 0                }, 'alarmTimeoutSeconds');

	$prefs->setValidate({
		validator => sub {
						if ($_[1] =~ /.+\.([^.]+)$/) {
							my $suffix = $1;
	
							return grep(/^$suffix$/, qw(jpg gif png jpeg));
					
						} else {
							return 1;
						}
					}
		}, 'coverArt',
	);
	
	# mediadirs must be a list of unique, valid folders
	$prefs->setValidate({
		validator => sub {
			my $new = $_[1];
			return 0 if ref $new ne 'ARRAY';

			# don't accept duplicate entries
			my %seen;
			return 0 if scalar ( grep { !$seen{$_}++ } @{$new} ) != scalar @$new;
			
			foreach (@{ $new }) {
				if (! (-d $_ || (main::ISWINDOWS && -d Win32::GetANSIPathName($_)) || -d Slim::Utils::Unicode::encode_locale($_)) ) {
					return 0;
				}
			}

			return 1;
		}
	}, 'mediadirs', 'ignoreInAudioScan', 'ignoreInVideoScan', 'ignoreInImageScan');

	# set on change functions
	$prefs->setChange( \&Slim::Web::HTTP::adjustHTTPPort, 'httpport' );
	
	if ( !main::SLIM_SERVICE ) {
		# All languages are always loaded on SN
		$prefs->setChange( sub { Slim::Utils::Strings::setLanguage($_[1]) }, 'language' );

		$prefs->setChange( 
			sub { Slim::Control::Request::executeRequest(undef, ['wipecache']) },
			qw(splitList groupdiscs useTPE2AsAlbumArtist)
		);
	
		$prefs->setChange( sub { Slim::Utils::Misc::setPriority($_[1]) }, 'serverPriority');
	
		$prefs->setChange( sub {
			Slim::Utils::Text::clearCaseArticleCache();
			Slim::Control::Request::executeRequest(undef, ['wipecache'])
		}, 'ignoredarticles');
	
		if ( !Slim::Utils::OSDetect::isSqueezeOS() ) {
			$prefs->setChange( \&Slim::Utils::Update::checkVersion, 'checkVersion' );

			if ( !main::SCANNER ) {
				$prefs->setChange( sub {
					return if Slim::Music::Import->stillScanning;
					
					my $newValues = $_[1];
					my $oldValues = $_[3];

					my @new = grep {
						!defined $oldValues->{$_};
					} keys %$newValues;

					# trigger artwork scan if we've got a new specification only
					if ( scalar @new ) {
						require Slim::Music::Artwork;
						
						Slim::Music::Import->setIsScanning('PRECACHEARTWORK_PROGRESS');
						Slim::Music::Artwork->precacheAllArtwork(sub {
							Slim::Music::Import->setIsScanning(0);
						}, 1);
					}
				}, 'customArtSpecs');
			}
		}

		if ( !main::SCANNER ) {
			$prefs->setChange( sub {
				my $newValues = $_[1];
				my $oldValues = $_[3];
				
				my %new = map { $_ => 1 } @$newValues;
		
				# get old paths which no longer exist:
				my @old = grep {
					delete $new{$_} != 1;
				} @$oldValues;
				
				# in order to get rid of stale entries trigger full rescan if path has been removed
				if (scalar @old) {
					main::INFOLOG && logger('scan.scanner')->info('removed folder from mediadirs - trigger wipecache: ' . Data::Dump::dump(@old));
					Slim::Control::Request::executeRequest(undef, ['wipecache']);
				}
	
				# if only new paths were added, only scan those folders
				else {
					foreach (keys %new) {
						main::INFOLOG && logger('scan.scanner')->info('added folder to mediadirs - trigger rescan of new folder only: ' . $_);
						Slim::Control::Request::executeRequest( undef, [ 'rescan', 'full', Slim::Utils::Misc::fileURLFromPath($_) ] );
					}
				}
			}, 'mediadirs');
	
			$prefs->setChange( sub {
				my $newValues = $_[1];
				my $oldValues = $_[3];
				
				my %old = map { $_ => 1 } @$oldValues;
		
				# get new exclusion paths which did not exist previously:
				my @new = grep {
					delete $old{$_} != 1;
				} @$newValues;
	
				# in order to get rid of stale entries trigger full rescan if path has been added
				if (scalar @new) {
					my %mediadirs = map { $_ => 1 } @{ Slim::Utils::Misc::getMediaDirs() };
	
					if (!scalar grep { $mediadirs{$_} } @new) {
						main::INFOLOG && logger('scan.scanner')->info("added folder to exclusion list which is not in mediadirs yet - don't trigger scan: " . Data::Dump::dump(@new));
					}
					else {
						main::INFOLOG && logger('scan.scanner')->info('added folder to exclusion list - trigger wipecache: ' . Data::Dump::dump(@new));
						Slim::Control::Request::executeRequest(undef, ['wipecache']);
					}
				}
	
				# if only new paths were added, only scan those folders
				else {
					foreach (keys %old) {
						main::INFOLOG && logger('scan.scanner')->info('removed folder from exclusion list - trigger rescan of new folder only: ' . $_);
						Slim::Control::Request::executeRequest( undef, [ 'rescan', 'full', Slim::Utils::Misc::fileURLFromPath($_) ] );
					}
				}
			}, 'ignoreInAudioScan', 'ignoreInVideoScan', 'ignoreInImageScan');
	
			$prefs->setChange( sub {
				require Slim::Music::PlaylistFolderScan;
				Slim::Music::PlaylistFolderScan->init;
				Slim::Control::Request::executeRequest(undef, ['rescan', 'playlists']);
			}, 'playlistdir');
		
			$prefs->setChange( sub {
				if ($_[1]) {
					Slim::Control::Request::subscribe(\&Slim::Player::Playlist::modifyPlaylistCallback, [['playlist']]);
					for my $client (Slim::Player::Client::clients()) {
						next if Slim::Player::Sync::isSlave($client);
						my $request = Slim::Control::Request->new($client, ['playlist','load_done']);
						Slim::Player::Playlist::modifyPlaylistCallback($request);
					}
				} else {
					Slim::Control::Request::unsubscribe(\&Slim::Player::Playlist::modifyPlaylistCallback);
				}
			}, 'persistPlaylists');
	
			# Rebuild Jive cache if VA setting is changed
			$prefs->setChange( sub {
				Slim::Schema->wipeCaches();
			}, 'variousArtistAutoIdentification', 'composerInArtists', 'conductorInArtists', 'bandInArtists');
		}
	}

	$prefs->setChange( sub {
		my $client = $_[2] || return;
		Slim::Player::Transporter::updateClockSource($client);
	}, 'clockSource');

	$prefs->setChange( sub {
		my $client = $_[2] || return;
		Slim::Player::Transporter::updateEffectsLoop($client);
	}, 'fxloopSource');

	$prefs->setChange( sub {
		my $client = $_[2] || return;
		Slim::Player::Transporter::updateEffectsLoop($client);
	}, 'fxloopClock');
	
	$prefs->setChange( sub {
		my $client = $_[2] || return;
		Slim::Player::Transporter::updateRolloff($client);
	}, 'rolloffSlow');

	$prefs->setChange( sub {
		my $client = $_[2] || return;
		if ( $client->display ) {
			$client->display->renderCache()->{'defaultfont'} = undef;
		}
	}, qw(activeFont idleFont activeFont_curr idleFont_curr) );

	$prefs->setChange( sub {
		my $client = $_[2] || return;
		Slim::Player::Boom::setAnalogOutMode($client);
	}, 'analogOutMode');
	
	$prefs->setChange( sub {
		foreach my $client ( Slim::Player::Client::clients() ) {
			if ($client->isa("Slim::Player::Boom")) {
				$client->setRTCTime();
			}		
		}
	}, 'timeFormat');

	# Clear SN cookies from the cookie jar if the session changes
	if ( !main::SLIM_SERVICE ) {
		$prefs->setChange( sub {
			# XXX the sn.com hostnames can be removed later
			my $cookieJar = Slim::Networking::Async::HTTP::cookie_jar();
			$cookieJar->clear( 'www.squeezenetwork.com' );
			$cookieJar->clear( 'www.test.squeezenetwork.com' );
			$cookieJar->clear( 'www.mysqueezebox.com' );
			$cookieJar->clear( 'www.test.mysqueezebox.com' );
			if ( $ENV{SN_DEV} ) {
				$cookieJar->clear( '127.0.0.1' );
			}
			$cookieJar->save();
			main::DEBUGLOG && logger('network.squeezenetwork')->debug( 'SN session has changed, removing cookies' );
		}, 'sn_session' );
		
		$prefs->setChange( sub {
			Slim::Utils::Timers::setTimer(
				$_[1],
				time() + 30,
				sub {
					my $isDisabled = shift;
					my $http = Slim::Networking::SqueezeNetwork->new(sub {}, sub {});
					
					$http->get( $http->url( '/api/v1/stats/mark_disabled/' . $isDisabled ? 1 : 0 ) );					
				},
			);
			
		}, 'sn_disable_stats');
	}

	# Reset IR state if preference change
	$prefs->setChange( sub {
		my $client = $_[2] || return;
		Slim::Hardware::IR::initClient($client);
	}, qw(disabledirsets irmap) );
	
	if ( main::SLIM_SERVICE ) {
		# Update players.name database field if name is changed
		$prefs->setChange( sub {
			my $name   = $_[1] || return;
			my $client = $_[2] || return;
			
			return if $name eq 'nil';
			
			$client->playerData->name( $name );
			$client->playerData->update;
		}, 'playername' );
	}
}

=head2 writeAll( )

Write all pending preference changes to disk.

=cut

sub writeAll {
	for my $n (values %namespaces) {
		$n->savenow;
	}
}

=head2 dir( )

Returns path to preference files.

=cut

sub dir {
	return $path;
}

=head2 SEE ALSO

L<Slim::Utils::Prefs::Base>
L<Slim::Utils::Prefs::Namespace>
L<Slim::Utils::Prefs::Client>
L<Slim::Utils::Prefs::OldPrefs>

=cut


# FIXME - support functions - should these be here?

use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
use Digest::MD5;

sub makeSecuritySecret {
	# each Logitech Media Server installation should have a unique,
	# strongly random value for securitySecret. This routine
	# will be called by the first time the server is started
	# to "seed" the prefs file with a value for this installation

	my $hash = new Digest::MD5;

	$hash->add(rand());

	my $secret = $hash->hexdigest();

	if ($log) {
		main::DEBUGLOG && $log->debug("Creating a securitySecret for this installation.");
	}

	$prefs->set('securitySecret', $secret);

	return $secret;
}

sub defaultLanguage {
	return Slim::Utils::OSDetect->getOS->getSystemLanguage;
}

sub defaultMediaDirs {
	my $audiodir = $prefs->get('audiodir');

	$prefs->remove('audiodir') if $audiodir;
	
	my @mediaDirs;
	
	# if an audiodir had been there before, configure LMS as we did in SBS: audio only
	if ($audiodir) {
		# set mediadirs to the former audiodir
		push @mediaDirs, $audiodir;
		
		# add the audiodir to the list of sources to be ignored by the other scans
		defaultMediaIgnoreFolders('music', $audiodir);
	}
	
	# new LMS installation: default to all media folders
	else {
		# try to find the OS specific default folders for various media types
		foreach my $medium ('music', 'videos', 'pictures') {
			my $path = Slim::Utils::OSDetect::dirsFor($medium);
			
			main::DEBUGLOG && $log && $log->debug("Setting default path for medium '$medium' to '$path' if available.");
			
			if ($path && -d $path) {
				push @mediaDirs, $path;
				
				# ignore media from other media's scan
				defaultMediaIgnoreFolders($medium, $path);
			}
		}
	}
	
	return \@mediaDirs;
}

# when using default folders for a given media type, exclude it from other media's scans
sub defaultMediaIgnoreFolders {
	my ($type, $dir) = @_;

	my %ignoreDirs = (
		music    => ['ignoreInVideoScan', 'ignoreInImageScan'],
		videos   => ['ignoreInAudioScan', 'ignoreInImageScan'],
		pictures => ['ignoreInVideoScan', 'ignoreInAudioScan'],
	);

	foreach ( @{ $ignoreDirs{$type} } ) {
		my $ignoreDirs = $prefs->get($_) || [];
		
		push @$ignoreDirs, $dir;
		$prefs->set($_, $ignoreDirs);
	}				
}

sub defaultPlaylistDir {
	my $path = Slim::Utils::OSDetect::dirsFor('playlists');

	if ($path) {

		# We've seen people have the defaultPlayListDir be a file. So
		# change the path slightly to allow for that.
		if (-f $path) {
			$path .= 'Squeezebox';
		}

		if (!-d $path) {
			mkpath($path) or msg("Couldn't create playlist path: $path - $!\n");
		}
	}

	return $path;
}

sub defaultCacheDir {
	my $CacheDir = Slim::Utils::OSDetect::dirsFor('cache');

	my @CacheDirs = splitdir($CacheDir);
	pop @CacheDirs;

	my $CacheParent = catdir(@CacheDirs);

	if ((!-e $CacheDir && !-w $CacheParent) || (-e $CacheDir && !-w $CacheDir)) {
		$CacheDir = undef;
	}
	
	return $CacheDir;
}

sub makeCacheDir {
	my $cacheDir = shift || $prefs->get('cachedir') || defaultCacheDir();

	if (defined $cacheDir && !-d $cacheDir) {

		mkpath($cacheDir) or do {

			logBacktrace("Couldn't create cache dir for $cacheDir : $!");
			return;
		};
	}
}

sub homeURL {
	require Slim::Utils::Network;
	
	my $host = $main::httpaddr || Slim::Utils::Network::hostname() || '127.0.0.1';
	my $port = $prefs->get('httpport');

	return "http://$host:$port/";
}

sub maxRate {
	my $client   = shift || return 0;
	my $soloRate = shift;

	# The default for a new client will be undef.
	my $rate     = $prefs->client($client)->get('maxBitrate');

	if (!defined $rate) {

		# Possibly the first time this pref has been accessed
		# if maxBitrate hasn't been set yet, allow wired squeezeboxen and ALL SB2's to default to no limit, others to 320kbps
		if ($client->isa("Slim::Player::Squeezebox2")) {

			$rate = 0;

		} elsif ($client->isa("Slim::Player::Squeezebox") && !defined $client->signalStrength()) {

			$rate = 0;

		} else {

			$rate = 320;
		}
	}

	# override the saved or default bitrate if a transcodeBitrate has been set via HTTP parameter
	$rate = $prefs->client($client)->get('transcodeBitrate') || $rate;

	if ($soloRate) {
		return $rate;
	}

	if ( $rate != 0 && logger('player.source')->is_debug ) {
		main::DEBUGLOG && logger('player.source')->debug(sprintf("Setting maxBitRate for %s to: %d", $client->name, $rate));
	}
	
	# if we're the master, make sure we return the lowest common denominator bitrate.
	my @playergroup = ($client->syncGroupActiveMembers());
	
	for my $everyclient (@playergroup) {

		my $otherRate = maxRate($everyclient, 1);
		
		# find the lowest bitrate limit of the sync group. Zero refers to no limit.
		$rate = ($otherRate && (($rate && $otherRate < $rate) || !$rate)) ? $otherRate : $rate;
	}

	# return lowest bitrate limit.
	return $rate;
}

1;

__END__
