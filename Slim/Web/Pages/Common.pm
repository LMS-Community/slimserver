package Slim::Web::Pages::Common;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Basename qw(basename);
use File::ReadBackwards;
use Scalar::Util qw(blessed);

use base qw(Slim::Web::Pages);

use Slim::Player::Playlist;
use Slim::Formats::Playlists::M3U;
use Slim::Player::Client;
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Progress;
use Slim::Web::HTTP;

my $prefs = preferences('server');

my $log    = logger('network.http');
my $sqllog = logger('database.sql');

our %hierarchy = (
	'artist' => 'album,track',
	'album'  => 'track',
	'song '  => '',
);

sub init(){

	Slim::Web::Pages->addPageFunction(qr/^firmware\.(?:html|xml)/,\&firmware);
	Slim::Web::Pages->addPageFunction(qr/^tunein\.(?:htm|xml)/,\&tuneIn);
	Slim::Web::Pages->addPageFunction(qr/^update_firmware\.(?:htm|xml)/,\&update_firmware);
	
	# cleanup potential left-overs from downloading ZIPped log files
	Slim::Utils::Misc::deleteFiles(Slim::Utils::OSDetect::dirsFor('log'), qr/^(?:server|scanner).*zip$/i);
}

sub _lcPlural {
	my ($class, $count, $singular, $plural) = @_;

	# only convert to lowercase if our language does not wand uppercase (default lc)
	my $word = ($count == 1 ? string($singular) : string($plural));
	$word = (string('MIDWORDS_UPPER') ? $word : lc($word));
	return sprintf("%s %s", $count, $word);
}

sub addLibraryStats {
	my ($class, $params, $client) = @_;
	
	if (!Slim::Schema::hasLibrary()) {
		return;
	}

	if (Slim::Music::Import->stillScanning) {

		$params->{'warn'} = 1;

		if (my $p = Slim::Schema->rs('Progress')->search({ 'type' => 'importer', 'active' => 1 })->first) {

			my $name = $p->name;
			$name =~ s/(.*)\|//;
			
			$params->{'progress'} = {
				'name' => $name,
				'bar'  => Slim::Web::Pages::Progress::progressBar($p, 40),
				'obj'  => $p,
			}
		}

		return;
	}

	if ($prefs->get('disableStatistics')) {

		$params->{'song_count'}   = 0;
		$params->{'album_count'}  = 0;
		$params->{'artist_count'} = 0;

		return;
	}

	my $totals = Slim::Schema->totals($client);
	$params->{'album_count'}  = $class->_lcPlural($totals->{'album'}, 'ALBUM', 'ALBUMS');
	$params->{'song_count'}   = $class->_lcPlural($totals->{'track'}, 'SONG', 'SONGS');
	$params->{'artist_count'} = $class->_lcPlural($totals->{'contributor'}, 'ARTIST', 'ARTISTS');

	if ( main::INFOLOG && $sqllog->is_info ) {
		$sqllog->info(sprintf("Found %s, %s & %s", 
			$params->{'song_count'}, $params->{'album_count'}, $params->{'artist_count'}
		));
	}
}

