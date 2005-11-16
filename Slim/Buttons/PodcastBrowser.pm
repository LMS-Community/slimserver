# Podcast Browser v0.0
# Copyright (c) 2005 Slim Devices, Inc. (www.slimdevices.com)

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This file create the 'podcastbrowser' mode.  The mode allows users
# to scroll through podcast entries and play audio enclosures.  The
# name is a misnomer, really, as this mode also browses RSS news
# feeds, and recently added, some OPML outlines.  (someone could
# rename this file and mode if they have a better name idea).

package Slim::Buttons::PodcastBrowser;

use strict;
use XML::Simple;

use Slim::Buttons::Common;
use Slim::Control::Command;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Cache;
use Slim::Utils::Misc;

# When to expire feeds from cache, in seconds.
our $default_cache_expiration = 60 * 60;

our $feedCache = Slim::Utils::Cache->new();

sub init {
	Slim::Buttons::Common::addMode('podcastbrowser', getFunctions(), \&setMode);
}

sub getFunctions {
	return {};
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $url = $client->param('url');

	# if no url, error
	if (!$url) {
		my @lines = (
			# TODO: l10n
			"Podcast Browse Mode requires url param",
		);

		#TODO: display the error on the client
		my %params = (
			header => "{PODCAST_ERROR} {count}",
			listRef => \@lines,
		);

		Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);

	} else {

		getFeedAsync($client, $url);
		# we're done.  gotFeed callback will finish setting up mode.
	}
}

sub getFeedAsync {
	my $client = shift;
	my $url = shift;

	# try to get from cache
	my $feed = $feedCache->get($url);

	if ($feed) {
		return gotFeed($client, $url, $feed);
	}

	# TODO: if url is local file, read it

	# URL is remote, load it asynchronously...

	# give user feedback while loading
	$client->block(
		$client->string('PODCAST_LOADING'),
		$client->param('title') || $url,
	);

	# if not found in cache, get via HTTP
	getFeedViaHTTP($client, $url, \&gotFeed, \&gotError);
}

sub gotFeed {
	my ($client, $url, $feed) = @_;

	# must unblock now, before pushMode is called by getRSS or gotOPML
	$client->unblock;

	# "feed" was originally an RSS feed.  Now it could be either RSS or an OPML outline.
	if ($feed->{'type'} eq 'rss') {

		gotRSS($client, $url, $feed);

	} elsif ($feed->{'type'} eq 'opml') {

		gotOPML($client, $url, $feed);

	} else {

		$client->update();
	}
}

