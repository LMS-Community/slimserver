package Plugins::MusicMagic::Plugin;

# $Id: MusicMagic.pm 1757 2005-01-18 21:22:50Z dsully $

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

our %mixMap = ('add.single' => 'play_1',
								'add.hold' => 'play_1',
								);
our %mixFunctions = ();

sub strings {
	return '';
}

sub getFunctions {
	return '';
}

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
	Slim::Music::Import::useImporter('MUSICMAGIC',$use);

	$::d_musicmagic && msg("using musicmagic: $use\n");
	
	return $use;
}

sub canUseMusicMagic {
	return $initialized || initPlugin();
}

sub playlists {
	return Slim::Music::Info::playlists;
}

sub getDisplayName {
	return 'SETUP_MUSICMAGIC';
}

sub enabled {
	return ($::VERSION !~/^5/) && initPlugin();
}

sub disablePlugin {
	# turn off checker
	Slim::Utils::Timers::killTimers(0, \&checker);
	
	# remove playlists
	
	# disable protocol handler?
	#Slim::Player::Source::registerProtocolHandler("musicmaglaylist", "0");
	
	# delGroups, categories and prefs
	Slim::Web::Setup::delCategory('musicmagic');
	Slim::Web::Setup::delGroup('server','musicmagic',1);
	
	# set importer to not use
	Slim::Utils::Prefs::set('musicmagic', 0);
	Slim::Music::Import::useImporter('MUSICMAGIC',0);
}

sub initPlugin {
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
		checker();
		Slim::Music::Import::addImporter('MUSICMAGIC',\&startScan,\&mixerFunction,\&addGroups);
		Slim::Music::Import::useImporter('MUSICMAGIC',Slim::Utils::Prefs::get('musicmagic'));
		Slim::Player::Source::registerProtocolHandler("musicmagicplaylist", "0");
		addGroups();
	}
	
	$mixFunctions{'play'} = \&playMix;
	Slim::Buttons::Common::addMode('musicmagic_mix', \%mixFunctions);
	Slim::Hardware::IR::addModeDefaultMapping('musicmagic_mix',\%mixMap);
	
	return $initialized;
}

sub defaultMap {
	Slim::Hardware::IR::addModeDefaultMapping('musicmagic_mix',\%mixMap);
	return undef;
}

sub  playMix {
	my $client = shift;
	my $button = shift;
	my $append = shift;
	my $line1;
	my $line2;
	
	if ($append) {
		$line1 = $client->string('ADDING_TO_PLAYLIST')
	} elsif (Slim::Player::Playlist::shuffle($client)) {
		$line1 = $client->string('PLAYING_RANDOMLY_FROM');
	} else {
		$line1 = $client->string('NOW_PLAYING_FROM')
	}
	$line2 = $client->string('MUSICMAGIC_MIX');
	
	$client->showBriefly($client->renderOverlay($line1, $line2, undef, Slim::Display::Display::symbol('notesymbol')));
	
	my $mixRef = Slim::Buttons::Common::param($client,'listRef');
	Slim::Control::Command::execute($client, ["playlist", $append ? "append" : "play", $mixRef->[0]]);
	
	for (my $i=1; $i < scalar(@$mixRef); $i++) {
	Slim::Control::Command::execute($client, ["playlist", "append", $mixRef->[$i]]);
	}
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
	return unless (Slim::Utils::Prefs::get('musicmagic'));
	
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

	
	$export = 'start';
	$scan = 0;
	
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
	
	Slim::Music::Import::endImporter('MUSICMAGIC');

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
			$::d_import && $::d_import =~ m/musimagic/ &&  msg("$remoteRoot :: $nativeRoot \n");

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
				$::d_import && $::d_import =~ m/musimagic/ &&  msg("$remoteRoot :: $nativeRoot \n");

				# convert unix root to windows root
				$mmsPath =~ s/$remoteRoot/$nativeRoot/;
				# convert unix paths to windows
				$mmsPath =~ tr/\//\\/;
			}
		}
	$::d_import && $::d_import =~ m/musimagic/ && msg("$original is now $mmsPath\n");
	return $mmsPath
}

