package Plugins::MusicMagic::Importer;

# $Id: /slim/trunk/server/Plugins/MusicMagic/Plugin.pm 213 2005-11-09T17:07:36.536715Z dsully  $

use strict;
use Scalar::Util qw(blessed);

use Plugins::MusicMagic::Common;

use Slim::Player::Source;
use Slim::Player::Protocols::HTTP;
use Slim::Utils::Misc;
use Slim::Utils::Strings;

my $isScanning = 0;
my $initialized = 0;
my $MMSHost;
my $MMSport;

our %artwork = ();

sub useMusicMagic {
	my $class    = shift;
	my $newValue = shift;

	my $can      = canUseMusicMagic();
	
	if (defined($newValue)) {

		if (!$can) {
			Slim::Utils::Prefs::set('musicmagic', 0);
		} else {
			Slim::Utils::Prefs::set('musicmagic', $newValue);
		}
	}
	
	my $use = Slim::Utils::Prefs::get('musicmagic');

	if (!defined($use) && $can) { 

		Slim::Utils::Prefs::set('musicmagic', 1);

	} elsif (!defined($use) && !$can) {

		Slim::Utils::Prefs::set('musicmagic', 0);
	}

	$use = Slim::Utils::Prefs::get('musicmagic') && $can;

	Slim::Music::Import->useImporter($class, $use);

	$::d_musicmagic && msg("MusicMagic: using musicmagic: $use\n");

	return $use;
}

sub canUseMusicMagic {
	return $initialized || initPlugin();
}

sub shutdownPlugin {
	my $class = shift;

	# reset last scan time
	Slim::Utils::Prefs::set('MMMlastMusicLibraryFinishTime',undef);

	# set importer to not use, but only for this session.
	# leave server pref as is to support reenabling the features, 
	# without needing a forced rescan
	Slim::Music::Import->useImporter($class, 0);
}

sub initPlugin {
	my $class = shift;

	return 1 if $initialized;
	
	Plugins::MusicMagic::Common::checkDefaults();

	if (grep {$_ eq 'MusicMagic::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {

		$::d_musicmagic && msg("MusicMagic: don't initialize, it's disabled\n");
		$initialized = 0;

		return 0;		
	}

	$MMSport = Slim::Utils::Prefs::get('MMSport');
	$MMSHost = Slim::Utils::Prefs::get('MMSHost');

	$::d_musicmagic && msg("MusicMagic: Testing for API on $MMSHost:$MMSport\n");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'     => "http://$MMSHost:$MMSport/api/version",
		'create'  => 0,
		'timeout' => 5,
	});

	if (!$http) {

		$initialized = 0;
		$::d_musicmagic && msg("MusicMagic: Cannot Connect\n");

	} else {

		# Note: Check version restrictions if any
		$initialized = $http->content;
		$http->close;

		$::d_musicmagic && msg("MusicMagic: $initialized\n");

		Slim::Music::Import->addImporter($class, {
			'playlistOnly' => 1,
		});

		Slim::Music::Import->useImporter($class, Slim::Utils::Prefs::get('musicmagic'));

		Slim::Player::Source::registerProtocolHandler("musicmagicplaylist", "0");
	}

	return $initialized;
}

sub isMusicLibraryFileChanged {

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'     => "http://$MMSHost:$MMSport/api/cacheid?contents",
		'create'  => 0,
		'timeout' => 5,
	}) || return 0;

	my $fileMTime = $http->content;

	$::d_musicmagic && msg("MusicMagic: read cacheid of $fileMTime");

	$http->close;

	$http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/getStatus",
		'create' => 0,
		'timeout' => 5,
	}) || return 0;

	my $MMMstatus = $http->content;

	$::d_musicmagic && msg("MusicMagic: got status - $MMMstatus");

	$http->close;

	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, $lastMusicLibraryDate is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	my $oldTime = Slim::Utils::Prefs::get('MMMlastMusicMagicLibraryDate') || 0;
	my $lastMusicLibraryFinishTime = Slim::Utils::Prefs::get('MMMlastMusicLibraryFinishTime') || 0;

	if ($fileMTime > $oldTime) {

		my $musicmagicscaninterval = Slim::Utils::Prefs::get('musicmagicscaninterval');

		if ($::d_musicmagic) {

			msg("MusicMagic: music library has changed! Details:\n");
			msg("\tCacheid - $fileMTime\n");
			msg("\tLastCacheid - $oldTime\n");
			msg("\tReload Interval - $musicmagicscaninterval\n");
			msg("\tLast Scan - $lastMusicLibraryFinishTime\n");
		}
		
		if (!$musicmagicscaninterval) {

			# only scan if musicmagicscaninterval is non-zero.
			$::d_musicmagic && msg("MusicMagic: Scan Interval set to 0, rescanning disabled\n");

			return 0;
		}

		if (time - $lastMusicLibraryFinishTime > $musicmagicscaninterval) {

			return 1;
		}

		$::d_musicmagic && msg("MusicMagic: waiting for $musicmagicscaninterval seconds to pass before rescanning\n");
	}

	return 0;
}

