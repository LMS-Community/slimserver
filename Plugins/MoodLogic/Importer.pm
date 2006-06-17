package Plugins::MoodLogic::Importer;

# $Id$

use strict;

use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Misc;

use Plugins::MoodLogic::Common;

my $initialized = 0;

my $conn;
my $rs;
my $auto;
my $playlist;

my $browser;
my %genre_hash = ();
my $isauto = 1;

my $lastMusicLibraryFinishTime = undef;
my $last_error = 0;
my $mixer;

our @mood_names;
our %mood_hash;

sub useMoodLogic {
	my $class    = shift;
	my $newValue = shift;

	my $can      = canUseMoodLogic();

	if (defined($newValue)) {

		if (!$can) {
			Slim::Utils::Prefs::set('moodlogic', 0);
		} else {
			Slim::Utils::Prefs::set('moodlogic', $newValue);
		}
	}

	my $use = Slim::Utils::Prefs::get('moodlogic');

	if (!defined($use) && $can) { 

		Slim::Utils::Prefs::set('moodlogic', 1);

	} elsif (!defined($use) && !$can) {

		Slim::Utils::Prefs::set('moodlogic', 0);

	}

	$use = Slim::Utils::Prefs::get('moodlogic') && $can;

	Slim::Music::Import->useImporter($class,$use);

	$::d_moodlogic && msg("MoodLogic: using moodlogic: $use\n");

	return $use;
}

sub canUseMoodLogic {
	my $class = shift;

	return (Slim::Utils::OSDetect::OS() eq 'win' && initPlugin());
}

sub shutdownPlugin {
	my $class    = shift;
	
	# turn off checker
	Slim::Utils::Timers::killTimers(0, \&checker);
	
	# remove playlists
	
	# disable protocol handler
	Slim::Player::ProtocolHandlers->registerHandler('moodlogicplaylist', 0);

	# reset last scan time

	$lastMusicLibraryFinishTime = undef;

	$initialized = 0;
	
	# delGroups, categories and prefs
	Slim::Web::Setup::delCategory('MOODLOGIC');
	Slim::Web::Setup::delGroup('SERVER_SETTINGS','moodlogic',1);
	
	# set importer to not use
	#Slim::Utils::Prefs::set('moodlogic', 0);
	Slim::Music::Import->useImporter($class,0);
}

sub initPlugin {
	my $class    = shift;

	return 1 if $initialized; 
	return 0 if Slim::Utils::OSDetect::OS() ne 'win';
	
	Plugins::MoodLogic::Common::checkDefaults();
	
	require Win32::OLE;
	import Win32::OLE qw(EVENTS);
	
	Win32::OLE->Option(Warn => \&Plugins::MoodLogic::Common::OLEError);
	my $name = "mL_MixerCenter";
	
	$mixer = Win32::OLE->new("$name.MlMixerComponent");
	
	if (!defined $mixer) {
		$name = "mL_Mixer";
		$mixer = Win32::OLE->new("$name.MlMixerComponent");
	}
	
	if (!defined $mixer) {
		$::d_moodlogic && msg("MoodLogic: could not find moodlogic mixer component\n");
		return 0;
	}
	
	$browser = Win32::OLE->new("$name.MlMixerFilter");
	
	if (!defined $browser) {
		$::d_moodlogic && msg("MoodLogic: could not find moodlogic filter component\n");
		return 0;
	}
	
	Win32::OLE->WithEvents($mixer, \&Plugins::MoodLogic::Common::event_hook);
	
	$mixer->{JetPwdMixer} = 'C393558B6B794D';
	$mixer->{JetPwdPublic} = 'F8F4E734E2CAE6B';
	$mixer->{JetPwdPrivate} = '5B1F074097AA49F5B9';
	$mixer->{UseStrings} = 1;
	$mixer->Initialize();
	$mixer->{MixMode} = 0;
	
	if ($last_error != 0) {
		$::d_moodlogic && msg("MoodLogic: rebuilding mixer db\n");
		$mixer->MixerDb_Create();
		$last_error = 0;
		$mixer->Initialize();
		if ($last_error != 0) {
			return 0;
		}
	}
	
	my $i = 0;
	
	push @mood_names, string('MOODLOGIC_MOOD_0');
	push @mood_names, string('MOODLOGIC_MOOD_1');
	push @mood_names, string('MOODLOGIC_MOOD_2');
	push @mood_names, string('MOODLOGIC_MOOD_3');
	push @mood_names, string('MOODLOGIC_MOOD_4');
	push @mood_names, string('MOODLOGIC_MOOD_5');
	push @mood_names, string('MOODLOGIC_MOOD_6');
	
	map { $mood_hash{$_} = $i++ } @mood_names;

	#Slim::Utils::Strings::addStrings($strings);
	Slim::Player::ProtocolHandlers->registerHandler("moodlogicplaylist", "0");

	Slim::Music::Import->addImporter($class, {
		'playlistOnly' => 1,
	});

	Slim::Music::Import->useImporter($class,Slim::Utils::Prefs::get('moodlogic'));

	$initialized = 1;

	return $initialized;
}