sub exportFunction {
	my $playlist;
	my $req;
	my $res;
	my @lines;
	
	return 0 if $export eq 'done';

	$isScanning = 1;

	# We need to use the datastore to get at our id's
	my $ds = Slim::Music::Info::getCurrentDataStore();
	
	$MMSport = Slim::Utils::Prefs::get('MMSport') unless $MMSport;
	$MMSHost = Slim::Utils::Prefs::get('MMSHost') unless $MMSHost;

	if ($export eq 'start') {
		$req = new HTTP::Request GET => "http://$MMSHost:$MMSport/api/getSongCount";
		$res = (new LWP::UserAgent)->request($req);

		if ($res->is_error()) {
			$count = 0;
		} else {
			$count = $res->content(); # convert to integer
		}
		
		$::d_musicmagic && msg("Got $count song(s).\n");
		
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

			for (my $j = 0; $j < $count2; $j++) {
				my ($song_field, $song_value) = $lines[$j] =~ /(\w+) (.*)/;
				$songInfo{$song_field} = $song_value;
			}
		
			$cacheEntry{'ALBUM'} = $songInfo{'album'};
			$cacheEntry{'TRACKNUM'} = $songInfo{'track'};
			$cacheEntry{'BITRATE'} = $songInfo{'bitrate'};
			$cacheEntry{'YEAR'} = $songInfo{'year'};
			$cacheEntry{'SIZE'} = $songInfo{'bytes'};

			# cache the file size & date
			$cacheEntry{'FS'}  = -s $songInfo{'file'};
			$cacheEntry{'AGE'} = (stat($songInfo{'file'}))[9];
		
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
				$cacheEntry{'MUSICMAGIC_MIXABLE'} = 1;
			}
			
			$::d_musicmagic && msg("Exporting song $scan: $songInfo{'file'}\n");
		
			my $fileurl = Slim::Utils::Misc::fileURLFromPath($songInfo{'file'});

			$ds->updateOrCreate($fileurl, \%cacheEntry);
			$ds->updateOrCreate($fileurl, \%cacheEntry);
			
			# NYI: MMM has more ways to access artwork...
			if (Slim::Utils::Prefs::get('lookForArtwork')) {

				if ($cacheEntry{'ALBUM'} && 
					!Slim::Music::Import::artwork($cacheEntry{'ALBUM'}) && 
					!defined Slim::Music::Info::cacheItem($fileurl,'THUMB')) {

					Slim::Music::Import::artwork($cacheEntry{'ALBUM'},$fileurl);
				}
			}

			# the above object was just created - fetch it back
			# into something we can use
			my $track = $ds->objectForUrl($fileurl);

			if ($songInfo{'active'} eq 'yes' && defined $track) {

				my $album = $track->album();

				$album->musicmagic_mixable(1);
				$album->update(1);
			}
		}

		if ($scan == $count) {
			$export = 'genres';
			$ds->forceCommit();
		}
		
		# would be nice to chunk this in groups.  One at a time is slow, 
		# but doing it all at once breaks audio up when its a full scan.
		return 1 if !($scan % 1);
	}

	if ($export eq 'genres') {

		$req = new HTTP::Request GET => "http://$MMSHost:$MMSport/api/genres?active";
		$res = (new LWP::UserAgent)->request($req);

		if ($res->is_error()) {
			return 1;
		}

		@lines = split(/\n/, $res->content());
		$count = scalar @lines;
		$::d_import && $::d_import =~ m/musimagic/ && msg("Got $count active genre(s).\n");
	
		for (my $i = 0; $i < $count; $i++) {

			my ($obj) = $ds->find('genre', { 'genre.name' => $lines[$i] });

			if ($obj) {
				$obj->musicmagic_mixable(1);
				$obj->update();
			}
		}

		$export = 'artists';

		return 1;
	}

	if ($export eq 'artists') {

		$req = new HTTP::Request GET => "http://$MMSHost:$MMSport/api/artists?active";
		$res = (new LWP::UserAgent)->request($req);

		if ($res->is_error()) {
			return 1;
		}

		@lines = split(/\n/, $res->content());
		$count = scalar @lines;
		$::d_import && $::d_import =~ m/musimagic/ && msg("Got $count active artist(s).\n");

		for (my $i = 0; $i < $count; $i++) {

			my ($obj) = $ds->find('contributor', { 'contributor.name' => $lines[$i] });

			if ($obj) {
				$obj->musicmagic_mixable(1);
				$obj->update();
			}
		}

		$export = 'playlists';
		return 1;
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
	$ds->forceCommit();
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
	
	my $genre       = Slim::Buttons::BrowseID3::selection($client,'curgenre');
	my $artist      = Slim::Buttons::BrowseID3::selection($client,'curartist');
	my $album       = Slim::Buttons::BrowseID3::selection($client,'curalbum');
	my $currentItem = Slim::Buttons::BrowseID3::browseID3dir($client,Slim::Buttons::BrowseID3::browseID3dirIndex($client));
	my @oldlines    = Slim::Display::Display::curLines($client);

	my $ds          = Slim::Music::Info::getCurrentDataStore();
	my @mix  = ();
	
	# if we've chosen a particular song
	if (Slim::Buttons::BrowseID3::picked($genre) && 
		Slim::Buttons::BrowseID3::picked($artist) && 
		Slim::Buttons::BrowseID3::picked($album)) {

		my ($obj) = $ds->objectForUrl($currentItem);

		if ($obj && $obj->musicmagic_mixable()) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			@mix = getMix(Slim::Utils::Misc::pathFromFileURL($currentItem), 'song');
		}

	# if we've picked an artist 
	} elsif (Slim::Buttons::BrowseID3::picked($genre) && 
		!Slim::Buttons::BrowseID3::picked($artist) &&
		!Slim::Buttons::BrowseID3::picked($album)) {

		my ($obj) = $ds->find('contributor', { 'contributor' => $currentItem });

		if ($obj && $obj->musicmagic_mixable()) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			@mix = getMix($currentItem, 'artist');
		}

	# if we've picked an album 
	} elsif (Slim::Buttons::BrowseID3::picked($genre) && 
		Slim::Buttons::BrowseID3::picked($artist) &&
		!Slim::Buttons::BrowseID3::picked($album)) {

		# If $artist is selected (as in picked Album by Artist) then we
		# need to include artist in the find.  If artist is not chosen (as in any Album of 
		# a given title) then we cannot include the contributor key, and want any track 
		# from the album to key the mixer.
		my ($obj) = $artist eq "*" ? 
			$ds->find('track', {'album' => $currentItem,}) : 
			$ds->find('album', {'album' => $currentItem,'contributor' => $artist,});

		if ($obj && $obj->musicmagic_mixable()) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			my $key = $artist eq "*" ? 
				Slim::Utils::Misc::pathFromFileURL($obj->{'url'}) : 
				"$artist\@\@$currentItem";
				
			@mix = getMix($key, 'album');
		}

	} else {

		# if we've picked a genre 
		my ($obj) = $ds->find('genre', { 'genre' => $currentItem });

		if ($obj && $obj->musicmagic_mixable()) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			@mix = getMix($currentItem, 'genre');
		}
	}

	if (scalar @mix) {
		my %params = (
			'listRef' => \@mix,
	
			'externRef' => sub {
				my $client = shift;
				my $string = shift;
	
				return Slim::Music::Info::standardTitle($client,$string);
			},
			'externRefArgs' => 'CV',
			'stringExternRef' => 1,
	
			'onChange' => sub {
				my ($client, $value) = @_;
				my $curMenu = Slim::Buttons::Common::param($client,'curMenu');
				$client->curSelection($curMenu,$value);
			},
			'onChangeArgs' => 'CV',
			
			'header' => 'MUSICMAGIC_MIX',
			'headerAddCount' => 1,
			'stringHeader' => 1,
			
			'callback' => \&mixExitHandler,
	
			'overlayRef' => sub { return (undef, Slim::Display::Display::symbol('rightarrow')) },
	
			'overlayRefArgs' => '',
			'valueRef' => undef,
			'parentMode' => 'musicmagic_mix',
		);
		
		Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
		specialPushLeft($client, 0, @oldlines);

	} else {
		# don't do anything if nothing is mixable
		$client->bumpRight();
	}
}

