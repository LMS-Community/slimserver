package Slim::Music::MusicMagic;

# $Id$

use strict;

use File::Spec::Functions qw(catfile);

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use LWP ();

my $isScanning = 0;
my $initialized = 0;
our %artwork;
my $last_error = 0;
my $export = '';
my $count = 0;
my $scan = 0;
my $MMSHost;
my $MMSport;

my $lastMusicLibraryFinishTime = undef;

sub useMusicMagic {
	my $newValue = shift;
	my $can = canUseMusicMagic();
	
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
	Slim::Music::Import::useImporter('musicmagic',$use);

	$::d_musicmagic && msg("using musicmagic: $use\n");
	
	return $use;
}

sub canUseMusicMagic {
	return init();
}

sub playlists {
	return Slim::Music::Info::playlists;
}

sub init {
	return $initialized if ($initialized == 1);
	checkDefaults();
	
	my $MMSport = Slim::Utils::Prefs::get('MMSport');
	my $MMSHost = Slim::Utils::Prefs::get('MMSHost');
	my $req = new HTTP::Request GET => "http://$MMSHost:$MMSport/api/version";
	my $res = (new LWP::UserAgent)->request($req);
	if ($res->is_error()) {
		$initialized = 0;
	} else {
		my $content = $res->content();
		$::d_musicmagic && msg("$content\n");
	
		# Note: Check version restrictions if any
		$initialized = 1;
		Slim::Music::Import::addImporter('musicmagic',\&startScan,\&mixerFunction,\&addGroups);
		Slim::Player::Source::registerProtocolHandler("musicmagicplaylist", "0");
		addGroups();
	}
	
	return $initialized;
}

sub addGroups {
	Slim::Web::Setup::addCategory('musicmagic',&setupCategory);
	my ($groupRef,$prefRef) = &setupGroup();
	Slim::Web::Setup::addGroup('server','musicmagic',$groupRef,2,$prefRef);
	Slim::Web::Setup::addChildren('server','musicmagic');
}

sub isMusicLibraryFileChanged {
	my $MMSport = Slim::Utils::Prefs::get('MMSport');
	my $MMSHost = Slim::Utils::Prefs::get('MMSHost');
	my $req = new HTTP::Request GET => "http://$MMSHost:$MMSport/api/cacheid";
	my $res = (new LWP::UserAgent)->request($req);
	if ($res->is_error()) {
		return 0;
	}

	my $fileMTime = $res->content();
	
	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, $lastMusicLibraryDate is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	my $oldTime = Slim::Utils::Prefs::get('lastMusicMagicLibraryDate') || 0;
	if ($fileMTime > $oldTime) {
		my $musicmagicscaninterval = Slim::Utils::Prefs::get('musicmagicscaninterval') || 1;
		$::d_musicmagic && msg("music library has changed!\n");
		$lastMusicLibraryFinishTime = 0 unless $lastMusicLibraryFinishTime;
		if (time()-$lastMusicLibraryFinishTime > $musicmagicscaninterval) {
			return 1;
		} else {
			$::d_musicmagic && msg("waiting for $musicmagicscaninterval seconds to pass before rescanning\n");
		}
	}
	
	return 0;
}

sub checker {
	return unless (useMusicMagic());
	
	if (!stillScanning() && isMusicLibraryFileChanged()) {
		startScan();
	}

	# make sure we aren't doing this more than once...
	Slim::Utils::Timers::killTimers(0, \&checker);

	# Call ourselves again after 5 seconds
	Slim::Utils::Timers::setTimer(0, (Time::HiRes::time() + 5.0), \&checker);
}