sub isMusicLibraryFileChanged {
	my $file = $mixer->{JetFilePublic};

	my $fileMTime = (stat $file)[9];
	
	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, $lastMusicLibraryDate is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	if ($file && $fileMTime > Slim::Utils::Prefs::get('lastMoodLogicLibraryDate')) {
		my $moodlogicscaninterval = Slim::Utils::Prefs::get('moodlogicscaninterval');
		
		$::d_moodlogic && msg("MoodLogic: music library has changed!\n");
		
		unless ($moodlogicscaninterval) {
			
			# only scan if moodlogicscaninterval is non-zero.
			$::d_moodlogic && msg("MoodLogic: Scan Interval set to 0, rescanning disabled\n");

			return 0;
		}

		return 1 if (!$lastMusicLibraryFinishTime);
		
		if (time() - $lastMusicLibraryFinishTime > $moodlogicscaninterval) {
			return 1;
		} else {
			$::d_moodlogic && msg("MoodLogic: waiting for $moodlogicscaninterval seconds to pass before rescanning\n");
		}
	}
	
	return 0;
}

sub startScan {
	my $class = shift;
	
	if (!useMoodLogic()) {
		return;
	}
		
	$::d_moodlogic && msg("MoodLogic: start export\n");
	
	if (Slim::Music::Import->scanPlaylistsOnly) {

		$class->exportPlaylists;

	} else {

		$class->exportFunction;
	}

	$class->doneScanning;
} 

sub doneScanning {
	my $class = shift;

	$rs->Close;
	$conn->Close;

	$::d_moodlogic && msg("MoodLogic: done Scanning\n");

	%genre_hash = ();
	
	$lastMusicLibraryFinishTime = time();

	Slim::Utils::Prefs::set('lastMoodLogicLibraryDate',(stat $mixer->{JetFilePublic})[9]);
	
	Slim::Music::Import->endImporter($class);
}

sub exportFunction {
	my $class = shift;
	
	$conn = Win32::OLE->new("ADODB.Connection");
	$rs   = Win32::OLE->new("ADODB.Recordset");

	$::d_moodlogic && msg("MoodLogic: Opening Object Link...\n");

	$conn->Open('PROVIDER=MSDASQL;DRIVER={Microsoft Access Driver (*.mdb)};DBQ='.$mixer->{JetFilePublic}.';UID=;PWD=F8F4E734E2CAE6B;');
	$rs->Open('SELECT tblSongObject.songId, tblSongObject.profileReleaseYear, tblAlbum.name, tblSongObject.tocAlbumTrack, tblMediaObject.bitrate FROM tblAlbum,tblMediaObject,tblSongObject WHERE tblAlbum.albumId = tblSongObject.tocAlbumId AND tblSongObject.songId = tblMediaObject.songId ORDER BY tblSongObject.songId', $conn, 1, 1);
	
	$browser->filterExecute();
	
	my $count = $browser->FLT_Genre_Count();
	
	for (my $i = 1; $i <= $count; $i++) {
		my $genre_id = $browser->FLT_Genre_MGID($i);
		$mixer->{Seed_MGID} = -$genre_id;
		my $genre_name = $mixer->Mix_GenreName(-1);
		$mixer->{Seed_MGID} = $genre_id;
		my $genre_mixable = $mixer->Seed_MGID_Mixable();
		$genre_hash{$genre_id} = [$genre_name, $genre_mixable];
	}

	$count = $browser->FLT_Song_Count();
	$::d_moodlogic && msg("MoodLogic: Begin song scan for ".$count." tracks. \n");

	$class->exportSongs($count);
	$class->exportPlaylists;
}

sub exportSongs {
	my $class = shift;
	my $count = shift;

	for (my $scan = 0; $scan <= $count; $scan++) {
		my @album_data = (-1, undef, undef);
	
		my $url;
		my %cacheEntry = ();
		my $song_id = $browser->FLT_Song_SID($scan);
		
		$mixer->{Seed_SID} = -$song_id;
		$url = Slim::Utils::Misc::fileURLFromPath($mixer->Mix_SongFile(-1));

		# merge album info, from query ('cause it is not available via COM)
		while (defined $rs && !$rs->EOF && $album_data[0] < $song_id && defined $rs->Fields('songId')) {

			@album_data = (
				$rs->Fields('songId')->value,
				$rs->Fields('name')->value,
				$rs->Fields('tocAlbumTrack')->value,
				$rs->Fields('bitrate')->value,
				$rs->Fields('profileReleaseYear')->value,
			);
			$rs->MoveNext;
		}
		
		if (defined $album_data[0] && $album_data[0] == $song_id && $album_data[1] ne "") {
			$cacheEntry{'ALBUM'}    = $album_data[1];
			$cacheEntry{'TRACKNUM'} = $album_data[2];
			$cacheEntry{'BITRATE'}  = $album_data[3];
			$cacheEntry{'YEAR'}     = $album_data[4] if defined $album_data[4];
		}

		$cacheEntry{'CT'}         = Slim::Music::Info::typeFromPath($url,'mp3');
		$cacheEntry{'TAG'}        = 1;
		$cacheEntry{'VALID'}      = 1;
		
		$cacheEntry{'TITLE'}      = $mixer->Mix_SongName(-1);
		$cacheEntry{'ARTIST'}     = $mixer->Mix_ArtistName(-1);
		$cacheEntry{'GENRE'}      = $genre_hash{$browser->FLT_Song_MGID($scan)}[0] if (defined $genre_hash{$browser->FLT_Song_MGID($scan)});
		$cacheEntry{'SECS'}       = int($mixer->Mix_SongDuration(-1) / 1000);
		
		$cacheEntry{'MOODLOGIC_ID'}      = $mixer->{'Seed_SID'} = $song_id;
		$cacheEntry{'MOODLOGIC_MIXABLE'} = $mixer->Seed_SID_Mixable();

		if ($] > 5.007) {

			for my $key (qw(ALBUM ARTIST GENRE TITLE)) {
				$cacheEntry{$key} = Slim::Utils::Unicode::utf8encode($cacheEntry{$key}) if defined $cacheEntry{$key};
			}
		}

		$::d_moodlogic && msg("MoodLogic: Creating entry for track $scan: $url\n");

		# that's all for the track
		my $track = Slim::Schema->rs('Track')->updateOrCreate({

			'url'        => $url,
			'attributes' => \%cacheEntry,
			'readTags'   => 1,

		}) || do {

			$::d_moodlogic && msg("MoodLogic: Couldn't create track for: $url\n");

		};
		$class->exportContribGenres($track,$scan);
	}
}

