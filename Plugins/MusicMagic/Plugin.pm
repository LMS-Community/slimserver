package Plugins::MusicMagic::Plugin;

# $Id: MusicMagic.pm 1757 2005-01-18 21:22:50Z dsully $

use strict;

use File::Spec::Functions qw(catfile);

use Slim::Player::Source;
use Slim::Player::Protocols::HTTP;
use Slim::Utils::Misc;
use Slim::Utils::Strings;

my $isScanning = 0;
my $initialized = 0;
my $last_error = 0;
my $export = '';
my $count = 0;
my $scan = 0;
my $MMSHost;
my $MMSport;

my $lastMusicLibraryFinishTime = undef;

our %artwork = ();

our %mixMap  = (
	'add.single' => 'play_1',
	'add.hold' => 'play_2'
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

	$::d_musicmagic && msg("MusicMagic: using musicmagic: $use\n");
	
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
	
	# reset last scan time

	$lastMusicLibraryFinishTime = undef;


	$initialized = 0;

	# delGroups, categories and prefs
	Slim::Web::Setup::delCategory('musicmagic');
	Slim::Web::Setup::delGroup('server','musicmagic',1);
	
	# set importer to not use
	Slim::Utils::Prefs::set('musicmagic', 0);
	Slim::Music::Import::useImporter('MUSICMAGIC',0);
}

sub initPlugin {
	return 1 if $initialized;
	
	checkDefaults();

	$MMSport = Slim::Utils::Prefs::get('MMSport');
	$MMSHost = Slim::Utils::Prefs::get('MMSHost');

	$::d_musicmagic && msg("MusicMagic: Testing for API on $MMSHost:$MMSport\n");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/version",
		'create' => 0,
		'timeout' => 5,
	});

	unless ($http) {

		$initialized = 0;
		$::d_musicmagic && msg("MusicMagic: Cannot Connect\n");
		
		my ($groupRef,$prefRef) = &setupGroup();
		Slim::Web::Setup::addGroup('plugins', 'musicmagic_connect', $groupRef, undef, $prefRef);

	} else {

		my $content = $http->content();
		$::d_musicmagic && msg("MusicMagic: $content\n");
		$http->close();

		# Note: Check version restrictions if any
		$initialized = $content;

		checker();

		Slim::Music::Import::addImporter('MUSICMAGIC', \&startScan, \&mixerFunction, \&addGroups, \&mixerlink);
		Slim::Music::Import::useImporter('MUSICMAGIC', Slim::Utils::Prefs::get('musicmagic'));

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

sub playMix {
	my $client = shift;
	my $button = shift;
	my $append = shift || 0;

	my $line1;
	my $playAddInsert;
	
	if ($append == 1) {
		$line1 = $client->string('ADDING_TO_PLAYLIST');
		$playAddInsert = 'addtracks';
	} elsif ($append == 2) {
		$line1 = $client->string('INSERT_TO_PLAYLIST');
		$playAddInsert = 'inserttracks';
	} elsif (Slim::Player::Playlist::shuffle($client)) {
		$line1 = $client->string('PLAYING_RANDOMLY_FROM');
		$playAddInsert = 'playtracks';
	} else {
		$line1 = $client->string('NOW_PLAYING_FROM');
		$playAddInsert = 'playtracks';
	}

	my $line2 = $client->param('stringHeader') ? $client->string($client->param('header')) : $client->param('header');
	
	$client->showBriefly($client->renderOverlay($line1, $line2, undef, Slim::Display::Display::symbol('notesymbol')));

	Slim::Control::Command::execute($client, ["playlist", $playAddInsert, "listref", $client->param('listRef')]);
	
}

sub addGroups {

	Slim::Web::Setup::addCategory('musicmagic',&setupCategory);

	my ($groupRef,$prefRef) = &setupUse();

	Slim::Web::Setup::addGroup('server', 'musicmagic', $groupRef, 2, $prefRef);
	Slim::Web::Setup::addChildren('server', 'musicmagic');
}

sub isMusicLibraryFileChanged {

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/cacheid",
		'create' => 0,
	}) || return 0;

	my $fileMTime = $http->content();
	$http->close();

	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, $lastMusicLibraryDate is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	my $oldTime = Slim::Utils::Prefs::get('lastMusicMagicLibraryDate') || 0;

	if ($fileMTime > $oldTime) {

		my $musicmagicscaninterval = Slim::Utils::Prefs::get('musicmagicscaninterval') || 1;

		$::d_musicmagic && msg("MusicMagic: music library has changed!\n");

		$lastMusicLibraryFinishTime = 0 unless $lastMusicLibraryFinishTime;

		if (time() - $lastMusicLibraryFinishTime > $musicmagicscaninterval) {

			return 1;
		}

		$::d_musicmagic && msg("MusicMagic: waiting for $musicmagicscaninterval seconds to pass before rescanning\n");
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

	# Call ourselves again after 60 seconds
	Slim::Utils::Timers::setTimer(0, (Time::HiRes::time() + 60), \&checker);
}