sub startScan {
	if (!useMusicMagic()) {
		return;
	}
		
	$::d_musicmagic && msg("MusicMagic: start export\n");
	stopScan();
	Slim::Music::Info::clearPlaylists();

	$isScanning = 1;
	$export = 'start';
	$scan = 0;
	
	# start the checker
	checker();
	
	Slim::Utils::Scheduler::add_task(\&exportFunction);
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
	$::d_musicmagic && msg("MusicMagic: done Scanning\n");

	$isScanning = 0;
	$scan = 0;
	
	$lastMusicLibraryFinishTime = time();

	my $MMSport = Slim::Utils::Prefs::get('MMSport');
	my $MMSHost = Slim::Utils::Prefs::get('MMSHost');
	my $req = new HTTP::Request GET => "http://$MMSHost:$MMSport/api/cacheid";
	my $res = (new LWP::UserAgent)->request($req);
	if (!$res->is_error()) {
		my $fileMTime = $res->content();
		Slim::Utils::Prefs::set('lastMusicMagicLibraryDate', $fileMTime);
	}
	
	Slim::Music::Info::generatePlaylists();
	
	Slim::Music::Import::endImporter('musicmagic');

}

sub convertPath {
	my $mmsPath = shift @_;
	
	return $mmsPath if  (Slim::Utils::Prefs::get('MMSHost') eq 'localhost');
	
	my $remoteRoot = Slim::Utils::Prefs::get('MMSremoteRoot');
	my $nativeRoot = Slim::Utils::Prefs::get('audiodir');
	my $original = $mmsPath;
	my $winPath = $mmsPath =~ m/\\/; # test if this is a windows path

	if (Slim::Utils::OSDetect::OS() eq 'unix')
	{
		# we are unix
		if ($winPath)
		{
			# we are running music magic on winders but
			# slim server is running on unix

			# convert any windozes paths to unix style
			$remoteRoot =~ tr/\\/\//;
			$::d_musicmagic &&  msg("$remoteRoot :: $nativeRoot \n");

			# convert windozes paths to unix style
			$mmsPath =~ tr/\\/\//;
			# convert remote root to native root
			$mmsPath =~ s/$remoteRoot/$nativeRoot/;
			}
		} else {
			# we are windows
			if (!$winPath)
			{
				# we recieved a unix path from music match
				# convert any unix paths to windows style
				# convert windows native to unix first
				# cuz matching dont work unless we do
				$nativeRoot =~ tr/\\/\//;
				$::d_musicmagic &&  msg("$remoteRoot :: $nativeRoot \n");

				# convert unix root to windows root
				$mmsPath =~ s/$remoteRoot/$nativeRoot/;
				# convert unix paths to windows
				$mmsPath =~ tr/\//\\/;
			}
		}
	$::d_musicmagic && msg("$original is now $mmsPath\n");
	return $mmsPath
}

