package Slim::Web::Pages::Playlist;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Web::Pages;
use Slim::Utils::Prefs;

my $log = logger('player.playlist');
my $prefs = preferences('server');
my $cache = Slim::Utils::Cache->new;

# keep a small cache of artist_id -> artistname mappings
my %artistIdMap;

use constant CACHE_TIME => 300;

sub init {
	Slim::Web::Pages->addPageFunction( qr/^playlist\.(?:htm|xml)/, \&playlist );
}

sub playlist {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('Start Playlist build');
	
	if (!defined($client)) {

		$params->{'playercount'} = 0;
		return Slim::Web::HTTP::filltemplatefile("playlist.html", $params);
	
	} elsif ($client->needsUpgrade() && !$client->isUpgrading()) {

		$params->{'player_needs_upgrade'} = '1';
		return Slim::Web::HTTP::filltemplatefile("playlist_needs_upgrade.html", $params);
	}
	
	# If synced, use the master's playlist
	$client = $client->master();

	$params->{'playercount'} = Slim::Player::Client::clientCount();
	
	my $songcount = Slim::Player::Playlist::count($client);
	my $currentItem = Slim::Player::Source::playingSongIndex($client);
	my $titleFormat = Slim::Music::Info::standardTitleFormat();
	my $externalFormats = Slim::Music::TitleFormatter->externalFormats();
	
	my $hasExternalFormatter = grep {
		$titleFormat =~ /\Q$_\E/;
	} @$externalFormats;

	$params->{'playlist_items'} = '';
	$params->{'skinOverride'} ||= '';
	
	my $itemsPerPage  = $prefs->get('itemsPerPage');
	my $stillScanning = Slim::Music::Import->stillScanning();
	my $currentSkin   = $params->{'skinOverride'} || $prefs->get('skin') || '';

	if ( !defined $params->{'start'} ) {
		$params->{'start'} = int($currentItem/$itemsPerPage) * $itemsPerPage;
	}

	if (!$songcount) {
		return Slim::Web::HTTP::filltemplatefile("playlist.html", $params);
	}
	
	my $cacheKey;
	# only cache rendered page for skins known to be compatible
	if ( !main::NOBROWSECACHE && !$hasExternalFormatter && $currentSkin =~ /(?:EN|Classic|Default)/ ) {
		$cacheKey = join(':', 
			$client->id,
			$client->currentPlaylistChangeTime(),
			$prefs->get('language'),
			$currentSkin,
			$params->{'start'},
			$songcount,
			$currentItem,
			$stillScanning ? 1 : 0,
			Slim::Utils::Misc::escape($titleFormat),
			$itemsPerPage,
			($params->{'cookies'} && $params->{'cookies'}->{'Squeezebox-noPlaylistCover'} && $params->{'cookies'}->{'Squeezebox-noPlaylistCover'}->value) ? 1 : 0
		);
	
		my $cached = $client->currentPlaylistRender();
		if ( $cached && !($cached = $cached->{$cacheKey}) ) {
			$cached = undef;
		}
		
		if ( !$cached && ($cached = $cache->get($cacheKey)) ) {
			$client->currentPlaylistRender({
				$cacheKey => $cached
			});
		}
		
		if ( $cached ) {
			main::INFOLOG && $log->info("Returning cached playlist html - not modified.");
			return $cached;
		}
	}

	if ($client->currentPlaylist() && !Slim::Music::Info::isRemoteURL($client->currentPlaylist())) {
		$params->{'current_playlist'} = $client->currentPlaylist();
		$params->{'current_playlist_modified'} = $client->currentPlaylistModified();
		$params->{'current_playlist_name'} = Slim::Music::Info::standardTitle($client,$client->currentPlaylist());
	}

	if (Slim::Utils::Misc::getPlaylistDir() && !$stillScanning) {
		$params->{'cansave'} = 1;
	}
	
	$params->{'pageinfo'} = Slim::Web::Pages::Common->pageInfo({
				'itemCount'    => $songcount,
				'currentItem'  => $currentItem,
				'path'         => $params->{'webroot'} . $params->{'path'},
				'otherParams'  => "&player=" . Slim::Utils::Misc::escape($client->id()),
				'start'        => $params->{'start'},
				'perPage'      => $params->{'itemsPerPage'} || $itemsPerPage,
	});
	
	my $start = $params->{'start'} = $params->{'pageinfo'}{'startitem'};
	my $end   = $params->{'pageinfo'}{'enditem'};
	
	my $offset = $start % 2 ? 0 : 1; 

	$params->{'playlist_items'} = [];

	# This is a hot loop.
	my $itemnum = 0;
	
	# get the playlist duration - use cached value if playlist has not changed
	my $durationCacheKey = 'playlist_duration_' . $client->currentPlaylistUpdateTime();
	if ( my $cached = $cache->get($durationCacheKey) ) {
		$params->{'pageinfo'}->{'totalDuration'} = Slim::Utils::DateTime::timeFormat($cached);
	}
	else {
		my $request = Slim::Control::Request->new( $client->id, [ 'status', 0, 1, 'tags:DD' ] );
		$request->source('internal');
		$request->execute();
		if ( $request->isStatusError() ) {
			$log->error($request->getStatusText());
		}
		elsif ( my $totalDuration = $request->getResult('playlist duration') ) {
			$params->{'pageinfo'}->{'totalDuration'} = Slim::Utils::DateTime::timeFormat($totalDuration);
			$cache->set($durationCacheKey, $totalDuration);
		}
	
		$params->{'pageinfo'}->{'totalDuration'} ||= 0;
	
		main::idleStreams();
	}

	# from BrowseLibrary->_tracks: dtuxgaAsSliqyorf, k, cJK
	my $tags = 'tags:xaAsSlLeNcJK';
	
	# Some additional tags we might need to satisfy the title format
	$titleFormat =~ /\bGENRE\b/    && ($tags .= 'g');
	$titleFormat =~ /\bTRACKNUM\b/ && ($tags .= 't');
	$titleFormat =~ /\bDISC\b/     && ($tags .= 'i');
	$titleFormat =~ /\bDISCC\b/    && ($tags .= 'q');
	$titleFormat =~ /\bCT\b/       && ($tags .= 'o');
	$titleFormat =~ /\bCOMMENT\b/  && ($tags .= 'k');
	$titleFormat =~ /\bYEAR\b/     && ($tags .= 'y');
	$titleFormat =~ /\bBITRATE\b/  && ($tags .= 'r');
	$titleFormat =~ /\bDURATION\b/ && ($tags .= 'd');
	$titleFormat =~ /\bURL\b/      && ($tags .= 'u');
	$titleFormat =~ /\bSAMPLERATE\b/ && ($tags .= 'T');
	$titleFormat =~ /\bSAMPLESIZE\b/ && ($tags .= 'I');
	
	my $includeAlbum  = $titleFormat !~ /\bALBUM\b/;
	my $includeArtist = $titleFormat !~ /\bARTIST\b/;
	
	# try to use cached data if we've been showing the same set of tracks before
	my $tracksCacheKey = join('_', 'playlist_tracks_', $client->currentPlaylistUpdateTime(), $start, $itemsPerPage, $tags);
	my $tracks;
	if ( my $cached = $cache->get($tracksCacheKey) ) {
		$tracks = $cached;
	}
	else {
		my $request = Slim::Control::Request->new( $client->id, [ 'status', $start, $itemsPerPage, $tags ] );
		$request->source('internal');
		$request->execute();
		if ( $request->isStatusError() ) {
			$log->error($request->getStatusText());
		}
		else {
			$tracks = $request->getResult('playlist_loop');
			$cache->set($tracksCacheKey, $tracks) if $tracks;
		}
		
		main::idleStreams();
	}
	
	my $titleFormatter = $titleFormat eq 'TITLE' 
		? sub { $_[0]->{title} }
		: sub {
			my $formatted = Slim::Music::TitleFormatter::infoFormat($_[1], $titleFormat) if $_[1];
			return $formatted || Slim::Music::TitleFormatter::infoFormat(undef, $titleFormat, 'TITLE', $_[0]) 
		};
	
	foreach ( @{ $tracks || [] } ) {
		$_->{'ct'}            = $_->{'type'} if $_->{'type'};
		if (my $secs = $_->{'duration'}) {
			$_->{'secs'}      = $secs;
			$_->{'duration'}  = sprintf('%d:%02d', int($secs / 60), $secs % 60);
		}
		$_->{'fs'}            = $_->{'filesize'} if $_->{'filesize'};
		$_->{'discc'}         = delete $_->{'disccount'} if defined $_->{'disccount'};
		$_->{'name'}          = $_->{'title'};
		
		$_->{'includeAlbum'}  = $includeAlbum;
		$_->{'includeArtist'} = $includeArtist;

		# we only handle full http URLs in cover element from remote services
		if ( $_->{'remote'} && $_->{'cover'} && $_->{'cover'} !~ /^http/ ) {
			delete $_->{'cover'};
		}
		$_->{'cover'} ||= $_->{'artwork_url'};
		$_->{'cover'} ||= '/music/' . ($_->{'coverid'} || $_->{'artwork_track_id'} || 0) . '/cover';
		
		$_->{'num'}           = $start + $itemnum;
		$_->{'currentsong'}   = 'current' if ($start + $itemnum) == $currentItem;
		$_->{'odd'}           = ($itemnum + $offset) % 2;
		
		# bug 17340 - in track lists we give the trackartist precedence over the artist
		if ( $_->{'trackartist'} ) {
			$_->{'artist'} = delete $_->{'trackartist'};
			$_->{'artist_ids'} = delete $_->{'trackartist_ids'};
		}
		# if the track doesn't have an ARTIST or TRACKARTIST tag, use all contributors of whatever other role is defined
		elsif ( !$_->{'artist_ids'} ) {
			my $artist_id = $_->{'artist_id'};
			foreach my $role ('albumartist', 'band') {
				my $id = $role . '_ids';
				if ( $_->{$id} && $_->{$id} =~ /$artist_id/ ) {
					$_->{'artist'} = $_->{$role};
				}
			}
		}
		
		# We might have multiple contributors for a track
		if (!$_->{'remote'}) {
			my @contributors = split /, /, join(', ', $_->{'albumartist'}, $_->{'artist'}, $_->{'trackartist'});
			my @ids = join(',', $_->{'albumartist_ids'}, $_->{'artist_ids'}, $_->{'trackartist_ids'}) =~ /(\b\d+\b)/g;
			
			# splitting comma separated artists sucks, as we could end up splitting Earth from Wind & Fire
			# Do potentially slow look up of artists one by one to get the right id -> name mapping
			if ( scalar @ids != scalar @contributors ) {
				@contributors = ();

				foreach my $id (@ids) {
					my $artistName = $artistIdMap{$id};
					
					if (!$artistName) {
						if ( my $request = Slim::Control::Request::executeRequest($client, [ 'artists', 0, 1, 'artist_id:' . $id ]) ) {
							($artistName) = map { $_->{artist} } grep { $_->{id} == $id } @{ $request->getResult('artists_loop') || [] };
							%artistIdMap = () if scalar keys %artistIdMap > 16;
							$artistIdMap{$id} = $artistName if $artistName;
						}
					}

					push @contributors, ($artistName || '');
				}
			}
			
			my %seen;
			my @tupels;
			
			for (my $x = 0; $x < scalar @ids; $x++) {
				next if $seen{$ids[$x]}++;
				
				push @tupels, {
					name => $contributors[$x],
					artistId => $ids[$x],
				};
			}
			
			$_->{'artistsWithAttributes'} ||= [];
			push @{$_->{'artistsWithAttributes'}}, @tupels;
		}
		
		# external formatters might expect a full track object
		my $track = $hasExternalFormatter ? Slim::Schema->find('Track', $_->{id}) : undef;

		$_->{'title'} = $titleFormatter->($_, $track);

		push @{$params->{'playlist_items'}}, $_;
		
		$itemnum++;

		# don't neglect the streams too long
		main::idleStreams() if !($itemnum % 10);
	}

	$params->{'noArtist'} = string('NO_ARTIST');
	$params->{'noAlbum'}  = string('NO_ALBUM');

	main::INFOLOG && $log->info("End playlist build.");

	my $page = Slim::Web::HTTP::filltemplatefile("playlist.html", $params);

	if ($cacheKey) {
		# keep one copy in memory for the old skins, polling frequently
		$client->currentPlaylistRender({
			$cacheKey => $page
		});
		
		# longer living copy in the disk cache
		$cache->set($cacheKey, $page);
	}

	return $page;
}

1;

__END__
