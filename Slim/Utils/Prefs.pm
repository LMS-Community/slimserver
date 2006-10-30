package Slim::Utils::Prefs;

# $Id$

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use File::Basename qw(dirname);
use File::Spec::Functions qw(:ALL);
use File::Path;
use File::Slurp;
use FindBin qw($Bin);
use Digest::MD5;
use YAML::Syck qw(DumpFile LoadFile Dump);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Unicode;

our %prefs = ();
my $prefsPath;
my $prefsFile;
my $canWrite;
my $canWriteAtomic = 0;
my $writePending = 0;

our %upgradeScripts = ();
our %DEFAULT = ();
our %prefChange = ();

my $DEFAULT_DBSOURCE = 'dbi:mysql:hostname=127.0.0.1;port=9092;database=%s';

# Prefs is special - we need to be loaded before logging, but use logging later on.
my $log = undef;

sub init {

	# These are scripts that are run once on old prefs file to bring them
	# up-to-date with specific changes we want to push out to default prefs.
	%upgradeScripts = (
		# moves client preferences to a hash under the 'clients' key
		'6.2b1' => sub {
			for my $key (keys %prefs) {
				# clear out any old 'clients' pref
				if (!defined $prefs{'clients'} || ref($prefs{'clients'}) ne "HASH") {
					$prefs{'clients'} = {};
				}

				# move old client preferences to new hash
				if ($key =~ /^((?:[[:xdigit:]]{2}:){5}[[:xdigit:]]{2})-(.+)/) {
					# matched hexidecimal client id (mac address)
					$prefs{'clients'}{$1}{$2} = $prefs{$key};
					CORE::delete($prefs{$key});
				} elsif ($key =~ /^((?:\d{1,3}\.){3}\d{1,3}(?::\d+)?)-(.+)/) {
					# matched ip address (optional port) client id (HTTP client)
					$prefs{'clients'}{$1}{$2} = $prefs{$key};
					CORE::delete($prefs{$key});
				}
			}
		},

		'6.2b1-2005-09-19' => sub {

			# ExBrowse2 went away.
			if ($prefs{'skin'} eq 'ExBrowse2') {
				$prefs{'skin'} = 'ExBrowse3';
			}
		},

		'6.2.1-2005-11-07' => sub {

			# Bug 2410 - We need a better solution for iTunes
			# rescanning, but in the meantime, don't scan every 60
			# seconds. Let the Plugin reset the value.
			if (defined $prefs{'itunesscaninterval'} && $prefs{'itunesscaninterval'} == 60) {
				delete $prefs{'itunesscaninterval'};
			}
		},

		'6.5b1-2006-01-25' => sub {

			if (Slim::Utils::OSDetect::OS() eq 'unix') {
				my $olddb = catdir(Slim::Utils::Prefs::get('cachedir'), '.slimserversql.db');
				my $newdb = catdir(Slim::Utils::Prefs::get('cachedir'), 'slimserversql.db');
				my $oldPref = catdir(preferencesPath(), '.slimserver.pref');
				my $newPref = catdir(preferencesPath(), 'slimserver.pref');

				if (-e $olddb) {
					rename($olddb,$newdb);
				}

				if (-e $oldPref && $prefsFile eq $oldPref) {
					# have loaded old file name at this point, move and change to new name
					rename($oldPref, $newPref);
					$prefsFile = $newPref;
				}
			}
		},
						   
		'6.5b1-2006-02-03' => sub {

			# Update our language list to be in line with ISO 639-1
			my %languages = (
				'CZ' => 'CS',
				'DK' => 'DA',
				'JP' => 'JA',
				'SE' => 'SV',
			);

			my $newLang = $languages{ $prefs{'language'} };

			if (defined $newLang) {
				$prefs{'language'} = $newLang;
			}
		},

		'6.5b1-2006-05-06' => sub {
			#check for empty date time setitngs and set defaults to current formats
			Slim::Utils::Prefs::set('screensaverTimeFormat', Slim::Utils::Prefs::get('timeFormat'))
				unless Slim::Utils::Prefs::get('screensaverTimeFormat');
			Slim::Utils::Prefs::set('screensaverDateFormat', Slim::Utils::Prefs::get('longdateFormat'))
				unless Slim::Utils::Prefs::get('screensaverDateFormat');
		},
	);

	# When adding new server and client preference options, put a default value for the option
	# into the DEFAULT hash.  For client options put the key => value pair in the client hash
	# in the client key of the main hash.
	# If the preference ends in a digit or a # then it will be interpreted as an array preference,
	# so if this is not what you intend, don't end it with a digit or a #
	# Squeezebox G may include several prefs not needed by other players.  For those defaults, use
	# %Slim::Player::Player::GPREFS
	%DEFAULT = (
		"httpport"		=> 9000,
		"audiodir"		=> defaultAudioDir(),
		"playlistdir"		=> defaultPlaylistDir(),
		"cachedir"		=> defaultCacheDir(),
		"securitySecret"	=> makeSecuritySecret(),
		"csrfProtectionLevel"	=> 1,
		"skin"			=> "Default",
		"language"		=> "EN",
		"refreshRate"		=> 30,
		"displaytexttimeout"	=> 1.0,
		'browseagelimit'	=> 100,
		"playtrackalbum"	=> 1,
		"ignoredarticles"	=> "The El La Los Las Le Les",
		"splitList"		=> '',
		"authorize"		=> 0,				# No authorization by default
		"username"		=> '',
		"password"		=> '',
		"filterHosts"		=> 0,				# No filtering by default
		"allowedHosts"		=> join(',', Slim::Utils::Network::hostAddr()),
		"tcpReadMaximum"	=> 20,
		"tcpWriteMaximum"	=> 20,
		"tcpConnectMaximum"	=> 30,
		"streamWriteMaximum"	=> 30,
		'webproxy'		=> '',
		"udpChunkSize"		=> 1400,
		'itemsPerPage'		=> 50,
		'disableStatistics'	=> 0,
		'artfolder'		=> '',
		'coverThumb'		=> '',
		'coverArt'		=> '',
		'thumbSize'		=> 100,
		'itemsPerPass'		=> 5,
		'plugins-onthefly'	=> 0,
		'longdateFormat'	=> q(%A, %B |%d, %Y),
		'shortdateFormat'	=> q(%m/%d/%Y),
		'showYear'		=> 0,
		'timeFormat'		=> q(|%I:%M:%S %p),
		'titleFormatWeb'	=> 1,
		'ignoreDirRE'		=> '',
		'checkVersion'		=> 1,
		'checkVersionInterval'	=> 60*60*24,
		'mDNSname'		=> 'SlimServer',
		'titleFormat'		=> [
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
		'guessFileFormats'	=> [
			'(ARTIST - ALBUM) TRACKNUM - TITLE', 
			'/ARTIST/ALBUM/TRACKNUM - TITLE', 
			'/ARTIST/ALBUM/TRACKNUM TITLE', 
			'/ARTIST/ALBUM/TRACKNUM. TITLE' 
		],
		'disabledplugins'	=> [],
		'enabledfonts'		=> ['small', 'medium', 'large', 'huge'],
		'persistPlaylists'	=> 1,
		'reshuffleOnRepeat'	=> 0,
		'saveShuffled'		=> 0,
		'searchSubString'	=> 0,
		'maxBitrate'		=> 320,
		'composerInArtists'	=> 0,
		'groupdiscs' 		=> 0,
		'remotestreamtimeout'	=> 5, # seconds to try to connect for a remote stream
		'prefsWriteDelay'	=> 30,
		'dbsource'		=> $DEFAULT_DBSOURCE,
		'dbusername'		=> 'slimserver',
		'dbpassword'		=> '',
		'commonAlbumTitles'	=> ['Greatest Hits', 'Best of...', 'Live'],
		'commonAlbumTitlesToggle' => 0,
		'noGenreFilter'		=> 0,
		'variousArtistAutoIdentification' => 0,
		'useBandAsAlbumArtist'  => 0,
		'upgrade-6.2b1-script'	=> 1,
		'upgrade-6.2b1-2005-09-19-script' => 1,
		'upgrade-6.2.1-2005-11-07-script' => 1,
		'upgrade-6.5b1-2006-01-25-script' => 1,
		'upgrade-6.5b1-2006-02-03-script' => 1,
		'upgrade-6.5b1-2006-03-31-script' => 1,
		'rank-PLUGIN_PICKS_MODULE_NAME' => 4,
		'disabledextensionsaudio' => '',
		'disabledextensionsplaylist' => '',
		'serverPriority' => '',
		'scannerPriority' => '0',
		'bufferSecs' => 3,
		'maxWMArate' => 9999,
	);

	# The following hash contains functions that are executed when the pref corresponding to
	# the hash key is changed.  Client specific preferences are contained in a hash stored
	# under the main hash key 'CLIENTPREFS'.
	# The functions expect the parameters $pref and $newvalue for non-client specific functions
	# where $pref is the preference which changed and $newvalue is the new value of the preference.
	# Client specific functions also expect a $client param containing a reference to the client
	# struct.  The param order is $client,$pref,$newvalue.
	%prefChange = (

		'CLIENTPREFS' => {

			'irmap' => sub {
				my ($client,$newvalue) = @_;

				require Slim::Hardware::IR;

				Slim::Hardware::IR::loadMapFile($newvalue);

				if ($newvalue eq Slim::Hardware::IR::defaultMapFile()) {
					Slim::Utils::PluginManager::addDefaultMaps();
				}
			},
		},

		'checkVersion' => sub {
			my $newValue = shift;
			if ($newValue) {
				main::checkVersion();
			}
		},

		'ignoredarticles' => sub {
			Slim::Utils::Text::clearCaseArticleCache();
		},

		'audiodir' => sub {
			my $newvalue = shift;

			Slim::Buttons::BrowseTree->init;
			Slim::Music::MusicFolderScan->init;
		},

		'playlistdir' => sub {
			my $newvalue = shift;

			if ($newvalue && !-d $newvalue) {

				mkpath($newvalue) or do {

					logError("Could't create playlistdir: [$newvalue]");
					return;
				};
			}

			Slim::Music::PlaylistFolderScan->init;

			for my $client (Slim::Player::Client::clients()) {
				Slim::Buttons::Home::updateMenu($client);
			}
		},

		'persistPlaylists' => sub {

			my $newvalue = shift;

			if ($newvalue) {

				Slim::Control::Request::subscribe(
					\&Slim::Player::Playlist::modifyPlaylistCallback, 
					[['playlist']]
					);

				for my $client (Slim::Player::Client::clients()) {
					next if Slim::Player::Sync::isSlave($client);
					
					my $request = Slim::Control::Request->new( 
						$client, 
						['playlist','load_done'],
					);
					Slim::Player::Playlist::modifyPlaylistCallback($request);
				}

			} else {
				Slim::Control::Request::unsubscribe(\&Slim::Player::Playlist::modifyPlaylistCallback);
			}
		},
				   
		'httpport' => sub {
			Slim::Web::HTTP::adjustHTTPPort();
		}
	);
}

# This needs to be run after Logging is initialized.
sub loadLogHandler {

	$log = logger('prefs');
}

sub makeSecuritySecret {
	
	# each SlimServer installation should have a unique,
	# strongly random value for securitySecret. This routine
	# will be called by checkServerPrefs() the first time
	# SlimServer is started to "seed" the prefs file with a
	# value for this installation
	#
	# do we already have a value?
	
	my $currentVal = get('securitySecret');
	
	if (defined($currentVal) && ($currentVal =~ m|^[0-9a-f]{32}$|)) {

		if ($log) {

			$log->debug("Server already has a securitySecret - returning existing");
		}

		return $currentVal;
	}
	
	# make a new value, based on a random number
	
	my $hash = new Digest::MD5;
	
	$hash->add(rand());
	
	# explicitly "set" this so it persists through shutdown/startupa
	my $secret = $hash->hexdigest();

	if ($log) {
		$log->debug("Creating a securitySecret for this installation.");
	}

	set('securitySecret', $secret);

	return $secret;
}

sub defaultAudioDir {
	my $path;

	if (Slim::Utils::OSDetect::OS() eq 'mac') {

		$path = ($ENV{'HOME'} . '/Music');

	} elsif (Slim::Utils::OSDetect::OS() eq 'win') {

		Slim::bootstrap::tryModuleLoad('Win32::Registry');

		if (!$@) {

			my $folder;

			if ($::HKEY_CURRENT_USER->Open("Software\\Microsoft\\Windows"
				   ."\\CurrentVersion\\Explorer\\Shell Folders", $folder)) {

				my ($type, $value);
				if ($folder->QueryValueEx("My Music", $type, $value)) {
					$path = $value;
				} elsif ($folder->QueryValueEx("Personal", $type, $value)) {
					$path = $value . '\\My Music';
				}
			}
		}		
	}

	if ($path && -d $path) {
		return $path;
	} else {
		return '';
	}
}

sub defaultPlaylistDir {
	my $path;

	if (Slim::Utils::OSDetect::OS() eq 'mac') {

		$path = $ENV{'HOME'} . '/Music/Playlists';

	} elsif (Slim::Utils::OSDetect::OS() eq 'win') {

		$path = $Bin . '/Playlists';

	} else {

		$path = '';
	}

	if ($path) {

		# We've seen people have the defaultPlayListDir be a file. So
		# change the path slightly to allow for that.
		if (-f $path) {
			$path .= 'SlimServer';
		}

		if (!-d $path) {
			mkpath($path) or msg("Couldn't create playlist path: $path - $!\n");
		}
	}

	return $path;
}

sub defaultCacheDir {
	my $CacheDir = catdir($Bin,'Cache');

	my $os = Slim::Utils::OSDetect::OS();

	if ($os eq 'mac') {

		$CacheDir = catdir($ENV{'HOME'}, '/Library/Caches/SlimServer');

	} elsif ($os eq 'unix') {

		$CacheDir = catdir($ENV{'HOME'},'Cache');
	}

	my @CacheDirs = splitdir($CacheDir);
	pop @CacheDirs;

	my $CacheParent = catdir(@CacheDirs);

	if ((!-e $CacheDir && !-w $CacheParent) || (-e $CacheDir && !-w $CacheDir)) {
		$CacheDir = undef;
	}

	return $CacheDir;
}

sub makeCacheDir {
	my $cacheDir = get("cachedir") || defaultCacheDir();
	
	if (defined $cacheDir && !-d $cacheDir) {

		mkpath($cacheDir) or do {

			logBacktrace("Couldn't create cache dir for $cacheDir : $!");
			return;
		};
	}
}

sub homeURL {
        my $host = $main::httpaddr || Slim::Utils::Network::hostname() || '127.0.0.1';
        my $port = Slim::Utils::Prefs::get('httpport');

        return "http://$host:$port/";
}

# Some routines to add and remove preference change handlers
sub addPrefChangeHandler {
	my ($pref,$handlerRef,$forClient) = @_;
	if (defined($pref) && ref($handlerRef) eq 'CODE') {
		if ($forClient) {
			$prefChange{'CLIENTPREFS'}{$pref} = $handlerRef;
		} else {
			$prefChange{$pref} = $handlerRef;
		}
	} else {
		warn "Invalid attempt to add a preference change handler.\n" 
			, defined($pref) ? "Invalid code reference supplied.\n" : "No preference supplied.\n";
	}
}

sub removePrefChangeHandler {
	my ($pref,$forClient) = @_;
	if ($forClient) {
		CORE::delete($prefChange{'CLIENTPREFS'}{$pref});
	} else {
		CORE::delete($prefChange{$pref});
	}
}

sub onChange {
	my $key = shift;
	my $value = shift;
	my $ind = shift;
	my $client = shift;
	
	if (defined($client)) {
		if (defined($key) && exists($prefChange{'CLIENTPREFS'}{$key})) {
			&{$prefChange{'CLIENTPREFS'}{$key}}($client,$value, $key, $ind);
		}
	} else {
		if (defined($key) && exists($prefChange{$key})) {
			&{$prefChange{$key}}($value, $key, $ind);
		}
	}
}

# This makes sure all the server preferences defined in %DEFAULT are in the pref file.
# If they aren't there already they are set to the value in %DEFAULT
sub checkServerPrefs {
	for my $key (keys %DEFAULT) {
		if (!defined($prefs{$key})) {
			if (ref($DEFAULT{$key}) eq 'ARRAY') {
				my @temp = @{$DEFAULT{$key}};
				$prefs{$key} = \@temp;
			} elsif (ref($DEFAULT{$key}) eq 'HASH') {
				my %temp = %{$DEFAULT{$key}};
				$prefs{$key} = \%temp;
			} else {
				$prefs{$key} = $DEFAULT{$key};
			}
		} elsif (ref($DEFAULT{$key}) eq 'HASH') {
			# check defaults for individual hash prefs
			for my $subkey (keys %{$DEFAULT{$key}}) {
				if (!defined $prefs{$key}{$subkey}) {
					$prefs{$key}{$subkey} = $DEFAULT{$key}{$subkey};
				}
			}
		}
	}

	# Always Upgrade SQLite to MySQL
	if ($prefs{'dbsource'} =~ /SQLite/) {
		$prefs{'dbsource'} = $DEFAULT_DBSOURCE;
	}

	for my $version (sort keys %upgradeScripts) {

		if (Slim::Utils::Prefs::get("upgrade-$version-script")) {
			&{$upgradeScripts{$version}}();
			Slim::Utils::Prefs::set("upgrade-$version-script", 0);
		}
	}

	# write it out
	writePrefs();
}

# This makes sure all the client preferences defined in the submitted hash are in the pref file.
sub initClientPrefs {
	my $client = shift;
	my $defaultPrefs = shift;
	
	my $prefs = getClientPrefs($client->id());

	for my $key (keys %{$defaultPrefs}) {

		if (!defined($prefs->{$key})) {

			# Take a copy of the default prefs
			if (ref($defaultPrefs->{$key}) eq 'ARRAY') {

				$prefs->{$key} = [ @{$defaultPrefs->{$key}} ];

			} elsif (ref($defaultPrefs->{$key}) eq 'HASH') {

				$prefs->{$key} = { %{$defaultPrefs->{$key}} };

			} elsif (defined($defaultPrefs->{$key})) {

				$prefs->{$key} = $defaultPrefs->{$key};
			}

		} elsif (ref($defaultPrefs->{$key}) eq 'HASH') {

			# check defaults for individual hash prefs
			for my $subkey (keys %{$defaultPrefs->{$key}}) {

				if (!defined $prefs->{$key}{$subkey}) {

					$prefs->{$key}{$subkey} = $defaultPrefs->{$key}{$subkey};
				}
			}
		}
	}

	scheduleWrite() unless $writePending;
}

sub push {
	my $arrayPref = shift;
	my $value     = shift;

	# allow clients to specify the preference hash to modify
	my $prefs     = shift || \%prefs;

	if (!defined($prefs->{$arrayPref})) {

		# auto-vivify
		$prefs->{$arrayPref} = [];
	}

	if (ref($prefs->{$arrayPref}) eq 'ARRAY') {

		CORE::push(@{$prefs->{$arrayPref}}, $value);

	} else {

		logBacktrace("Attempted to push a value onto a scalar pref!");
	}

	scheduleWrite() unless $writePending;
}

sub clientPush {
	my $client = shift;
	my $arrayPref = shift;
	my $value = shift;
	$client->prefPush($arrayPref,$value);
}

# getArrayMax($arrayPref)
sub getArrayMax{
	my $arrayPref = shift;
	if (defined($prefs{$arrayPref}) && ref($prefs{$arrayPref}) eq 'ARRAY') {
		my @prefArray = @{$prefs{$arrayPref}};
		my $max = $#prefArray;
		return $max;
	} else {
		return undef;
	}
}
# clientGetArrayMax($client, $arrayPref)
sub clientGetArrayMax {
	my $client = shift;
	my $arrayPref = shift;
	assert($client);
	return $client->prefGetArrayMax($arrayPref);
}

# getArray($arrayPref)
sub getArray {
	my $arrayPref = shift;
	if (defined($prefs{($arrayPref)}) && ref($prefs{$arrayPref}) eq 'ARRAY') {
		return @{$prefs{($arrayPref)}};
	} else {
		return ();
	}
}

# clientGetArray($client, $arrayPref)
sub clientGetArray {
	my $client = shift;
	my $arrayPref = shift;
	assert($client);
	return $client->prefGetArray($arrayPref);
}

# getClientPrefs($clientid)
# returns a reference to the hash of client preferences for the client with the id provided
# creates an empty hash if none currently exists.
sub getClientPrefs {
	my $clientid = shift;
	
	if (!defined $prefs{'clients'}{$clientid} || ref($prefs{'clients'}{$clientid}) ne "HASH") {

		$prefs{'clients'}{$clientid} = {};
	}
	
	return $prefs{'clients'}{$clientid};
}

# get($pref)
sub get { 
	return $prefs{$_[0]};
}

# getIjd($pref,$index)
# for indexed (array or hash) prefs
sub getInd {
	my ($pref,$index) = @_;

	if (defined $prefs{$pref}) {

		if (ref $prefs{$pref} eq 'ARRAY') {

			return $prefs{$pref}[$index];

		} elsif (ref $prefs{$pref} eq 'HASH') {

			return $prefs{$pref}{$index};
		}
	}

	return undef;
}

# getKeys($pref)
# gets the keys of a hash pref
sub getKeys {
	my $hashPref = shift;

	if (defined($prefs{$hashPref}) && ref($prefs{$hashPref}) eq 'HASH') {

		return keys %{$prefs{$hashPref}};

	} else {

		return ();
	}
}

# getHash($pref)
sub getHash {
	my $hashPref = shift;

	if (defined($prefs{($hashPref)}) && ref($prefs{$hashPref}) eq 'HASH') {

		return %{$prefs{($hashPref)}};

	} else {

		return ();
	}
}

# clientGetKeys($client, $hashPref)
sub clientGetKeys {
	my $client = shift;
	my $hashPref = shift;

	assert($client);

	return $client->prefGetKeys($hashPref);
}
	
# clientGetHash($client, $hashPref)
sub clientGetHash {
	my $client   = shift;
	my $hashPref = shift;

	assert($client);

	return $client->prefGetHash($hashPref);
}
	
# clientGet($client, $pref [,$ind])
sub clientGet {
	my $client = shift;
	my $key = shift;
	my $ind = shift;

	if (!defined($client)) {

		$log->logBacktrace("Undefined client!");

		return undef;
	}

	return $client->prefGet($key,$ind);
}

sub getDefault {
	my $key = shift;
	my $ind = shift;

	if (defined($ind)) {

		if (defined $DEFAULT{$key}) {

			if (ref $DEFAULT{$key} eq 'ARRAY') {

				return $DEFAULT{$key}[$ind];

			} elsif (ref $DEFAULT{$key} eq 'HASH') {

				return $DEFAULT{$key}{$ind};
			}
		}
	}

	return $DEFAULT{$key};
}

sub set {
	my $key   = shift || return;
	my $value = shift;
	my $ind   = shift;

	# allow clients to specify the preference hash to modify
	my $client = shift;
	my $prefsRef = shift || \%prefs;
	
	my $oldvalue;

	# We always want to write out just bytes to the pref file, so turn off
	# the UTF8 flag.
	$value = Slim::Utils::Unicode::utf8off($value);

	if (defined $ind) {

		if (defined $prefsRef->{$key}) {
			if (ref $prefsRef->{$key} eq 'ARRAY') {
				if (defined($prefsRef->{$key}[$ind]) && defined($value) && $value eq $prefsRef->{$key}[$ind]) {
						return $value;
				}

				$oldvalue = $prefsRef->{$key}[$ind];
				$prefsRef->{$key}[$ind] = $value;
			} elsif (ref $prefsRef->{$key} eq 'HASH') {
				if (defined($prefsRef->{$key}{$ind}) && defined($value) && $value eq $prefsRef->{$key}{$ind}) {
						return $value;
				}

				$oldvalue = $prefsRef->{$key}{$ind};
				$prefsRef->{$key}{$ind} = $value;
			}
		} elsif ( $ind =~ /\D/ ) {
			# Setting hash pref where no keys currently exist
			$prefsRef->{$key}{$ind} = $value;
		} else {
			# Setting array pref where no indexes currently exist
			$prefsRef->{$key}[$ind] = $value;
		}

	} elsif ($key =~ /(.+?)(\d+)$/) { 

		# trying to set a member of an array pref directly
		# re-call function the correct way
		return set($1,$value,$2,$client,$prefsRef);

	} else {

		if (defined($prefsRef->{$key}) && defined($value) && $value eq $prefsRef->{$key}) {
				return $value;
		}

		$oldvalue = $prefsRef->{$key};
		$prefsRef->{$key} = $value;
	}

	onChange($key, $value, $ind, $client);

	# must mark $ind as defined or indexed prefs cause an error in this msg
	if (defined $ind) {

		if ($log) {
			$log->debug(sprintf("Setting prefs $key $ind to " . ((defined $value) ? $value : "undef")));
		}

	} else {

		if ($log) {
			$log->debug(sprintf("Setting prefs $key to " . ((defined $value) ? $value : "undef")));
		}
	}

	if (!$writePending) {
		scheduleWrite();
	}

	return $oldvalue;
}

sub setArray {
	my $key   = shift;
	my $value = shift;
	
	my $oldvalue = $prefs{$key};
	
	$prefs{$key} = $value;
	
	onChange($key, $value);

	if ($log) {
		$log->debug(sprintf("%s => %s", $key, Data::Dump::dump($value)));
	}

	if (!$writePending) {
		scheduleWrite();
	}

	return $oldvalue;
}

sub maxRate {
	my $client   = shift || return 0;
	my $soloRate = shift;

	# The default for a new client will be undef.
	my $rate     = $client->prefGet('maxBitrate');

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
	$rate = $client->prefGet('transcodeBitrate') || $rate;

	if ($soloRate) {
		return $rate;
	}

	if ($rate != 0) {
		logger('player.source')->debug(sprintf("Setting maxBitRate for %s to: %d", $client->name, $rate));
	}
	
	# if we're the master, make sure we return the lowest common denominator bitrate.
	my @playergroup = ($client, Slim::Player::Sync::syncedWith($client));
	
	for my $everyclient (@playergroup) {

		if ($everyclient->prefGet('silent')) {
			next;
		}

		my $otherRate = maxRate($everyclient, 1);
		
		# find the lowest bitrate limit of the sync group. Zero refers to no limit.
		$rate = ($otherRate && (($rate && $otherRate < $rate) || !$rate)) ? $otherRate : $rate;
	}

	# return lowest bitrate limit.
	return $rate;
}

sub delete {
	my $key = shift;
	my $ind = shift;

	# allow clients to specify the preference hash to modify
	my $prefs = shift || \%prefs;
	
	if (!defined $prefs->{$key}) {
		return;
	}
	if (defined($ind)) {
		if (ref($prefs->{$key}) eq 'ARRAY') {
			splice(@{$prefs->{$key}},$ind,1);
		} elsif (ref($prefs->{$key}) eq 'HASH') {
			CORE::delete $prefs->{$key}{$ind};
		}
	} elsif ($key =~ /(.+?)(\d+)$/) { 
		#trying to delete a member of an array pref directly
		#re-call function the correct way
		Slim::Utils::Prefs::delete($1,$2,$prefs);
	} elsif (ref($prefs->{$key}) eq 'ARRAY') {
		#clear an array pref
		$prefs->{$key} = [];
	} else {
		CORE::delete $prefs->{$key};
	}
	scheduleWrite() unless $writePending;
}

sub clientDelete {
	my $client = shift;
	my $key = shift;
	my $ind = shift;
	
	$client->prefDelete($key,$ind);
}

sub isDefined {
	my $key = shift;
	my $ind = shift;
	if (defined($ind)) {
		if (defined $prefs{$key}) {
			if (ref $prefs{$key} eq 'ARRAY') {
				return defined $prefs{$key}[$ind];
			} elsif (ref $prefs{$key} eq 'HASH') {
				return defined $prefs{$key}{$ind};
			}
		}
	}
	return defined $prefs{$key};
}

sub clientIsDefined {
	my $client = shift;
	my $key = shift;
	my $ind = shift;
	
	return $client->prefIsDefined($key,$ind);
}

sub scheduleWrite {
	my $writeDelay = get('prefsWriteDelay') || 0;
	
	$writePending = 1;
	
	if ($writeDelay > 0) {
		Slim::Utils::Timers::setTimer(0, (Time::HiRes::time() + $writeDelay), \&writePrefs, 1);
	} else {
		writePrefs();
	}
}	

sub writePending {
	return $writePending;
}

sub writePrefs {

	return unless $canWrite;

	my $writeFile = prefsFile();
	my $prefdump  = Dump(\%prefs);

	my %writeAttr = (
		'atomic'  => $canWriteAtomic,
		'buf_ref' => \$prefdump,
		'binmode' => ':raw',
	);

	if ($log) {

		$log->info("Writing out prefs in $writeFile");
	}

	eval { File::Slurp::write_file($writeFile, \%writeAttr) };

	if ($@) {
		logError("Couldn't write prefs file: [$writeFile] - [$@]");
	}

	$writePending = 0;
}

sub preferencesPath {
	my $setPath = shift;

	if (defined $setPath) { 
		$prefsPath = $setPath;
	}

	if (defined($prefsPath)) {
		return $prefsPath;
	}

	if (Slim::Utils::OSDetect::OS() eq 'mac') {

		$prefsPath = catdir($ENV{'HOME'}, 'Library', 'SlimDevices');

	} elsif (Slim::Utils::OSDetect::OS() eq 'win')  {

		$prefsPath = $Bin;

	} else {

	 	$prefsPath = $ENV{'HOME'};
	}

	if ($log) {
		$log->info("The default prefs directory is $prefsPath");
	}

	return $prefsPath;
}

sub prefsFile {
	my $setFile = shift;
	
	# Bug: 2354 - if the user has passed in a prefs file - set the prefs
	# path based off of that.
	if (defined $setFile) { 

		$prefsFile = $setFile;

		preferencesPath(dirname($prefsFile));
	}
	
	if (defined($prefsFile)) {
		return $prefsFile;
	}

	my $pref_path = preferencesPath();

	if (Slim::Utils::OSDetect::OS() eq 'win')  {	

		$prefsFile = catdir($pref_path, 'slimserver.pref');

	} elsif (Slim::Utils::OSDetect::OS() eq 'mac') {

		$prefsFile = catdir($pref_path, 'slimserver.pref');

	} else {

		if (-r '/etc/slimserver.conf') {

			$prefsFile = '/etc/slimserver.conf';

			preferencesPath(dirname($prefsFile));

		} elsif (-r catdir($pref_path, '.slimserver.pref')) {

			$prefsFile = catdir($pref_path, '.slimserver.pref');

		} else {

			$prefsFile = catdir($pref_path, 'slimserver.pref');
		}
	}

	if ($log) {
		$log->info("The default prefs file location is $prefsFile");
	}

	return $prefsFile;
}

# Figures out where the preferences file should be on our platform, and loads it.
sub load {
	my $setFile = shift;
	my $nosetup = shift;

	my $readFile = prefsFile($setFile);

	# if we found some file to read, then let's read it!
	eval {
		if (-r $readFile) {

			open(NUPREFS, $readFile);
			my $firstline = <NUPREFS>;
			close(NUPREFS);

			if ($firstline =~ /^---/) {

				# it's a YAML formatted file
				if ($log) {
					$log->info("Loading YAML style prefs file: $readFile");
				}

				my $prefref = LoadFile($readFile);

				%prefs = %$prefref;

			} else {

				# it's the old style prefs file
				if ($log) {
					$log->info("Loading old style prefs file: $readFile");
				}

				loadOldPrefs($readFile);
			}
		}
	};

	if ($@) {

		print(
			"There was an error reading your SlimServer configuration file - it might be corrupted!: [$@]\n",
			"If you are on a Unix platform, you may need to install YAML::Syck\n",
			"Run './Bin/build-perl-modules.pl YAML::Syck'",
			"\n\n",
			"Exiting\n",
		);

		exit;
	}

	# see if we can write out the real prefs file
	$canWrite = (-e prefsFile() && -w prefsFile()) || (-w preferencesPath());
	
	$canWriteAtomic = (-w preferencesPath) ? 1 : 0;
	
	if (!$canWrite && !$nosetup) {

		logError("Can't write to preferences file: $prefsFile, any changes made will not be saved!");
	}
}

sub loadOldPrefs {
	my $readFile = shift;
	open(NUPREFS, $readFile);
	while (<NUPREFS>) {
		chomp; 			# no newline
		s/^\s+//;		# no leading white
		next unless length;	#anything left?
		my ($var, $value) = split(/\s=\s/, $_, 2);
		if ($var =~ /^(.+?)\%(.+)$/) {
			#part of hash
			$prefs{$1}{$2} = $value;
		} elsif ($var =~ /(.+?)(\d+|#)$/) {
			#part of array
			if ($2 eq '#') {
				$prefs{$1} = [] if $value == -1;
			} else {
				$prefs{$1}[$2] = $value;
			}
		} else {
			$prefs{$var} = $value;
		}
	}
	close(NUPREFS);	
}	

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