sub exportFunction {
	my $playlist;
	my $req;
	my $res;
	my @lines;
	
	return 0 if $export eq 'done';
	
	if ($export eq 'start') {
		$MMSport = Slim::Utils::Prefs::get('MMSport');
		$MMSHost = Slim::Utils::Prefs::get('MMSHost');
		$req = new HTTP::Request GET => "http://$MMSHost:$MMSport/api/genres?active";
		$res = (new LWP::UserAgent)->request($req);
		if ($res->is_error()) {
			# NYI
		} else {
			@lines = split(/\n/, $res->content());
			$count = scalar @lines;
			$::d_musicmagic && msg("Got $count active genre(s).\n");
		
			for (my $i=0; $i < $count; $i++) {
				#print "Genre $lines[$i]\n";
				Slim::Music::Info::updateGenreMMMixCache($lines[$i]);
			}
		}
		$export = 'artists';
		return 1;
	}
	if ($export eq 'artists') {
		$req = new HTTP::Request GET => "http://$MMSHost:$MMSport/api/artists?active";
		$res = (new LWP::UserAgent)->request($req);
		if ($res->is_error()) {
			# NYI
		} else {
			@lines = split(/\n/, $res->content());
			$count = scalar @lines;
			$::d_musicmagic && msg("Got $count active artist(s).\n");

			for (my $i=0; $i < $count; $i++) {
				Slim::Music::Info::updateArtistMMMixCache($lines[$i]);
			}
		}
		$export = 'count';
		return 1;
	}
	
	if ($export eq 'count') {
		$req = new HTTP::Request GET => "http://$MMSHost:$MMSport/api/getSongCount";
		$res = (new LWP::UserAgent)->request($req);
		if ($res->is_error()) {
			$count = 0;
		} else {
			$count = $res->content(); # convert to integer
		}
		$scan = 0;
		$export = 'songs';
		return 1;
	}
	
	while ($export eq 'songs' && $scan <= $count) {
		my %cacheEntry = ();
		my %songInfo = ();
		
		$req = new HTTP::Request GET => "http://$MMSHost:$MMSport/api/getSong?index=$scan";
		$res = (new LWP::UserAgent)->request($req);
		if ($res->is_error()) {
				# NYI
		} else {
			$scan++;
			@lines = split(/\n/, $res->content());
			my $count2 = scalar @lines;
			for (my $j=0; $j < $count2; $j++) {
				my ($song_field, $song_value) = $lines[$j] =~ /(\w+) (.*)/;
				$songInfo{$song_field} = $song_value;
			}
		
			$cacheEntry{'ALBUM'} = $songInfo{'album'};
			$cacheEntry{'TRACKNUM'} = $songInfo{'track'};
			$cacheEntry{'BITRATE'} = $songInfo{'bitrate'};
			$cacheEntry{'YEAR'} = $songInfo{'year'};
			$cacheEntry{'SIZE'} = $songInfo{'bytes'};
		
			$cacheEntry{'CT'} = Slim::Music::Info::typeFromPath($songInfo{'file'},'mp3');
			$cacheEntry{'TAG'} = 1;
			$cacheEntry{'VALID'} = 1;
			$cacheEntry{'TITLE'} = $songInfo{'name'};
			$cacheEntry{'ARTIST'} = $songInfo{'artist'};
			$cacheEntry{'GENRE'} = $songInfo{'genre'};
			$cacheEntry{'SECS'} = $songInfo{'seconds'};
			$cacheEntry{'OFFSET'} = 0;
			$cacheEntry{'BLOCKALIGN'} = 1;
		
			if ($songInfo{'active'} eq 'yes') {
				$cacheEntry{'MUSICMAGIC_SONG_MIXABLE'} = 1;
				$cacheEntry{'MUSICMAGIC_ALBUM_MIXABLE'}  = 1;
			}
		
			
			$::d_musicmagic && msg("Exporting song $scan: $songInfo{'file'}\n");
		
			my $fileurl = Slim::Utils::Misc::fileURLFromPath($songInfo{'file'});
			#$fileurl =~ tr/\\/\//;
			#$fileurl =~ s,\/\/\/\/,\/\/\/,;
			
			Slim::Music::Info::updateCacheEntry($fileurl, \%cacheEntry);
			
			# NYI: MMM has more ways to access artwork...
			if (Slim::Utils::Prefs::get('lookForArtwork')) {
				if ($cacheEntry{'ALBUM'} && !Slim::Music::Import::artwork($cacheEntry{'ALBUM'}) && !defined Slim::Music::Info::cacheItem($fileurl,'THUMB')) {
					Slim::Music::Import::artwork($cacheEntry{'ALBUM'},$fileurl);
				}
			}
			Slim::Music::Info::updateAlbumMMMixCache(\%cacheEntry);
		}
		if ($scan == $count) {
			$export = 'playlist';
		}
		
		# would be nice to chunk this in groups.  One at a time is slow, 
		# but doing it all at once breaks audio up when its a full scan.
		return 1 if !($scan % 1);
	}
	
	if ($export eq 'playlist') {
		$req = new HTTP::Request GET => "http://$MMSHost:$MMSport/api/playlists";
		$res = (new LWP::UserAgent)->request($req);
		if ($res->is_error()) {
			$count = 0;
		} else {
			@lines = split(/\n/, $res->content());
			$count = scalar @lines;
		}
		#print "Checking $count playlist(s)\n";
		
		for (my $i = 0; $i < $count; $i++) {
			my %cacheEntry = ();
			my @songs;
			
			$req = new HTTP::Request GET => "http://$MMSHost:$MMSport/api/getPlaylist?index=$i";
			$res = (new LWP::UserAgent)->request($req);
			if ($res->is_error()) {
				# NYI
			} else {
				@songs = split(/\n/, $res->content());
				my $count2 = scalar @songs;
			
				my $name = $lines[$i];
				my $url = 'musicmagicplaylist:' . Slim::Web::HTTP::escape($name);
				if (!defined($Slim::Music::Info::playlists[-1]) || $Slim::Music::Info::playlists[-1] ne $name) {
					$::d_musicmagic && msg("Found MusicMagic Playlist: $url\n");
				}
				# add this playlist to our playlist library
				$cacheEntry{'TITLE'} = Slim::Utils::Prefs::get('MusicMagicplaylistprefix') . $name . Slim::Utils::Prefs::get('MusicMagicplaylistsuffix');
				
				#print "Playlist size is $count2\n";
				my @list;
				for (my $j = 0; $j < $count2; $j++) {
					push @list, Slim::Utils::Misc::fileURLFromPath(convertPath($songs[$j]));
				}
				$cacheEntry{'LIST'} = \@list;
				$cacheEntry{'CT'} = 'mlp';
				$cacheEntry{'TAG'} = 1;
				$cacheEntry{'VALID'} = '1';
				Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);
			}
		}
	}

	doneScanning();
	$::d_musicmagic && msg("exportFunction: finished export ($count records, ".scalar @{Slim::Music::Info::playlists()}." playlists)\n");
	$export = '';
	return 0;
}