sub gotRSS {
	my ($client, $url, $feed) = @_;

	# Include an item to access feed info
	if (($feed->{'items'}->[0]->{'value'} ne 'description') &&
		# skip this if xmlns:slim is used, and no description found
		!($feed->{'xmlns:slim'} && !$feed->{'description'})) {

		my %desc = (
			name => '{PODCAST_FEED_DESCRIPTION}',
			value => 'description',
			onRight => sub {
				my $client = shift;
				my $item = shift;
				displayFeedDescription($client, $client->param('feed'));
			},

			# play all enclosures...
			onPlay => sub {
				my $client = shift;

				# play this feed as a playlist
				$client->execute(
					[ 'playlist', 'play',
					$client->param('url'),
					$client->param('feed')->{'title'},
				] );
			},

			onAdd => sub {
				my $client = shift;

				# addthis feed as a playlist
				$client->execute(
					[ 'playlist', 'add',
					$client->param('url'),
					$client->param('feed')->{'title'},
				] );
			},

			overlayRef => [ undef, Slim::Display::Display::symbol('rightarrow') ],
		);

		unshift @{$feed->{'items'}}, \%desc; # prepend
	}

	# use INPUT.Choice mode to display the feed.
	my %params = (
		url      => $url,
		feed     => $feed,
		# unique modeName allows INPUT.Choice to remember where user was browsing
		modeName => "PodcastBrowser:$url",
		header   => $feed->{'title'} . ' {count}',

		# TODO: we show only items here, we skip the description of the entire channel
		listRef  => $feed->{'items'},

		name => sub {
			my $client = shift;
			my $item = shift;
			return $item->{'title'};
		},

		onRight => sub {
			my $client = shift;
			my $item = shift;
			if (hasDescription($item)) {
				displayItemDescription($client, $item);
			} else {
				displayItemLink($client, $item);
			}
		},

		onPlay => sub {
			my $client = shift;
			my $item = shift;
			playItem($client, $item);
		},

		onAdd => sub {
			my $client = shift;
			my $item = shift;
			playItem($client, $item, 'add');
		},

		overlayRef => sub {
			my $client = shift;
			my $item = shift;

			my $overlay;

			if (hasAudio($item)) {
				$overlay .= Slim::Display::Display::symbol('notesymbol');
			}

			if (hasDescription($item) || hasLink($item)) {
				$overlay .= Slim::Display::Display::symbol('rightarrow');
			}

			return [ undef, $overlay ];
		},

	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
}

# use INPUT.Choice to display an OPML list of links. OPML support added
# because podcast alley uses OPML to list its top 10, and newest
# podcasts.  Currently this has been tested only with those OPML
# examples, it may or may not work perfectly with others.
sub gotOPML {
	my ($client, $url, $feed) = @_;

	my %params = (
		url      => $url,
		feed     => $feed,
		# unique modeName allows INPUT.Choice to remember where user was browsing
		modeName => "PodcastBrowser:$url",
		header   => $feed->{'title'} . ' {count}',
		listRef  => $feed->{'items'},

		onRight  => sub {
			my $client = shift;
			my $item = shift;

			if ($item->{'url'} && !scalar @{$item->{'items'}}) {

				# follow a link
				my %params = (
					url   => $item->{'url'},
					title => $item->{'name'},
				);

				Slim::Buttons::Common::pushMode($client, 'podcastbrowser', \%params);

			} elsif ($item->{'items'}) {

				# recurse into OPML item
				browseOPML($client, $client->param('url'), $item);

			} else {

				$client->bumpRight();
			}
		},

		overlayRef => [undef, Slim::Display::Display::symbol('rightarrow')],
	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
}

# recusively browse OPML outline
sub browseOPML {
	my ($client, $url, $item) = @_;

	my %params = (
		url      => $url,
		item     => $item,
		# unique modeName allows INPUT.Choice to remember where user was browsing
		modeName => "PodcastBrowser:$url:" . $item->{'name'},
		header   => $item->{'name'} . ' {count}',
		listRef  => $item->{'items'},

		onRight  => sub {
			my $client = shift;
			my $item   = shift;

			if ($item->{'type'} && $item->{'type'} =~ /^(?:audio|playlist)$/) {

				playItem($client, $item);

			} elsif ($item->{'value'} && !scalar @{$item->{'items'}}) {

				# follow a link
				my %params = (
					url   => $item->{'value'},
					title => $item->{'name'},
				);

				Slim::Buttons::Common::pushMode($client, 'podcastbrowser', \%params);

			} elsif ($item->{'items'}) {

				# recurse into OPML item
				browseOPML($client, $client->param('url'), $item);

			} else {

				$client->bumpRight();
			}
		},

		onPlay  => sub {
			my $client = shift;
			my $item   = shift;

			if ($item->{'type'} && $item->{'type'} =~ /^(?:audio|playlist)$/) {

				playItem($client, $item);

			} else {

				$client->bumpRight();
			}
		},

		overlayRef => [undef, Slim::Display::Display::symbol('rightarrow')],
	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
}

sub hasAudio {
	my $item = shift;

   	if ($item->{'enclosure'} && ($item->{'enclosure'}->{'type'} =~ /audio/)) {

		return $item->{'enclosure'}->{'url'};

	} else {

		return undef;
	}
}

sub hasLink {
	my $item = shift;

	# for now, only follow link in "slim" namespace
	return $item->{'slim:link'};
}

sub hasDescription {
	my $item = shift;

	my $description = $item->{'description'};

	if ($description and !ref($description)) {

		return $description;

	} else {

		return undef;
	}
}

sub gotError {
	my $client = shift;
	my $url = shift;
	my $err = shift;

	$::d_plugins && msg("Podcast: error retrieving <$url>:\n");
	$::d_plugins && msg($err);

	# unblock client
	$client->unblock;

	my @lines = (
		"{PODCAST_GET_FAILED} <$url>",
		$err,
	);

	#TODO: display the error on the client
	my %params = (
		header => "{PODCAST_ERROR} {count}",
		listRef => \@lines,
	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
}

sub _breakItemIntoLines {
	my ($client, $item) = @_;

	my @lines   = ();
	my $curline = '';
	my $description = $item->{'description'};

	while ($description =~ /(\S+)/g) {

		my $newline = $curline . ' ' . $1;

		if ($client->measureText($newline, 2) > $client->displayWidth) {
			push @lines, trim($curline);
			$curline = $1;
		} else {
			$curline = $newline;
		}
	}

	if ($curline) {
		push @lines, trim($curline);
	}

	return ($curline, @lines);
}

sub displayItemDescription {
	my $client = shift;
	my $item = shift;

	# verbose debug
	#use Data::Dumper;
	#print Dumper($item);

	# use remotetrackinfo mode to display item in detail

	# break description into lines
	my ($curline, @lines) = _breakItemIntoLines($client, $item);

	if (my $link = hasLink($item)) {

		push @lines, {
			name => '{PODCAST_LINK}: ' . $link,
			value => $link,
			overlayRef => [ undef, Slim::Display::Display::symbol('rightarrow') ],
		}
	}

	if (hasAudio($item)) {

		push @lines, {
			name => '{PODCAST_ENCLOSURE}: ' . $item->{'enclosure'}->{'url'},
			value => $item->{'enclosure'}->{'url'},
			overlayRef => [ undef, Slim::Display::Display::symbol('notesymbol') ],
		};

		# its a remote audio source, use remotetrackinfo
		my %params = (
			title   =>$item->{'title'},
			url     => $item->{'enclosure'}->{'url'},
			details => \@lines,
			onRight => sub {
				my $client = shift;
				my $item = $client->param('item');
				displayItemLink($client, $item);
			},
			hideTitle => 1,
			hideURL => 1,
		);

		Slim::Buttons::Common::pushModeLeft($client, 'remotetrackinfo', \%params);

	} else {
		# its not audio, use INPUT.Choice to display...

		my %params = (
			item    => $item,
			header  => $item->{'title'} . ' {count}',
			listRef => \@lines,

			onRight => sub {
				my $client = shift;
				my $item = $client->param('item');
				displayItemLink($client, $item);
			},

			onPlay => sub {
				my $client = shift;
				my $item = $client->param('item');
				playItem($client, $item);
			},

			onAdd => sub {
				my $client = shift;
				my $item = $client->param('item');
				playItem($client, $item, 'add');
			},
		);

		Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
	}
}

sub displayFeedDescription {
	my $client = shift;
	my $feed = shift;

	# verbose debug
	#use Data::Dumper;
	#print Dumper($feed);

	# use remotetrackinfo mode to display item in detail

	# break description into lines
	my ($curline, @lines) = _breakItemIntoLines($client, $feed);

	# how many enclosures?
	my $count = 0;

	for my $i (@{$feed->{'items'}}) {
		if (hasAudio($i)) {
			$count++;
		}
	}

	if ($count) {
		push @lines, {
			name => '{PODCAST_AUDIO_ENCLOSURES}: ' . $count,
			value => $feed,
			overlayRef => [ undef, Slim::Display::Display::symbol('notesymbol') ],
		};
	}

	push @lines, '{PODCAST_URL}: ' . $client->param('url');

	$feed->{'lastBuildDate'}  && push @lines, '{PODCAST_DATE}: ' . $feed->{'lastBuildDate'};
	$feed->{'managingEditor'} && push @lines, '{PODCAST_EDITOR}: ' . $feed->{'managingEditor'};
	
	# TODO: more lines to show feed date, ttl, source, etc.
	# even a line to play all enclosures

	my %params = (
		url => $client->param('url'),
		title => $feed->{'title'},
		feed => $feed,
		header => $feed->{'title'} . ' {count}',
		details => \@lines,
		hideTitle => 1,
		hideURL => 1,

	);

	Slim::Buttons::Common::pushModeLeft($client, 'remotetrackinfo', \%params);
}

sub displayItemLink {
	my $client = shift;
	my $item = shift;

	my $url = hasLink($item);

	if (!$url) {
		$client->bumpRight();
		return;
	}

	# use PLUGIN.podcast mode to show the next url
	my %params = (
		url => $url,
		title => $item->{'title'},
	);

	Slim::Buttons::Common::pushModeLeft($client, 'podcastbrowser', \%params);
}

sub playItem {
	my $client = shift;
	my $item   = shift;
	my $action = shift || 'play';

	# verbose debug
	#msg("Podcast playing item\n");
	#use Data::Dumper;
	#print Dumper($item);

	if ($item->{'type'} && $item->{'type'} =~ /^(?:audio|playlist)$/) {

		$client->execute([ 'playlist', $action, $item->{'url'}, $item->{'name'} ]);

	} elsif ($item->{'enclosure'} && ($item->{'enclosure'}->{'type'} =~ /audio/ || 
		Slim::Music::Info::typeFromSuffix($item->{'enclosure'}->{'url'} ne 'unk')) ) {

		$client->execute( [ 'playlist', $action, $item->{'enclosure'}->{'url'}, $item->{'title'}, ] );

	} else {

		$client->showBriefly($item->{'title'}, $client->string("PODCAST_NOTHING_TO_PLAY"));
	}
}

sub getFeedViaHTTP {
	my $client = shift;
	my $url    = shift;
	my $cb     = shift;
	my $ecb    = shift;

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&gotViaHTTP, \&gotErrorViaHTTP, {

			client => $client,
			cb     => $cb,
			ecb    => $ecb
	});

	$::d_plugins && msg("Podcast: async request: $url\n");

	$http->get($url);
}

sub gotErrorViaHTTP {
	my $http = shift;
	my $params = $http->params();

	$::d_plugins && msg("Podcast: error getting " . $http->url() . "\n");
	$::d_plugins && msg("Podcast: " . $http->error() . "\n");

	# call ecb
	gotError($params->{'client'}, $http->url(), $http->error());
}

sub gotViaHTTP {
	my $http = shift;
	my $params = $http->params();

	$::d_plugins && msg("Podcast: got " . $http->url() . "\n");
	$::d_plugins && msg("Podcast: content type is " . $http->headers()->{'Content-Type'} . "\n");

	# verbose debug
	#$::d_plugins && msg("Podcast: content:\n " . $http->content() . "\n\n");
	
	my $content = $http->content();
	
	# deal with windows encoding stupidity (see Bug #1392)
	$content =~ s/encoding="windows-1252"/encoding="iso-8859-1"/i;

	# async http request succeeded.  Parse XML
	# forcearray to treat items as array,
	# keyattr => [] prevents id attrs from overriding
	my $xml = eval { XMLin($content, forcearray => ["item", "outline"], keyattr => []) };

	if ($@) {
		$::d_plugins && msg("Podcast: failed to parse feed because:\n$@\n");
		$::d_plugins && msg("Podcast: here's the bad feed:\n" . $http->content() . "\n\n");
		# call ecb
		gotError($params->{'client'}, $http->url(), $@);
		return;
	}

	# verbose debug
	#use Data::Dumper;
	#print Dumper($xml);

	# convert XML into data structure
	my $feed;
	if ($xml && $xml->{body} && $xml->{body}->{outline}) {
		# its OPML outline
		$feed = parseOPML($xml);
	} else {
		# its RSS or podcast
		$feed = parseRSS($xml);
	}

	if (!$feed) {
		# call ecb
		gotError($params->{'client'}, $http->url(), '{PARSE_ERROR}');
		return;
	}

	# cache feed to save time and effort next time we need it.
	$feedCache->put($http->url(), $feed, Time::HiRes::time() + $default_cache_expiration);

	# call cb
	gotFeed($params->{'client'}, $http->url(), $feed);
}

# takes XML podcast
# returns 'feed': a data structure summarizing the xml.
sub parseRSS {
	my $xml = shift;

	my %feed = (
		'type'           => 'rss',
		'items'          => (),
		'title'          => unescapeAndTrim($xml->{'channel'}->{'title'}),
		'description'    => unescapeAndTrim($xml->{'channel'}->{'description'}),
		'lastBuildDate'  => unescapeAndTrim($xml->{'channel'}->{'lastBuildDate'}),
		'managingEditor' => unescapeAndTrim($xml->{'channel'}->{'managingEditor'}),
		'xmlns:slim'     => unescapeAndTrim($xml->{'xmlsns:slim'}),
	);

	# some feeds (slashdot) have items at same level as channel
	my $items;

	if ($xml->{'item'}) {
		$items = $xml->{'item'};
	} else {
		$items = $xml->{'channel'}->{'item'};
	}

	my $count = 1;

	for my $itemXML (@$items) {

		my %item = (
			'description' => unescapeAndTrim($itemXML->{'description'}),
			'title'       => unescapeAndTrim($itemXML->{'title'}),
			'link'        => unescapeAndTrim($itemXML->{'link'}),
			'slim:link'   => unescapeAndTrim($itemXML->{'slim:link'}),
		);

		my $enclosure = $itemXML->{'enclosure'};

		if (ref $enclosure eq 'ARRAY') {
			$enclosure = $enclosure->[0];
		}

		if ($enclosure) {
			$item{'enclosure'}->{'url'}    = trim($enclosure->{'url'});
			$item{'enclosure'}->{'type'}   = trim($enclosure->{'type'});
			$item{'enclosure'}->{'length'} = trim($enclosure->{'length'});
		}

		# this is a convencience for using INPUT.Choice later.
		# it expects each item in it list to have some 'value'
		$item{'value'} = $count++;

		push @{$feed{'items'}}, \%item;
	}

	return \%feed;
}

# represent OPML in a simple data structure compatable with INPUT.Choice mode.
sub parseOPML {
	my $xml = shift;

	return {
		'type'  => 'opml',
		'title' => unescapeAndTrim($xml->{'head'}->{'title'}),
		'items' => _parseOPMLOutline($xml->{'body'}->{'outline'}),
	};
}

# recursively parse an OPML outline entry
sub _parseOPMLOutline {
	my $outlines = shift;

	my @items = ();

	for my $itemXML (@$outlines) {

		my $url = $itemXML->{'url'} || $itemXML->{'URL'};

		# Some programs, such as OmniOutliner put garbage in the URL.
		if ($url) {
			$url =~ s/^.*?<(\w+:\/\/.+?)>.*$/$1/;
		}

		push @items, {

			# compatable with INPUT.Choice, which expects 'name' and 'value'
			'name'  => $itemXML->{'text'},
			'value' => $url || $itemXML->{'text'},
			'url'   => $url,
			'type'  => $itemXML->{'type'},
			'items' => _parseOPMLOutline($itemXML->{'outline'}),
		};
	}

	return \@items;
}

#### Some routines for munging strings
sub unescape {
	my $data = shift;

	return '' unless(defined($data));

	use utf8; # required for 5.6
	
	$data =~ s/&amp;/&/sg;
	$data =~ s/&lt;/</sg;
	$data =~ s/&gt;/>/sg;
	$data =~ s/&quot;/\"/sg;
	$data =~ s/&bull;/\*/sg;
	$data =~ s/&pound;/\xa3/sg;
	$data =~ s/&mdash;/-/sg;
	$data =~ s/&\#(\d+);/chr($1)/gse;

	return $data;
}

sub trim {
	my $data = shift;
	return '' unless(defined($data));
	use utf8; # important for regexps that follow

	$data =~ s/\s+/ /g; # condense multiple spaces
	$data =~ s/^\s//g; # remove leading space
	$data =~ s/\s$//g; # remove trailing spaces

	return $data;
}

# unescape and also remove unnecesary spaces
# also get rid of markup tags
sub unescapeAndTrim {
	my $data = shift;
	return '' unless(defined($data));
	use utf8; # important for regexps that follow
	my $olddata = $data;
	
	$data = unescape($data);

	$data = trim($data);
	
	# strip all markup tags
	$data =~ s/<[a-zA-Z\/][^>]*>//gi;

	# the following taken from Rss News plugin, but apparently
	# it results in an unnecessary decode, which actually causes problems
	# and things seem to work fine without it, so commenting it out.
	#if ($] >= 5.008) {
	#	utf8::decode($data);
	#}

	return $data;
}

1;