sub startScan {
	my $class = shift;

	if (!$class->useMusicMagic) {
		return;
	}
		
	$::d_musicmagic && msg("MusicMagic: start export\n");

	#$class->stopScan;

	if (Slim::Music::Import->scanPlaylistsOnly) {

		$class->exportPlaylists;

	} else {

		$class->exportFunction;
	}

	$class->doneScanning;
} 

sub stopScan {
	my $class = shift;

	if ($class->stillScanning) {

		$::d_musicmagic && msg("MusicMagic: Scan already in progress. Restarting\n");
		$isScanning = 0;
	}
}

sub stillScanning {
	my $class = shift;

	return $isScanning;
}

sub doneScanning {
	my $class = shift;

	$::d_musicmagic && msg("MusicMagic: done Scanning\n");

	$isScanning = 0;

	Slim::Utils::Prefs::set('MMMlastMusicLibraryFinishTime',time);

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/cacheid?contents",
		'create' => 0,
	}) || return 0;

	if ($http) {

		Slim::Utils::Prefs::set('MMMlastMusicMagicLibraryDate', $http->content);

		$http->close;
	}

	Slim::Music::Import->endImporter($class);
}

sub exportFunction {
	my $class = shift;

	my $count = 0;

	$isScanning = 1;

	$MMSport = Slim::Utils::Prefs::get('MMSport') unless $MMSport;
	$MMSHost = Slim::Utils::Prefs::get('MMSHost') unless $MMSHost;

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/getSongCount",
		'create' => 0,
	});

	if ($http) {
		# convert to integer
		chomp($count = $http->content);

		$http->close;

		$count += 0;
	}

	$::d_musicmagic && msg("MusicMagic: Got $count song(s).\n");

	$class->exportSongs($count);
	$class->exportPlaylists;
	$class->exportDuplicates;
}

