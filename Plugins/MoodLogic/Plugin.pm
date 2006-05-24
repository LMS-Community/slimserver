package Plugins::MoodLogic::Plugin;

#$Id$
use strict;

use File::Spec::Functions qw(catfile);

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use Plugins::MoodLogic::VarietyCombo;
use Plugins::MoodLogic::InstantMix;
use Plugins::MoodLogic::MoodWheel;

my $conn;
my $rs;
my $auto;
my $playlist;

my $mixer;
my $browser;
my $isScanning = 0;
my $initialized = 0;
our @mood_names;
our %mood_hash;
our %artwork;
my $last_error = 0;
my $isauto = 1;
my %genre_hash = ();

my $lastMusicLibraryFinishTime = undef;

sub strings {
	return '';
}

sub getFunctions {
	return '';
}

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
	Slim::Music::Import->useImporter('MOODLOGIC',$use);
	
	$::d_moodlogic && msg("MoodLogic: using moodlogic: $use\n");
	
	return $use;
}

sub canUseMoodLogic {
	return (Slim::Utils::OSDetect::OS() eq 'win' && initPlugin());
}

sub getDisplayName {
	return 'SETUP_MOODLOGIC';
}

sub enabled {
	return ($::VERSION ge '6.1') && Slim::Utils::OSDetect::OS() eq 'win' && initPlugin();
}

sub shutdownPlugin {
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
	Slim::Music::Import->useImporter('MOODLOGIC',0);
}

sub initPlugin {
	return 1 if $initialized; 
	return 0 if Slim::Utils::OSDetect::OS() ne 'win';
	
	checkDefaults();
	
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
		$::d_moodlogic && msg("MoodLogic: could not find moodlogic mixer component\n");
		return 0;
	}
	
	$browser = Win32::OLE->new("$name.MlMixerFilter");
	
	if (!defined $browser) {
		$::d_moodlogic && msg("MoodLogic: could not find moodlogic filter component\n");
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

	Slim::Music::Import->addImporter('MOODLOGIC', {
		'scan'      => \&startScan,
		'mixer'     => \&mixerFunction,
		'setup'     => \&addGroups,
		'mixerlink' => \&mixerlink,
		'playlistOnly' => 1,
	});

	Slim::Music::Import->useImporter('MOODLOGIC',Slim::Utils::Prefs::get('moodlogic'));
	addGroups();

	Plugins::MoodLogic::InstantMix::init();
	Plugins::MoodLogic::MoodWheel::init();
	Plugins::MoodLogic::VarietyCombo::init();

	$initialized = 1;
	checker($initialized);

	return $initialized;
}

