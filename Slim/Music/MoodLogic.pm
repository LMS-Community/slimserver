package Slim::Music::MoodLogic;

#$Id: MoodLogic.pm,v 1.10 2004/04/28 13:10:53 kdf Exp $
use strict;

use File::Spec::Functions qw(catfile);

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

#$::d_moodlogic = 1;
#$::d_moodlogic_verbose = 1;

my $mixer;
my $browser;
my $isScanning = 0;
my $initialized = 0;
my @mood_names;
my %mood_hash;
my @playlists=();
my %artwork;
my $last_error = 0;
my $isauto = 1;

sub useMoodLogic {
	my $newValue = shift;
	my $can = canUseMoodLogic();
	
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

	$::d_moodlogic && msg("using moodlogic: $use\n");
	
	return $use;
}

sub canUseMoodLogic {
	return (Slim::Utils::OSDetect::OS() eq 'win' && init());
}

sub playlists {
	return \@playlists;
}

sub init {
	return $initialized if ($initialized == 1);
	
	require Win32::OLE;
	import Win32::OLE qw(EVENTS);
	
		Win32::OLE->Option(Warn => \&OLEError);
	my $name = "mL_MixerCenter";
	
	$mixer = Win32::OLE->new("$name.MlMixerComponent");
	
	if (!defined $mixer) {
		$name = "mL_Mixer";
		$mixer = Win32::OLE->new("$name.MlMixerComponent");
	}
	
	if (!defined $mixer) {
		$::d_moodlogic && msg("could not find moodlogic mixer component\n");
		return 0;
	}
	
	$browser = Win32::OLE->new("$name.MlMixerFilter");
	
	if (!defined $browser) {
		$::d_moodlogic && msg("could not find moodlogic filter component\n");
		return 0;
	}
	
	Win32::OLE->WithEvents($mixer, \&event_hook);
	
	$mixer->{JetPwdMixer} = 'C393558B6B794D';
	$mixer->{JetPwdPublic} = 'F8F4E734E2CAE6B';
	$mixer->{JetPwdPrivate} = '5B1F074097AA49F5B9';
	$mixer->{UseStrings} = 1;
	$mixer->Initialize();
	$mixer->{MixMode} = 0;
	
	if ($last_error != 0) {
		$::d_moodlogic && msg("rebuilding mixer db\n");
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
	
	$initialized = 1;
	return $initialized;
}

sub checker {
	if (useMoodLogic() && !stillScanning()) {
		startScan();
	}
}

sub startScan {
	if (!useMoodLogic()) {
		return;
	}
		
	$::d_moodlogic && msg("startScan: start export\n");
	stopScan();
	@playlists = ();

	$::d_moodlogic && msg("Clearing ID3 cache\n");

	Slim::Music::Info::clearCache();

	Slim::Utils::Scheduler::add_task(\&exportFunction);
	$isScanning = 1;

	# start the checker
	checker();
	
} 

sub stopScan {
	if (stillScanning()) {
		Slim::Utils::Scheduler::remove_task(\&exportFunction);
		doneScanning();
	}
}

sub stillScanning {
	return $isScanning;
}

sub doneScanning {
	$::d_moodlogic && msg("MoodLogic: done Scanning\n");

	$isScanning = 0;
	
	if (Slim::Utils::Prefs::get('lookForArtwork')) {Slim::Utils::Scheduler::add_task(\&artScan);}
	
	@playlists = Slim::Music::Info::sortIgnoringCase(@playlists);
}

sub artScan {
	my @albums = keys %artwork;
	my $album = $albums[0];
	my $thumb = Slim::Music::Info::haveThumbArt($artwork{$album});
	
	if (defined $thumb && $thumb) {
		$::d_artwork && Slim::Utils::Misc::msg("Caching $thumb for $album\n");
		Slim::Music::Info::updateArtworkCache($artwork{$album}, {'ALBUM' => $album, 'THUMB' => $thumb});
	}
	
	delete $artwork{$album};
	
	if (!%artwork) {
		$::d_artwork && Slim::Utils::Misc::msg("Completed Artwork Scan\n");
		return 0;
	}
	
	return 1;
}

sub getPlaylistItems {
	my $playlist = shift;
	my $item = $playlist->Fields('name')->value;
	my @list;
	
	while (!$playlist->EOF && defined($playlist->Fields('name')->value) && ($playlist->Fields('name')->value eq $item)) {
		push @list,"file://localhost/".catfile($playlist->Fields('volume')->value.$playlist->Fields('path')->value,$playlist->Fields('filename')->value);
		$playlist->MoveNext;
	}
	$::d_moodlogic && msg("adding ". scalar(@list)." items\n");
	return \@list;
}

sub exportFunction {
	
	my $conn = Win32::OLE->new("ADODB.Connection");
	my $rs   = Win32::OLE->new("ADODB.Recordset");
	my $playlist   = Win32::OLE->new("ADODB.Recordset");
	my $auto   = Win32::OLE->new("ADODB.Recordset");

	$conn->Open('PROVIDER=MSDASQL;DRIVER={Microsoft Access Driver (*.mdb)};DBQ='.$mixer->{JetFilePublic}.';UID=;PWD=F8F4E734E2CAE6B;');
	$rs->Open('SELECT tblSongObject.songId, tblSongObject.profileReleaseYear, tblAlbum.name, tblSongObject.tocAlbumTrack, tblMediaObject.bitrate, tblMediaObject.fileSize FROM tblAlbum,tblMediaObject,tblSongObject WHERE tblAlbum.albumId = tblSongObject.tocAlbumId AND tblSongObject.songId = tblMediaObject.songId ORDER BY tblSongObject.songId', $conn, 1, 1);
	#PLAYLIST QUERY
	$playlist->Open('Select tblPlaylist.name, tblMediaObject.volume, tblMediaObject.path, tblMediaObject.filename  From "tblPlaylist", "tblPlaylistSong", "tblMediaObject" where "tblPlaylist"."playlistId" = "tblPlaylistSong"."playlistId" AND "tblPlaylistSong"."songId" = "tblMediaObject"."songId" order by tblPlaylist.playlistId,tblPlaylistSong.playOrder', $conn, 1, 1);
	# AUTO PLAYLIST QUERY: 
	$auto->Open('Select tblAutoPlaylist.name, tblMediaObject.volume, tblMediaObject.path, tblMediaObject.filename From "tblAutoPlaylist", "tblAutoPlaylistSong", "tblMediaObject" where "tblAutoPlaylist"."playlistId" = tblAutoPlaylistSong.playlistId AND tblAutoPlaylistSong.songId = tblMediaObject.songId order by tblAutoPlaylist.playlistId,tblAutoPlaylistSong.playOrder', $conn, 1, 1);

	$browser->filterExecute();
	my %genre_hash;
	my $count = $browser->FLT_Genre_Count();
	
	for (my $i=1; $i<$count; $i++) {
		my $genre_id = $browser->FLT_Genre_MGID($i);
		$mixer->{Seed_MGID} = -$genre_id;
		my $genre_name = $mixer->Mix_GenreName(-1);
		$mixer->{Seed_MGID} = $genre_id;
		my $genre_mixable = $mixer->Seed_MGID_Mixable();
		$genre_hash{$genre_id} = [$genre_name, $genre_mixable];
	}
	
	$count = $browser->FLT_Song_Count();
	my @album_data = (-1, undef, undef);
	
	for (my $i=1; $i<$count; $i++) {
		my $filename;
		my %cacheEntry = ();
		my $song_id = $browser->FLT_Song_SID($i);
		
		$mixer->{Seed_SID} = -$song_id;
		$filename = Slim::Utils::Misc::fileURLFromPath($mixer->Mix_SongFile(-1));

		# merge album info, from query ('cause it is not available via COM)
		while (defined $rs && !$rs->EOF && $album_data[0] < $song_id && defined $rs->Fields('songId')) {
			@album_data = (
				$rs->Fields('songId')->value,
				$rs->Fields('name')->value,
				$rs->Fields('tocAlbumTrack')->value,
				$rs->Fields('bitrate')->value,
				$rs->Fields('profileReleaseYear')->value,
				$rs->Fields('fileSize')->value
			);
			$rs->MoveNext;
		}

		while (defined $playlist && !$playlist->EOF) {
			my $name= $playlist->Fields('name')->value;
			my %cacheEntry = ();
			my $url = 'moodlogicplaylist:' . Slim::Web::HTTP::escape($name);
			if (!defined($playlists[-1]) || $playlists[-1] ne $name) {
				push @playlists, $url;
				$::d_moodlogic && msg("Found MoodLogic Playlist: $url\n");
			} else {print $playlists[-1];}
			$::d_moodlogic && msg("got a playlist ($url) named $name\n");
			# add this playlist to our playlist library
			$cacheEntry{'TITLE'} = Slim::Utils::Prefs::get('MoodLogicplaylistprefix') . $name . Slim::Utils::Prefs::get('MoodLogicplaylistsuffix');
			$cacheEntry{'LIST'} = getPlaylistItems($playlist);
			$cacheEntry{'CT'} = 'itu';
			$cacheEntry{'TAG'} = 1;
			$cacheEntry{'VALID'} = '1';
			Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);
			$playlist->MoveNext unless $playlist->EOF;
		}
		
		if ($isauto) { #TODO find a way to prevent a crash if no auto playlists exist.  they don't for old versions of moodlogic.
			while (defined $auto && !$auto->EOF) {
				my $name= $auto->Fields('name')->value;
				
				my %cacheEntry = ();
				my $url = 'moodlogicplaylist:' . Slim::Web::HTTP::escape($name);
				if ($playlists[-1] ne $name) {
					push @playlists, $url;
					$::d_moodlogic && msg("Found MoodLogic Auto Playlist: $url\n");
				}
				$::d_moodlogic && msg("got a playlist ($url) named $name\n");
				# add this playlist to our playlist library
				$cacheEntry{'TITLE'} = Slim::Utils::Prefs::get('MoodLogicplaylistprefix') . $name . Slim::Utils::Prefs::get('MoodLogicplaylistsuffix');
				$cacheEntry{'LIST'} = getPlaylistItems($auto);
				$cacheEntry{'CT'} = 'itu';
				$cacheEntry{'TAG'} = 1;
				$cacheEntry{'VALID'} = '1';
				Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);
				$auto->MoveNext unless $auto->EOF;
			}
		}
		
		if (defined $album_data[0] && $album_data[0] == $song_id && $album_data[1] ne "") {
			$cacheEntry{'ALBUM'} = $album_data[1];
			$cacheEntry{'TRACKNUM'} = $album_data[2];
			$cacheEntry{'BITRATE'} = $album_data[3];
			$cacheEntry{'YEAR'} = $album_data[4];
			$cacheEntry{'SIZE'} = $album_data[5];
		}
		$cacheEntry{'CT'} = 'mp3';
		$cacheEntry{'TAG'} = 1;
		$cacheEntry{'VALID'} = 1;
		$cacheEntry{'TITLE'} = $mixer->Mix_SongName(-1);
		$cacheEntry{'ARTIST'} = $mixer->Mix_ArtistName(-1);
		$cacheEntry{'GENRE'} = $genre_hash{$browser->FLT_Song_MGID($i)}[0] if (defined $genre_hash{$browser->FLT_Song_MGID($i)});
		$cacheEntry{'SECS'} = int($mixer->Mix_SongDuration(-1) / 1000);
		$cacheEntry{'OFFSET'} = 0;
		$cacheEntry{'BLOCKALIGN'} = 1;
		
		$cacheEntry{'MOODLOGIC_SONG_ID'} = $song_id;
		$cacheEntry{'MOODLOGIC_ARTIST_ID'} = $browser->FLT_Song_AID($i);
		$cacheEntry{'MOODLOGIC_GENRE_ID'} = $browser->FLT_Song_MGID($i);
		$mixer->{Seed_SID} = $song_id;
		$cacheEntry{'MOODLOGIC_SONG_MIXABLE'} = $mixer->Seed_SID_Mixable();
		$mixer->{Seed_AID} = $browser->FLT_Song_AID($i);
		$cacheEntry{'MOODLOGIC_ARTIST_MIXABLE'} = $mixer->Seed_AID_Mixable();
		$cacheEntry{'MOODLOGIC_GENRE_MIXABLE'} = $genre_hash{$browser->FLT_Song_MGID($i)}[1] if (defined $genre_hash{$browser->FLT_Song_MGID($i)});
			
		Slim::Music::Info::updateCacheEntry($filename, \%cacheEntry);

		if (Slim::Utils::Prefs::get('lookForArtwork')) {
			if ($cacheEntry{'ALBUM'} && !exists $artwork{$cacheEntry{'ALBUM'}} && !defined Slim::Music::Info::cacheItem($filename,'THUMB')) { 	 
				$artwork{$cacheEntry{'ALBUM'}} = Slim::Utils::Misc::pathFromFileURL($filename); 	 
				$::d_artwork && msg("$cacheEntry{'ALBUM'} refers to ".Slim::Utils::Misc::pathFromFileURL($filename)."\n"); 	 
			}
		}
		Slim::Music::Info::updateGenreMixCache(\%cacheEntry);
		Slim::Music::Info::updateArtistMixCache(\%cacheEntry);
	}

	$rs->Close;
	$playlist->Close;
	$auto->Close;
	$conn->Close;
	
	doneScanning();
	$::d_moodlogic && msg("exportFunction: finished export ($count records, ".scalar @playlists." playlists)\n");
	return 0;
}