sub exportSongs {
	my $class = shift;
	my $count = shift;

	# We need to use the datastore to get at our id's
	my $ds = Slim::Music::Info::getCurrentDataStore();

	for (my $scan = 0; $scan <= $count; $scan++) {

		my %attributes = ();
		my %songInfo   = ();
		
		my $http = Slim::Player::Protocols::HTTP->new({
			'url'    => "http://$MMSHost:$MMSport/api/getSong?index=$scan",
			'create' => 0,
		}) || next;

		my @lines  = split(/\n/, $http->content);
		my $count2 = scalar @lines;

		$http->close;

		for (my $j = 0; $j < $count2; $j++) {

			my ($song_field, $song_value) = $lines[$j] =~ /(\w+) (.*)/;

			$songInfo{$song_field} = $song_value;
		}

		# If we've already read tags on these items - save trips to the db.
		if (!Slim::Music::Import->useFolderImporter) {

			$attributes{'TRACKNUM'} = $songInfo{'track'};

			if ($songInfo{'bitrate'}) {
				$attributes{'BITRATE'} = $songInfo{'bitrate'} * 1000;
			}

			$attributes{'YEAR'}  = $songInfo{'year'};
			$attributes{'CT'}    = Slim::Music::Info::typeFromPath($songInfo{'file'},'mp3');
			$attributes{'TAG'}   = 1;
			$attributes{'VALID'} = 1;
			$attributes{'SECS'}  = $songInfo{'seconds'} if $songInfo{'seconds'};

			for my $key (qw(album artist genre name)) {

				my $enc = Slim::Utils::Unicode::encodingFromString($songInfo{$key});

				$songInfo{$key} = Slim::Utils::Unicode::utf8decode_guess($songInfo{$key}, $enc);
			}

			# Assign these after they may have been verified as UTF-8
			$attributes{'ALBUM'}  = $songInfo{'album'};
			$attributes{'TITLE'}  = $songInfo{'name'};
			$attributes{'ARTIST'} = $songInfo{'artist'};
			$attributes{'GENRE'}  = $songInfo{'genre'};
		}
	
		my $fileurl = Slim::Utils::Misc::fileURLFromPath($songInfo{'file'});

		if ($songInfo{'active'} eq 'yes') {
			$attributes{'MUSICMAGIC_MIXABLE'} = 1;
		}

		$::d_musicmagic && msg("MusicMagic: Exporting song $scan: $songInfo{'file'}\n");

		# Both Linux & Windows need conversion to the current charset.
		if (Slim::Utils::OSDetect::OS() ne 'mac') {
			$songInfo{'file'} = Slim::Utils::Unicode::utf8encode_locale($songInfo{'file'});
		}

		my $track = $ds->updateOrCreate({

			'url'        => $fileurl,
			'attributes' => \%attributes,
			'readTags'   => Slim::Music::Import->useFolderImporter ? 0 : 1,

		}) || do {

			$::d_musicmagic && msg("MusicMagic: Couldn't create track for $fileurl!\n");
			next;
		};

		my $albumObj = $track->album;

		# NYI: MMM has more ways to access artwork...
		if (!Slim::Music::Import->useFolderImporter) {

			if (Slim::Utils::Prefs::get('lookForArtwork') && defined $albumObj) {

				if (!Slim::Music::Import->artwork($albumObj) && !defined $track->thumb) {

					Slim::Music::Import->artwork($albumObj, $track);
				}
			}
		}

		if ($songInfo{'active'} eq 'yes' && blessed($albumObj)) {

			$albumObj->musicmagic_mixable(1);
			$albumObj->update;

			for my $artistObj ($track->contributors) {
				$artistObj->musicmagic_mixable(1);
				$artistObj->update;
			}
			
			for my $genreObj ($track->genres) {
				$genreObj->musicmagic_mixable(1);
				$genreObj->update;
			}
		}
	}
}

sub exportPlaylists {
	my $class = shift;

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/playlists",
		'create' => 0,

	}) || return;

	my @playlists = split(/\n/, $http->content);

	$http->close;

	for (my $i = 0; $i <= scalar @playlists; $i++) {

		my $http = Slim::Player::Protocols::HTTP->new({
			'url'    => "http://$MMSHost:$MMSport/api/getPlaylist?index=$i",
			'create' => 0,

		}) || next;

		my @songs = split(/\n/, $http->content);
		my $count = scalar @songs;

		$http->close;
	
		$::d_musicmagic && msgf("MusicMagic: got playlist %s with %d items\n", $playlists[$i], scalar @songs);

		$class->_updatePlaylist($playlists[$i], \@songs);
	}
}

# Create playlists containing the duplicate items as identified by MusicMagic
sub exportDuplicates {
	my $class = shift;

	# check for dupes, but not with 1.1.3
	if ($initialized =~ m/1\.1\.3$/) {
		return;
	}

	$::d_musicmagic && msg("MusicMagic: Checking for duplicates.\n");
	
	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/duplicates",
		'create' => 0,

	}) || return;

	my @songs = split(/\n/, $http->content);

	$http->close;

	$class->_updatePlaylist('Duplicates', \@songs);

	$::d_musicmagic && msgf("MusicMagic: finished export (%d records)\n", scalar @songs);
}
	
sub _updatePlaylist {
	my ($class, $name, $songs) = @_;

	my %attributes = ();
	my $url        = 'musicmagicplaylist:' . Slim::Utils::Misc::escape($name);

	# add this list of duplicates to our playlist library
	$attributes{'TITLE'} = join('', 
		Slim::Utils::Prefs::get('MusicMagicplaylistprefix'),
		$name,
		Slim::Utils::Prefs::get('MusicMagicplaylistsuffix'),
	);
	
	$attributes{'LIST'}  = [ map { Slim::Utils::Misc::fileURLFromPath(

		Plugins::MusicMagic::Common::convertPath($_)

	) } @{$songs} ];

	$attributes{'CT'}    = 'mmp';
	$attributes{'TAG'}   = 1;
	$attributes{'VALID'} = 1;

	Slim::Music::Info::updateCacheEntry($url, \%attributes);
}

1;

__END__