sub addGroups {
	my ($groupRef,$prefRef) = &setupUse();
	Slim::Web::Setup::addGroup('SERVER_SETTINGS','moodlogic',$groupRef,undef,$prefRef);
	Slim::Web::Setup::addChildren('SERVER_SETTINGS','MOODLOGIC');
	Slim::Web::Setup::addCategory('MOODLOGIC',&setupCategory);
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

sub checker {
	my $firstTime = shift || 0;

	return unless (Slim::Utils::Prefs::get('moodlogic'));
	
	if (!$firstTime && !stillScanning() && isMusicLibraryFileChanged()) {
		startScan();
	}

	# make sure we aren't doing this more than once...
	Slim::Utils::Timers::killTimers(0, \&checker);

	# Call ourselves again after 5 seconds
	Slim::Utils::Timers::setTimer(0, (Time::HiRes::time() + 5.0), \&checker);
}

sub startScan {
	
	if (!useMoodLogic()) {
		return;
	}
		
	$::d_moodlogic && msg("MoodLogic: start export\n");
	
	stopScan();
	
	exportFunction();
} 

sub stopScan {
	
	if (stillScanning()) {
		$::d_moodlogic && msg("MoodLogic: Scan already in progress. Restarting\n");
		$isScanning = 0;
		%genre_hash = ();
	}
}

sub stillScanning {
	return $isScanning;
}

sub doneScanning {
	$::d_moodlogic && msg("MoodLogic: done Scanning\n");

	$isScanning = 0;
	%genre_hash = ();
	
	$lastMusicLibraryFinishTime = time();

	Slim::Utils::Prefs::set('lastMoodLogicLibraryDate',(stat $mixer->{JetFilePublic})[9]);
	
	Slim::Music::Import->endImporter('MOODLOGIC');
}

sub getPlaylistItems {
	my $playlist = shift;
	my $item = $playlist->Fields('name')->value;
	my @list;
	
	while (!$playlist->EOF && defined($playlist->Fields('name')->value) && ($playlist->Fields('name')->value eq $item)) {
		push @list,Slim::Utils::Misc::fileURLFromPath(catfile($playlist->Fields('volume')->value.$playlist->Fields('path')->value,$playlist->Fields('filename')->value));
		$playlist->MoveNext;
	}
	$::d_moodlogic && msg("MoodLogic: adding ". scalar(@list)." items\n");
	return \@list;
}

sub exportFunction {
	
	my $prefix = Slim::Utils::Prefs::get('MoodLogicplaylistprefix');
	my $suffix = Slim::Utils::Prefs::get('MoodLogicplaylistsuffix');

	if (!$isScanning) {
		$conn = Win32::OLE->new("ADODB.Connection");
		$rs   = Win32::OLE->new("ADODB.Recordset");
		$playlist   = Win32::OLE->new("ADODB.Recordset");
		$auto   = Win32::OLE->new("ADODB.Recordset");

		$::d_moodlogic && msg("MoodLogic: Opening Object Link...\n");
		$conn->Open('PROVIDER=MSDASQL;DRIVER={Microsoft Access Driver (*.mdb)};DBQ='.$mixer->{JetFilePublic}.';UID=;PWD=F8F4E734E2CAE6B;');
		$rs->Open('SELECT tblSongObject.songId, tblSongObject.profileReleaseYear, tblAlbum.name, tblSongObject.tocAlbumTrack, tblMediaObject.bitrate FROM tblAlbum,tblMediaObject,tblSongObject WHERE tblAlbum.albumId = tblSongObject.tocAlbumId AND tblSongObject.songId = tblMediaObject.songId ORDER BY tblSongObject.songId', $conn, 1, 1);
		#PLAYLIST QUERY
		$playlist->Open('Select tblPlaylist.name, tblMediaObject.volume, tblMediaObject.path, tblMediaObject.filename  From "tblPlaylist", "tblPlaylistSong", "tblMediaObject" where "tblPlaylist"."playlistId" = "tblPlaylistSong"."playlistId" AND "tblPlaylistSong"."songId" = "tblMediaObject"."songId" order by tblPlaylist.playlistId,tblPlaylistSong.playOrder', $conn, 1, 1);
		{
			# AUTO PLAYLIST QUERY: 
			local $Win32::OLE::Warn = 0;
			$auto->Open('Select tblAutoPlaylist.name, tblMediaObject.volume, tblMediaObject.path, tblMediaObject.filename From "tblAutoPlaylist", "tblAutoPlaylistSong", "tblMediaObject" where "tblAutoPlaylist"."playlistId" = tblAutoPlaylistSong.playlistId AND tblAutoPlaylistSong.songId = tblMediaObject.songId order by tblAutoPlaylist.playlistId,tblAutoPlaylistSong.playOrder', $conn, 1, 1);
			if (Win32::OLE->LastError) {
				$isauto = 0;
				$::d_moodlogic && msg("MoodLogic: No AutoPlaylists Found\n");
			};
		}
		
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
		$isScanning = 1;
		$::d_moodlogic && msg("MoodLogic: Begin song scan for ".$browser->FLT_Song_Count()." tracks. \n");
		
		return 1;
	}

	if ($isScanning <= $browser->FLT_Song_Count()) {
		my @album_data = (-1, undef, undef);
	
		my $url;
		my %cacheEntry = ();
		my $song_id = $browser->FLT_Song_SID($isScanning);
		
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
			$cacheEntry{'ALBUM'} = $album_data[1];
			$cacheEntry{'TRACKNUM'} = $album_data[2];
			$cacheEntry{'BITRATE'} = $album_data[3];
			$cacheEntry{'YEAR'} = $album_data[4] if defined $album_data[4];
		}

		$cacheEntry{'CT'}         = Slim::Music::Info::typeFromPath($url,'mp3');
		$cacheEntry{'TAG'}        = 1;
		$cacheEntry{'VALID'}      = 1;
		
		$cacheEntry{'TITLE'}      = $mixer->Mix_SongName(-1);
		$cacheEntry{'ARTIST'}     = $mixer->Mix_ArtistName(-1);
		$cacheEntry{'GENRE'}      = $genre_hash{$browser->FLT_Song_MGID($isScanning)}[0] if (defined $genre_hash{$browser->FLT_Song_MGID($isScanning)});
		$cacheEntry{'SECS'}       = int($mixer->Mix_SongDuration(-1) / 1000);
		
		$cacheEntry{'MOODLOGIC_ID'} = $mixer->{'Seed_SID'} = $song_id;
		$cacheEntry{'MOODLOGIC_MIXABLE'} = $mixer->Seed_SID_Mixable();

		if ($] > 5.007) {

			for my $key (qw(ALBUM ARTIST GENRE TITLE)) {
				$cacheEntry{$key} = Slim::Utils::Unicode::utf8encode($cacheEntry{$key}) if defined $cacheEntry{$key};
			}
		}

		$::d_moodlogic && msg("MoodLogic: Creating entry for track $isScanning: $url\n");

		# that's all for the track
		my $track = Slim::Schema->rs('Track')->updateOrCreate({

			'url'        => $url,
			'attributes' => \%cacheEntry,
			'readTags'   => 1,

		}) || do {

			$::d_moodlogic && msg("MoodLogic: Couldn't create track for: $url\n");

			return 1;
		};

		# Now add to the contributors and genres
		for my $contributor ($track->contributors()) {
			$mixer->{'Seed_AID'} = $browser->FLT_Song_AID($isScanning);

			$contributor->moodlogic_id($mixer->{'Seed_AID'});
			$contributor->moodlogic_mixable($mixer->Seed_AID_Mixable());
			$contributor->update();
		}

		for my $genre ($track->genres()) {

			$genre->moodlogic_id($browser->FLT_Song_MGID($isScanning));

			if (defined $genre_hash{$browser->FLT_Song_MGID($isScanning)}) {
				$genre->moodlogic_mixable($genre_hash{$browser->FLT_Song_MGID($isScanning)}[1]);
			}

			$genre->update();
		}

		my $albumObj = $track->album();

		if (Slim::Utils::Prefs::get('lookForArtwork') && $albumObj) {

			if (!Slim::Music::Import->artwork($albumObj) && !defined $track->thumb()) {

				Slim::Music::Import->artwork($albumObj, $track);
			}
		}
		
		$isScanning++;
		
		return 1;
	}
	
	$::d_moodlogic && msg("MoodLogic: Song scan complete, checking playlists\n");


	if (defined $playlist && !$playlist->EOF) {

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
		return 1;
	}
	
	#TODO find a way to prevent a crash if no auto playlists exist.  they don't for old versions of moodlogic.
	if ($isauto) {

		if (defined $auto && !$auto->EOF) {

			my $name= $auto->Fields('name')->value;
			
			my %cacheEntry = ();
			my $url = 'moodlogicplaylist:' . Slim::Utils::Misc::escape($name);
			$url = Slim::Utils::Misc::fixPath($url);

			$::d_moodlogic && msg("MoodLogic: Found MoodLogic Auto Playlist: $url\n");

			# add this playlist to our playlist library
			$cacheEntry{'TITLE'} =  $prefix . $name . $suffix;
			$cacheEntry{'LIST'} = getPlaylistItems($auto);
			$cacheEntry{'CT'} = 'mlp';
			$cacheEntry{'TAG'} = 1;
			$cacheEntry{'VALID'} = '1';

			Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);

			$auto->MoveNext unless $auto->EOF;
			return 1;
		}
	}

	$rs->Close;
	$playlist->Close;
	$auto->Close if $isauto;
	$conn->Close;

	$::d_moodlogic && msgf("MoodLogic: finished export (%d records)\n", $isScanning - 1);
	
	doneScanning();

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
		$::d_moodlogic && msg('MoodLogic: no/unknown type specified for mood wheel');
		return undef;
	}
	
	push @enabled_moods, $mood_names[1] if ($mixer->{MF_1_Enabled});
	push @enabled_moods, $mood_names[3] if ($mixer->{MF_3_Enabled});
	push @enabled_moods, $mood_names[4] if ($mixer->{MF_4_Enabled});
	push @enabled_moods, $mood_names[6] if ($mixer->{MF_6_Enabled});
	push @enabled_moods, $mood_names[0] if ($mixer->{MF_0_Enabled});

	return \@enabled_moods;
}