sub startScan {
	
	if (!useMusicMagic()) {
		return;
	}
		
	$::d_musicmagic && msg("MusicMagic: start export\n");
	stopScan();
	
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

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/cacheid",
		'create' => 0,
	}) || return 0;

	if ($http) {

		Slim::Utils::Prefs::set('lastMusicMagicLibraryDate', $http->content());

		$http->close();
	}
	
	Slim::Music::Info::generatePlaylists();
	
	Slim::Music::Import::endImporter('MUSICMAGIC');
}

sub convertPath {
	my $mmsPath = shift;
	
	return $mmsPath if (Slim::Utils::Prefs::get('MMSHost') eq 'localhost');
	
	my $remoteRoot = Slim::Utils::Prefs::get('MMSremoteRoot');
	my $nativeRoot = Slim::Utils::Prefs::get('audiodir');
	my $original   = $mmsPath;
	my $winPath    = $mmsPath =~ m/\\/; # test if this is a windows path

	if (Slim::Utils::OSDetect::OS() eq 'unix') {

		# we are unix
		if ($winPath) {

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
		if (!$winPath) {

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

	$::d_musicmagic && msg("MusicMagic: $original is now $mmsPath\n");

	return $mmsPath
}

sub exportFunction {
	my $playlist;

	my $http;
	my @lines;
	
	return 0 if $export eq 'done';

	$isScanning = 1;

	# We need to use the datastore to get at our id's
	my $ds = Slim::Music::Info::getCurrentDataStore();
	
	$MMSport = Slim::Utils::Prefs::get('MMSport') unless $MMSport;
	$MMSHost = Slim::Utils::Prefs::get('MMSHost') unless $MMSHost;

	$::d_musicmagic && msg("MusicMagic: export mode is: $export\n");

	if ($export eq 'start') {

		$http = Slim::Player::Protocols::HTTP->new({
			'url'    => "http://$MMSHost:$MMSport/api/getSongCount",
			'create' => 0,
		});

		if ($http) {
			# convert to integer
			chomp($count = $http->content());

			$http->close();
		}

		$count += 0;

		$::d_musicmagic && msg("MusicMagic: Got $count song(s).\n");
		
		$scan = 0;
		$export = 'songs';
		return 1;
	}
	
	while ($export eq 'songs' && $scan <= $count) {
		my %cacheEntry = ();
		my %songInfo = ();
		
		$http = Slim::Player::Protocols::HTTP->new({
			'url'    => "http://$MMSHost:$MMSport/api/getSong?index=$scan",
			'create' => 0,
		}) || next;

		if ($http) {

			$scan++;
			@lines = split(/\n/, $http->content());
			my $count2 = scalar @lines;

			$http->close();

			for (my $j = 0; $j < $count2; $j++) {
				my ($song_field, $song_value) = $lines[$j] =~ /(\w+) (.*)/;
				$songInfo{$song_field} = $song_value;
			}
		
			$cacheEntry{'TRACKNUM'} = $songInfo{'track'};

			if ($songInfo{'bitrate'}) {
				$cacheEntry{'BITRATE'} = $songInfo{'bitrate'} * 1000;
			}

			$cacheEntry{'YEAR'}  = $songInfo{'year'};
			$cacheEntry{'CT'}    = Slim::Music::Info::typeFromPath($songInfo{'file'},'mp3');
			$cacheEntry{'TAG'}   = 1;
			$cacheEntry{'VALID'} = 1;
			$cacheEntry{'SECS'}  = $songInfo{'seconds'};
		
			if ($songInfo{'active'} eq 'yes') {
				$cacheEntry{'MUSICMAGIC_MIXABLE'} = 1;
			}

			$::d_musicmagic && msg("MusicMagic: Exporting song $scan: $songInfo{'file'}\n");

			# fileURLFromPath will turn this into UTF-8 - so we
			# need to make sure we're in the current locale first.
			if ($] > 5.007) {
				$songInfo{'file'} = Encode::encode($Slim::Utils::Misc::locale, $songInfo{'file'}, Encode::FB_QUIET());

				for my $key (qw(album artist genre name)) {
					$songInfo{$key} = Encode::encode('utf8', $songInfo{$key}, Encode::FB_QUIET());
				}
			}

			# Assign these after they may have been verified as UTF-8
			$cacheEntry{'ALBUM'}  = $songInfo{'album'};
			$cacheEntry{'TITLE'}  = $songInfo{'name'};
			$cacheEntry{'ARTIST'} = $songInfo{'artist'};
			$cacheEntry{'GENRE'}  = $songInfo{'genre'};
		
			my $fileurl = Slim::Utils::Misc::fileURLFromPath($songInfo{'file'});

			my $track = $ds->updateOrCreate({

				'url'        => $fileurl,
				'attributes' => \%cacheEntry,
				'readTags'   => 1,

			}) || do {

				$::d_musicmagic && Slim::Utils::Misc::msg("Couldn't create track for $fileurl!\n");
				next;
			};

			my $albumObj = $track->album();

			# NYI: MMM has more ways to access artwork...
			if (Slim::Utils::Prefs::get('lookForArtwork') && defined $albumObj) {

				if (!Slim::Music::Import::artwork($albumObj) && !defined $track->thumb()) {

					Slim::Music::Import::artwork($albumObj, $track);
				}
			}

			if ($songInfo{'active'} eq 'yes') {

				if (defined $albumObj) {
					$albumObj->musicmagic_mixable(1);
					$albumObj->update();
				}

				for my $artistObj ($track->contributors()) {
					$artistObj->musicmagic_mixable(1);
					$artistObj->update();
				}
				
				for my $genreObj ($track->genres()) {
					$genreObj->musicmagic_mixable(1);
					$genreObj->update();
				}
			}
		}

		if ($scan == $count) {
			$export = 'playlists';
		}
		
		# would be nice to chunk this in groups.  One at a time is slow, 
		# but doing it all at once breaks audio up when its a full scan.
		return 1 if !($scan % 1);
	}

	if ($export eq 'genres') {

		$http = Slim::Player::Protocols::HTTP->new({
			'url'    => "http://$MMSHost:$MMSport/api/genres?active",
			'create' => 0,
		}) || return 1;

		@lines = split(/\n/, $http->content());
		$count = scalar @lines;
		$::d_musicmagic && msg("MusicMagic: Got $count active genre(s).\n");

		$http->close();
	
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

		$http = Slim::Player::Protocols::HTTP->new({
			'url'    => "http://$MMSHost:$MMSport/api/artists?active",
			'create' => 0,
		}) || return 1;

		@lines = split(/\n/, $http->content());
		$count = scalar @lines;
		$::d_musicmagic && msg("MusicMagic: Got $count active artist(s).\n");

		$http->close();

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
	
	if ($export eq 'playlists') {

		$http = Slim::Player::Protocols::HTTP->new({
			'url'    => "http://$MMSHost:$MMSport/api/playlists",
			'create' => 0,
		});

		$count = 0;

		if ($http) {
			@lines = split(/\n/, $http->content());
			$count = scalar @lines;
			$http->close();
		}

		#print "Checking $count playlist(s)\n";
		for (my $i = 0; $i < $count; $i++) {

			my %cacheEntry = ();
			my @songs = ();
			
			$http = Slim::Player::Protocols::HTTP->new({
				'url'    => "http://$MMSHost:$MMSport/api/getPlaylist?index=$i",
				'create' => 0,
			});

			if ($http) {

				@songs = split(/\n/, $http->content());
				my $count2 = scalar @songs;
				$http->close();
			
				my $name = $lines[$i];
				my $url = 'musicmagicplaylist:' . Slim::Web::HTTP::escape($name);

				if (!defined($Slim::Music::Info::playlists[-1]) || $Slim::Music::Info::playlists[-1] ne $name) {
					$::d_musicmagic && msg("MusicMagic: Found playlist: $url\n");
				}

				# add this playlist to our playlist library
				$cacheEntry{'TITLE'} = Slim::Utils::Prefs::get('MusicMagicplaylistprefix') . $name . Slim::Utils::Prefs::get('MusicMagicplaylistsuffix');
				
				my @list;
				for (my $j = 0; $j < $count2; $j++) {
					push @list, Slim::Utils::Misc::fileURLFromPath(convertPath($songs[$j]));
				}

				$cacheEntry{'LIST'} = \@list;
				$cacheEntry{'CT'} = 'mmp';
				$cacheEntry{'TAG'} = 1;
				$cacheEntry{'VALID'} = '1';

				Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);
			}
		}
		
		# skipping to done here.  Duplicates currently crash the linux version of MusicMagic.
		if ($initialized !~ m/1\.1\.3$/) {
			$export = 'duplicates';
			return 1;
		}
	}
	
	if ($export eq 'duplicates') {

		my %cacheEntry = ();
		my @songs = ();
		$::d_musicmagic && msg("MusicMagic: Checking for duplicates.\n");
		
		$http = Slim::Player::Protocols::HTTP->new({
			'url'    => "http://$MMSHost:$MMSport/api/duplicates",
			'create' => 0,
		});

		if ($http) {

			@songs = split(/\n/, $http->content());
			my $count = scalar @songs;
			$http->close();
		
			my $name = "Duplicates";
			my $url = 'musicmagicplaylist:' . Slim::Web::HTTP::escape($name);

			if ($count && (!defined($Slim::Music::Info::playlists[-1]) || $Slim::Music::Info::playlists[-1] ne $name)) {
				$::d_musicmagic && msg("MusicMagic: Found duplicates list.\n");
			}

			# add this list of duplicates to our playlist library
			$cacheEntry{'TITLE'} = Slim::Utils::Prefs::get('MusicMagicplaylistprefix') . $name . Slim::Utils::Prefs::get('MusicMagicplaylistsuffix');
			
			my @list;
			for (my $j = 0; $j < $count; $j++) {
				push @list, Slim::Utils::Misc::fileURLFromPath(convertPath($songs[$j]));
			}

			$cacheEntry{'LIST'} = \@list;
			$cacheEntry{'CT'} = 'mlp';
			$cacheEntry{'TAG'} = 1;
			$cacheEntry{'VALID'} = '1';

			Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);
		}
	}

	doneScanning();

	$::d_musicmagic && msgf("exportFunction: finished export ($count records, %d playlists)\n", scalar @{Slim::Music::Info::playlists()});
	$export = 'done';
	
	return 0;
}

sub specialPushLeft {
	my $client   = shift;
	my $step     = shift;
	my @oldlines = @_;

	my $now  = Time::HiRes::time();
	my $when = $now + 0.5;
	
	my $mixer  = Slim::Utils::Strings::string('MUSICMAGIC_MIXING');

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
	my $mix;
	
	# if we've chosen a particular song
	if (Slim::Buttons::BrowseID3::picked($genre) && 
		Slim::Buttons::BrowseID3::picked($artist) && 
		Slim::Buttons::BrowseID3::picked($album)) {

		my ($obj) = $ds->objectForUrl($currentItem);

		if ($obj && $obj->musicmagic_mixable()) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			$mix = getMix(Slim::Utils::Misc::pathFromFileURL($currentItem), 'song');
		}

	# if we've picked an artist 
	} elsif (Slim::Buttons::BrowseID3::picked($genre) && 
		!Slim::Buttons::BrowseID3::picked($artist) &&
		!Slim::Buttons::BrowseID3::picked($album)) {

		my ($obj) = $ds->find('contributor', { 'contributor' => $currentItem });

		if ($obj && $obj->musicmagic_mixable()) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			$mix = getMix($currentItem, 'artist');
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
				
			$mix = getMix($key, 'album');
		}

	} else {

		# if we've picked a genre 
		my ($obj) = $ds->find('genre', { 'genre' => $currentItem });

		if ($obj && $obj->musicmagic_mixable()) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			$mix = getMix($currentItem, 'genre');
		}
	}

	if (defined $mix && scalar @$mix) {
		my %params = (
			'listRef' => $mix,
			'externRef' => \&Slim::Music::Info::standardTitle,
			'header' => 'MUSICMAGIC_MIX',
			'headerAddCount' => 1,
			'stringHeader' => 1,
			'callback' => \&mixExitHandler,
			'overlayRef' => sub { return (undef, Slim::Display::Display::symbol('rightarrow')) },
			'overlayRefArgs' => '',
			'parentMode' => 'musicmagic_mix',
		);
		
		Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
		specialPushLeft($client, 0, @oldlines);

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
		$form->{'mmmixable_descend'} = 1;
	} else {
		$form->{'mmmixable_not_descend'} = 1;
	}
	
	if ($item->musicmagic_mixable() && canUseMusicMagic() && Slim::Utils::Prefs::get('musicmagic')) {
		#set up a musicmagic link
		Slim::Web::Pages::addLinks("mixer", {'MUSICMAGIC' => "plugins/MusicMagic/mixerlink.html"},1);
	} else {
		Slim::Web::Pages::addLinks("mixer", {'MUSICMAGIC' => undef});
	}
	
	return $form;
}

