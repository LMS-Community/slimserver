package Slim::Formats::XML;

# $Id$

# Copyright (c) 2006 Logitech

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class handles retrieval and parsing of remote XML feeds (OPML and RSS)

use strict;
use File::Slurp;
use HTML::Entities;
use Scalar::Util qw(weaken);
use XML::Simple;

use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Player::Protocols::HTTP;
use Slim::Utils::Cache;
use Slim::Utils::Misc;
use Slim::Utils::Log;

# How long to cache parsed XML data
our $XML_CACHE_TIME = 300;

my $log = logger('formats.xml');

# Get xml for a feed synchronously
# Only used to support the web interface
# when browsing, feeds are downloaded asynchronously, see Slim::Buttons::XMLBrowser
sub getFeedSync {
	my ($class, $url) = @_;

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => $url,
		'create' => 0,
	});

	if (defined $http) {

		my $content = $http->content;

		$http->close;

		return 0 unless defined $content;

		my $xml = eval { xmlToHash(\$content) };

		if ($@) {

			logError("Failed to parse XML feed: $@");
			return 0;
		}

		return $xml;
	}

	return 0;
}

sub getFeedAsync {
	my $class = shift;
	my ( $cb, $ecb, $params ) = @_;
	
	my $url = $params->{'url'};
	
	# Try to load a cached copy of the parsed XML
	my $cache = Slim::Utils::Cache->new();
	my $feed  = $cache->get( $url . '_parsedXML' );

	if ( $feed ) {

		$log->info("Got cached XML data for $url");

		return $cb->( $feed, $params );
	}
	
	if (Slim::Music::Info::isFileURL($url)) {

		my $path    = Slim::Utils::Misc::pathFromFileURL($url);

		# read_file from File::Slurp
		my $content = eval { read_file($path) };

		if ( $content ) {

			$feed = eval { parseXMLIntoFeed(\$content) };

		} else {

			return $ecb->( "Unable to open file '$path'", $params );
		}
	}

	if ($feed) {
		return $cb->( $feed, $params );
	}
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&gotViaHTTP, \&gotErrorViaHTTP, {

			'params'  => $params,
			'cb'      => $cb,
			'ecb'     => $ecb,
			'cache'   => 1,
			'expires' => $params->{'expires'}, 
	});

	$log->info("Async request: $url");
	
	# Bug 3165
	# Override user-agent and Icy-Metadata headers so we appear to be a web browser
	my $ua = Slim::Utils::Misc::userAgentString();
	$ua =~ s{iTunes/4.7.1}{Mozilla/5.0};

	my %headers = (
		'User-Agent'   => $ua,
		'Icy-Metadata' => '',
	);

	$http->get( $url, %headers );
}

sub gotViaHTTP {
	my $http = shift;
	my $params = $http->params();
	my $feed;

	$log->debug("Got ", $http->url);
	$log->debug("Content type is ", $http->headers()->content_type);

	# Try and turn the content we fetched into a parsed data structure.
	if (my $parser = $params->{'params'}->{'parser'}) {

		$log->info("Parsing with parser $parser");

		eval "use $parser";

		$log->warn("$@") if $@;

		$feed = eval { $parser->parse($http) };

		if ($feed->{'type'} && $feed->{'type'} eq 'redirect') {

			my $url = $feed->{'url'};

			$log->info("Redirected to $url");

			$params->{'params'}->{'url'} = $url;

			$http->get($url);

			return;
		}

	} else {

		$feed = eval { parseXMLIntoFeed($http->contentRef) };
	}

	if ($@) {
		# call ecb
		my $ecb = $params->{'ecb'};
		$ecb->( $@, $params->{'params'} );
		return;
	}

	if ( !ref $feed || ref $feed ne 'HASH' ) {
		# call ecb
		my $ecb = $params->{'ecb'};
		$ecb->( '{PARSE_ERROR}', $params->{'params'} );
		return;
	}
	
	# Cache the parsed XML
	if ( Slim::Utils::Misc::shouldCacheURL( $http->url ) ) {

		my $cache = Slim::Utils::Cache->new();

		$log->info("Caching parsed XML for $XML_CACHE_TIME seconds");

		$cache->set( $http->url() . '_parsedXML', $feed, $XML_CACHE_TIME );
	}
	else {

		$log->info(sprintf("Not caching parsed XML for %s, appears to be a local resource",
			$http->url,
		));
	}

	# call cb
	my $cb = $params->{'cb'};
	$cb->( $feed, $params->{'params'} );

	undef($http);
}