sub mixerFunction {
	my $client = shift;
	
	# look for parentParams (needed when multiple mixers have been used)
	my $paramref = defined $client->param('parentParams') ? $client->param('parentParams') : $client->modeParameterStack(-1);
	my $listIndex = $paramref->{'listIndex'};

	my $items = $paramref->{'listRef'};
	my $hierarchy = $paramref->{'hierarchy'};
	my $level	   = $paramref->{'level'} || 0;
	my $descend   = $paramref->{'descend'};

	my $currentItem = $items->[$listIndex];
	my $all = !ref($currentItem);

	my @levels = split(",", $hierarchy);

	my $mix;

	# if we've chosen a particular song
	if ($levels[$level] eq 'track' && $currentItem && $currentItem->moodlogic_mixable()) {

		Slim::Buttons::Common::pushMode($client, 'moodlogic_variety_combo', {'song' => $currentItem});
		$client->pushLeft();

	} elsif ($levels[$level] eq 'artist' && $currentItem && $currentItem->moodlogic_mixable()) {

		# if we've picked an artist 
		Slim::Buttons::Common::pushMode($client, 'moodlogic_mood_wheel', {'artist' => $currentItem});
		$client->pushLeft();

	} elsif ($levels[$level] eq 'genre' && $currentItem && $currentItem->moodlogic_mixable()) {

		# if we've picked a genre 
		Slim::Buttons::Common::pushMode($client, 'moodlogic_mood_wheel', {'genre' => $currentItem});
		$client->pushLeft();

	} else {

		# don't do anything if nothing is mixable
		$client->bumpRight();
	}
}

