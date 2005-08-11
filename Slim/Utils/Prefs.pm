package Slim::Utils::Prefs;

# $Id$

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use File::Path;
use FindBin qw($Bin);
use Digest::MD5;
use YAML qw(DumpFile LoadFile);

use Slim::Utils::Misc;
use Slim::Utils::Unicode;

our %prefs = ();
my $prefsPath;
my $prefsFile;
my $canWrite;
my $writePending = 0;

our %upgradeScripts = ();
our %DEFAULT = ();
our %prefChange = ();

sub init {

	# These are scripts that are run once on old prefs file to bring them
	# up-to-date with specific changes we want to push out to default prefs.
	%upgradeScripts = (
		# Default browse mode for music folders is sort by filename				   
		'6.0b3' => sub {
			Slim::Utils::Prefs::set('filesort', 1);
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
		"cliport"		=> 9090,
		"music"			=> defaultAudioDir(),
		"playlistdir"		=> defaultPlaylistDir(),
		"cachedir"		=> defaultCacheDir(),
		"securitySecret"	=> makeSecuritySecret(),
		"csrfProtectionLevel"	=> 1,
		"skin"			=> "Default",
		"language"		=> "EN",
		"refreshRate"		=> 30,
		"displaytexttimeout"	=> 1.0,
		"filesort"		=> 1,
		'browseagelimit'	=> 100,
		"playtrackalbum"	=> 1,
		"ignoredarticles"	=> "The El La Los Las Le Les",
		"splitList"		=> '',
		"authorize"		=> 0,				# No authorization by default
		"username"		=> '',
		"password"		=> '',
		"filterHosts"		=> 0,				# No filtering by default
		"allowedHosts"		=> join(',', Slim::Utils::Misc::hostaddr()),
		"tcpReadMaximum"	=> 20,
		"tcpWriteMaximum"	=> 20,
		"tcpConnectMaximum"	=> 30,
		"streamWriteMaximum"	=> 30,
		'webproxy'		=> '',
		"udpChunkSize"		=> 1400,
		'itemsPerPage'		=> 50,
		'lookForArtwork'	=> 1,
		'includeNoArt'		=> 0,
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
		'livelog'		=> 102400, # keep around an in-memory log of 100kbytes, available from the web interfaces
		'remotestreamtimeout'	=> 5, # seconds to try to connect for a remote stream
		'xplir'			=> 'both',
		'xplinterval'		=> 5,
		'xplsupport'		=> 0,
		'prefsWriteDelay'	=> 30,
		'dbsource'		=> 'dbi:SQLite:dbname=%s',
		'dbusername'		=> '',
		'dbpassword'		=> '',
		'commonAlbumTitles'	=> ['Greatest Hits', 'Best of...', 'Live'],
		'noGenreFilter'		=> 0,
		'variousArtistAutoIdentification' => 1,
		'upgrade-6.0b3-script'	=> 1,
		'rank-PLUGIN_PICKS_MODULE_NAME' => 4,
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

			'powerOnBrightness' => sub {
				my ($client,$newvalue) = @_;
				if ($client->power()) {
					$client->brightness($newvalue);
				}
			},

			'powerOffBrightness' => sub {
				my ($client,$newvalue) = @_;
				if (!$client->power()) {
					$client->brightness($newvalue);
				}
			},

			'idleBrightness' => sub {
				my ($client,$newvalue) = @_;
				if ($client->power()) {
					$client->brightness($newvalue);
				}
			},

			'irmap' => sub {
				my ($client,$newvalue) = @_;

				require Slim::Hardware::IR;

				Slim::Hardware::IR::loadMapFile($newvalue);

				if ($newvalue eq Slim::Hardware::IR::defaultMapFile()) {
					Slim::Buttons::Plugins::addDefaultMaps();
				}
			},
		},

		'language' => sub {
			my $newvalue = shift;

			Slim::Buttons::Plugins::clearGroups();
			Slim::Web::Setup::initSetup();
			Slim::Music::Import::resetSetupGroups();
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

			Slim::Buttons::BrowseTree::init();

			if (defined(Slim::Utils::Prefs::get('audiodir')) && -d Slim::Utils::Prefs::get("audiodir")) {

				Slim::Music::Import::useImporter('FOLDER', 1);
			} else {
				Slim::Music::Import::useImporter('FOLDER', 0);
			}

			Slim::Music::Import::startScan('FOLDER');
		},

		'lookForArtwork' => sub {
			my $lookForArtwork = shift;

			Slim::Music::Import::startScan() if $lookForArtwork;
		},

		'playlistdir' => sub {
			my $newvalue = shift;

			if (defined($newvalue) && $newvalue ne '' && !-d $newvalue) {
				mkdir $newvalue || ($::d_files && msg("Could not create $newvalue\n"));
			}

			for my $client (Slim::Player::Client::clients()) {
				Slim::Buttons::Home::updateMenu($client);
			}
		},

		'persistPlaylists' => sub {

			my $newvalue = shift;

			if ($newvalue) {

				Slim::Control::Command::setExecuteCallback(\&Slim::Player::Playlist::modifyPlaylistCallback);

				for my $client (Slim::Player::Client::clients()) {
					next if Slim::Player::Sync::isSlave($client);
					Slim::Player::Playlist::modifyPlaylistCallback($client,['playlist','load_done']);
				}

			} else {
				Slim::Control::Command::clearExecuteCallback(\&Slim::Player::Playlist::modifyPlaylistCallback);
			}
		}
	);
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
	
		$::d_prefs && msg("server already has a securitySecret\n");
		return $currentVal;
	
	}
	
	# make a new value, based on a random number
	
	my $hash = new Digest::MD5;
	
	$hash->add(rand());
	
	# explicitly "set" this so it persists through shutdown/startupa
	my $secret = $hash->hexdigest();
	
	$::d_prefs && msg("creating a securitySecret for this installation\n");
	set('securitySecret',$secret);
	
	return $secret;
}