sub mixExitHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} elsif ($exittype eq 'RIGHT') {
		my @oldlines = Slim::Display::Display::curLines($client);
		my $valueref = Slim::Buttons::Common::param($client,'valueRef');
		Slim::Buttons::Common::pushMode($client, 'trackinfo', {'track' => $$valueref});
		$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
	}
}


sub getMix {
	my $id = shift;
	my $for = shift;

	my @instant_mix = ();
	my $mixArgs;
	my $req;
	my $res;
	my @type = qw(tracks min mbytes);
	 
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
		$::d_import && $::d_import =~ m/musimagic/ && msg("no valid type specified for instant mix");
		return undef;
	}
	
	my $MMSport = Slim::Utils::Prefs::get('MMSport');
	my $MMSHost = Slim::Utils::Prefs::get('MMSHost');

	$::d_musicmagic && msg("Musicmagic request: http://$MMSHost:$MMSport/api/mix?$mixArgs\&$argString\n");

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

			$::d_musicmagic && msg("Original $songs[$j] : New $newPath\n");

			push @instant_mix, Slim::Utils::Misc::fileURLFromPath($newPath);
		}
	}

	return @instant_mix;
}

sub webPages {
	my %pages = (
		"musicmagic_mix\.(?:htm|xml)" => \&musicmagic_mix,
	);

	return (\%pages);
}