sub mixerlink {
	my $item = shift;
	my $form = shift;
	my $descend = shift;
	
	if ($descend) {
		$form->{'mixable_descend'} = 1;
	} else {
		$form->{'mixable_not_descend'} = 1;
	}
	
	if ($item->can('moodlogic_mixable') && $item->moodlogic_mixable() && canUseMoodLogic() && Slim::Utils::Prefs::get('moodlogic')) {
		#set up a musicmagic link
		#Slim::Web::Pages->addPageLinks("mixer", {'MOODLOGIC' => "plugins/MoodLogic/mixerlink.html"},1);
		$form->{'mixerlinks'}{'MOODLOGIC'} = "plugins/MoodLogic/mixerlink.html";
	} else {
		#Slim::Web::Pages->addPageLinks("mixer", {'MOODLOGIC' => undef});
	}
	
	return $form;
}

sub getMix {
	my $id = shift @_;
	my $mood = shift @_;
	my $for = shift @_;
	my @instant_mix = ();
	
	$mixer->{VarietyCombo} = 0; # resets mixer
	if (defined $mood) {$::d_moodlogic && msg("MoodLogic: Create $mood mix for $for $id\n")};
	
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
			$::d_moodlogic && msg("MoodLogic: no valid type specified for instant mix");
			return undef;
		}
	} else {
		$::d_moodlogic && msg("MoodLogic: no valid mood specified for instant mix");
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
		push @instant_mix, Slim::Utils::Misc::fileURLFromPath($mixer->Mix_SongFile($i));
	}

	return \@instant_mix;
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