sub defaultAudioDir {
	my $path;
	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		$path = ($ENV{'HOME'} . '/Music');

	} elsif (Slim::Utils::OSDetect::OS() eq 'win') {

		if (!eval "use Win32::Registry;") {

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

		$CacheDir = $ENV{'HOME'};
	}

	my @CacheDirs = splitdir($CacheDir);
	pop @CacheDirs;

	my $CacheParent = catdir(@CacheDirs);

	if ((!-e $CacheDir && !-w $CacheParent) || (-e $CacheDir && !-w $CacheDir)) {
		$CacheDir = undef;
	}

	if (defined $CacheDir && !-d $CacheDir) {
		mkpath($CacheDir);
	}

	return $CacheDir;
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
	for my $key (keys %{$defaultPrefs}) {
		my $clientkey = $client->id() . '-' . $key;
		if (!defined($prefs{$clientkey})) {
			if (ref($defaultPrefs->{$key}) eq 'ARRAY') {
				my @temp = @{$defaultPrefs->{$key}};
				$prefs{$clientkey} = \@temp;
			} elsif (ref($defaultPrefs->{$key}) eq 'HASH') {
				my %temp = %{$defaultPrefs->{$key}};
				$prefs{$clientkey} = \%temp;
			} else {
				$prefs{$clientkey} = $defaultPrefs->{$key};
			}
		} elsif (ref($defaultPrefs->{$key}) eq 'HASH') {
			# check defaults for individual hash prefs
			for my $subkey (keys %{$defaultPrefs->{$key}}) {
				if (!defined $prefs{$clientkey}{$subkey}) {
					$prefs{$clientkey}{$subkey} = $defaultPrefs->{$key}{$subkey};
				}
			}
		}
	}
	scheduleWrite() unless $writePending;
}

