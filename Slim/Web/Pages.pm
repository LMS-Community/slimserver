package Slim::Web::Pages;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use POSIX ();
use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

use Slim::Web::Pages::Search;
use Slim::Web::Pages::BrowseDB;
use Slim::Web::Pages::BrowseTree;
use Slim::Web::Pages::Home;
use Slim::Web::Pages::Status;
use Slim::Web::Pages::Playlist;
use Slim::Web::Pages::History;
use Slim::Web::Pages::EditPlaylist;
use Slim::Web::Pages::Progress;
use Slim::Utils::Progress;

my $prefs = preferences('server');

our %additionalLinks = ();

our %hierarchy = (
	'artist' => 'album,track',
	'album'  => 'track',
	'song '  => '',
);

sub init {

	Slim::Web::HTTP::addPageFunction(qr/^firmware\.(?:html|xml)/,\&firmware);
	Slim::Web::HTTP::addPageFunction(qr/^songinfo\.(?:htm|xml)/,\&songInfo);
	Slim::Web::HTTP::addPageFunction(qr/^tunein\.(?:htm|xml)/,\&tuneIn);
	Slim::Web::HTTP::addPageFunction(qr/^update_firmware\.(?:htm|xml)/,\&update_firmware);

	# pull in the memory usage module if requested.
	if (logger('server.memory')->is_info) {

		Slim::bootstrap::tryModuleLoad('Slim::Utils::MemoryUsage');

		if ($@) {

			logError("Couldn't load Slim::Utils::MemoryUsage: [$@]");

		} else {

			Slim::Web::HTTP::addPageFunction(qr/^memoryusage\.html.*/,\&memory_usage);
		}
	}

	Slim::Web::Pages::Home->init();
	Slim::Web::Pages::BrowseDB::init();
	Slim::Web::Pages::BrowseTree::init();
	Slim::Web::Pages::Search::init();
	Slim::Web::Pages::Status::init();
	Slim::Web::Pages::EditPlaylist::init(); # must precede Playlist::init();
	Slim::Web::Pages::Playlist::init();
	Slim::Web::Pages::History::init();
	Slim::Web::Pages::Progress::init();
}

sub _lcPlural {
	my ($class, $count, $singular, $plural) = @_;

	# only convert to lowercase if our language does not wand uppercase (default lc)
	my $word = ($count == 1 ? string($singular) : string($plural));
	$word = (string('MIDWORDS_UPPER', '', 1) ? $word : lc($word));
	return sprintf("%s %s", $count, $word);
}

sub addPageLinks {
	my ($class, $category, $links, $noquery) = @_;

	if (ref($links) ne 'HASH') {
		return;
	}

	while (my ($title, $path) = each %$links) {

		if (defined($path)) {

			my $separator = '';

			if (!$noquery) {

				if ($path =~ /\?/) {
					$separator = '&';
				} else {
					$separator = '?';
				}
			}

			$additionalLinks{$category}->{$title} = $path . $separator;

		} else {

			delete($additionalLinks{$category}->{$title});
		}
	}

	if (not keys %{$additionalLinks{$category}}) {

		delete($additionalLinks{$category});
	}
}

