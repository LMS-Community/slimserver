package Plugins::MoodLogic::Importer;

# $Id$

use strict;
use File::Spec::Functions qw(catfile);

use Plugins::MoodLogic::Common;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.moodlogic',
	'defaultLevel' => 'WARN',
});

my $initialized = 0;

my $conn;
my $rs;
my $auto;
my $playlist;

my $browser;
my %genre_hash = ();
my $isauto = 1;

my $last_error = 0;
my $mixer;

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

	Slim::Music::Import->useImporter($class, $use);

	$log->info(sprintf("Using moodlogic?: %s", $use ? 'yes' : 'no'));

	return $use;
}

sub canUseMoodLogic {
	my $class = shift;

	return (Slim::Utils::OSDetect::OS() eq 'win' && initPlugin());
}

sub initPlugin {
	my $class = shift;

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

		$log->error("Error: Could not find MoodLogic mixer component!");
		return 0;
	}
	
	$browser = Win32::OLE->new("$name.MlMixerFilter");
	
	if (!defined $browser) {

		$log->error("Error: Could not find MoodLogic filter component!");
		return 0;
	}
	
	Win32::OLE->WithEvents($mixer, \&Plugins::MoodLogic::Common::event_hook);

	# Are these constants documented anywhere?
	$mixer->{JetPwdMixer}   = 'C393558B6B794D';
	$mixer->{JetPwdPublic}  = 'F8F4E734E2CAE6B';
	$mixer->{JetPwdPrivate} = '5B1F074097AA49F5B9';
	$mixer->{UseStrings}    = 1;
	$mixer->{MixMode}       = 0;
	$mixer->Initialize();
	
	if ($last_error != 0) {

		$log->warn("Warning: Rebuilding mixer database!");

		$mixer->MixerDb_Create();

		$last_error = 0;

		$mixer->Initialize();

		if ($last_error != 0) {
			return 0;
		}
	}

	Slim::Player::ProtocolHandlers->registerHandler("moodlogicplaylist", "0");

	Slim::Music::Import->addImporter($class, {
		'reset'        => \&resetState,
		'playlistOnly' => 1,
	});

	Slim::Music::Import->useImporter($class,Slim::Utils::Prefs::get('moodlogic'));

	$initialized = 1;

	return $initialized;
}

sub resetState {

	$log->info("Resetting Last Library Change Time.");

	Slim::Music::Import->setLastScanTime('MLLastLibraryChange', 0);
}

sub startScan {
	my $class = shift;
	
	if (!useMoodLogic()) {
		return;
	}

	$log->info("Starting export.");

	if (Slim::Music::Import->scanPlaylistsOnly) {

		$class->exportPlaylists;

	} else {

		$class->exportFunction;
	}

	$class->doneScanning;
} 

sub doneScanning {
	my $class = shift;

	$conn->Close;

	$log->info("Finished scanning.");

	%genre_hash = ();

	Slim::Music::Import->setLastScanTime('MLLastLibraryChange', (stat $mixer->{'JetFilePublic'})[9]);

	Slim::Music::Import->endImporter($class);
}

sub exportFunction {
	my $class = shift;
	
	$conn = Win32::OLE->new("ADODB.Connection");
	$rs   = Win32::OLE->new("ADODB.Recordset");

	$log->debug("Opening Object Link...");

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

	$log->info("Begin song scan for $count tracks.");

	$class->exportSongs($count);

	$rs->Close;

	$class->exportPlaylists;
}

