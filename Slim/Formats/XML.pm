package Slim::Formats::XML;

# $Id$

# Copyright 2006-2009 Logitech

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class handles retrieval and parsing of remote XML feeds (OPML and RSS)

use strict;
use File::Slurp;
use HTML::Entities;
use JSON::XS::VersionOneAndTwo;
use Scalar::Util qw(weaken);
use URI::Escape qw(uri_escape uri_escape_utf8);
use XML::Simple;

use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Player::Protocols::HTTP;
use Slim::Utils::Cache;
use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

# How long to cache parsed XML data
our $XML_CACHE_TIME = 300;

my $log   = logger('formats.xml');
my $prefs = preferences('server');

sub _cacheKey {
	my ( $url, $client ) = @_;
	
	my $cachekey = $url;
	
	if ($client) {
		$cachekey .= '-' . ($client->languageOverride || '');
	}
	
	return $cachekey . '_parsedXML';
}

sub getCachedFeed {
	my ( $class, $url, $client ) = @_;
	
	my $cache = Slim::Utils::Cache->new();
	return $cache->get( _cacheKey($url, $client) );
}

sub getFeedAsync {
	my $class = shift;
	my ( $cb, $ecb, $params ) = @_;
	
	my $url = $params->{'url'};
	
	# Try to load a cached copy of the parsed XML
	my $cache = Slim::Utils::Cache->new();
	my $feed  = $cache->get( _cacheKey($url, $params->{client}) );

	if ( $feed ) {

		main::INFOLOG && $log->is_info && $log->info("Got cached XML data for $url");

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

	# if we have a single item, we might need to expand it to some list (eg. Spotify Album -> track list)
	my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url) unless $feed;

	if ( $handler && $handler->can('explodePlaylist') ) {
		$handler->explodePlaylist($params->{client}, $url, sub {
			my ($tracks) = @_;

			return $cb->({
				'type'  => 'opml',
				'title' => '',
				'items' => [
					map {
						{
							# compatable with INPUT.Choice, which expects 'name' and 'value'
							'name'  => $_,
							'value' => $_,
							'url'   => $_,
							'type'  => 'audio',
							'items' => [],
						}
					} @{$tracks || []}
				],
			}, $params);
		});
		
		return;
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
			'Timeout' => $params->{'timeout'},
	});

	main::INFOLOG && $log->is_info && $log->info("Async request: $url");
	
	# Bug 3165
	# Override user-agent and Icy-Metadata headers so we appear to be a web browser
	my $ua = Slim::Utils::Misc::userAgentString();
	$ua =~ s{iTunes/4.7.1}{Mozilla/5.0};

	my %headers = (
		'User-Agent'   => $ua,
		'Icy-Metadata' => '',
	);

	if ( $url =~ /(?:radiotime|tunein\.com)/ ) {
		# Add the TuneIn username
		if ( $url !~ /username/ && $url =~ /(?:presets|title)/ 
			&& Slim::Utils::PluginManager->isEnabled('Slim::Plugin::InternetRadio::Plugin') 
			&& ( my $username = Slim::Plugin::InternetRadio::TuneIn->getUsername($params->{client}) )
		) {
			$url .= '&username=' . uri_escape_utf8($username);
		}
	}
	
	# If the URL is on SqueezeNetwork, add session headers or login first
	if ( !main::NOMYSB && Slim::Networking::SqueezeNetwork->isSNURL($url) && !$params->{no_sn} ) {
		
		# Sometimes from the web we won't have a client, so pick a random one
		$params->{client} ||= Slim::Player::Client::clientRandom();
		
		my %snHeaders = Slim::Networking::SqueezeNetwork->getHeaders( $params->{client} );
		while ( my ($k, $v) = each %snHeaders ) {
			$headers{$k} = $v;
		}
		
		# Don't require SN session for public URLs
		if ( $url !~ m|/public/| ) {
			main::INFOLOG && $log->is_info && $log->info("URL requires SqueezeNetwork session");

			if ( !$params->{client} ) {
				# No player connected, cannot continue
				$ecb->( string('SQUEEZENETWORK_NO_PLAYER_CONNECTED'), $params );
				return;
			}
		
			if ( my $snCookie = Slim::Networking::SqueezeNetwork->getCookie( $params->{client} ) ) {
				$headers{Cookie} = $snCookie;
			}
			else {
				main::INFOLOG && $log->is_info && $log->info("Logging in to SqueezeNetwork to obtain session ID");
		
				# Login and get a session ID
				Slim::Networking::SqueezeNetwork->login(
					client => $params->{client},
					cb     => sub {
						if ( my $snCookie = Slim::Networking::SqueezeNetwork->getCookie( $params->{client} ) ) {
							$headers{Cookie} = $snCookie;

							main::INFOLOG && $log->is_info && $log->info('Got SqueezeNetwork session ID');
						}
				
						$http->get( $url, %headers );
					},
					ecb   => sub {
						my ( $http, $error ) = @_;
						$ecb->( $error, $params );
					},
				);
		
				return;
			}
		}
	}

	$http->get( $url, %headers );
}