sub musicmagic_mix {
	my ($client, $params) = @_;

	my $output = "";
	my @mix  = ();

	my $song   = $params->{'song'};
	my $artist = $params->{'artist'};
	my $album  = $params->{'album'};
	my $genre  = $params->{'genre'};
	my $player = $params->{'player'};
	my $p0     = $params->{'p0'};

	my $itemnumber = 0;
	my $ds = Slim::Music::Info::getCurrentDataStore();

	#$params->{'pwd_list'} = Slim::Web::Pages::generate_pwd_list($genre, $artist, $album, $player);

	if (defined $song && $song ne "") {
		$params->{'src_mix'} = Slim::Music::Info::standardTitle(undef, $song);
	}

	$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MusicMagic/musicmagic_pwdlist.html", $params)};

	my $track = $ds->objectForUrl($song);

	if (defined $song && $song ne "") {

		my ($obj) = $ds->objectForUrl($song);

		if ($obj && $obj->musicmagic_mixable()) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			@mix = getMix(Slim::Utils::Misc::pathFromFileURL($song), 'song');
		}

	} elsif (defined $artist && $artist ne "" && !$album) {

		my ($obj) = $ds->objectForId('contributor', $artist);

		if ($obj && $obj->musicmagic_mixable()) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			@mix = getMix($obj->name(), 'artist');
		}

	} elsif (defined $album && $album ne "") {

		my ($albobj) = $ds->objectForId('album', $album);
		
		my ($obj) = $artist eq "" ? 
				$ds->find('track', {'album' => $albobj,}) : 
				$albobj;

		if ($obj && $obj->musicmagic_mixable()) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			my $key = $artist eq "" ? 
				Slim::Utils::Misc::pathFromFileURL($obj->{'url'}) : 
				$ds->objectForId('contributor', $artist)->name()."\@\@".$obj->title();
				
			@mix = getMix($key, 'album');
		}
		
	} elsif (defined $genre && $genre ne "" && $genre ne "*") {

		my ($obj) = $ds->objectForId('genre', $genre);

		if ($obj && $obj->musicmagic_mixable()) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			@mix = getMix($genre, 'genre');
		}
	
	} else {

		$::d_musicmagic && msg('no/unknown type specified for mix');
		return 1;
	}

	for my $item (@mix) {

		my %list_form = %$params;
		my $webFormat = Slim::Utils::Prefs::getInd("titleFormat",Slim::Utils::Prefs::get("titleFormatWeb"));
		
		$list_form{'artist'}        = $track ? $track->artist() : $artist;
		$list_form{'album'}         = $track ? $track->album() : $album;
		$list_form{'genre'}         = $genre;
		$list_form{'player'}        = $player;
		$list_form{'itempath'}      = $item; 
		$list_form{'item'}          = $item; 
		$list_form{'title'}         = Slim::Music::Info::infoFormat($item, $webFormat, 'TITLE');
		$list_form{'includeArtist'} = ($webFormat !~ /ARTIST/);
		$list_form{'includeAlbum'}  = ($webFormat !~ /ALBUM/) ;
		$list_form{'odd'}           = ($itemnumber + 1) % 2;

		$itemnumber++;

		$params->{'mix_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MusicMagic/musicmagic_mix_list.html", \%list_form)};
	}

	if (defined $p0 && defined $client) {

		Slim::Control::Command::execute($client, ["playlist", $p0 eq "append" ? "append" : "play", $mix[0]]);
		
		for (my $i = 1; $i <= $#mix; $i++) {
			Slim::Control::Command::execute($client, ["playlist", "append", $mix[$i]]);
		}
	}

	return Slim::Web::HTTP::filltemplatefile("plugins/MusicMagic/musicmagic_mix.html", $params);
}