sub exportContribGenres {
	my $class = shift;
	my $track = shift;
	my $scan  = shift;
	
	return unless $track;
	
	# Now add to the contributors and genres
	for my $contributor ($track->contributors()) {
		$mixer->{'Seed_AID'} = $browser->FLT_Song_AID($scan);

		$contributor->moodlogic_id($mixer->{'Seed_AID'});
		$contributor->moodlogic_mixable($mixer->Seed_AID_Mixable());
		$contributor->update();
	}

	for my $genre ($track->genres()) {

		$genre->moodlogic_id($browser->FLT_Song_MGID($scan));

		if (defined $genre_hash{$browser->FLT_Song_MGID($scan)}) {
			$genre->moodlogic_mixable($genre_hash{$browser->FLT_Song_MGID($scan)}[1]);
		}

		$genre->update();
	}
	
	#$::d_moodlogic && msg("MoodLogic: Song scan complete, checking playlists\n");
}

sub exportPlaylists {
	my $class = shift;

	$playlist   = Win32::OLE->new("ADODB.Recordset");
	$auto   = Win32::OLE->new("ADODB.Recordset");

	#PLAYLIST QUERY
	eval {$playlist->Open('Select tblPlaylist.name, tblMediaObject.volume, tblMediaObject.path, tblMediaObject.filename  From "tblPlaylist", "tblPlaylistSong", "tblMediaObject" where "tblPlaylist"."playlistId" = "tblPlaylistSong"."playlistId" AND "tblPlaylistSong"."songId" = "tblMediaObject"."songId" order by tblPlaylist.playlistId,tblPlaylistSong.playOrder', $conn, 1, 1);}
	
	unless ($@) { 
		$class->processPlaylists($playlist);
		$playlist->Close;
	}
	
	# AUTO PLAYLIST QUERY: 
	local $Win32::OLE::Warn = 0;
	eval {$auto->Open('Select tblAutoPlaylist.name, tblMediaObject.volume, tblMediaObject.path, tblMediaObject.filename From "tblAutoPlaylist", "tblAutoPlaylistSong", "tblMediaObject" where "tblAutoPlaylist"."playlistId" = tblAutoPlaylistSong.playlistId AND tblAutoPlaylistSong.songId = tblMediaObject.songId order by tblAutoPlaylist.playlistId,tblAutoPlaylistSong.playOrder', $conn, 1, 1);}

	if (Win32::OLE->LastError) {
		$::d_moodlogic && msg("MoodLogic: No AutoPlaylists Found\n");
	} else {
		$class->processPlaylists($auto);
		$auto->Close;
	}
}

sub processPlaylists {
	my $class    = shift;
	my $playlist = shift;

	my $prefix = Slim::Utils::Prefs::get('MoodLogicplaylistprefix');
	my $suffix = Slim::Utils::Prefs::get('MoodLogicplaylistsuffix');

	while (defined $playlist && !$playlist->EOF) {

		my $name = $playlist->Fields('name')->value;
		my %cacheEntry = ();
		my $url = 'moodlogicplaylist:' . Slim::Utils::Misc::escape($name);

		$::d_moodlogic && msg("MoodLogic: Found MoodLogic Playlist: $url\n");

		# add this playlist to our playlist library
		$cacheEntry{'TITLE'} =  $prefix . $name . $suffix;
		$cacheEntry{'LIST'} = getPlaylistItems($playlist);
		$cacheEntry{'CT'} = 'mlp';
		$cacheEntry{'TAG'} = 1;
		$cacheEntry{'VALID'} = '1';

		Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);

		$playlist->MoveNext unless $playlist->EOF;
	}
}

1;

__END__