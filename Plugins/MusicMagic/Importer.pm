package Plugins::MusicMagic::Importer;

# $Id$

use strict;

use File::Spec::Functions qw(:ALL);
use Data::VString qw(vstring_cmp);
use LWP::Simple;
use Scalar::Util qw(blessed);
use Socket qw($LF);

use Plugins::MusicMagic::Common;

use Slim::Music::Import;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $initialized = 0;
my $MMMVersion  = 0;
my $MMSHost;
my $MMSport;

sub useMusicMagic {
	my $class    = shift;
	my $newValue = shift;

	my $can      = $class->canUseMusicMagic();

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
	my $class = shift;

	return $initialized || $class->initPlugin();
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

	my $initialized = get("http://$MMSHost:$MMSport/api/version");

	if (defined $initialized) {

		# Note: Check version restrictions if any
		chomp($initialized);

		$::d_musicmagic && msg("MusicMagic: $initialized\n");

		($MMMVersion) = ($initialized =~ /Version ([\d\.]+)$/);

		Slim::Music::Import->addImporter($class, {
			'reset'        => \&resetState,
			'playlistOnly' => 1,
			'use'          => Slim::Utils::Prefs::get('musicmagic'),
		});

		Slim::Player::ProtocolHandlers->registerHandler('musicmagicplaylist', 0);

	} else {

		$initialized = 0;
		$::d_musicmagic && msg("MusicMagic: Cannot Connect\n");
	}

	return $initialized;
}

sub resetState {

	$::d_musicmagic && msg("MusicMagic: Resetting Last Library Change Time.\n");

	Slim::Music::Import->setLastScanTime('MMMLastLibraryChange', 0);
}

sub startScan {
	my $class = shift;

	if (!$class->useMusicMagic) {
		return;
	}
		
	$::d_musicmagic && msg("MusicMagic: start export\n");

	if (Slim::Music::Import->scanPlaylistsOnly) {

		$class->exportPlaylists;

	} else {

		$class->exportFunction;
	}

	$class->doneScanning;
} 

sub doneScanning {
	my $class = shift;

	$::d_musicmagic && msg("MusicMagic: done Scanning\n");

	my $lastDate = get("http://$MMSHost:$MMSport/api/cacheid?contents");

	if ($lastDate) {

		chomp($lastDate);

		Slim::Music::Import->setLastScanTime('MMMLastLibraryChange', $lastDate);
	}

	Slim::Music::Import->endImporter($class);
}