sub exportSongs {
	my $class = shift;
	my $count = shift;

	my $progress = Slim::Utils::ProgressBar->new({ 'total' => $count });

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
		
		if (defined $album_data[0] && $album_data[0] == $song_id
		 && defined $album_data[1] && $album_data[1] ne "") 
		{
			$cacheEntry{'ALBUM'}    = $album_data[1];
			$cacheEntry{'TRACKNUM'} = $album_data[2];
			$cacheEntry{'BITRATE'}  = $album_data[3];
			$cacheEntry{'YEAR'}     = $album_data[4] if defined $album_data[4];
		}

		$cacheEntry{'CT'}         = Slim::Music::Info::typeFromPath($url,'mp3');
		$cacheEntry{'AUDIO'}      = 1;
		
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

		$log->debug("Creating entry for track $scan: $url");

		# that's all for the track
		my $track = Slim::Schema->rs('Track')->updateOrCreate({

			'url'        => $url,
			'attributes' => \%cacheEntry,
			'readTags'   => 1,

		}) || do {

			$log->error("Error: Couldn't create track for: $url");

		};
		
		$class->exportContribGenres($track,$scan);
		
		$progress->update if $progress;
	}

	$progress->final($count) if $progress;
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
	
	$log->info("Song scan complete, checking playlists.");
}

sub exportPlaylists {
	my $class = shift;

	if (!defined $conn) {
		$conn = Win32::OLE->new("ADODB.Connection");

		$log->debug("Opening Object Link...");

		$conn->Open('PROVIDER=MSDASQL;DRIVER={Microsoft Access Driver (*.mdb)};DBQ='.$mixer->{JetFilePublic}.';UID=;PWD=F8F4E734E2CAE6B;');
	}
	
	$playlist   = Win32::OLE->new("ADODB.Recordset");
	$auto       = Win32::OLE->new("ADODB.Recordset");

	# PLAYLIST QUERY
	eval {
		$playlist->Open('Select tblPlaylist.name, tblMediaObject.volume, tblMediaObject.path, tblMediaObject.filename  From "tblPlaylist", "tblPlaylistSong", "tblMediaObject" where "tblPlaylist"."playlistId" = "tblPlaylistSong"."playlistId" AND "tblPlaylistSong"."songId" = "tblMediaObject"."songId" order by tblPlaylist.playlistId,tblPlaylistSong.playOrder', $conn, 1, 1);
	};
	
	if ($@) {

		$log->info("No Playlists Found: $@");

	} else {

		$class->processPlaylists($playlist);
		#$playlist->Close;
	}

	# AUTO PLAYLIST QUERY: 
	local $Win32::OLE::Warn = 0;

	eval {
		$auto->Open('Select tblAutoPlaylist.name, tblMediaObject.volume, tblMediaObject.path, tblMediaObject.filename From "tblAutoPlaylist", "tblAutoPlaylistSong", "tblMediaObject" where "tblAutoPlaylist"."playlistId" = "tblAutoPlaylistSong"."playlistId" AND "tblAutoPlaylistSong"."songId" = "tblMediaObject"."songId" order by tblAutoPlaylist.playlistId,tblAutoPlaylistSong.playOrder', $conn, 1, 1);
	};

	if (Win32::OLE->LastError) {

		$log->info("No AutoPlaylists Found");

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

		my $name = defined $playlist->Fields('name') ? $playlist->Fields('name')->value : "Unnamed";
		my $url  = 'moodlogicplaylist:' . Slim::Utils::Misc::escape($name);
		my $list = getPlaylistItems($playlist);

		if (ref($list) eq 'ARRAY' && scalar @$list > 0) {

			$log->info("Found MoodLogic Playlist: $url");

			# add this playlist to our playlist library
			Slim::Music::Info::updateCacheEntry($url, {
				'TITLE' => join('', $prefix, $name, $suffix),
				'LIST'  => $list,
				'CT'    => 'mlp',
			});

		} else {

			$log->warn("Playlist [$name] has no entries!");
		}

		$playlist->MoveNext unless $playlist->EOF;
	}
}

sub getPlaylistItems {
	my $playlist = shift;

	my $name = $playlist->Fields('name');
	my $item = $name->value;
	my @list = ();

	while (!$playlist->EOF && defined($playlist->Fields('name')->value) &&
		($playlist->Fields('name')->value eq $item)) {

		push @list, Slim::Utils::Misc::fileURLFromPath(catfile(
			$playlist->Fields('volume')->value . $playlist->Fields('path')->value,
			$playlist->Fields('filename')->value
		));

		$playlist->MoveNext;
	}

	$log->info("Adding ", scalar(@list), " items");

	return \@list;
}

1;

__END__