sub mixExitHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		my @oldlines = Slim::Display::Display::curLines($client);
		my $valueref = $client->param('valueRef');

		Slim::Buttons::Common::pushMode($client, 'trackinfo', {'track' => $$valueref});

		$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
	}
}

sub getMix {
	my $id = shift;
	my $for = shift;

	my @mix = ();
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
		$::d_musicmagic && msg("MusicMagic no valid type specified for mix");
		return undef;
	}

	# url encode the request, but not the argstring
	$mixArgs   = Slim::Web::HTTP::escape($mixArgs);
	#$argString = Slim::Web::HTTP::escape($argString);
	
	$::d_musicmagic && msg("Musicmagic request: http://$MMSHost:$MMSport/api/mix?$mixArgs\&$argString\n");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/mix?$mixArgs\&$argString",
		'create' => 0,
	});

	unless ($http) {
		# NYI
		$::d_musicmagic && msg("Musicmagic Error - Couldn't get mix: $mixArgs\&$argString");
		return @mix;
	}

	my @songs = split(/\n/, $http->content());
	my $count = scalar @songs;

	$http->close();

	for (my $j = 0; $j < $count; $j++) {
		my $newPath = convertPath($songs[$j]);

		$::d_musicmagic && msg("MusicMagic: Original $songs[$j] : New $newPath\n");

		push @mix, Slim::Utils::Misc::fileURLFromPath($newPath);
	}

	return \@mix;
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
	my $mix;

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
			$mix = getMix(Slim::Utils::Misc::pathFromFileURL($song), 'song');
		}

	} elsif (defined $artist && $artist ne "" && !$album) {

		my ($obj) = $ds->objectForId('contributor', $artist);

		if ($obj && $obj->musicmagic_mixable()) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			$mix = getMix($obj->name(), 'artist');
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
				
			$mix = getMix($key, 'album');
		}
		
	} elsif (defined $genre && $genre ne "" && $genre ne "*") {

		my ($obj) = $ds->objectForId('genre', $genre);

		if ($obj && $obj->musicmagic_mixable()) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			$mix = getMix($genre, 'genre');
		}
	
	} else {

		$::d_musicmagic && msg('no/unknown type specified for mix');
		return 1;
	}

	if (defined $mix && ref $mix eq "ARRAY") {
		# We'll be using this to play the entire mix using 
		# playlist (add|play|load|insert)tracks listref=musicmagic_mix
		$client->param('musicmagic_mix',$mix);
	} else {
		$mix = [];
	}

	for my $item (@$mix) {

		my %list_form = %$params;
		my $webFormat = Slim::Utils::Prefs::getInd("titleFormat",Slim::Utils::Prefs::get("titleFormatWeb"));

		# If we can't get an object for this url, skip it, as the
		# user's database is likely out of date. Bug 863
		my $trackObj  = $ds->objectForUrl($item) || next;
		
		$list_form{'artist'}        = $track ? $track->artist() : $artist;
		$list_form{'album'}         = $track ? $track->album() : $album;
		$list_form{'genre'}         = $genre;
		$list_form{'player'}        = $player;
		$list_form{'itempath'}      = $item; 
		$list_form{'item'}          = $trackObj->id; 
		$list_form{'title'}         = Slim::Music::Info::infoFormat($trackObj, $webFormat, 'TITLE');
		$list_form{'includeArtist'} = ($webFormat !~ /ARTIST/);
		$list_form{'includeAlbum'}  = ($webFormat !~ /ALBUM/) ;
		$list_form{'odd'}           = ($itemnumber + 1) % 2;

		$itemnumber++;

		$params->{'mix_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MusicMagic/musicmagic_mix_list.html", \%list_form)};
	}

	if (defined $p0 && defined $client) {
		Slim::Control::Command::execute($client, ["playlist", $p0 eq "append" ? "addtracks" : "playtracks", "listref=musicmagic_mix"]);
	}

	return Slim::Web::HTTP::filltemplatefile("plugins/MusicMagic/musicmagic_mix.html", $params);
}