sub push {
	my $arrayPref = shift;
	my $value = shift;
	if (ref($prefs{$arrayPref}) eq 'ARRAY' || !defined($prefs{$arrayPref})) {
		CORE::push @{$prefs{$arrayPref}}, $value;
	} else {
		bt();
		warn "Attempted to push a value onto a scalar pref";
	}
	scheduleWrite() unless $writePending;
}

sub clientPush {
	my $client = shift;
	my $arrayPref = shift;
	my $value = shift;
	Slim::Utils::Prefs::push(($client->id() . '-' . $arrayPref),$value);
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
	return getArrayMax($client->id() . "-" . $arrayPref);
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
	return getArray($client->id() . "-" . $arrayPref);
}

# get($pref)
sub get { 
	return $prefs{$_[0]};
}

# getInd($pref,$index)
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
	return keys %{$prefs{(shift)}};
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
	return getKeys($client->id() . "-" . $hashPref);
}
	
# clientGetHash($client, $hashPref)
sub clientGetHash {
	my $client = shift;
	my $hashPref = shift;
	assert($client);
	return getHash($client->id() . "-" . $hashPref);
}
	
# Ugh - this should be a method on $client.
#
# clientGet($client, $pref [,$ind])
sub clientGet {
	my $client = shift;
	my $key = shift;
	my $ind = shift;
	if (!defined($client)) {
		$::d_prefs && msg("clientGet on an undefined client\n");
		bt();
		return undef;
	}
	if (defined($ind)) {
		return getInd($client->id() . "-" . $key,$ind);
	} else {
		return get($client->id() . "-" . $key);
	}
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

	# We always want to write out just bytes to the pref file, so turn off
	# the UTF8 flag.
	$value = Slim::Utils::Unicode::utf8off($value);

	if (defined $ind) {

		if (defined $prefs{$key}) {
			if (ref $prefs{$key} eq 'ARRAY') {
				if (defined($prefs{$key}[$ind]) && defined($value) && $value eq $prefs{$key}[$ind]) {
						return;
				}

				$prefs{$key}[$ind] = $value;
			} elsif (ref $prefs{$key} eq 'HASH') {
				if (defined($prefs{$key}{$ind}) && defined($value) && $value eq $prefs{$key}{$ind}) {
						return;
				}

				$prefs{$key}{$ind} = $value;
			}
		} elsif ( $ind =~ /\D/ ) {
			# Setting hash pref where no keys currently exist
			$prefs{$key}{$ind} = $value;
		} else {
			# Setting array pref where no indexes currently exist
			$prefs{$key}[$ind] = $value;
		}

	} elsif ($key =~ /(.+?)(\d+)$/) { 

		# trying to set a member of an array pref directly
		# re-call function the correct way
		return set($1,$value,$2);

	} else {

		if (defined($prefs{$key}) && defined($value) && $value eq $prefs{$key}) {
				return;
		}

		$prefs{$key} = $value;
	}

	onChange($key, $value, $ind);

	# must mark $ind as defined or indexed prefs cause an error in this msg
	$::d_prefs && msg("Setting prefs $key".defined($ind)." equal to " . ((defined $prefs{$key}) ? $prefs{$key} : "undefined") . "\n");

	scheduleWrite() unless $writePending;
}

sub clientSet {
	my $client = shift;
	my $key = shift;
	my $value = shift;
	my $ind = shift;

	set($client->id() . "-" . $key, $value,$ind);
	onChange($key, $value, $ind, $client);
}