sub getMoodWheel {
	my $id = shift @_;
	my $for = shift @_;
	my @enabled_moods = ();
	
	if ($for eq "genre") {
		$mixer->{Seed_MGID} = $id;
		$mixer->{MixMode} = 3;
	} elsif ($for eq "artist") {
		$mixer->{Seed_AID} = $id;
		$mixer->{MixMode} = 2;
	} else {
		$::d_moodlogic && msg('no/unknown type specified for mood wheel');
		return undef;
	}
	
	push @enabled_moods, $mood_names[1] if ($mixer->{MF_1_Enabled});
	push @enabled_moods, $mood_names[3] if ($mixer->{MF_3_Enabled});
	push @enabled_moods, $mood_names[4] if ($mixer->{MF_4_Enabled});
	push @enabled_moods, $mood_names[6] if ($mixer->{MF_6_Enabled});
	push @enabled_moods, $mood_names[0] if ($mixer->{MF_0_Enabled});
	
	return @enabled_moods;
}

sub getMix {
	my $id = shift @_;
	my $mood = shift @_;
	my $for = shift @_;
	my @instant_mix = ();
	
	$mixer->{VarietyCombo} = 0; # resets mixer
	if (defined $mood) {$::d_moodlogic && msg("Create $mood mix for $for $id\n")};
	
	if ($for eq "song") {
		$mixer->{Seed_SID} = $id;
		$mixer->{MixMode} = 0;
	} elsif (defined $mood && defined $mood_hash{$mood}) {
		$mixer->{MoodField} = $mood_hash{$mood};
		if ($for eq "artist") {
			$mixer->{Seed_AID} = $id;
			$mixer->{MixMode} = 2;
		} elsif ($for eq "genre") {
			$mixer->{Seed_MGID} = $id;
			$mixer->{MixMode} = 3;
		} else {
			$::d_moodlogic && msg("no valid type specified for instant mix");
			return undef;
		}
	} else {
		$::d_moodlogic && msg("no valid mood specified for instant mix");
		return undef;
	}

	$mixer->Process();	# the VarietyCombo property can only be set
						# after an initial mix has been created
	my $count = Slim::Utils::Prefs::get('instantMixMax');
	my $variety = Slim::Utils::Prefs::get('varietyCombo');
	while ($mixer->Mix_PlaylistSongCount() < $count && $mixer->{VarietyCombo} > $variety)
	{
		# $mixer->{VarietyCombo} = 0 causes a mixer reset, so we have to avoid it.
		$mixer->{VarietyCombo} = $mixer->{VarietyCombo} == 10 ? $mixer->{VarietyCombo} - 9 : $mixer->{VarietyCombo} - 10;
		$mixer->Process(); # recreate mix
	}

	$count = $mixer->Mix_PlaylistSongCount();

	for (my $i=1; $i<=$count; $i++) {
		push @instant_mix, $mixer->Mix_SongFile($i);
	}

	return @instant_mix;
}

sub event_hook {
	my ($mixer,$event,@args) = @_;
	return if ($event eq "TaskProgress");
	$last_error = $args[0]->Value();
	print "MoodLogic Error Event triggered: '$event',".join(",", $args[0]->Value())."\n";
	print $mixer->ErrorDescription()."\n";
}

sub OLEError {
	$::d_moodlogic && msg(Win32::OLE->LastError() . "\n");
}

sub DESTROY {
	Win32::OLE->Uninitialize();
}

1;
__END__