sub specialPushLeft {
	my $client = shift @_;
	my $step = shift @_;
	my @oldlines = @_;

	my $now = Time::HiRes::time();
	my $when = $now + 0.5;
	my $mixer;
	
	$mixer  = string('MUSICMAGIC_MIXING');

	if ($step == 0) {
		Slim::Buttons::Common::pushMode($client, 'block');
		$client->pushLeft(\@oldlines, [$mixer]);
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);
	} elsif ($step == 3) {
		Slim::Buttons::Common::popMode($client);
		$client->pushLeft([$mixer."...", ""], [Slim::Display::Display::curLines($client)]);
	} else {
		$client->update( [$client->renderOverlay($mixer.("." x $step))], undef);
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);
	}
}

sub mixerFunction {
	my $client = shift;
	
	my $genre = Slim::Buttons::BrowseID3::selection($client,'curgenre');
	my $artist = Slim::Buttons::BrowseID3::selection($client,'curartist');
	my $album = Slim::Buttons::BrowseID3::selection($client,'curalbum');
	my $currentItem = Slim::Buttons::BrowseID3::browseID3dir($client,Slim::Buttons::BrowseID3::browseID3dirIndex($client));
	my @oldlines = Slim::Display::Display::curLines($client);
	my @instantMix = ();
	
	# if we've chosen a particular song
	if (Slim::Buttons::BrowseID3::picked($genre) && Slim::Buttons::BrowseID3::picked($artist) && Slim::Buttons::BrowseID3::picked($album) && Slim::Music::Info::isSongMMMixable($currentItem)) {
		# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
		@instantMix = getMix(Slim::Utils::Misc::pathFromFileURL($currentItem), 'song');

	# if we've picked an artist 
	} elsif (Slim::Buttons::BrowseID3::picked($genre) && ! Slim::Buttons::BrowseID3::picked($album) && Slim::Music::Info::isArtistMMMixable($currentItem)) {
		# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
		@instantMix = getMix($currentItem, 'artist');

	# if we've picked an album 
	} elsif (Slim::Buttons::BrowseID3::picked($genre) && Slim::Buttons::BrowseID3::picked($artist) && !Slim::Buttons::BrowseID3::picked($album) && Slim::Music::Info::isAlbumMMMixable($artist, $currentItem)) {
		# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
		my $key = "$artist\@\@$currentItem";
		@instantMix = getMix($key, 'album');

	# if we've picked a genre 
	} elsif (Slim::Music::Info::isGenreMMMixable($currentItem)) {
		# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
		@instantMix = getMix($currentItem, 'genre');
	}
	if (scalar @instantMix) {
		Slim::Buttons::Common::pushMode($client, 'instant_mix', {'mix' => \@instantMix});
		specialPushLeft($client, 0, @oldlines);
	# don't do anything if nothing is mixable
	} else {
		$client->bumpLeft();
	}
}