sub gotErrorViaHTTP {
	my $http = shift;
	my $params = $http->params();

	logError("getting ", join("\n", $http->url, $http->error));

	# call ecb
	my $ecb = $params->{'ecb'};
	$ecb->( $http->error, $params->{'params'} );
}

sub parseXMLIntoFeed {
	my $content = shift || return undef;

	my $xml = xmlToHash($content);

	# convert XML into data structure
	if ($xml && $xml->{'body'} && $xml->{'body'}->{'outline'}) {

		$log->debug("Parsing body as OPML");

		# its OPML outline
		return parseOPML($xml);
		
	} elsif ($xml && $xml->{'entry'}) {
		
		# It's Atom
		return parseAtom($xml);

	} elsif ($xml) {

		$log->debug("Parsing body as RSS");

		# its RSS or podcast
		return parseRSS($xml);
	}

	return;
}

# takes XML podcast
# returns 'feed': a data structure summarizing the xml.
sub parseRSS {
	my $xml = shift;

	my %feed = (
		'type'           => 'rss',
		'items'          => [],
		'title'          => unescapeAndTrim($xml->{'channel'}->{'title'}),
		'description'    => unescapeAndTrim($xml->{'channel'}->{'description'}),
		'lastBuildDate'  => unescapeAndTrim($xml->{'channel'}->{'lastBuildDate'}),
		'managingEditor' => unescapeAndTrim($xml->{'channel'}->{'managingEditor'}),
		'xmlns:slim'     => unescapeAndTrim($xml->{'xmlsns:slim'}),
	);
	
	# look for an image
	if ( ref $xml->{'channel'}->{'image'} ) {
		
		my $image = $xml->{'channel'}->{'image'};
		my $url   = $image->{'url'};
		
		# some Podcasts have the image URL in the link tag
		if ( !$url && $image->{'link'} && $image->{'link'} =~ /(jpg|gif|png)$/i ) {
			$url = $image->{'link'};
		}
		
		$feed{'image'} = $url;
	}
	elsif ( $xml->{'itunes:image'} ) {
		$feed{'image'} = $xml->{'itunes:image'}->{'href'};
	}

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
			'pubdate'     => unescapeAndTrim($itemXML->{'pubDate'}),
			# image is included in each item due to the way XMLBrowser works
			'image'       => $feed{'image'},
		);

		# Add iTunes-specific data if available
		# http://www.apple.com/itunes/podcasts/techspecs.html
		if ( $xml->{'xmlns:itunes'} ) {

			$item{'duration'} = unescapeAndTrim($itemXML->{'itunes:duration'});
			$item{'explicit'} = unescapeAndTrim($itemXML->{'itunes:explicit'});

			# don't duplicate data
			if ( $itemXML->{'itunes:subtitle'} && $itemXML->{'title'} && 
				$itemXML->{'itunes:subtitle'} ne $itemXML->{'title'} ) {
				$item{'subtitle'} = unescapeAndTrim($itemXML->{'itunes:subtitle'});
			}
			
			if ( $itemXML->{'itunes:summary'} && $itemXML->{'description'} &&
				$itemXML->{'itunes:summary'} ne $itemXML->{'description'} ) {
				$item{'summary'} = unescapeAndTrim($itemXML->{'itunes:summary'});
			}
		}

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

