package Slim::Web::Pages::Playlist;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use POSIX ();
use Scalar::Util qw(blessed);
use Tie::Cache::LRU::Expires;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Web::Pages;
use Slim::Utils::Prefs;

my $log = logger('player.playlist');

my $prefs = preferences('server');

use constant CACHE_TIME => 300;

tie my %albumCache, 'Tie::Cache::LRU::Expires', EXPIRES => 5, ENTRIES => 5;

sub init {
	
	Slim::Web::Pages->addPageFunction( qr/^playlist\.(?:htm|xml)/, \&playlist );
}

sub playlist {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	
	if (!defined($client)) {

		# fixed faster rate for noclients
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

	$params->{'playlist_items'} = '';
	$params->{'skinOverride'} ||= '';
	
	my $itemsPerPage = $prefs->get('itemsPerPage');

	if ( !$params->{'start'} ) {
		$params->{'start'} = int($currentItem/$itemsPerPage) * $itemsPerPage;
	}

	if ($client->currentPlaylist() && !Slim::Music::Info::isRemoteURL($client->currentPlaylist())) {
		$params->{'current_playlist'} = $client->currentPlaylist();
		$params->{'current_playlist_modified'} = $client->currentPlaylistModified();
		$params->{'current_playlist_name'} = Slim::Music::Info::standardTitle($client,$client->currentPlaylist());
	}

#	if (main::DEBUGLOG && $log->is_debug && $client->currentPlaylistRender() && ref($client->currentPlaylistRender()) eq 'ARRAY') {
#
#		$log->debug("currentPlaylistChangeTime : " . localtime($client->currentPlaylistChangeTime()));
#		$log->debug("currentPlaylistRender     : " . localtime($client->currentPlaylistRender()->[0]));
#		$log->debug("currentPlaylistRenderSkin : " . $client->currentPlaylistRender()->[1]);
#		$log->debug("currentPlaylistRenderStart: " . $client->currentPlaylistRender()->[2]);
#
#		$log->debug("skinOverride: $params->{'skinOverride'}");
#		$log->debug("start: $params->{'start'}");
#	}
#
#	# Only build if we need to - try to return cached html or build page from cached info
#	my $cachedRender = $client->currentPlaylistRender();
#
#	if ($songcount > 0 && 
#		defined $params->{'skinOverride'} &&
#		defined $params->{'start'} &&
#		$cachedRender && ref($cachedRender) eq 'ARRAY' &&
#		$client->currentPlaylistChangeTime() &&
#		$client->currentPlaylistChangeTime() < $cachedRender->[0] &&
#		$cachedRender->[1] eq $params->{'skinOverride'} &&
#		$cachedRender->[2] eq $params->{'start'} ) {
#
#		if ($cachedRender->[5]) {
#
#			main::INFOLOG && $log->info("Returning cached playlist html - not modified.");
#
#			# reset cache timer to forget cached html
#			Slim::Utils::Timers::killTimers($client, \&flushCachedHTML);
#			Slim::Utils::Timers::setTimer($client, time() + CACHE_TIME, \&flushCachedHTML);
#
#			return $cachedRender->[5];
#
#		} else {
#
#			main::INFOLOG && $log->info("Rebuilding playlist from cached params.");
#
#			if (Slim::Utils::Misc::getPlaylistDir() && !Slim::Music::Import->stillScanning()) {
#				$params->{'cansave'} = 1;
#			}
#
#			$params->{'playlist_items'}   = $cachedRender->[3];
#			$params->{'pageinfo'}         = $cachedRender->[4];
#
#			return Slim::Web::HTTP::filltemplatefile("playlist.html", $params);
#		}
#	}

	if (!$songcount) {
		return Slim::Web::HTTP::filltemplatefile("playlist.html", $params);
	}

	my $item;
	my %form;

	if (Slim::Utils::Misc::getPlaylistDir() && !Slim::Music::Import->stillScanning()) {
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
	
	my ($start,$end);
	$start = $params->{'start'} = $params->{'pageinfo'}{'startitem'};
	$end = $params->{'pageinfo'}{'enditem'};
	
	my $offset = $start % 2 ? 0 : 1; 

	my $composerIn   = $prefs->get('composerInArtists');

	my $titleFormat  = Slim::Music::Info::standardTitleFormat();

	$params->{'playlist_items'} = [];
	$params->{'myClientState'}  = $client;

	# This is a hot loop.
	# But it's better done all at once than through the scheduler.
	my $itemnum = 0;
	
	my $t = Time::HiRes::time;

	# get the playlist duration
	my $request = Slim::Control::Request->new( $client->id, [ 'status', 0, $songcount-1, 'tags:DD' ] );
	$request->source('internal');
	$request->execute();
	if ( $request->isStatusError() ) {
		$log->error($request->getStatusText());
	}
	elsif ( my $totalDuration = $request->getResult('playlist duration') ) {
		$params->{'pageinfo'}->{'totalDuration'} = Slim::Utils::DateTime::timeFormat($totalDuration);
	}
	
	main::idleStreams();
	
	$params->{'pageinfo'}->{'totalDuration'} ||= 0;

	# from BrwoseLibrary->_tracks: dtuxgaAsSliqyorf, k, cJK
	my $tags = 'tags:xaAsSlLeN' . 'cJK';
	
	# Some additional tags we might need to satisfy the title format
	$titleFormat =~ /\bGENRE\b/    && ($tags .= 'g');
	$titleFormat =~ /\bTRACKNUM\b/ && ($tags .= 't');
	$titleFormat =~ /\bDISC\b/     && ($tags .= 'i');
	$titleFormat =~ /\bDISCC\b/    && ($tags .= 'q');
	$titleFormat =~ /\bCT\b/       && ($tags .= 'o');
	$titleFormat =~ /\bCOMMENT\b/  && ($tags .= 'k');
	$titleFormat =~ /\bYEAR\b/     && ($tags .= 'y');
	$titleFormat =~ /\bBITRATE\b/  && ($tags .= 'r');
	
	my $includeAlbum  = $titleFormat !~ /\bALBUM\b/;
	my $includeArtist = $titleFormat !~ /\bARTIST\b/;
	
	$request = Slim::Control::Request->new( $client->id, [ 'status', $start, $itemsPerPage, $tags ] );
	$request->source('internal');
	$request->execute();
	if ( $request->isStatusError() ) {
		$log->error($request->getStatusText());
	}
	
	main::idleStreams();
	
	my $titleFormatter = $titleFormat eq 'TITLE' 
		? sub { $_[0]->{title} }
		: sub { Slim::Music::TitleFormatter::infoFormat(undef, $titleFormat, 'TITLE', $_[0]) };
	
	foreach ( @{ $request->getResult('playlist_loop') } ) {
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
		
		$_->{'num'}           = $itemnum;
		$_->{'currentsong'}   = 'current' if ($start + $itemnum) == $currentItem;
		$_->{'odd'}           = ($itemnum + $offset) % 2;
		
		# bug 17340 - in track lists we give the trackartist precedence over the artist
		if ( $_->{'trackartist'} ) {
			$_->{'artist'} = $_->{'trackartist'};
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
		
		# TODO - contributors on multi-contributor track?
		if (!$_->{'remote'}) {
			$_->{'artistsWithAttributes'} = [{
				name => $_->{'artist'},
				artistId => $_->{'artist_id'},
			}];
		}

		# TODO - current_title for remote streams?
		$_->{'title'}         = $titleFormatter->($_);

		push @{$params->{'playlist_items'}}, $_;
		
		$itemnum++;

		# don't neglect the streams too long
		main::idleStreams() if !($itemnum % 10);
	}

	$params->{'noArtist'} = Slim::Utils::Strings::string('NO_ARTIST');
	$params->{'noAlbum'}  = Slim::Utils::Strings::string('NO_ALBUM');

	main::INFOLOG && $log->info("End playlist build.");

	my $page = Slim::Web::HTTP::filltemplatefile("playlist.html", $params);

#	if ($client) {
#
#		# Cache to reduce cpu spike seen when playlist refreshes
#		# For the moment cache html for Classic, other skins only cache params
#		# Later consider caching as html unless an ajaxRequest
#		# my $cacheHtml = !$params->{'ajaxRequest'};
#		my $cacheHtml = (($params->{'skinOverride'} || $prefs->get('skin')) eq 'Classic');
#
#		my $time = time();
#
#		$client->currentPlaylistRender([
#			$time,
#			($params->{'skinOverride'} || ''),
#			($params->{'start'}),
#			$params->{'playlist_items'},
#			$params->{'pageinfo'},
#			$cacheHtml ? $page : undef,
#		]);
#
#		if ( main::INFOLOG && $log->is_info ) {
#			$log->info( sprintf("Caching playlist as %s.", $cacheHtml ? 'html' : 'params') );
#		}
#
#		Slim::Utils::Timers::killTimers($client, \&flushCachedHTML);
#
#		if ($cacheHtml) {
#			Slim::Utils::Timers::setTimer($client, $time + CACHE_TIME, \&flushCachedHTML);
#		}
#	}

	return $page;
}

#sub flushCachedHTML {
#	my $client = shift;
#
#	main::INFOLOG && $log->info("Flushing playlist html cache for client.");
#	$client->currentPlaylistRender(undef);
#}

1;

__END__