sub setupUse {
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
				'1' => Slim::Utils::Strings::string('USE_MUSICMAGIC'),
				'0' => Slim::Utils::Strings::string('DONT_USE_MUSICMAGIC'),
			},

			'onChange' => sub {
				my ($client,$changeref,$paramref,$pageref) = @_;
				
				foreach my $client (Slim::Player::Client::clients()) {
					Slim::Buttons::Home::updateMenu($client);
				}

				Slim::Music::Import::useImporter('MUSICMAGIC',$changeref->{'musicmagic'}{'new'});
				Slim::Music::Info::clearPlaylists('musicmagicplaylist:');
				Slim::Music::Import::startScan('MUSICMAGIC');
			},

			'optionSort' => 'KR',
			'inputTemplate' => 'setup_input_radio.html',
		}
	);

	return (\%setupGroup,\%setupPrefs);
}


sub setupGroup {

	my $client = shift;

	my %setupGroup = (
			'PrefOrder' => [qw(MMSport)]
		);

	my %setupPrefs = (
		'MMSport' => {
			'validate' => \&Slim::Web::Setup::validateInt,
			'validateArgs' => [1025,65535,undef,1],
		},

		'MMSHost' => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll,
			'PrefSize' => 'large'
		},
	);

	return (\%setupGroup,\%setupPrefs);
};

sub setupCategory {

	my %setupCategory = (

		'title' => Slim::Utils::Strings::string('SETUP_MUSICMAGIC'),
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
				'GroupHead' => Slim::Utils::Strings::string('SETUP_MUSICMAGICPLAYLISTFORMAT'),
				'GroupDesc' => Slim::Utils::Strings::string('SETUP_MUSICMAGICPLAYLISTFORMAT_DESC'),
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
					'0' => Slim::Utils::Strings::string('MMMMIXTYPE_TRACKS'),
					'1' => Slim::Utils::Strings::string('MMMMIXTYPE_MIN'),
					'2' => Slim::Utils::Strings::string('MMMMIXTYPE_MBYTES'),
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

	if (!Slim::Utils::Prefs::isDefined('musicmagic')) {
		Slim::Utils::Prefs::set('musicmagic',0)
	}

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
