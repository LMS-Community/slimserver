# Podcast Browser v0.0
# Copyright (c) 2005 Slim Devices, Inc. (www.slimdevices.com)

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

package Plugins::Podcast::Browse;
use strict;

# When to expire feeds from cache, in seconds.
our $default_cache_expiration = 60 * 60;

use Slim::Utils::Misc;
use Slim::Networking::SimpleAsyncHTTP;
use XML::Simple;
use Slim::Buttons::Common;
use Slim::Control::Command;
use Plugins::Podcast::Cache;
use Plugins::Podcast::Parse;

our %browseCache = (); # remember where each client is browsing
our $feedCache = Plugins::Podcast::Cache->new();

sub initPlugin {
	Slim::Buttons::Common::addMode('PLUGIN.Browse', getFunctions(),
								   \&setMode);
}

sub getFunctions {
	return {};
}

sub setMode {
	my $client = shift;
	my $method = shift;

	$::d_plugins && msg("Browser: setMode $method\n");
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
		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
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
	Slim::Buttons::Block::block($client,
								$client->string('PODCAST_LOADING'),
								$client->param('title') || $url);

	# if not found in cache, get via HTTP
	getFeedViaHTTP($client, $url, \&gotFeed, \&gotError);
}

sub gotFeed {
	my $client = shift;
	my $url = shift;
	my $feed = shift;

	# unblock client
	Slim::Buttons::Block::unblock($client);

	# restore client to where they were last browsing this feed.
	my $initialValue;
	if ($browseCache{$client->id()}) {
		$initialValue = $browseCache{$client->id()}->{$url};
	}

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
				Slim::Control::Command::execute( $client,
												 [ 'playlist', 'play',
												   $client->param('url'),
												   $client->param('feed')->{'title'},
											   ] );
			},
			onAdd => sub {
				my $client = shift;
				# play this feed as a playlist
				Slim::Control::Command::execute( $client,
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
		url => $url,
		feed => $feed,
		initialValue => $initialValue,
		header => $feed->{'title'} . ' {count}',
		# TODO: we show only items here, we skip the description of the entire channel
		listRef => $feed->{'items'},
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
		onChange => sub {
			my $client = shift;
			my $item = shift;

			# remember where client was browsing
			if (!defined($browseCache{$client->id()})) {
				$browseCache{$client->id()} = {};
			}
			$browseCache{$client->id}->{$client->param('url')} = $item->{'value'};
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
		#TODO: overlay

	);
	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub hasAudio {
	my $item = shift;
   	if ($item->{'enclosure'} && 
		($item->{'enclosure'}->{'type'} =~ /audio/)) {
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
	Slim::Buttons::Block::unblock($client);

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


sub displayItemDescription {
	my $client = shift;
	my $item = shift;

	# verbose debug
	#use Data::Dumper;
	#print Dumper($item);

	# use remotetrackinfo mode to display item in detail

	# break description into lines
	my @lines;
	my $curline = '';
	my $description = $item->{'description'};
	while ($description =~ /(\S+)/g) {
        my $newline = $curline . ' ' . $1;
        if ($client->measureText($newline, 2) > $client->displayWidth) {
            push @lines, trim($curline);
            $curline = $1;
        }
        else {
            $curline = $newline;
        }
    }
    if ($curline) {
        push @lines, trim($curline);
    }

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
			title =>$item->{'title'},
			url => $item->{'enclosure'}->{'url'},
			details => \@lines,
			onRight => sub {
				my $client = shift;
				my $item = $client->param('item');
				displayItemLink($client, $item);
			},
			hideTitle => 1,
			hideURL => 1,
		);
		Slim::Buttons::Common::pushMode($client,
										'remotetrackinfo',
										\%params);
	} else {
		# its not audio, use INPUT.Choice to display...

		my %params = (
			item => $item,
			header => $item->{'title'} . ' {count}',
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

		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
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
	my @lines;
	my $curline = '';
	my $description = $feed->{'description'};
	while ($description =~ /(\S+)/g) {
        my $newline = $curline . ' ' . $1;
        if ($client->measureText($newline, 2) > $client->displayWidth) {
            push @lines, trim($curline);
            $curline = $1;
        }
        else {
            $curline = $newline;
        }
    }
    if ($curline) {
        push @lines, trim($curline);
    }

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
	$feed->{'lastBuildDate'} && push @lines, '{PODCAST_DATE}: ' . $feed->{'lastBuildDate'};
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
	Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.Browse', \%params);
}

sub playItem {
	my $client = shift;
	my $item = shift;
	my $action = shift || 'play';

	# verbose debug
	#msg("Podcast playing item\n");
	#use Data::Dumper;
	#print Dumper($item);

	if ($item->{'enclosure'} && 
		($item->{'enclosure'}->{'type'} =~ /audio/)) {
		Slim::Control::Command::execute( $client,
										 [ 'playlist', $action,
										   $item->{'enclosure'}->{'url'},
										   $item->{'title'},
									   ] );
	} else {
		$client->showBriefly($item->{'title'},
							 $client->string("PODCAST_NOTHING_TO_PLAY"));
	}

}


sub getFeedViaHTTP {
	my $client = shift;
	my $url = shift;
	my $cb = shift;
	my $ecb = shift;

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotViaHTTP,
													  \&gotErrorViaHTTP,
													  {client => $client,
													   cb => $cb,
													   ecb => $ecb});
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

	# async http request succeeded.  Parse XML
	# forcearray to treat items as array,
	# keyattr => [] prevents id attrs from overriding
	my $xml = eval { XMLin($http->content(), 
						   forcearray => ["item"],
						   keyattr => []) };

	if ($@) {
		$::d_plugins && msg("Podcast: failed to parse feed because:\n$@\n");
		# call ecb
		gotError($params->{'client'}, $http->url(), $@);
		return;
	}

	# verbose debug
	#use Data::Dumper;
	#print Dumper($xml);

	# convert XML into data structure
	my $feed = feedFromXML($xml);
	if (!$feed) {
		# call ecb
		gotError($params->{'client'}, $http->url(), '{PARSE_ERROR}');
		return;
	}

	# cache feed to save time and effort next time we need it.
	$feedCache->put($http->url(),
					$feed,
					Time::HiRes::time() + $default_cache_expiration);

	# call cb
	gotFeed($params->{'client'}, $http->url(), $feed);
}

# takes XML podcast
# returns 'feed': a data structure summarizing the xml.
sub feedFromXML {
	my $xml = shift;

	my %feed;
	$feed{'items'} = ();

	$feed{'title'} = unescapeAndTrim($xml->{channel}->{title});
	$feed{'description'} = unescapeAndTrim($xml->{channel}->{description});
	$feed{'lastBuildDate'} = unescapeAndTrim($xml->{channel}->{lastBuildDate});
	$feed{'managingEditor'} = unescapeAndTrim($xml->{channel}->{managingEditor});
	$feed{'xmlns:slim'} = unescapeAndTrim($xml->{'xmlsns:slim'});
	# anything else worth grabbing?

	# some feeds (slashdot) have items at same level as channel
	my $items;
	if ($xml->{item}) {
		$items = $xml->{item};
	} else {
		$items = $xml->{channel}->{item};
	}

	my $count = 1;
	for my $itemXML (@$items) {
		my %item;
		$item{'description'} = unescapeAndTrim($itemXML->{description});
		$item{'title'} = unescapeAndTrim($itemXML->{title});
		$item{'link'} = unescapeAndTrim($itemXML->{link});
		$item{'slim:link'} = unescapeAndTrim($itemXML->{'slim:link'});
		if ($itemXML->{enclosure}) {
			my %enclosure;
			$enclosure{'url'} = trim($itemXML->{enclosure}->{url});
			$enclosure{'type'} = trim($itemXML->{enclosure}->{type});
			$enclosure{'length'} = trim($itemXML->{enclosure}->{length});
			$item{'enclosure'} = \%enclosure;
		}
		# this is a convencience for using INPUT.Choice later.
		# it expects each item in it list to have some 'value'
		$item{'value'} = $count++;
		push @{$feed{'items'}}, \%item;
	}

	return \%feed;
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