sub addLibraryStats {
	my ($class, $params, $rs, $previousLevel) = @_;

	if (Slim::Music::Import->stillScanning) {

		$params->{'warn'} = 1;

		if (my $p = Slim::Schema->rs('Progress')->search({ 'type' => 'importer', 'active' => 1 })->first) {

			$params->{'progress'} = {
				'name' => $p->name,
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

	my %counts = ();
	my $level  = $params->{'levelName'} || '';

	# Albums needs a roles check, as it doesn't go through contributors first.
	# if (defined $rs && !grep { 'contributorAlbums' } @{$rs->{'attrs'}->{'join'}}) {

	#	if (my $roles = Slim::Schema->artistOnlyRoles) {

			#$rs = $rs->search_related('contributorAlbums', {
			#	'contributorAlbums.role' => { 'in' => $roles }
			#});
	#	}
	#}

	# The current level will always be a ->browse call, so just reuse the resultset.
	if ($level eq 'album') {

		$counts{'album'}       = $rs;
		$counts{'contributor'} = $rs->search_related('contributorAlbums')->search_related('contributor');
		$counts{'track'}       = $rs->search_related('tracks');

	} elsif ($level eq 'contributor' && $previousLevel && $previousLevel eq 'genre') {

		$counts{'album'}       = $rs->search_related('contributorAlbums')->search_related('album');
		$counts{'contributor'} = $rs;
		$counts{'track'}       = $rs->search_related('contributorTracks')->search_related('track');

	} elsif ($level eq 'track') {

		$counts{'album'}       = $rs->search_related('album');
		$counts{'contributor'} = $rs->search_related('contributorTracks')->search_related('contributor');
		$counts{'track'}       = $rs;

	} else {

		$counts{'album'}       = Slim::Schema->resultset('Album')->browse;
		$counts{'track'}       = Slim::Schema->resultset('Track')->browse;
		$counts{'contributor'} = Slim::Schema->resultset('Contributor')->browse;
	}

	$params->{'song_count'}   = $class->_lcPlural($counts{'track'}->distinct->count, 'SONG', 'SONGS');
	$params->{'album_count'}  = $class->_lcPlural($counts{'album'}->distinct->count, 'ALBUM', 'ALBUMS');
	$params->{'artist_count'} = $class->_lcPlural($counts{'contributor'}->distinct->count, 'ARTIST', 'ARTISTS');

	logger('database.sql')->info(sprintf("Found %s, %s & %s", 
		$params->{'song_count'}, $params->{'album_count'}, $params->{'artist_count'}
	));
}

sub addPlayerList {
	my ($class,$client, $params) = @_;

	$params->{'playercount'} = Slim::Player::Client::clientCount();
	
	my @players = Slim::Player::Client::clients();

	if (scalar(@players) > 1) {

		my %clientlist = ();

		for my $eachclient (@players) {

			$clientlist{$eachclient->id()} =  $eachclient->name();

			if (Slim::Player::Sync::isSynced($eachclient)) {
				$clientlist{$eachclient->id()} .= " (".string('SYNCHRONIZED_WITH')." ".
					Slim::Player::Sync::syncwith($eachclient).")";
			}	
		}

		$params->{'player_chooser_list'} = $class->options($client->id(), \%clientlist, $params->{'skinOverride'});
	}
}

sub addSongInfo {
	my ($class, $client, $params, $getCurrentTitle) = @_;

	# 
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

		$track = Slim::Schema->rs('Track')->objectForUrl({
			'url'      => $url,
			'create'   => 1,
			'readTags' => 1
		});

	} elsif ($id) {

		$track = Slim::Schema->find('Track', $id);
		$url   = $track->url() if $track;
	}

	$url   = $track->url() if $track;

	if (blessed($track) && $track->can('filesize')) {

		# let the template access the object directly.
		$params->{'itemobj'}    = $track unless $params->{'itemobj'};

		$params->{'filelength'} = Slim::Utils::Misc::delimitThousands($track->filesize);
		$params->{'bitrate'}    = $track->prettyBitRate;

		if ($getCurrentTitle) {
			$params->{'songtitle'} = Slim::Music::Info::getCurrentTitle(undef, $track->url);
		} else {
			$params->{'songtitle'} = Slim::Music::Info::standardTitle(undef, $track);
		}

		# make urls in comments into links
		for my $comment ($track->comment) {

			next unless defined $comment && $comment !~ /^\s*$/;

			if (!($comment =~ s!\b(http://[\-~A-Za-z0-9_/\.]+)!<a href=\"$1\" target=\"_blank\">$1</a>!igo)) {

				# handle emusic-type urls which don't have http://
				$comment =~ s!\b(www\.[\-~A-Za-z0-9_/\.]+)!<a href=\"http://$1\" target=\"_blank\">$1</a>!igo;
			}

			$params->{'comment'} .= $comment;
		}
	
		# handle artwork bits
		if ($track->coverArt) {
			$params->{'coverThumb'} = $track->id;
		}

		if (Slim::Music::Info::isRemoteURL($url)) {

			$params->{'download'} = $url;

		} else {

			$params->{'download'} = sprintf('%smusic/%d/download', $params->{'webroot'}, $track->id);
		}
	}
}

# TODO: find where this is used?
sub anchor {
	my ($class, $item, $suppressArticles) = @_;
	
	if ($suppressArticles) {
		$item = Slim::Utils::Text::ignoreCaseArticles($item) || return '';
	}

	return Slim::Utils::Text::matchCase(substr($item, 0, 1));
}

sub options {
	my ($class, $selected, $option, $skinOverride) = @_;

	# pass in the selected value and a hash of value => text pairs to get the option list filled
	# with the correct option selected.

	my $optionlist = '';

	for my $curroption (sort { $option->{$a} cmp $option->{$b} } keys %{$option}) {

		$optionlist .= ${Slim::Web::HTTP::filltemplatefile("select_option.html", {
			'selected'     => ($curroption eq $selected),
			'key'          => $curroption,
			'value'        => $option->{$curroption},
			'skinOverride' => $skinOverride,
		})};
	}

	return $optionlist;
}

# Build a simple header 
sub simpleHeader {
	my ($class, $args) = @_;
	
	my $itemCount    = $args->{'itemCount'};
	my $startRef     = $args->{'startRef'};
	my $headerRef    = $args->{'headerRef'};
	my $skinOverride = $args->{'skinOverride'};
	my $count		 = $args->{'perPage'} || $prefs->get('itemsPerPage');
	my $offset		 = $args->{'offset'} || 0;

	my $start = (defined($$startRef) && $$startRef ne '') ? $$startRef : 0;

	if ($start >= $itemCount) {
		$start = $itemCount - $count;
	}

	$$startRef = $start;

	my $end    = $start + $count - 1 - $offset;

	if ($end >= $itemCount) {
		$end = $itemCount - 1;
	}

	# Don't bother with a pagebar on a non-pagable item.
	if ($itemCount < $count) {
		return ($start, $end);
	}

	$$headerRef = ${Slim::Web::HTTP::filltemplatefile("pagebarheader.html", {
		"start"        => $start,
		"end"          => $end,
		"itemcount"    => $itemCount - 1,
		'skinOverride' => $skinOverride
	})};

	return ($start, $end);
}

# Return a hashref with paging information, all list indexes are zero based

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
	
	my $results      = $args->{'results'};
	my $otherparams  = $args->{'otherParams'};
	my $start        = $args->{'start'};
	my $itemsPerPage = $args->{'perPage'} || $prefs->get('itemsPerPage');

	my %pageinfo  = ();
	my %alphamap  = ();
	my $itemCount = 0;
	my $end;

	# Use the ResultSet from pageBarResults to build our offset list.
	if ($args->{'addAlpha'}) {

		my $first = $results->first;

		$alphamap{Slim::Utils::Unicode::utf8decode($first->get_column('letter'), 'utf-8')} = 0;

		$itemCount += $first->get_column('count');

		while (my $row = $results->next) {

			my $count  = $row->get_column('count');
			my $letter = $row->get_column('letter');

			# Set offset for subsequent letter rows to current # $itemCount
			# (*before* we add number of items for this letter to $itemCount!)
			$alphamap{Slim::Utils::Unicode::utf8decode($letter, 'utf-8')} = $itemCount;

			$itemCount += $count;
		}

	} else {

		if ($args->{'itemCount'}) {

			$itemCount = $args->{'itemCount'}

		} elsif ($results) {

			$itemCount = $results->count;

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

	if ($args->{'addAlpha'} && $itemCount) {

		my @letterstarts = sort { $a <=> $b } values %alphamap;
		my @pagestarts   = $letterstarts[0];

		# some cases of alphamap shift the start index from 0, trap this.
		$start = $letterstarts[0] unless $args->{'start'} ;

		my $newend = $end;

		for my $nextend (@letterstarts) {

			if ($nextend > $end && $newend == $end) {
				$newend = $nextend - 1;
			}

			if ($pagestarts[0] + $itemsPerPage < $nextend) {

				# build pagestarts in descending order
				unshift @pagestarts, $nextend;
			}
		}

		if ($newend == $end && $itemCount > $end) {
			$newend = $itemCount -1;
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
	}

	# set the start index, accounding for alpha cases
	$pageinfo{'startitem'} = $start || 0;

	return \%pageinfo;
}

## The following are smaller web page handlers, and are not class methods.
##
# Call into the memory usage class - this will return live data about memory
# usage, opcodes, and more. Note that loading this takes up memory itself!
sub memory_usage {
	my ($client, $params) = @_;

	my $item    = $params->{'item'};
	my $type    = $params->{'type'};
	my $command = $params->{'command'};

	unless ($item && $command) {

		return Slim::Utils::MemoryUsage->status_memory_usage();
	}

	if (defined $item && defined $command && Slim::Utils::MemoryUsage->can($command)) {

		return Slim::Utils::MemoryUsage->$command($item, $type);
	}
}

sub songInfo {
	my ($client, $params) = @_;

	Slim::Web::Pages->addSongInfo($client, $params, 0);

	return Slim::Web::HTTP::filltemplatefile("songinfo.html", $params);
}

sub firmware {
	my ($client, $params) = @_;

	return Slim::Web::HTTP::filltemplatefile("firmware.html", $params);
}

# This is here just to support SDK4.x (version <=10) clients
# so it always sends an upgrade to version 10 using the old upgrade method.
sub update_firmware {
	my ($client, $params) = @_;

	$params->{'warning'} = Slim::Player::Squeezebox::upgradeFirmware($params->{'ipaddress'}, 10) 
		|| string('UPGRADE_COMPLETE_DETAILS');
	
	return Slim::Web::HTTP::filltemplatefile("update_firmware.html", $params);
}

sub tuneIn {
	my ($client, $params) = @_;
	return Slim::Web::HTTP::filltemplatefile('tunein.html', $params);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