# Parse Atom feeds into the same format as RSS
sub parseAtom {
	my $xml = shift;
	
	my %feed = (
		'type'           => 'rss',
		'items'          => [],
		'title'          => unescapeAndTrim($xml->{'title'}),
		'description'    => unescapeAndTrim( $xml->{'subtitle'} || $xml->{'tagline'} ),
		'lastBuildDate'  => unescapeAndTrim( $xml->{'updated'} || $xml->{'modified'} ),
		'managingEditor' => unescapeAndTrim($xml->{'author'}),
		'xmlns:slim'     => unescapeAndTrim($xml->{'xmlsns:slim'}),
	);
	
	# look for an image
	if ( $xml->{'logo'} ) {
		$feed{'image'} = $xml->{'logo'};
	}
	
	my $count = 1;
	
	my $items = $xml->{'entry'} || [];

	for my $itemXML ( @{$items} ) {
		
		my %item = (
			'description' => unescapeAndTrim($itemXML->{'summary'}),
			'title'       => unescapeAndTrim($itemXML->{'title'}),
			'link'        => unescapeAndTrim($itemXML->{'link'}),
			'slim:link'   => unescapeAndTrim($itemXML->{'slim:link'}),
			'pubdate'     => unescapeAndTrim($itemXML->{'updated'}),
			# image is included in each item due to the way XMLBrowser works
			'image'       => $feed{'image'},
		);

		# this is a convencience for using INPUT.Choice later.
		# it expects each item in it list to have some 'value'
		$item{'value'} = $count++;

		push @{ $feed{'items'} }, \%item;
	}

	return \%feed;
}

# represent OPML in a simple data structure compatable with INPUT.Choice mode.
sub parseOPML {
	my $xml = shift;

	my $opml = {
		'type'  => 'opml',
		'title' => unescapeAndTrim($xml->{'head'}->{'title'}),
		'items' => _parseOPMLOutline($xml->{'body'}->{'outline'}),
	};

	$xml = undef;

	# Don't leak
	weaken(\$opml);

	return $opml;
}

# recursively parse an OPML outline entry
sub _parseOPMLOutline {
	my $outlines = shift;

	my @items = ();

	for my $itemXML (@$outlines) {

		my $url = $itemXML->{'url'} || $itemXML->{'URL'} || $itemXML->{'xmlUrl'};

		# Some programs, such as OmniOutliner put garbage in the URL.
		if ($url) {
			$url =~ s/^.*?<(\w+:\/\/.+?)>.*$/$1/;
		}
		
		# Pull in all attributes we find
		my %attrs;
		for my $attr ( keys %{$itemXML} ) {
		    next if $attr =~ /text|type|URL|xmlUrl/i;
		    $attrs{$attr} = $itemXML->{$attr};
	    }

		push @items, {

			# compatable with INPUT.Choice, which expects 'name' and 'value'
			'name'  => unescapeAndTrim( $itemXML->{'text'} ),
			'value' => $url || $itemXML->{'text'},
			'url'   => $url,
			'type'  => $itemXML->{'type'},
			'items' => _parseOPMLOutline($itemXML->{'outline'}),
			%attrs,
		};
	}

	return \@items;
}

sub openSearch {
	my $class = shift;
	my ( $cb, $ecb, $params ) = @_;

	# Fetch the OpenSearch description file
	my $url = $params->{'search'};

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&openSearchDescription,
		\&gotErrorViaHTTP,
		{
			'params' => $params,
			'cb'     => $cb,
			'ecb'    => $ecb,
			'cache'  => 1,
		},
	);

	$log->info("Async opensearch description request: $url");

	$http->get($url);
}

sub openSearchDescription {
	my $http = shift;
	my $params = $http->params;

	my $desc = eval { xmlToHash( $http->contentRef ) };

	if ($@) {
		# call ecb
		my $ecb = $params->{'ecb'};
		$ecb->( $@, $params->{'params'} );
		return;
	}

	if (!$desc) {
		# call ecb
		my $ecb = $params->{'ecb'};
		$ecb->( '{PARSE_ERROR}', $params->{'params'} );
		return;
	}
	
	# run the search query
	my $url = $desc->{'Url'}->{'template'};
	my $query = $params->{'params'}->{'query'};
	$url =~ s/{searchTerms}/$query/;
	
	my $asyncHTTP = Slim::Networking::SimpleAsyncHTTP->new(
		\&openSearchResult,
		\&gotErrorViaHTTP,
		$params,
	);

	$log->info("Async opensearch query: $url");

	$asyncHTTP->get($url);
}