sub maxRate {
	my $client   = shift || return 0;
	my $soloRate = shift;

	# The default for a new client will be undef.
	my $rate     = clientGet($client, 'maxBitrate');

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
	$rate = clientGet($client, 'transcodeBitrate') || $rate;

	$::d_source && msgf("Setting maxBitRate for %s to: %d\n", $client->name(), $rate);
	
	return $rate if $soloRate;
	
	# if we're the master, make sure we return the lowest common denominator bitrate.
	my @playergroup = ($client, Slim::Player::Sync::syncedWith($client));
	
	for my $everyclient (@playergroup) {

		next if Slim::Utils::Prefs::clientGet($everyclient,'silent');

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
	if (!defined $prefs{$key}) {
		return;
	}
	if (defined($ind)) {
		if (ref($prefs{$key}) eq 'ARRAY') {
			splice(@{$prefs{$key}},$ind,1);
		} elsif (ref($prefs{$key}) eq 'HASH') {
			CORE::delete $prefs{$key}{$ind};
		}
	} elsif ($key =~ /(.+?)(\d+)$/) { 
		#trying to delete a member of an array pref directly
		#re-call function the correct way
		Slim::Utils::Prefs::delete($1,$2);
	} elsif (ref($prefs{$key}) eq 'ARRAY') {
		#clear an array pref
		$prefs{$key} = [];
	} else {
		CORE::delete $prefs{$key};
	}
	scheduleWrite() unless $writePending;
}

sub clientDelete {
	my $client = shift;
	my $key = shift;
	my $ind = shift;
	
	Slim::Utils::Prefs::delete($client->id() . "-" . $key,$ind);
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
	
	return isDefined($client->id() . "-" . $key,$ind);
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

	$writePending = 0;
	
	my $writeFile = prefsFile();

	$::d_prefs && msg("Writing out prefs in $writeFile\n");

	open(OUT, ">$writeFile") or do {
		msg("Severe Warning! Couldn't write out Prefs file: [$writeFile]: $!\n");
		return;
	};

	if ($] > 5.007) {
		binmode(\*OUT, ":raw");
	}

	print OUT YAML::Dump(\%prefs);

	close(OUT);
}

sub preferencesPath {

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
	
	$::d_prefs && msg("The default prefs directory is $prefsPath\n");

	return $prefsPath;
}

sub prefsFile {
	my $setFile = shift;
	
	if (defined $setFile) { 
		$prefsFile = $setFile;
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
		} else {
			$prefsFile = catdir($pref_path, '.slimserver.pref');
		}
	}
	
	$::d_prefs && msg("The default prefs file location is $prefsFile\n");
	
	return $prefsFile;
}

#
# Figures out where the preferences file should be on our platform, and loads it.
#
sub load {
	my $setFile = shift;
	my $nosetup = shift;

	my $readFile = prefsFile($setFile);
	
	# if we can't open up the new one, try the old ones
	if (!-r $readFile) {
		$readFile = '/etc/slimp3.pref';
	}
	
	if (!-r $readFile) {
		$readFile = catdir(preferencesPath(), 'SLIMP3.PRF');
	}
	
	if (!-r $readFile) {
		if (exists($ENV{'windir'})) {
			$readFile = catdir($ENV{'windir'}, 'SLIMP3.PRF');
		}
	}
		
	if (!-r $readFile && preferencesPath()) {
		$readFile = catdir(preferencesPath(), '.slimp3.pref');
	}
	
	if (!-r $readFile && $ENV{'HOME'}) {
		$readFile = catdir($ENV{'HOME'}, '.slimp3.pref');
	}
	
	# if we found some file to read, then let's read it!
	if (-r $readFile) {
		open(NUPREFS, $readFile);
		my $firstline = <NUPREFS>;
		close(NUPREFS);
		if ($firstline =~ /^---/) {
			# it's a YAML formatted file
			$::d_prefs && msg("Loading YAML style prefs file $readFile\n");
			my $prefref = LoadFile($readFile);
			%prefs = %$prefref;
		} else {
			# it's the old style prefs file
			$::d_prefs && msg("Loading old style prefs file $readFile\n");
			loadOldPrefs($readFile);
		}
	}
	
	# see if we can write out the real prefs file
	$canWrite = (-e prefsFile() && -w prefsFile()) || (-w preferencesPath());
	
	if (!$canWrite && !$nosetup) {
		msg("Cannot write to preferences file $prefsFile, any changes made will not be preserved for the next startup of the server\n");
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
