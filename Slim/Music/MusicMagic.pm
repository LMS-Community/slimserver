package Slim::Music::MusicMagic;

use strict;

use File::Spec::Functions qw(catfile);

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use LWP;

my $isScanning = 0;
my $initialized = 0;
my %artwork;
my $last_error = 0;

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
	
	my $MMSport = Slim::Utils::Prefs::get('MMSport');
	my $req = new HTTP::Request GET => "http://localhost:$MMSport/api/version";
	my $res = (new LWP::UserAgent)->request($req);
	if ($res->is_error()) {
		$initialized = 0;
	} else {
		my $content = $res->content();
		$::d_musicmagic && msg("$content\n");
	
		# Note: Check version restrictions if any
		$initialized = 1;
	}
	return $initialized;
}
	
sub isMusicLibraryFileChanged {
	my $MMSport = Slim::Utils::Prefs::get('MMSport');
	my $req = new HTTP::Request GET => "http://localhost:$MMSport/api/cacheid";
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
		
	$::d_musicmagic && msg("startScan: start export\n");
	stopScan();
	Slim::Music::Info::clearPlaylists();

	Slim::Utils::Scheduler::add_task(\&exportFunction);
	$isScanning = 1;

	# start the checker
	checker();
	
	Slim::Music::Import::addImport('musicmagic');
	
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
	
	#if (Slim::Utils::Prefs::get('lookForArtwork')) {Slim::Utils::Scheduler::add_task(\&artScan);}

	$lastMusicLibraryFinishTime = time();

	my $MMSport = Slim::Utils::Prefs::get('MMSport');
	my $req = new HTTP::Request GET => "http://localhost:$MMSport/api/cacheid";
	my $res = (new LWP::UserAgent)->request($req);
	if (!$res->is_error()) {
		my $fileMTime = $res->content();
		Slim::Utils::Prefs::set('lastMusicMagicLibraryDate', $fileMTime);
	}
	
	Slim::Music::Info::generatePlaylists();
	
	Slim::Music::Import::delImport('musicmagic');

}

sub exportFunction {
	my $count;
	my $playlist;
	my $req;
	my $res;
	my @lines;
	
	my $MMSport = Slim::Utils::Prefs::get('MMSport');
	$req = new HTTP::Request GET => "http://localhost:$MMSport/api/genres?active";
	$res = (new LWP::UserAgent)->request($req);
	if ($res->is_error()) {
	    # NYI
	} else {
		@lines = split(/\n/, $res->content());
		$count = scalar @lines;
		#print "Got $count active genre(s).\n";
	
		for (my $i=0; $i < $count; $i++) {
			#print "Genre $lines[$i]\n";
			Slim::Music::Info::updateGenreMMMixCache($lines[$i]);
		}
	}
	$req = new HTTP::Request GET => "http://localhost:$MMSport/api/artists?active";
	$res = (new LWP::UserAgent)->request($req);
	if ($res->is_error()) {
	    # NYI
	} else {
		@lines = split(/\n/, $res->content());
		$count = scalar @lines;
		#print "Got $count active artist(s).\n";
	
		for (my $i=0; $i < $count; $i++) {
			#print "Artist $lines[$i]\n";
			Slim::Music::Info::updateArtistMMMixCache($lines[$i]);
		}
	}
	
	
	$req = new HTTP::Request GET => "http://localhost:$MMSport/api/getSongCount";
	$res = (new LWP::UserAgent)->request($req);
	if ($res->is_error()) {
		$count = 0;
	} else {
		$count = $res->content(); # convert to integer
	}
	#print "Checking $count song(s)\n";
	
	for (my $i = 0; $i < $count; $i++) {
		my %cacheEntry = ();
		my %songInfo = ();
		
		$req = new HTTP::Request GET => "http://localhost:$MMSport/api/getSong?index=$i";
		$res = (new LWP::UserAgent)->request($req);
		if ($res->is_error()) {
	    		# NYI
		} else {
			@lines = split(/\n/, $res->content());
			my $count2 = scalar @lines;
			for (my $j=0; $j < $count2; $j++) {
				my ($song_field, $song_value) = $lines[$j] =~ /(\w+) (.*)/;
				$songInfo{$song_field} = $song_value;
			}
			#print "Got $i $songInfo{'name'}\n";
		
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
		
			
			$::d_musicmagic && msg("Exporting song: $songInfo{'file'}\n");
		
			my $fileurl = Slim::Utils::Misc::fileURLFromPath($songInfo{'file'});
			#$fileurl =~ tr/\\/\//;
			#$fileurl =~ s,\/\/\/\/,\/\/\/,;
			
			Slim::Music::Info::updateCacheEntry($fileurl, \%cacheEntry);

			# NYI: MMM has more ways to access artwork...
			if (Slim::Utils::Prefs::get('lookForArtwork')) {
				if ($cacheEntry{'ALBUM'} && !exists $artwork{$cacheEntry{'ALBUM'}} && !defined Slim::Music::Info::cacheItem($fileurl,'THUMB')) { 	 
					$artwork{$cacheEntry{'ALBUM'}} = Slim::Utils::Misc::pathFromFileURL($fileurl); 	 
					$::d_artwork && msg("$cacheEntry{'ALBUM'} refers to ".Slim::Utils::Misc::pathFromFileURL($fileurl)."\n"); 	 
				}
			}
			Slim::Music::Info::updateAlbumMMMixCache(\%cacheEntry);
		}
	}
	
	$req = new HTTP::Request GET => "http://localhost:$MMSport/api/playlists";
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
		
		$req = new HTTP::Request GET => "http://localhost:$MMSport/api/getPlaylist?index=$i";
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
				push @list, Slim::Utils::Misc::fileURLFromPath($songs[$j]);
			}
			$cacheEntry{'LIST'} = \@list;
			$cacheEntry{'CT'} = 'mlp';
			$cacheEntry{'TAG'} = 1;
			$cacheEntry{'VALID'} = '1';
			Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);
		}
	}


	doneScanning();
	$::d_musicmagic && msg("exportFunction: finished export ($count records, ".scalar @{Slim::Music::Info::playlists()}." playlists)\n");
	return 0;
}

sub getMix {
	my $id = shift @_;
	my $for = shift @_;
	my @instant_mix = ();
        my $mixArgs;
	my $req;
	my $res;
	
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
	$::d_musicmagic && msg("Musicmagic request: http://localhost:$MMSport/api/mix?$mixArgs");
	$req = new HTTP::Request GET => "http://localhost:$MMSport/api/mix?$mixArgs";
	$res = (new LWP::UserAgent)->request($req);
	if ($res->is_error()) {
    		# NYI
	} else {
		my @songs = split(/\n/, $res->content());
		my $count = scalar @songs;
	
		#print "List size is $count\n";
		for (my $j = 0; $j < $count; $j++) {
			push @instant_mix, Slim::Utils::Misc::fileURLFromPath($songs[$j]);
		}
	}

	return @instant_mix;
}

1;
__END__

