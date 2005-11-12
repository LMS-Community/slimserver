package Slim::Web::Pages;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use POSIX ();
use Scalar::Util qw(blessed);

use Slim::DataStores::Base;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use Slim::Web::Pages::Search;
use Slim::Web::Pages::BrowseDB;
use Slim::Web::Pages::BrowseTree;
use Slim::Web::Pages::Home;
use Slim::Web::Pages::Status;
use Slim::Web::Pages::Playlist;

our %additionalLinks = ();

our %hierarchy = (
	'artist' => 'album,track',
	'album'  => 'track',
	'song '  => '',
);

sub init {

	Slim::Web::HTTP::addPageFunction(qr/^edit_playlist\.(?:htm|xml)/, \&Slim::Web::EditPlaylist::editplaylist);
	Slim::Web::HTTP::addPageFunction(qr/^firmware\.(?:html|xml)/,\&firmware);
	Slim::Web::HTTP::addPageFunction(qr/^hitlist\.(?:htm|xml)/,\&Slim::Web::History::hitlist);
	Slim::Web::HTTP::addPageFunction(qr/^songinfo\.(?:htm|xml)/,\&songInfo);
	Slim::Web::HTTP::addPageFunction(qr/^setup\.(?:htm|xml)/,\&Slim::Web::Setup::setup_HTTP);
	Slim::Web::HTTP::addPageFunction(qr/^tunein\.(?:htm|xml)/,\&tuneIn);
	Slim::Web::HTTP::addPageFunction(qr/^update_firmware\.(?:htm|xml)/,\&update_firmware);

	# pull in the memory usage module if requested.
	if ($::d_memory) {

		eval "use Slim::Utils::MemoryUsage";

		if ($@) {
			print "Couldn't load Slim::Utils::MemoryUsage - error: [$@]\n";
		} else {
			Slim::Web::HTTP::addPageFunction(qr/^memoryusage\.html.*/,\&memory_usage);
		}
	}

	Slim::Web::Pages::Home->init();
	Slim::Web::Pages::BrowseDB::init();
	Slim::Web::Pages::BrowseTree::init();
	Slim::Web::Pages::Search::init();
	Slim::Web::Pages::Status::init();
	Slim::Web::Pages::Playlist::init();
}