sub exportFunction {
	my $class = shift;

	$MMSport = Slim::Utils::Prefs::get('MMSport') unless $MMSport;
	$MMSHost = Slim::Utils::Prefs::get('MMSHost') unless $MMSHost;

	my $count = get("http://$MMSHost:$MMSport/api/getSongCount");

	if ($count) {

		# convert to integer
		chomp($count);

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

	my $progress = Slim::Utils::ProgressBar->new({ 'total' => $count });

	# MMM Version 1.5+ adds support for /api/songs?extended, which pulls
	# down the entire library, separated by $LF$LF - this allows us to make
	# 1 HTTP request, and the process the file.
	if (vstring_cmp($MMMVersion, '>=', '1.5')) {

		$::d_musicmagic && msg("MusicMagic: Fetching ALL song data via songs/extended..\n");

		my $MMMSongData = catdir( Slim::Utils::Prefs::get('cachedir'), 'mmm-song-data.txt' );

		my $MMMDataURL  = "http://$MMSHost:$MMSport/api/songs?extended";

		getstore($MMMDataURL, $MMMSongData);

		if (!-r $MMMSongData) {

			errorMsg("MusicMagic: Couldn't connect to $MMMDataURL ! : $!\n");
			return;
		}

		open(MMMDATA, $MMMSongData) || do {

			errorMsg("MusicMagic: Couldn't read file: $MMMSongData : $!\n");
			return;
		};

		$::d_musicmagic && msg("MusicMagic: done fetching - processing.\n");

		local $/ = "$LF$LF";

		while(my $content = <MMMDATA>) {

			$class->processSong($content, $progress);
		}

		close(MMMDATA);
		unlink($MMMSongData);

	} else {

		for (my $scan = 0; $scan <= $count; $scan++) {

			my $content = get("http://$MMSHost:$MMSport/api/getSong?index=$scan");

			$class->processSong($content, $progress);
		}
	}

	$progress->final($count) if $progress;
}

sub processSong {
	my $class    = shift;
	my $content  = shift || return;
	my $progress = shift;

	my %attributes = ();
	my %songInfo   = ();
	my @lines      = split(/\n/, $content);

	for my $line (@lines) {

		if ($line =~ /^(\w+)\s+(.*)/) {

			$songInfo{$1} = $2;
		}
	}

	$attributes{'TRACKNUM'} = $songInfo{'track'};

	if ($songInfo{'bitrate'}) {
		$attributes{'BITRATE'} = $songInfo{'bitrate'} * 1000;
	}

	$attributes{'YEAR'}  = $songInfo{'year'};
	$attributes{'CT'}    = Slim::Music::Info::typeFromPath($songInfo{'file'},'mp3');
	$attributes{'AUDIO'} = 1;
	$attributes{'SECS'}  = $songInfo{'seconds'} if $songInfo{'seconds'};

	# Bug 3318
	# MiP 1.6+ encode filenames as UTF-8, even on Windows.
	# So we need to turn the string from MiP to UTF-8, which then gets
	# turned into the local charset below with utf8encode_locale
	for my $key (qw(album artist genre name file)) {

		if (!$songInfo{$key}) {
			next;
		}

		my $enc = Slim::Utils::Unicode::encodingFromString($songInfo{$key});

		$songInfo{$key} = Slim::Utils::Unicode::utf8decode_guess($songInfo{$key}, $enc);
	}

	# Assign these after they may have been verified as UTF-8
	$attributes{'ALBUM'}  = $songInfo{'album'};
	$attributes{'TITLE'}  = $songInfo{'name'};
	$attributes{'ARTIST'} = $songInfo{'artist'};
	$attributes{'GENRE'}  = $songInfo{'genre'};

	if ($songInfo{'active'} eq 'yes') {
		$attributes{'MUSICMAGIC_MIXABLE'} = 1;
	}

	$::d_musicmagic && msg("MusicMagic: Exporting song: $songInfo{'file'}\n");

	# Both Linux & Windows need conversion to the current charset.
	if (Slim::Utils::OSDetect::OS() ne 'mac') {
		$songInfo{'file'} = Slim::Utils::Unicode::utf8encode_locale($songInfo{'file'});
	}

	my $fileurl = Slim::Utils::Misc::fileURLFromPath($songInfo{'file'});

	my $track   = Slim::Schema->rs('Track')->updateOrCreate({

		'url'        => $fileurl,
		'attributes' => \%attributes,
		'readTags'   => 1,

	}) || do {

		$::d_musicmagic && msg("MusicMagic: Couldn't create track for $fileurl!\n");

		$progress->update if $progress;

		return;
	};

	my $albumObj = $track->album;

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

	$progress->update if $progress;
}

sub exportPlaylists {
	my $class = shift;

	my @playlists = split(/\n/, get("http://$MMSHost:$MMSport/api/playlists"));

	if (!scalar @playlists) {
		return;
	}

	for (my $i = 0; $i <= scalar @playlists; $i++) {

		my $playlist = get("http://$MMSHost:$MMSport/api/getPlaylist?index=$i") || next;
		my @songs    = split(/\n/, $playlist);

		$::d_musicmagic && msgf("MusicMagic: got playlist %s with %d items\n", $playlists[$i], scalar @songs);

		$class->_updatePlaylist($playlists[$i], \@songs);
	}
}

# Create playlists containing the duplicate items as identified by MusicMagic
sub exportDuplicates {
	my $class = shift;

	# check for dupes, but not with 1.1.3
	if (vstring_cmp($MMMVersion, '<=', '1.1.3')) {
		return;
	}

	$::d_musicmagic && msg("MusicMagic: Checking for duplicates.\n");
	
	my @songs = split(/\n/, get("http://$MMSHost:$MMSport/api/duplicates"));

	$class->_updatePlaylist('Duplicates', \@songs);

	$::d_musicmagic && msgf("MusicMagic: finished export (%d records)\n", scalar @songs);
}
	
sub _updatePlaylist {
	my ($class, $name, $songs) = @_;

	if (!$name || !scalar @$songs) {
		return;
	}

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

	$attributes{'CT'}                 = 'mmp';
	$attributes{'TAG'}                = 1;
	$attributes{'VALID'}              = 1;
	$attributes{'MUSICMAGIC_MIXABLE'} = 1;

	Slim::Music::Info::updateCacheEntry($url, \%attributes);
}

1;

__END__