sub setupGroup {
	my $client = shift;

	my %setupGroup = (
		'PrefOrder' => ['musicmagic'],
		'Suppress_PrefLine' => 1,
		'Suppress_PrefSub' => 1,
		'GroupLine' => 1,
		'GroupSub' => 1,
	);

	my %setupPrefs = (

		'musicmagic' => {
			'validate' => \&Slim::Web::Setup::validateTrueFalse,
			'changeIntro' => "",

			'options' => {
				'1' => string('USE_MUSICMAGIC'),
				'0' => string('DONT_USE_MUSICMAGIC'),
			},

			'onChange' => sub {
				my ($client,$changeref,$paramref,$pageref) = @_;
				
				foreach my $client (Slim::Player::Client::clients()) {
					Slim::Buttons::Home::updateMenu($client);
				}

				Slim::Music::Import::useImporter('MUSICMAGIC',$changeref->{'musicmagic'}{'new'});
				Slim::Music::Import::startScan('MUSICMAGIC');
			},

			'optionSort' => 'KR',
			'inputTemplate' => 'setup_input_radio.html',
		}
	);

	return (\%setupGroup,\%setupPrefs);
}

sub setupCategory {

	my %setupCategory = (

		'title' => string('SETUP_MUSICMAGIC'),
		'parent' => 'server',
		'GroupOrder' => ['Default','MusicMagicPlaylistFormat'],
		'Groups' => {

			'Default' => {
				'PrefOrder' => [qw(MMMSize MMMMixType MMMStyle MMMVariety musicmagicscaninterval MMSHost MMSport MMSremoteRoot)]
			},

			'MusicMagicPlaylistFormat' => {
				'PrefOrder' => ['MusicMagicplaylistprefix','MusicMagicplaylistsuffix'],
				'PrefsInTable' => 1,
				'Suppress_PrefHead' => 1,
				'Suppress_PrefDesc' => 1,
				'Suppress_PrefLine' => 1,
				'Suppress_PrefSub' => 1,
				'GroupHead' => string('SETUP_MUSICMAGICPLAYLISTFORMAT'),
				'GroupDesc' => string('SETUP_MUSICMAGICPLAYLISTFORMAT_DESC'),
				'GroupLine' => 1,
				'GroupSub' => 1,
			}
		},

		'Prefs' => {

			'MusicMagicplaylistprefix' => {
				'validate' => \&Slim::Web::Setup::validateAcceptAll,
				'PrefSize' => 'large',
			},

			'MusicMagicplaylistsuffix' => {
				'validate' => \&Slim::Web::Setup::validateAcceptAll,
				'PrefSize' => 'large',
			},

			'musicmagicscaninterval' => {
				'validate' => \&Slim::Web::Setup::validateNumber,
				'validateArgs' => [0,undef,1000],
			},

			'MMMSize' => {
				'validate' => \&Slim::Web::Setup::validateInt,
				'validateArgs' => [1,undef,1]
			},

			'MMMMixType' => {
				'validate' => \&Slim::Web::Setup::validateInList,
				'validateArgs' => [0,1,2],
				'options'=> {
					'0' => string('MMMMIXTYPE_TRACKS'),
					'1' => string('MMMMIXTYPE_MIN'),
					'2' => string('MMMMIXTYPE_MBYTES'),
				}
			},

			'MMMStyle' => {
				'validate' => \&Slim::Web::Setup::validateInt,
				'validateArgs' => [0,200,1,1],
			},

			'MMMVariety' => {
				'validate' => \&Slim::Web::Setup::validateInt,
				'validateArgs' => [0,9,1,1],
			},

			'MMSport' => {
				'validate' => \&Slim::Web::Setup::validateInt,
				'validateArgs' => [1025,65535,undef,1],
			},

			'MMSHost' => {
				'validate' => \&Slim::Web::Setup::validateAcceptAll,
				'PrefSize' => 'large'
			},

			'MMSremoteRoot'=> {
				'validate' =>  \&Slim::Web::Setup::validateAcceptAll,
				'PrefSize' => 'large'
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
}

1;

__END__