sub getMix {
	my $id = shift @_;
	my $for = shift @_;
	my @instant_mix = ();
	my $mixArgs;
	my $req;
	my $res;
	my @type = ('tracks','min','mbytes');
	 
	my %args = (
		size		=> Slim::Utils::Prefs::get('MMMSize'),       # Set the size of the list (default 12)
		sizetype	=> $type[Slim::Utils::Prefs::get('MMMMixType')], # (tracks|min|mb) Set the units for size (default tracks)
		style		=> Slim::Utils::Prefs::get('MMMStyle'),       # Set the style slider (default 20)
		variety		=> Slim::Utils::Prefs::get('MMMVariety'),        # Set the variety slider (default 0)
	);
	my $argString = join( '&', map { "$_=$args{$_}" } keys %args );

	if ($for eq "song") {
		$mixArgs = "song=$id";
	} elsif ($for eq "album") {
		$mixArgs = "album=$id";
	} elsif ($for eq "artist") {
		$mixArgs = "artist=$id";
	} elsif ($for eq "genre") {
		$mixArgs = "genre=$id";
	} else {
		$::d_musicmagic && msg("no valid type specified for instant mix");
		return undef;
	}
	
	my $MMSport = Slim::Utils::Prefs::get('MMSport');
	my $MMSHost = Slim::Utils::Prefs::get('MMSHost');
	$::d_musicmagic && msg("Musicmagic request: http://$MMSHost:$MMSport/api/mix?$mixArgs\&$argString");
	$req = new HTTP::Request GET => "http://$MMSHost:$MMSport/api/mix?$mixArgs\&$argString";
	$res = (new LWP::UserAgent)->request($req);
	if ($res->is_error()) {
		# NYI
		$::d_musicmagic && msg("Musicmagic Error!");
	} else {

		my @songs = split(/\n/, $res->content());
		my $count = scalar @songs;
	
		for (my $j = 0; $j < $count; $j++) {
			my $newPath = convertPath($songs[$j]);

			$::d_musicmagic && msg("Original $songs[$j] : New $newPath");

			push @instant_mix, Slim::Utils::Misc::fileURLFromPath($newPath);
		}
	}

	return @instant_mix;
}

sub setupGroup {
	my $client = shift;
	my %setupGroup = (
			'PrefOrder' => ['musicmagic']
			,'Suppress_PrefLine' => 1
			,'Suppress_PrefSub' => 1
			,'GroupLine' => 1
			,'GroupSub' => 1
	);
	my %setupPrefs = (
		'musicmagic' => {
			'validate' => \&Slim::Web::Setup::validateTrueFalse
			,'changeIntro' => ""
			,'options' => {
				'1' => string('USE_MUSICMAGIC')
				,'0' => string('DONT_USE_MUSICMAGIC')
			}
			,'onChange' => sub {
					my ($client,$changeref,$paramref,$pageref) = @_;
					
					foreach my $client (Slim::Player::Client::clients()) {
						Slim::Buttons::Home::updateMenu($client);
					}
					Slim::Music::Import::useImporter('musicmagic',$changeref->{'musicmagic'}{'new'});
					Slim::Music::Import::startScan('musicmagic');
				}
			,'optionSort' => 'KR'
			,'inputTemplate' => 'setup_input_radio.html'
		}
	);
	return (\%setupGroup,\%setupPrefs);
}