### DEPRECATED stub for third party plugins
sub addLinks {
	msg("Slim::Web::Pages::addLinks() has been deprecated in favor of 
	     Slim::Web::Pages->addPageLinks. Please update your calls!\n");
	Slim::Utils::Misc::bt();
	
	return Slim::Web::Pages->addPageLinks(@_);
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

	return if (ref($links) ne 'HASH');

	while (my ($title, $path) = each %$links) {
		if (defined($path)) {
			$additionalLinks{$category}->{$title} = $path . 
				($noquery ? '' : (($path =~ /\?/) ? '&' : '?'));
		} else {
			delete($additionalLinks{$category}->{$title});
		}
	}

	if (not keys %{$additionalLinks{$category}}) {
		delete($additionalLinks{$category});
	}
}

sub addLibraryStats {
	my ($class,$params, $genre, $artist, $album) = @_;
	
	if (Slim::Music::Import::stillScanning()) {
		$params->{'warn'} = 1;
		return;
	}

	my $ds   = Slim::Music::Info::getCurrentDataStore();
	my $find = {};

	$find->{'genre'}       = $genre  if $genre;
	$find->{'contributor'} = $artist if $artist && !$album;
	$find->{'album'}       = $album  if $album;

	$params->{'song_count'}   = $class->_lcPlural($ds->count('track', $find), 'SONG', 'SONGS');
	$params->{'album_count'}  = $class->_lcPlural($ds->count('album', $find), 'ALBUM', 'ALBUMS');

	# Right now hitlist.html is the only page that uses genre_count -
	# which can be expensive. Only generate it if we need to.
	if ($params->{'path'} =~ /hitlist/) {

		$params->{'genre_count'} = $class->_lcPlural($ds->count('genre', $find), 'GENRE', 'GENRES');
	}

	# Bug 1913 - don't put counts for contributor & tracks when an artist
	# is a composer on a different artist's tracks.
	if ($artist && $artist eq $ds->variousArtistsObject->id) {

		delete $find->{'contributor'};

		$find->{'album.compilation'} = 1;
	}

	$params->{'artist_count'} = $class->_lcPlural($ds->count('contributor', $find), 'ARTIST', 'ARTISTS');
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
	my $url = $params->{'itempath'};
	my $id  = $params->{'item'};

	# kinda pointless, but keeping with compatibility
	if (!defined $url && !defined $id) {
		return;
	}

	if (ref($url) && !$url->can('id')) {
		return;
	}

	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $track;

	if ($url) {

		$track = $ds->objectForUrl($url, 1, 1);

	} elsif ($id) {

		$track = $ds->objectForId('track', $id);
		$url   = $track->url() if $track;
	}

	if (blessed($track) && $track->can('filesize')) {

		# let the template access the object directly.
		$params->{'itemobj'}    = $track unless $params->{'itemobj'};

		$params->{'filelength'} = Slim::Utils::Misc::delimitThousands($track->filesize());
		$params->{'bitrate'}    = $track->bitrate();

		if ($getCurrentTitle) {
			$params->{'songtitle'} = Slim::Music::Info::getCurrentTitle(undef, $track);
		} else {
			$params->{'songtitle'} = Slim::Music::Info::standardTitle(undef, $track);
		}

		# make urls in comments into links
		for my $comment ($track->comment()) {

			next unless defined $comment && $comment !~ /^\s*$/;

			if (!($comment =~ s!\b(http://[\-~A-Za-z0-9_/\.]+)!<a href=\"$1\" target=\"_blank\">$1</a>!igo)) {

				# handle emusic-type urls which don't have http://
				$comment =~ s!\b(www\.[\-~A-Za-z0-9_/\.]+)!<a href=\"http://$1\" target=\"_blank\">$1</a>!igo;
			}

			$params->{'comment'} .= $comment;
		}
	
		# handle artwork bits
		if ($track->coverArt('thumb')) {
			$params->{'coverThumb'} = $track->id;
		}

		if (Slim::Music::Info::isRemoteURL($url)) {

			$params->{'download'} = $url;

		} else {

			$params->{'download'} = sprintf('%smusic/%d/download', $params->{'webroot'}, $track->id());
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
	my $count		 = $args->{'perPage'} || Slim::Utils::Prefs::get('itemsPerPage');
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

# Build a bar of links to multiple pages of items
sub pageBar {
	my ($class, $args) = @_;
	
	my $itemcount    = $args->{'itemCount'};
	my $path         = $args->{'path'};
	my $currentitem  = $args->{'currentItem'} || 0;
	my $otherparams  = $args->{'otherParams'};
	my $startref     = $args->{'startRef'}; #will be modified
	my $headerref    = $args->{'headerRef'}; #will be modified
	my $pagebarref   = $args->{'pageBarRef'}; #will be modified
	my $skinOverride = $args->{'skinOverride'};
	my $count        = $args->{'PerPage'} || Slim::Utils::Prefs::get('itemsPerPage');

	my $start = (defined($$startref) && $$startref ne '') ? $$startref : (int($currentitem/$count)*$count);

	if ($start >= $itemcount) {
		$start = $itemcount - $count;
	}

	$$startref = $start;

	my $end = $start+$count-1;

	if ($end >= $itemcount) {
		$end = $itemcount - 1;
	}

	# Don't bother with a pagebar on a non-pagable item.
	if ($itemcount < $count) {
		return ($start, $end);
	}

	if ($itemcount > $count) {

		$$headerref = ${Slim::Web::HTTP::filltemplatefile("pagebarheader.html", {
			"start"        => ($start+1),
			"end"          => ($end+1),
			"itemcount"    => $itemcount,
			'skinOverride' => $skinOverride
		})};

		my %pagebar = ();

		my $numpages  = POSIX::ceil($itemcount/$count);
		my $curpage   = int($start/$count);
		my $pagesperbar = 25; #make this a preference
		my $pagebarstart = (($curpage - int($pagesperbar/2)) < 0 || $numpages <= $pagesperbar) ? 0 : ($curpage - int($pagesperbar/2));
		my $pagebarend = ($pagebarstart + $pagesperbar) > $numpages ? $numpages : ($pagebarstart + $pagesperbar);

		$pagebar{'pagesstart'} = ($pagebarstart > 0);

		if ($pagebar{'pagesstart'}) {
			$pagebar{'pagesprev'} = ($curpage - $pagesperbar) * $count;
			if ($pagebar{'pagesprev'} < 0) { $pagebar{'pagesprev'} = 0; };
		}

		if ($pagebarend < $numpages) {
			$pagebar{'pagesend'} = ($numpages -1) * $count;
			$pagebar{'pagesnext'} = ($curpage + $pagesperbar) * $count;
			if ($pagebar{'pagesnext'} > $pagebar{'pagesend'}) { $pagebar{'pagesnext'} = $pagebar{'pagesend'}; }
		}

		$pagebar{'pageprev'} = $curpage > 0 ? (($curpage - 1) * $count) : undef;
		$pagebar{'pagenext'} = ($curpage < ($numpages - 1)) ? (($curpage + 1) * $count) : undef;
		$pagebar{'otherparams'} = defined($otherparams) ? $otherparams : '';
		$pagebar{'skinOverride'} = $skinOverride;
		$pagebar{'path'} = $path;

		for (my $j = $pagebarstart;$j < $pagebarend;$j++) {
			$pagebar{'pageslist'} .= ${Slim::Web::HTTP::filltemplatefile('pagebarlist.html'
							,{'currpage' => ($j == $curpage)
							,'itemnum0' => ($j * $count)
							,'itemnum1' => (($j * $count) + 1)
							,'pagenum' => ($j + 1)
							,'otherparams' => $otherparams
							,'skinOverride' => $skinOverride
							,'path' => $path})};
		}
		$$pagebarref = ${Slim::Web::HTTP::filltemplatefile("pagebar.html", \%pagebar)};
	}
	return ($start, $end);
}

sub alphaPageBar {
	my ($class, $args) = @_;
	
	my $itemsref     = $args->{'itemsRef'};
	my $path         = $args->{'path'};
	my $otherparams  = $args->{'otherParams'};
	my $startref     = $args->{'startRef'}; #will be modified
	my $pagebarref   = $args->{'pageBarRef'}; #will be modified
	my $skinOverride = $args->{'skinOverride'};
	my $maxcount     = $args->{'PerPage'} || Slim::Utils::Prefs::get('itemsPerPage');

	my $itemcount = scalar(@$itemsref);

	my $start = $$startref;

	if (!$start) { 
		$start = 0;
	}

	if ($start >= $itemcount) { 
		$start = $itemcount - $maxcount; 
	}

	$$startref = $start;

	my $end = $itemcount - 1;

	# Don't bother with a pagebar on a non-pagable item.
	if ($itemcount < $maxcount) {
		return ($start, $end);
	}

	if ($itemcount > ($maxcount / 2)) {

		my $lastLetter = '';
		my $lastLetterIndex = 0;
		my $pageslist = '';

		$end = -1;

		# This could be more efficient.
		for (my $j = 0; $j < $itemcount; $j++) {

			my $curLetter = substr($itemsref->[$j], 0, 1);
			$curLetter = '' if (!defined($curLetter));

			if ($lastLetter ne $curLetter) {

				if (($j - $lastLetterIndex) > $maxcount) {
					if ($end == -1 && $j > $start) {
						$end = $j - 1;
					}
					$lastLetterIndex = $j;
				}

				$pageslist .= ${Slim::Web::HTTP::filltemplatefile('alphapagebarlist.html', {
					'currpage'     => ($lastLetterIndex == $start),
					'itemnum0'     => $lastLetterIndex,
					'itemnum1'     => ($lastLetterIndex + 1),
					'pagenum'      => $curLetter,
					'fragment'     => ("#" . $curLetter),
					'otherparams'  => ($otherparams || ''),
					'skinOverride' => $skinOverride,
					'path'         => $path
				})};

				$lastLetter = $curLetter;
			}
		}

		if ($end == -1) {
			$end = $itemcount - 1;
		}

		my %pagebar_params = (
			'otherparams'  => ($otherparams || ''),
			'pageslist'    => $pageslist,
			'skinOverride' => $skinOverride,
		);

		$$pagebarref = ${Slim::Web::HTTP::filltemplatefile("pagebar.html", \%pagebar_params)};
	}
	
	return ($start, $end);
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
