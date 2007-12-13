package Slim::Plugin::MusicMagic::Importer;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use LWP::Simple;
use Scalar::Util qw(blessed);
use Socket qw($LF);

use Slim::Plugin::MusicMagic::Common;

use Slim::Music::Import;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Versions;

my $initialized = 0;
my $MMMVersion  = 0;
my $MMSHost;
my $MMSport;

my $OS  = Slim::Utils::OSDetect::OS();

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.musicmagic',
	'defaultLevel' => 'ERROR',
});

my $prefs = preferences('plugin.musicmagic');

sub useMusicMagic {
	my $class    = shift;
	my $newValue = shift;

	my $can      = $class->canUseMusicMagic();

	if (defined($newValue)) {

		if (!$can) {
			$prefs->set('musicmagic', 0);
		} else {
			$prefs->set('musicmagic', $newValue);
		}
	}

	my $use = $prefs->get('musicmagic');

	if (!defined($use) && $can) { 

		$prefs->set('musicmagic', 1);

	} elsif (!defined($use) && !$can) {

		$prefs->set('musicmagic', 0);
	}

	$use = $prefs->get('musicmagic') && $can;

	Slim::Music::Import->useImporter($class, $use);

	$log->info("Using musicip: $use");

	return $use;
}

sub canUseMusicMagic {
	my $class = shift;

	return $initialized || $class->initPlugin();
}

sub initPlugin {
	my $class = shift;

	return 1 if $initialized;

	Slim::Plugin::MusicMagic::Common::checkDefaults();

	$MMSport = $prefs->get('port');
	$MMSHost = $prefs->get('host');

	$log->info("Testing for API on $MMSHost:$MMSport");

	my $initialized = get("http://$MMSHost:$MMSport/api/version");

	if (defined $initialized) {

		# Note: Check version restrictions if any
		chomp($initialized);

		$log->info($initialized);

		($MMMVersion) = ($initialized =~ /Version ([\d\.]+)$/);

		Slim::Music::Import->addImporter($class, {
			'reset'        => \&resetState,
			'playlistOnly' => 1,
			'use'          => $prefs->get('musicmagic'),
		});

		Slim::Player::ProtocolHandlers->registerHandler('musicmagicplaylist', 0);

	} else {

		$initialized = 0;

		$log->info("Cannot Connect");
	}

	return $initialized;
}

sub resetState {

	$log->debug("Resetting Last Library Change Time.");

	Slim::Music::Import->setLastScanTime('MMMLastLibraryChange', 0);
}

sub startScan {
	my $class = shift;

	if (!$class->useMusicMagic) {
		return;
	}
		
	$log->debug("Start export");

	if (Slim::Music::Import->scanPlaylistsOnly) {

		$class->exportPlaylists;

	} else {

		$class->exportFunction;
	}

	$class->doneScanning;
} 

sub doneScanning {
	my $class = shift;

	$log->info("Done Scanning");

	my $lastDate = get("http://$MMSHost:$MMSport/api/cacheid?contents");

	if ($lastDate) {

		chomp($lastDate);

		Slim::Music::Import->setLastScanTime('MMMLastLibraryChange', $lastDate);
	}

	Slim::Music::Import->endImporter($class);
}

sub exportFunction {
	my $class = shift;

	$MMSport = $prefs->get('port') unless $MMSport;
	$MMSHost = $prefs->get('host') unless $MMSHost;

	my $count = get("http://$MMSHost:$MMSport/api/getSongCount");

	if ($count) {

		# convert to integer
		chomp($count);

		$count += 0;
	}

	$log->info("Got $count song(s).");

	$class->exportSongs($count);
	$class->exportPlaylists;
	$class->exportDuplicates;
}

sub exportSongs {
	my $class = shift;
	my $count = shift;

	my $progress = Slim::Utils::Progress->new({ 
		'type'  => 'importer', 
		'name'  => 'musicmagic', 
		'total' => $count, 
		'bar'   => 1
	});

	# MMM Version 1.5+ adds support for /api/songs?extended, which pulls
	# down the entire library, separated by $LF$LF - this allows us to make
	# 1 HTTP request, and the process the file.
	if (Slim::Utils::Versions->compareVersions($MMMVersion, '1.5') >= 0) {

		$log->info("Fetching ALL song data via songs/extended..");

		my $MMMSongData = catdir( preferences('server')->get('cachedir'), 'mmm-song-data.txt' );

		my $MMMDataURL  = "http://$MMSHost:$MMSport/api/songs?extended";

		getstore($MMMDataURL, $MMMSongData);

		if (!-r $MMMSongData) {

			logError("Couldn't connect to $MMMDataURL ! : $!");
			return;
		}

		open(MMMDATA, $MMMSongData) || do {

			logError("Couldn't read file: $MMMSongData : $!");
			return;
		};

		$log->info("Finished fetching - processing.");

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
	# 
	# This breaks Linux however, so only do it on Windows & OS X
	my @keys  = qw(album artist genre name);

	if ($OS eq 'mac' || $OS eq 'win') {

		push @keys, 'file';
	}

	for my $key (@keys) {

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

	$log->debug("Exporting song: $songInfo{'file'}");

	# Both Linux & Windows need conversion to the current charset.
	if ($OS ne 'mac') {
		$songInfo{'file'} = Slim::Utils::Unicode::utf8encode_locale($songInfo{'file'});
	}

	my $fileurl = Slim::Utils::Misc::fileURLFromPath($songInfo{'file'});

	my $track   = Slim::Schema->rs('Track')->updateOrCreate({

		'url'        => $fileurl,
		'attributes' => \%attributes,
		'readTags'   => 1,

	}) || do {

		$log->warn("Couldn't create track for $fileurl");

		$progress->update($songInfo{'file'});

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

	$progress->update($songInfo{'file'});
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

		if ( $log->is_info ) {
			$log->info(sprintf("Got playlist %s with %d items", $playlists[$i], scalar @songs));
		}

		$class->_updatePlaylist($playlists[$i], \@songs);
	}
}

# Create playlists containing the duplicate items as identified by MusicMagic
sub exportDuplicates {
	my $class = shift;

	# check for dupes, but not with 1.1.3
	if (Slim::Utils::Versions->compareVersions('1.1.3', $MMMVersion) <= 0) {
		return;
	}

	$log->info("Checking for duplicates.");

	my @songs = split(/\n/, get("http://$MMSHost:$MMSport/api/duplicates"));

	$class->_updatePlaylist('Duplicates', \@songs);

	if ( $log->is_info ) {
		$log->info(sprintf("Finished export (%d records)", scalar @songs));
	}
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
		$prefs->get('playlist_prefix'),
		$name,
		$prefs->get('playlist_suffix'),
	);

	$attributes{'LIST'}  = [];

	for my $song (@$songs) {

		if ($OS eq 'win') {

			$song = Slim::Utils::Unicode::utf8decode_guess(
				$song, Slim::Utils::Unicode::encodingFromString($song),
			);
		}

		$song = Slim::Utils::Misc::fileURLFromPath(
			Slim::Plugin::MusicMagic::Common::convertPath($song)
		);

		push @{$attributes{'LIST'}}, $song;
	}

	$attributes{'CT'}                 = 'mmp';
	$attributes{'TAG'}                = 1;
	$attributes{'VALID'}              = 1;
	$attributes{'MUSICMAGIC_MIXABLE'} = 1;

	Slim::Music::Info::updateCacheEntry($url, \%attributes);
}

1;

__END__