sub gotViaHTTP {
	my $http = shift;
	my $params = $http->params();
	my $feed;
	
	my $ct = $http->headers()->content_type;

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug("Got ", $http->url);
		$log->debug("Content type is $ct");
	}

	# Try and turn the content we fetched into a parsed data structure.
	if (my $parser = $params->{'params'}->{'parser'}) {

		main::INFOLOG && $log->is_info && $log->info("Parsing with parser $parser");

		my $parserParams;

		if ($parser =~ /(.*)\?(.*)/) {
			($parser, $parserParams) = ($1, $2);
		}

		eval "use $parser";

		if ($@) {

			$log->error("$@");

		} else {

			$feed = eval { $parser->parse($http, $parserParams) };

			if ($@) {

				$log->error("$@");
			}
		}

		if ($feed->{'type'} && $feed->{'type'} eq 'redirect') {

			my $url = $feed->{'url'};

			main::INFOLOG && $log->is_info && $log->info("Redirected to $url");

			$params->{'params'}->{'url'} = $url;

			$http->get($url);

			return;
		}

	} else {

		$feed = eval { parseXMLIntoFeed( $http->contentRef, $ct ) };
	}

	if ($@) {
		# call ecb
		my $ecb = $params->{'ecb'};
		$log->error("XML/JSON parse error: $@");
		$ecb->( string('XML_GET_FAILED'), $params->{'params'} );
		return;
	}

	if ( !ref $feed || ref $feed ne 'HASH' ) {
		# call ecb
		my $ecb = $params->{'ecb'};
		$ecb->( '{PARSE_ERROR}', $params->{'params'} );
		return;
	}
	
	# Cache the parsed XML or raw response
	if ( Slim::Utils::Misc::shouldCacheURL( $http->url ) ) {

		my $cache   = Slim::Utils::Cache->new();

		my $expires;

		# parsers may set 'cachetime' to specify a specific cachetime which is also honored by caching within xmlbrowser
		if (defined $feed->{'cachetime'}) {

			$expires = $feed->{'cachetime'};

		} elsif (defined $http->cacheTime) {

			$expires = $http->cacheTime;

		} else {

			$expires = $XML_CACHE_TIME;
		}

		if ( !$feed->{'nocache'} ) {

			if ( main::INFOLOG && $log->is_info ) {
				$log->info("Caching parsed XML for " . $http->url . " for $expires seconds");
			}

			$cache->set( _cacheKey($http->url, $params->{params}->{client}), $feed, $expires );

		} elsif ( $expires && !$cache->get( $http->url() ) ) {

			if ( main::INFOLOG && $log->is_info ) {
				$log->info("Caching raw response for " . $http->url . " for $expires seconds - not previously cached");
			}

			# Responses not previously cached by SimpleAsyncHTTP as web page did not request caching
			# cache it now for a short time to speed up reparsing of this page
			$http->cacheResponse( $expires );
		}
	}
	else {

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf("Not caching parsed XML for %s, appears to be a local resource",
				$http->url,
			));
		}
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
	my $type    = shift || 'text/xml';

	my $xml;
	
	if ( $type =~ /json/ ) {
		$xml = from_json($$content);
	}
	else {
		$xml = xmlToHash($content);
	}
	
	# convert XML into data structure
	if ($xml && $xml->{'body'}) {

		main::DEBUGLOG && $log->is_debug && $log->debug("Parsing body as OPML");

		# its OPML outline
		return parseOPML($xml);
		
	} elsif ($xml && $xml->{'entry'}) {

		main::DEBUGLOG && $log->is_debug && $log->debug("Parsing body as Atom");
		
		# It's Atom
		return parseAtom($xml);

	} elsif ($xml) {

		main::DEBUGLOG && $log->is_debug && $log->debug("Parsing body as RSS");

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
			'description' => unescapeAndTrim( ref $itemXML->{'description'} eq 'HASH' ? $itemXML->{'description'}->{'content'} : $itemXML->{'description'} ),
			'title'       => unescapeAndTrim( ref $itemXML->{'title'} eq 'HASH' ? $itemXML->{'title'}->{'content'} : $itemXML->{'title'} ),
			'link'        => unescapeAndTrim($itemXML->{'link'}),
			'slim:link'   => unescapeAndTrim($itemXML->{'slim:link'}),
			'pubdate'     => unescapeAndTrim( ref $itemXML->{'pubDate'} eq 'HASH' ? $itemXML->{'pubDate'}->{'content'} : $itemXML->{'pubDate'} ),
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
	
	# Handle text constructs
	for my $field ( qw(title subtitle tagline) ) {
		if ( ref $xml->{$field} eq 'HASH' ) {
			$xml->{$field} = $xml->{$field}->{content};
		}
	}
	
	# Support Person construct
	if ( ref $xml->{author} eq 'HASH' ) {
		my $name = $xml->{author}->{name};
		if ( my $email = $xml->{author}->{email} ) {
			$name .= ' (' . $email . ')';
		}
		$xml->{author} = $name;
	}
	
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
		
		# Handle text constructs
		for my $field ( qw(summary title) ) {
			if ( ref $itemXML->{$field} eq 'HASH' ) {
				$itemXML->{$field} = $itemXML->{$field}->{content};
			}
		}
		
		my %item = (
			'description' => unescapeAndTrim($itemXML->{'summary'}),
			'title'       => unescapeAndTrim($itemXML->{'title'}),
			'link'        => unescapeAndTrim($itemXML->{'link'}),
			'slim:link'   => unescapeAndTrim($itemXML->{'slim:link'}),
			'pubdate'     => unescapeAndTrim($itemXML->{'updated'}),
			# image is included in each item due to the way XMLBrowser works
			'image'       => $feed{'image'},
		);
		
		# some Atom streams come with multiple link items, one of them pointing to the stream (enclosure)
		# create a valid enclosure element our XMLBrowser implementations understand
		if ( !$item{link} && $itemXML->{link} && ref $itemXML->{link} && ref $itemXML->{link} eq 'ARRAY' ) {
			my @links = grep {
				$_->{rel} && lc($_->{rel}) eq 'enclosure'
			} @{$itemXML->{link}};

			if (scalar @links) {
				$item{enclosure} = {
					url => $links[0]->{href},
					type => $links[0]->{type},
					duration => $itemXML->{'itunes:duration'}
				};
			}
		}

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
	
	my $head = $xml->{head};

	my $opml = {
		'type'  => 'opml',
		'title' => unescapeAndTrim($head->{'title'}),
		'items' => _parseOPMLOutline($xml->{'body'}->{'outline'}),
	};
	
	# Optional command to run (used by Pandora)
	if ( $xml->{'command'} ) {
		$opml->{'command'} = $xml->{'command'};
		
		# Optional flag to abort OPML processing after command is run
		$opml->{abort} = $xml->{abort} if $xml->{abort};
	}
	
	# Optional item to indicate if the list is sorted
	if ( $xml->{sorted} ) {
		$opml->{sorted} = $xml->{sorted};
	}
	
	# respect cache time as returned by the data source
	if ( defined $head->{cachetime} ) {
		$opml->{cachetime} = $head->{cachetime} + 0;
	}
	
	# Optional windowId to support nextWindow
	if ( $head->{windowId} ) {
		$opml->{windowId} = $head->{windowId};
	}
	
	# Bug 15343, a menu may define forceRefresh in the head to always
	# be refreshed when accessing this menu item
	if ( $head->{forceRefresh} ) {
		$opml->{forceRefresh} = 1;
	}
	
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
		    next if $attr =~ /^(?:text|type|URL|xmlUrl|outline)$/i;
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

sub xmlToHash {
	my $content = shift || return undef;

	# deal with windows encoding stupidity (see Bug #1392)
	$$content =~ s/encoding="windows-1252"/encoding="iso-8859-1"/i;

	my $xml     = undef;
	my $timeout = preferences('server')->get('remotestreamtimeout') * 2;

	# Bug 3510 - check for bogus content.
	if ($$content !~ /<\??(?:xml|rss|opml)/) {

		# Set $@, so the block below will catch it.
		$@ = "Invalid XML feed\n";

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
				$log->warn("Pass $pass failed to parse: $@");
			}
			else {
				last;
			}
		}
	}

	# Always reset the alarm to 0.
	alarm 0;

	if ($@) {

		$log->warn("Failed to parse feed because: [$@]");

		if (defined $content && ref($content) eq 'SCALAR') {

			if ( main::DEBUGLOG && $log->is_debug && length $$content < 50000 ) {
				$log->debug("Here's the bad feed:\n[$$content]\n");
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