sub setupUse {
	my $client = shift;
	my %setupGroup = (
		'PrefOrder' => ['moodlogic']
		,'Suppress_PrefLine' => 1
		,'Suppress_PrefSub' => 1
		,'GroupLine' => 1
		,'GroupSub' => 1
	);
	my %setupPrefs = (
		'moodlogic' => {
			'validate' => \&Slim::Utils::Validate::trueFalse
			,'changeIntro' => ""
			,'options' => {
				'1' => string('USE_MOODLOGIC')
				,'0' => string('DONT_USE_MOODLOGIC')
			}
			,'onChange' => sub {
					my ($client,$changeref,$paramref,$pageref) = @_;
					
					foreach my $client (Slim::Player::Client::clients()) {
						Slim::Buttons::Home::updateMenu($client);
					}
					Slim::Music::Import->useImporter('MOODLOGIC',$changeref->{'moodlogic'}{'new'});
					Slim::Music::Info::clearPlaylists('moodlogicplaylist:');
					Slim::Music::Import->startScan('MOODLOGIC');
				}
			,'optionSort' => 'KR'
			,'inputTemplate' => 'setup_input_radio.html'
		}
	);
	return (\%setupGroup,\%setupPrefs);
}

sub checkDefaults {

	if (!Slim::Utils::Prefs::isDefined('moodlogic')) {
		Slim::Utils::Prefs::set('moodlogic',0)
	}
	
	if (!Slim::Utils::Prefs::isDefined('moodlogicscaninterval')) {
		Slim::Utils::Prefs::set('moodlogicscaninterval',60)
	}
	
	if (!Slim::Utils::Prefs::isDefined('MoodLogicplaylistprefix')) {
		Slim::Utils::Prefs::set('MoodLogicplaylistprefix','MoodLogic: ');
	}
	
	if (!Slim::Utils::Prefs::isDefined('MoodLogicplaylistsuffix')) {
		Slim::Utils::Prefs::set('MoodLogicplaylistsuffix','');
	}
	
	if (!Slim::Utils::Prefs::isDefined('instantMixMax')) {
		Slim::Utils::Prefs::set('instantMixMax',12);
	}
	
	if (!Slim::Utils::Prefs::isDefined('varietyCombo')) {
		Slim::Utils::Prefs::set('varietyCombo',50);
	}
}

sub setupCategory {
	my %setupCategory =(
		'title' => string('SETUP_MOODLOGIC')
		,'parent' => 'SERVER_SETTINGS'
		,'GroupOrder' => ['Default','MoodLogicPlaylistFormat']
		,'Groups' => {
			'Default' => {
					'PrefOrder' => ['instantMixMax','varietyCombo','moodlogicscaninterval']
				}
			,'MoodLogicPlaylistFormat' => {
					'PrefOrder' => ['MoodLogicplaylistprefix','MoodLogicplaylistsuffix']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => string('SETUP_MOODLOGICPLAYLISTFORMAT')
					,'GroupDesc' => string('SETUP_MOODLOGICPLAYLISTFORMAT_DESC')
					,'GroupLine' => 1
					,'GroupSub' => 1
				}
			}
		,'Prefs' => {
			'MoodLogicplaylistprefix' => {
					'validate' => \&Slim::Utils::Validate::acceptAll
					,'PrefSize' => 'large'
				}
			,'MoodLogicplaylistsuffix' => {
					'validate' => \&Slim::Utils::Validate::acceptAll
					,'PrefSize' => 'large'
				}
			,'moodlogicscaninterval' => {
					'validate' => \&Slim::Utils::Validate::number
					,'validateArgs' => [0,undef,1000]
				}
			,'instantMixMax'	=> {
					'validate' => \&Slim::Utils::Validate::isInt
					,'validateArgs' => [1,undef,1]
				}
			,'varietyCombo'	=> {
					'validate' => \&Slim::Utils::Validate::isInt
					,'validateArgs' => [1,100,1,1]
				}
		}
	);
	return (\%setupCategory);
};

sub webPages {
	my %pages = (
		"instant_mix\.(?:htm|xml)" => \&instant_mix,
		"mood_wheel\.(?:htm|xml)" => \&mood_wheel,
	);

	return (\%pages);
}