sub addSongInfo {
	my ($class, $client, $params, $getCurrentTitle) = @_;

	my $track = $params->{'itemobj'};
	my $id    = $params->{'item'};
	my $url;

	# kinda pointless, but keeping with compatibility
	if (!defined $track && !defined $id) {
		return;
	}

	if (ref($track) && !$track->can('id')) {
		return;
	}

	if ($track && !blessed($track)) {

		$track = Slim::Schema->objectForUrl({
			'url'      => $url,
			'create'   => 1,
			'readTags' => 1
		});

	} elsif ($id) {

		$track = Slim::Schema->find('Track', $id);
		$url   = $track->url() if $track;
	}

	$url   = $track->url() if $track;
	
	# Add plugin metadata if available
	if ( Slim::Music::Info::isRemoteURL($url) ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $url );
		if ( $handler && $handler->can('getMetadataFor') ) {
			$params->{'plugin_meta'} = $handler->getMetadataFor( $client, $url );
			
			# Only use cover if it's a full URL
			if ( $params->{'plugin_meta'}->{'cover'} && $params->{'plugin_meta'}->{'cover'} !~ /^http/ ) {
				delete $params->{'plugin_meta'}->{'cover'};
			}

		}
	}

	if (blessed($track) && $track->can('filesize')) {

		# let the template access the object directly.
		$params->{'itemobj'}    = $track unless $params->{'itemobj'};

		$params->{'filelength'} = Slim::Utils::Misc::delimitThousands($track->filesize);
		$params->{'bitrate'}    = $track->prettyBitRate;

		if ($getCurrentTitle) {
			$params->{'songtitle'} = Slim::Music::Info::getCurrentTitle($client, $track->url, 'web');
		} else {
			$params->{'songtitle'} = Slim::Music::Info::standardTitle(undef, $track);
		}

		$params->{favoritesEnabled} = Slim::Utils::Favorites->enabled;
		if ($params->{favoritesEnabled} && Slim::Music::Info::isURL($url)) {
			$params->{isFavorite} = defined Slim::Utils::Favorites->new($client)->findUrl($url);
		}

		# make urls in comments into links
		for my $comment ($track->comment) {

			next unless defined $comment && $comment !~ /^\s*$/;

			if (!($comment =~ s!\b(http://[A-Za-z0-9\-_\.\!~*'();/?:@&=+$,]+)!<a href=\"$1\" target=\"_blank\">$1</a>!igo)) {

				# handle emusic-type urls which don't have http://
				$comment =~ s!\b(www\.[A-Za-z0-9\-_\.\!~*'();/?:@&=+$,]+)!<a href=\"http://$1\" target=\"_blank\">$1</a>!igo;
			}

			$params->{'comment'} .= $comment;
		}
	
		# handle artwork bits
		if ($track->coverArt) {
			$params->{'coverThumb'} = $track->coverid;
		}

		if (Slim::Music::Info::isRemoteURL($url)) {

			$params->{'download'} = $url;

		} else {

			$params->{'download'} = sprintf('%smusic/%d/download', $params->{'webroot'}, $track->id);

		}
	}
}

sub addPlayerList {
	my ($class, $client, $params) = @_;

	$params->{'playercount'} = Slim::Player::Client::clientCount();
	
	my @players = Slim::Player::Client::clients();

	if (scalar(@players) > 1) {

		my %clientlist = ();

		for my $eachclient (@players) {

			$clientlist{$eachclient->id()} =  $eachclient->name();

			if ($eachclient->isSynced()) {
				$clientlist{$eachclient->id()} .= " (" . string('SYNCHRONIZED_WITH') . " " .
					$eachclient->syncedWithNames() .")";
			}	
		}

		$params->{'player_chooser_list'} = $class->options($client->id(), \%clientlist, $params->{'skinOverride'}, 50);
	}
}

sub options {
	my ($class, $selected, $option, $skinOverride, $truncate) = @_;

	# pass in the selected value and a hash of value => text pairs to get the option list filled
	# with the correct option selected.

	my $optionlist = '';

	for my $curroption (sort { $option->{$a} cmp $option->{$b} } keys %{$option}) {

		$optionlist .= ${Slim::Web::HTTP::filltemplatefile("select_option.html", {
			'selected'     => ($curroption eq $selected),
			'key'          => $curroption,
			'value'        => $option->{$curroption},
			'skinOverride' => $skinOverride,
			'maxLength'    => $truncate,
		})};
	}

	return $optionlist;
}


# Return a hashref with paging information, all list indexes are zero based
#
# named arguments:
# itemsRef : reference to the list of items
# itemCount : number of items in the list, not needed if itemsRef supplied
# otherParams : used to build the query portion of the url
# path : used to build the path portion of the url
# start : starting index of the displayed page in the list of items
# perPage : items per page to display, preference used by default
# addAlpha : flag determining whether to build the alpha map, requires itemsRef
# currentItem : the index of the "current" item in the list, 
#                if start not supplied this will be used to determine starting page
#
# Hash keys set:
# startitem : index in list of first item on page
# enditem : index in list of last item on page
# totalitems : number of items in the list
# itemsPerPage : number of items on each page
# currentpage : index of current page in list of pages
# totalpages : number of pages of items
# otherparams : as above
# path : as above
# alphamap : hash relating first character of sorted list to the index of the
#             first appearance of that character in the list.
# totalalphapages : total number of pages in alpha pagebar

sub pageInfo {
	my ($class, $args) = @_;
	
	my $otherparams  = $args->{'otherParams'};
	my $start        = $args->{'start'};
	my $itemsPerPage = $args->{'perPage'} || $prefs->get('itemsPerPage');
	my $index        = $args->{'indexList'};

	my %pageinfo  = ();
	my %alphamap  = ();
	my @alphaindex = ();
	my $itemCount = 0;
	my $end;
	
	if ($index) {
		foreach (@$index) {
			my $key = $_->[0];
			utf8::decode($key);
			$key = ' ' if !defined $key;
			$alphamap{$key} = $itemCount;
			$itemCount += $_->[1];
			push (@alphaindex, $key);
		}
		
		if ($args->{'itemCount'} && $args->{'itemCount'} > $itemCount) {
			$itemCount = $args->{'itemCount'};
		}
	}

	else {

		if ($args->{'itemCount'}) {

			$itemCount = $args->{'itemCount'}

		} else {

			$itemCount = 0;
		}
	}

	if (!$itemsPerPage || $itemsPerPage > $itemCount) {

		# we divide by this, so make sure it will never be 0
		$itemsPerPage = $itemCount || 1;
	}

	if (!defined($start) || $start eq '') {

		if ($args->{'currentItem'}) {

			$start = int($args->{'currentItem'} / $itemsPerPage) * $itemsPerPage;
		
		} else {

			$start = 0;
		}
	}

	if ($start >= $itemCount) {

		$start = $itemCount - $itemsPerPage;

		if ($start < 0) {
			$start = 0;
		}
	}
	
	$end = $start + $itemsPerPage - 1;

	if ($end >= $itemCount) {
		$end = $itemCount - 1;
	}

	# Don't let a negative end through.
	if ($end < 0) {
		$end = $itemCount;
	}

	$pageinfo{'enditem'}      = $end;
	$pageinfo{'totalitems'}   = $itemCount;
	$pageinfo{'itemsperpage'} = $itemsPerPage;
	$pageinfo{'currentpage'}  = int($start/$itemsPerPage);
	$pageinfo{'totalpages'}   = POSIX::ceil($itemCount/$itemsPerPage) || 0;
	$pageinfo{'otherparams'}  = defined($otherparams) ? $otherparams : '';
	$pageinfo{'path'}         = $args->{'path'};

	if ($index && $itemCount) {

		my @letterstarts = sort { $a <=> $b } values %alphamap;
		my @pagestarts   = $letterstarts[0];

		# some cases of alphamap shift the start index from 0, trap this.
		$start = $letterstarts[0] unless $args->{'start'} ;

		my $newend;

		for my $nextend (@letterstarts) {

			# check for overflow of alpha boundary, reset end to end of next alpha
			if ($nextend > $end && !defined($newend)) {
				$newend = $nextend - 1;
			}

			if ($pagestarts[0] + $itemsPerPage - 1 < $nextend) {

				# build pagestarts in descending order
				unshift @pagestarts, $nextend;
			}
		}

		# if last block and still no newend found, set it to the last of the list
		if (!defined($newend) && $itemCount > $end) {
			$newend = $itemCount - 1;
		}

		$pageinfo{'enditem'}         = $newend;
		$pageinfo{'totalalphapages'} = scalar(@pagestarts);

		KEYLOOP: for my $alphakey (keys %alphamap) {

			my $alphavalue = $alphamap{$alphakey};

			for my $pagestart (@pagestarts) {

				if ($alphavalue >= $pagestart) {

					$alphamap{$alphakey} = $pagestart;
					next KEYLOOP;
				}
			}
		}

		$pageinfo{'alphamap'} = \%alphamap;
		$pageinfo{'alphaindex'} = \@alphaindex;
	}

	# set the start index, accounting for alpha cases
	$pageinfo{'startitem'} = $start || 0;

	return \%pageinfo;
}

sub firmware {
	my ($client, $params) = @_;

	return Slim::Web::HTTP::filltemplatefile("firmware.html", $params);
}

# This is here just to support SDK4.x (version <=10) clients
# so it always sends an upgrade to version 10 using the old upgrade method.
sub update_firmware {
	my ($client, $params) = @_;

	$params->{'warning'} = Slim::Player::Squeezebox1::upgradeFirmware($params->{'ipaddress'}, 10) 
		|| string('UPGRADE_COMPLETE_DETAILS');
	
	return Slim::Web::HTTP::filltemplatefile("update_firmware.html", $params);
}

sub tuneIn {
	my ($client, $params) = @_;
	
	if ( $params->{'url'} ) {
		$client->execute( [ 
			'playlist', 
			$params->{'tuneInAdd'} ? 'add' : 'play', 
			$params->{'url'} 
		] );
	}
	
	return Slim::Web::HTTP::filltemplatefile('tunein.html', $params);
}

sub logFile {
	my ($class, $httpClient, $params, $response, $logfile) = @_;
	
	$logfile =~ s/log/server/;
	$logfile .= 'LogFile';
	
	my $logFile = Slim::Utils::Log->$logfile;

	if ( $params->{zip} && -f $logFile ) {
		my $zip;

		eval {
			require Archive::Zip;

			Archive::Zip::setErrorHandler( sub {
				$log->error("Error compressing log file: " . shift);
			} );
			
			$zip = Archive::Zip->new();
		};
		
		if (defined $zip) {
			# COMPRESSION_LEVEL_FASTEST == 1
			my $member = $zip->addFile( $logFile, basename($logFile), 1 );
			
			my $zipFile = $logFile . '.zip';
			
			# AZ_OK == 0
			if ( $member && $zip->writeToFileNamed( $zipFile ) == 0 ) {
				$response->code(HTTP::Status::RC_OK);
				Slim::Web::HTTP::sendStreamingFile( $httpClient, $response, 'application/zip', $zipFile  );
				return;
			}
		}

		$log->error("Error compressing log file using Archive::Zip $@ - returning uncompressed log file instead");
		$params->{full} = 1;
	}
	
	if ( $params->{full} && -f $logFile ) {
		$response->code(HTTP::Status::RC_OK);
		Slim::Web::HTTP::sendStreamingFile( $httpClient, $response, 'text/plain', $logFile );
		return;
	}

	my $lines = $params->{lines};
	my $search = $params->{search};
	my $url = $params->{path};
	$url .= "?lines=$lines" if $lines;
	$url .= ($lines ? '&' : '?') . "search=$search" if $search;

	# if we're called with a GET, then likely it was a link, use default refresh rate
	$params->{refresh} = 10 if !defined $params->{refresh} && $response->request->method eq 'GET';	

	my $count = ($lines * 1) || 50;

	$params->{logLines} = '';
	
	my $file = File::ReadBackwards->new($logFile);
		
	if ($file){

		my @lines;
		while ( $count && (my $line = $file->readline()) ) {
			next if $search && $line !~ /\Q$search\E/i; 
			
			$line = "<span style=\"color:green\">$line<\/span>" if $line =~ /main::init.*Starting/;
			$line = qq(<span style="color:red">$line<\/span>) if $line =~ /(error)\b/i;
			$line = qq(<span style="color:orange">$line<\/span>) if $line =~ /(warn.*?)\b/i;
			unshift (@lines, $line);
			
			--$count;
		}
		$params->{logLines} .= join('', @lines);

		$file->close();			
	};

	$response->expires(0);
	$response->header('Cache-Control' => 'no-cache');

	return Slim::Web::HTTP::filltemplatefile("log.html", $params);
}

sub statusM3u {
	my ($class, $client) = @_;
	
	# if the HTTP client has asked for a .m3u file, then always return the current playlist as an M3U
	if (defined($client)) {

		my $count = Slim::Player::Playlist::count($client) && do {
			return Slim::Formats::Playlists::M3U->write(\@{Slim::Player::Playlist::playList($client)});
		};
	}
}

1;
