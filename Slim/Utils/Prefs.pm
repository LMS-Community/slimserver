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

my $DEFAULT_DBSOURCE = 'dbi:mysql:hostname=127.0.0.1;port=9092;database=%s';

my $log   = logger('prefs');

my $path; # path to directory where preferences are stored

my %namespaces;

# we need to check for prefsdir being set on cmdline as we are run before the server parses options
Getopt::Long::GetOptions('prefsdir=s' => \$path);

$path ||= Slim::Utils::OSDetect::dirsFor('prefs');

my $prefs = preferences('server');


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
	my %defaults = (
		# Server Prefs not settable from web pages
		'bindAddress'           => '127.0.0.1',            # Default MySQL bind address
		'dbsource'              => $DEFAULT_DBSOURCE,
		'dbusername'            => 'slimserver',
		'dbpassword'            => '',
		'cachedir'              => \&defaultCacheDir,
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
		# Internet Radio menu ordering
		'rank-PLUGIN_PICKS_MODULE_NAME'            => 25,
		'rank-PLUGIN_RADIOIO_MODULE_NAME'          => 20,
		'rank-PLUGIN_RADIOTIME_MODULE_NAME'        => 15,
		'rank-PLUGIN_LIVE365_MODULE_NAME'          => 10,
		'rank-PLUGIN_SHOUTCASTBROWSER_MODULE_NAME' => 5,
		# Music Services menu ordering
		'rank-PLUGIN_PANDORA_MODULE_NAME'         => 25,
		'rank-PLUGIN_RHAPSODY_DIRECT_MODULE_NAME' => 20,
		'rank-PLUGIN_SLACKER_MODULE_NAME'         => 15,
		'rank-PLUGIN_MP3TUNES_MODULE_NAME'        => 10,
		'rank-PLUGIN_LMA_MODULE_NAME'             => 5,
		# Extras menu ordering
		'rank-PLUGIN_PODCAST'                     => 35,
		'rank-PLUGIN_RSSNEWS'                     => 30,
		'rank-PLUGIN_SOUNDS_MODULE_NAME'          => 25,
		'rank-GAMES'                              => 20,
		# Server Settings - Basic
		'language'              => 'EN',
		'audiodir'              => \&defaultAudioDir,
		'playlistdir'           => \&defaultPlaylistDir,
		# Server Settings - Behaviour
		'displaytexttimeout'    => 1,
		'checkVersion'          => 1,
		'checkVersionInterval'	=> 60*60*24,
		'noGenreFilter'         => 0,
		'searchSubString'       => 0,
		'ignoredarticles'       => "The El La Los Las Le Les",
		'splitList'             => '',
		'browseagelimit'        => 100,
		'groupdiscs'            => 0,
		'persistPlaylists'      => 1,
		'playtrackalbum'        => 1,
		'reshuffleOnRepeat'     => 0,
		'saveShuffled'          => 0,
		'composerInArtists'     => 0,
		'conductorInArtists'    => 0,
		'bandInArtists'         => 0,
		'variousArtistAutoIdentification' => 0,
		'useBandAsAlbumArtist'  => 0,
		'variousArtistsString'  => undef,
		# Server Settings - FileTypes
		'disabledextensionsaudio'    => '',
		'disabledextensionsplaylist' => '',
		'disabledformats'       => [],
		# Server Settings - Networking
		'webproxy'              => \&Slim::Utils::OSDetect::getProxy,
		'httpport'              => 9000,
		'bufferSecs'            => 3,
		'remotestreamtimeout'   => 5,
		'maxWMArate'            => 9999,
		'tcpConnectMaximum'	    => 30,             # not on web page
		'udpChunkSize'          => 1400,           # only used for Slimp3
		'mDNSname'              => 'SqueezeCenter',
		# Server Settings - Performance
		'disableStatistics'     => 0,
		'serverPriority'        => '',
		'scannerPriority'       => 0,
		# Server Settings - Security
		'filterHosts'           => 0,
		'allowedHosts'          => sub { join(',', Slim::Utils::Network::hostAddr()) },
		'csrfProtectionLevel'   => 1,
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
									'FILE.EXT',
									'TRACKNUM. TITLE from ALBUM by ARTIST',
									'TITLE (ARTIST)',
									'ARTIST - TITLE'
								   ],
		'titleFormatWeb'        => 1,
		# Server Settings - UserInterface
		'skin'                  => 'Default',
		'itemsPerPage'          => 50,
		'refreshRate'           => 30,
		'coverArt'              => '',
		'artfolder'             => '',
		'thumbSize'             => 100,
		# Server Settings - SqueezeNetwork
		'sn_sync'               => 1,
	);

	# add entry to dispatch table if it is loaded (it isn't in scanner.pl) as migration may call notify for this
	# this is required as Slim::Control::Request::init will not have run at this point
	if (exists &Slim::Control::Request::addDispatch) {
		Slim::Control::Request::addDispatch(['prefset', '_namespace', '_prefname', '_newvalue'], [0, 0, 1, undef]);
	}

	# migrate old prefs across
	$prefs->migrate(1, sub {
		unless (-d $path) { mkdir $path; }
		unless (-d $path) { logError("can't create new preferences directory at $path"); }

		for my $pref (keys %defaults) {
			my $old = Slim::Utils::Prefs::OldPrefs->get($pref);
			$prefs->set($pref, $old) if !$prefs->exists($pref) && defined $old;
		}

		1;
	});
	
	unless (-d $path && -w $path) {
		logError("unable to write to preferences directory $path");
	}
	
	# rank of Staff Picks has changed
	$prefs->migrate( 2, sub {
		$prefs->set( 'rank-PLUGIN_PICKS_MODULE_NAME' => 25 );
	} );

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
						 screensaver idlesaver offsaver screensavertimeout visualMode visualModes
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

	# migrate client prefs to version 2 - sync prefs changed
	$prefs->migrateClient(2, sub {
		my $cprefs = shift;
		my $defaults = $Slim::Player::Player::defaultPrefs;
		$cprefs->set( syncBufferThreshold => $defaults->{'syncBufferThreshold'}) if ($cprefs->get('syncBufferThreshold') > 255);
		$cprefs->set( minSyncAdjust       => $defaults->{'minSyncAdjust'}      ) if ($cprefs->get('minSyncAdjust') < 1);
		$cprefs->set( packetLatency       => $defaults->{'packetLatency'}      ) if ($cprefs->get('packetLatency') < 1);
		1;
	});
	
	# migrate menuItem pref so everyone gets the correct menu structure
	$prefs->migrateClient( 3, sub {
		my ( $cprefs, $client ) = @_;
		my $defaults = $Slim::Player::Player::defaultPrefs;
		
		if ( $client->hasDigitalIn ) {
			$defaults = $Slim::Player::Transporter::defaultPrefs;
		}
		
		$cprefs->set( menuItem => Storable::dclone($defaults->{menuItem}) ); # clone for each client
		1;
	} );
	
	# initialise any new prefs
	$prefs->init(\%defaults);

	# set validation functions
	$prefs->setValidate( 'num',   qw(displaytexttimeout browseagelimit remotestreamtimeout screensavertimeout 
									 itemsPerPage refreshRate thumbSize httpport bufferSecs remotestreamtimeout) );
	$prefs->setValidate( 'dir',   qw(cachedir playlistdir audiodir artfolder) );
	$prefs->setValidate( 'array', qw(guessFileFormats titleFormat disabledformats) );

	# allow users to set a port below 1024 on windows which does not require admin for this
	my $minP = Slim::Utils::OSDetect::OS() eq 'win' ? 1 : 1024;
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
	$prefs->setValidate({ 'validator' => 'intlimit', 'low' =>    1, 'high' =>   255 }, 'syncBufferThreshold');

	# set on change functions
	$prefs->setChange( \&Slim::Web::HTTP::adjustHTTPPort,                              'httpport'    );
	$prefs->setChange( sub { Slim::Utils::Strings::setLanguage($_[1]) },               'language'    );
	$prefs->setChange( \&main::checkVersion,                                           'checkVersion');

	$prefs->setChange( sub { Slim::Control::Request::executeRequest(undef, ['wipecache']) }, qw(splitList groupdiscs) );

	$prefs->setChange( sub {
		Slim::Utils::Text::clearCaseArticleCache();
		Slim::Control::Request::executeRequest(undef, ['wipecache'])
	}, 'ignoredarticles');

	$prefs->setChange( sub {
		Slim::Buttons::BrowseTree->init;
		Slim::Music::MusicFolderScan->init;
		Slim::Control::Request::executeRequest(undef, ['wipecache']);
	}, 'audiodir');

	$prefs->setChange( sub {
		Slim::Music::PlaylistFolderScan->init;
		Slim::Control::Request::executeRequest(undef, ['rescan', 'playlists']);
		for my $client (Slim::Player::Client::clients()) {
			Slim::Buttons::Home::updateMenu($client);
		}
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

	$prefs->setChange( sub {
		my $client = $_[2] || return;
		$client->display->renderCache()->{'defaultfont'} = undef;
	}, qw(activeFont idleFont activeFont_curr idleFont_curr) );

	# Clear SN cookies from the cookie jar if the session changes
	if ( !$ENV{SLIM_SERVICE} ) {
		$prefs->setChange( sub {
			my $cookieJar = Slim::Networking::Async::HTTP::cookie_jar();
			$cookieJar->clear( 'www.squeezenetwork.com' );
			$cookieJar->save();
			logger('network.squeezenetwork')->debug( 'SN session has changed, removing cookies' );
		}, 'sn_session' );
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
	# each SqueezeCenter installation should have a unique,
	# strongly random value for securitySecret. This routine
	# will be called by the first time SqueezeCenter is started
	# to "seed" the prefs file with a value for this installation

	my $hash = new Digest::MD5;

	$hash->add(rand());

	my $secret = $hash->hexdigest();

	if ($log) {
		$log->debug("Creating a securitySecret for this installation.");
	}

	$prefs->set('securitySecret', $secret);

	return $secret;
}

sub defaultAudioDir {
	my $path = Slim::Utils::OSDetect::dirsFor('music');

	if ($path && -d $path) {
		return $path;
	} else {
		return '';
	}
}

sub defaultPlaylistDir {
	my $path = Slim::Utils::OSDetect::dirsFor('playlists');;

	if ($path) {

		# We've seen people have the defaultPlayListDir be a file. So
		# change the path slightly to allow for that.
		if (-f $path) {
			$path .= 'SqueezeCenter';
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
	my $cacheDir = $prefs->get('cachedir') || defaultCacheDir();

	if (defined $cacheDir && !-d $cacheDir) {

		mkpath($cacheDir) or do {

			logBacktrace("Couldn't create cache dir for $cacheDir : $!");
			return;
		};
	}
}

sub homeURL {
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
		logger('player.source')->debug(sprintf("Setting maxBitRate for %s to: %d", $client->name, $rate));
	}
	
	# if we're the master, make sure we return the lowest common denominator bitrate.
	my @playergroup = ($client, Slim::Player::Sync::syncedWith($client));
	
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