sub openSearchResult {
	my $http = shift;
	my $params = $http->params;
	
	my $feed = eval { parseXMLIntoFeed($http->contentRef) };
	
	if ($@) {
		# call ecb
		my $ecb = $params->{'ecb'};
		$ecb->( $@, $params->{'params'} );
		return;
	}

	if (!$feed) {
		# call ecb
		my $ecb = $params->{'ecb'};
		$ecb->( '{PARSE_ERROR}', $params->{'params'} );
		return;
	}
	
	# check for error reported in RSS
	if ( $feed->{'items'}->[0]->{'title'} eq 'Error' ) {
		my $ecb = $params->{'ecb'};
		return $ecb->( $feed->{'items'}->[0]->{'description'}, $params->{'params'} );
	}
	
	$log->info(sprintf("Got opensearch results [%s]", scalar @{ $feed->{'items'} }));
	
	my $cb = $params->{'cb'};
	$cb->( $feed, $params->{'params'} );
}

sub xmlToHash {
	my $content = shift || return undef;

	# deal with windows encoding stupidity (see Bug #1392)
	$$content =~ s/encoding="windows-1252"/encoding="iso-8859-1"/i;

	my $xml     = undef;
	my $timeout = (Slim::Utils::Prefs::get('remotestreamtimeout') || 5) * 2;

	# Bug 3510 - check for bogus content.
	if ($$content !~ /<\??(?:xml|rss)/) {

		# Set $@, so the block below will catch it.
		$@ = "Invalid XML feed - didn't find <xml>!\n";

	} else {
		
		# make 2 passes at parsing:
		# 1. Parse content as-is
		# 2. Try decoding invalid characters
		for my $pass ( 1..2 ) {
		
			if ( $pass == 2 ) {
				# Some feeds have invalid (usually Windows encoding) in a UTF-8 XML file.
				my @lines = ();

				for my $line (split /\n/, $$content) {

					$line = Slim::Utils::Unicode::utf8decode_guess($line, 'utf8');

					push @lines, $line;
				}

				$content = join("\n", @lines);
			}

			eval {
				# NB: \n required
				local $SIG{'ALRM'} = sub { die "XMLin parsing timed out!\n" };

				alarm $timeout;

				# forcearray to treat items as array,
				# keyattr => [] prevents id attrs from overriding
				$xml = XMLin( ref $content ? $content : \$content, 'forcearray' => [qw(item outline entry)], 'keyattr' => []);
			};
			
			if ($@) {
				logError("Pass $pass failed to parse: $@");
			}
			else {
				last;
			}
		}
	}

	# Always reset the alarm to 0.
	alarm 0;

	if ($@) {

		logError("Failed to parse feed because: [$@]");

		if (defined $content && ref($content) eq 'SCALAR') {

			if (length $$content < 50000) {
				logError("Here's the bad feed:\n[$$content]\n");
			}

			undef $content;
		}

		# XXX - Ugh. Need real exceptions!
		die $@;
	}

	# Release
	undef $content;

	return $xml;
}

#### Some routines for munging strings
sub unescape {
	my $data = shift || return '';

	# Decode all entities in-place
	decode_entities($data);
	
	# Unescape URI (some Odeo OPML needs this)
	$data =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	return $data;
}

sub trim {
	my $data = shift || return '';

	use utf8; # important for regexps that follow

	$data =~ s/\s+/ /g; # condense multiple spaces
	$data =~ s/^\s//g; # remove leading space
	$data =~ s/\s$//g; # remove trailing spaces

	return $data;
}

# unescape and also remove unnecesary spaces
# also get rid of markup tags
sub unescapeAndTrim {
	my $data = shift || return '';

	if (ref($data)) {
		return '';
	}

	# important for regexps that follow
	use utf8;

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