sub mood_wheel {
	my ($client, $params) = @_;

	my $items = "";

	my $song   = $params->{'song'};
	my $artist = $params->{'artist'};
	my $album  = $params->{'album'};
	my $genre  = $params->{'genre'};
	my $player = $params->{'player'};

	my $itemnumber = 0;

	if (defined $artist && $artist ne "") {

		$items = getMoodWheel(Slim::Schema->find('Contributor', $artist)->moodlogic_id, 'artist');

	} elsif (defined $genre && $genre ne "" && $genre ne "*") {

		$items = getMoodWheel(Slim::Schema->find('Genre', $genre)->moodlogic_id, 'genre');

	} else {

		$::d_moodlogic && msg('MoodLogic: no/unknown type specified for mood wheel');
		return undef;
	}

	#$params->{'pwd_list'} = Slim::Web::Pages::generate_pwd_list($genre, $artist, $album, $player,$params->{'webroot'});
	
	$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/mood_wheel_pwdlist.html", $params)};
	$params->{'mood_list'} = $items;

	return Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/mood_wheel.html", $params);
}

sub instant_mix {
	my ($client, $params) = @_;

	my $output = "";
	my $items  = "";

	my $song   = $params->{'song'};
	my $artist = $params->{'artist'};
	my $album  = $params->{'album'};
	my $genre  = $params->{'genre'};
	my $player = $params->{'player'};
	my $mood   = $params->{'mood'};
	my $p0     = $params->{'p0'};

	my $itemnumber = 0;
	my $track      = Slim::Schema->find('Track', $song);

	$params->{'browse_items'} = [];
	$params->{'levelName'} = "track";

	if (defined $mood && $mood ne "") {
		$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/mood_wheel_pwdlist.html", $params)};
	}

	if (defined $song && $song ne "") {
		$params->{'src_mix'} = Slim::Music::Info::standardTitle(undef, $track);
	} elsif (defined $mood && $mood ne "") {
		$params->{'src_mix'} = $mood;
	}

	$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/instant_mix_pwdlist.html", $params)};

	if (defined $song && $song ne "") {

		$items = getMix($track->moodlogic_id, undef, 'song');

	} elsif (defined $artist && $artist ne "" && $artist ne "*" && $mood ne "") {

		$items = getMix(Slim::Schema->find('Contributor', $artist)->moodlogic_id, $mood, 'artist');

	} elsif (defined $genre && $genre ne "" && $genre ne "*" && $mood ne "") {

		$items = getMix(Slim::Schema->find('Genre', $genre)->moodlogic_id, $mood, 'genre');

	} else {

		$::d_moodlogic && msg('MoodLogic: no/unknown type specified for instant mix');
		return undef;
	}

	if (defined $items && ref $items eq "ARRAY" && defined $client) {
		# We'll be using this to play the entire mix using 
		# playlist (add|play|load|insert)tracks listref=moodlogic_mix
		$client->param('moodlogic_mix',$items);
	} else {
		$items = [];
	}

	if (scalar @$items) {

		push @{$params->{'browse_items'}}, {

			'text'         => Slim::Utils::Strings::string('THIS_ENTIRE_PLAYLIST'),
			'attributes'   => "&listRef=moodlogic_mix",
			'odd'          => ($itemnumber + 1) % 2,
			'webroot'      => $params->{'webroot'},
			'skinOverride' => $params->{'skinOverride'},
			'player'       => $params->{'player'},
		};

		$itemnumber++;
	}

	for my $item (@$items) {

		my %form = ();

		# If we can't get an object for this url, skip it, as the
		# user's database is likely out of date. Bug 863
		my $trackObj  = Slim::Schema->rs('Track')->objectForUrl($item) || next;

		$trackObj->displayAsHTML(\%form, 0);

		$form{'attributes'} = join('=', '&track.id', $trackObj->id);

		$itemnumber++;

		push @{$params->{'browse_items'}}, \%form;
		
	}

	if (defined $p0 && defined $client) {

		$client->execute(["playlist", $p0 eq "append" ? "addtracks" : "playtracks", "listref=moodlogic_mix"]);
	}

	return Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/instant_mix.html", $params);
}

1;

__END__