sub setupCategory {
	my %setupCategory =(
		'title' => string('SETUP_MUSICMAGIC')
		,'parent' => 'server'
		,'GroupOrder' => ['Default','MusicMagicPlaylistFormat']
		,'Groups' => {
			'Default' => {
					'PrefOrder' => ['MMMSize','MMMMixType','MMMStyle','MMMVariety','musicmagicscaninterval','MMSHost','MMSport','MMSremoteRoot']
				}
			,'MusicMagicPlaylistFormat' => {
					'PrefOrder' => ['MusicMagicplaylistprefix','MusicMagicplaylistsuffix']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => string('SETUP_MUSICMAGICPLAYLISTFORMAT')
					,'GroupDesc' => string('SETUP_MUSICMAGICPLAYLISTFORMAT_DESC')
					,'GroupLine' => 1
					,'GroupSub' => 1
				}
		}
		,'Prefs' => {
			'MusicMagicplaylistprefix' => {
					'validate' => \&Slim::Web::Setup::validateAcceptAll
					,'PrefSize' => 'large'
				}
			,'MusicMagicplaylistsuffix' => {
					'validate' => \&Slim::Web::Setup::validateAcceptAll
					,'PrefSize' => 'large'
				}
			,'musicmagicscaninterval' => {
					'validate' => \&Slim::Web::Setup::validateNumber
					,'validateArgs' => [0,undef,1000]
				}
			,'MMMSize'	=> {
					'validate' => \&Slim::Web::Setup::validateInt
					,'validateArgs' => [1,undef,1]
				}
			,'MMMMixType'	=> {
					'validate' => \&Slim::Web::Setup::validateInList
					,'validateArgs' => [0,1,2]
					,'options'=> {
						'0' => string('MMMMIXTYPE_TRACKS')
						,'1' => string('MMMMIXTYPE_MIN')
						,'2' => string('MMMMIXTYPE_MBYTES')
					}
				}
			,'MMMStyle'	=> {
					'validate' => \&Slim::Web::Setup::validateInt
					,'validateArgs' => [0,200,1,1]
				}
			,'MMMVariety'	=> {
					'validate' => \&Slim::Web::Setup::validateInt
					,'validateArgs' => [0,9,1,1]
				}
			,'MMSport'	=> {
					'validate' => \&Slim::Web::Setup::validateInt
					,'validateArgs' => [1025,65535,undef,1]
				}
			,'MMSHost'     => {
					'validate' => \&Slim::Web::Setup::validateIntvalidateAcceptAll
					,'PrefSize' => 'large'
				}
			,'MMSremoteRoot'=> {
					'validate' =>  \&Slim::Web::Setup::validateIntvalidateAcceptAll
					,'PrefSize' => 'large'
				}
		}
	);
	return (\%setupCategory);
};

sub checkDefaults {

	if (!Slim::Utils::Prefs::isDefined('MMMMixType')) {
		Slim::Utils::Prefs::set('MMMMixType',0)
	}
	if (!Slim::Utils::Prefs::isDefined('MMMStyle')) {
		Slim::Utils::Prefs::set('MMMStyle',0);
	}
	if (!Slim::Utils::Prefs::isDefined('MMMVariety')) {
		Slim::Utils::Prefs::set('MMMVariety',0);
	}
	if (!Slim::Utils::Prefs::isDefined('MMMSize')) {
		Slim::Utils::Prefs::set('MMMSize',12);
	}
	if (!Slim::Utils::Prefs::isDefined('MusicMagicplaylistprefix')) {
		Slim::Utils::Prefs::set('MusicMagicplaylistprefix','MusicMagic: ');
	}
	if (!Slim::Utils::Prefs::isDefined('MusicMagicplaylistsuffix')) {
		Slim::Utils::Prefs::set('MusicMagicplaylistsuffix','');
	}
	if (!Slim::Utils::Prefs::isDefined('musicmagicscaninterval')) {
		Slim::Utils::Prefs::set('musicmagicscaninterval',60);
	}
	if (!Slim::Utils::Prefs::isDefined('MMSport')) {
		Slim::Utils::Prefs::set('MMSport',10002);
	}
	if (!Slim::Utils::Prefs::isDefined('MMSHost')) {
		Slim::Utils::Prefs::set('MMSHost','localhost');
	}
};


1;
