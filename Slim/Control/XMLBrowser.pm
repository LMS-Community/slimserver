package Slim::Control::XMLBrowser;

# $Id: XMLBrowser.pm 23262 2008-09-23 19:21:03Z andy $

# Copyright 2005-2009 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Control::XMLBrowser

=head1 DESCRIPTION

L<Slim::Control::XMLBrowser> offers base code for xmlbrowser based CLI commands.

=cut

use strict;

use Scalar::Util qw(blessed);
use Tie::IxHash;
use URI::Escape qw(uri_escape_utf8 uri_unescape);
use List::Util qw(min);

use Slim::Control::Request;
use Slim::Formats::XML;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Music::TitleFormatter;
#use Slim::Utils::Timers;
use Slim::Web::ImageProxy qw(proxiedImage);

use constant CACHE_TIME => 3600; # how long to cache browse sessions

my $log = logger('formats.xml');
my $prefs = preferences('server');

sub cliQuery {
	my ( $query, $feed, $request, $expires, $forceTitle ) = @_;

	main::INFOLOG && $log->info("cliQuery($query)");
	main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($request->getParamsCopy));

	# check this is the correct query.
	if ($request->isNotQuery([[$query], ['items', 'playlist']])) {
		$request->setStatusBadDispatch();
		return;
	}

	$request->setStatusProcessing();
	
	my $itemId     = $request->getParam('item_id');	# get our parameters
	my $index      = $request->getParam('_index');
	my $quantity   = $request->getParam('_quantity');
	my $client     = $request->client();

	# Bug 14100: sending requests that involve newWindow param from SP side results in no
	# _index _quantity args being sent, but XML Browser actually needs them, so they need to be hacked in
	# here and the tagged params mistakenly put in _index and _quantity need to be re-added
	# to the $request params
	if ( defined $index && $index =~ /:/ ) {
		$request->addParam(split (/:/, $index));
		$index = 0;
		$request->addParam('_index', $index);
	}
	if ( defined $quantity && $quantity =~ /:/ ) {
		$request->addParam(split(/:/, $quantity));
		$quantity = 200;
		$request->addParam('_quantity', $quantity);
	}
	
	my $isPlayCommand = $request->isQuery([[$query], ['playlist']]);
	
	# Handle touch-to-play
	if ($request->getParam('touchToPlay') && !$request->getParam('xmlBrowseInterimCM')
		&& (!$isPlayCommand || $request->getParam('_method') eq 'play')) {

		$isPlayCommand = 1;
		
		# A hack to handle clients that cannot map the 'go' action
		if (!$request->getParam('_method')) {
			$request->addParam('_method', 'play');
			$request->addResult('goNow', 'nowPlaying');
		}
		
		my $playalbum = undef;
		if ( $client ) {
			$playalbum = $prefs->client($client)->get('playtrackalbum');
		}
	
		# if player pref for playtrack album is not set, get the old server pref.
		if ( !defined $playalbum ) {
			$playalbum = $prefs->get('playtrackalbum');
		}
		
		if ($playalbum && !$request->getParam('touchToPlaySingle')) {
			$itemId =~ s/(.*)\.(\d+)/$1/;			# strip off last node
			$request->addParam('playIndex', $2);	# and save in playIndex
			$request->addParam('item_id', $itemId);
		}
		
	}
	
	my %args = (
		'request' => $request,
		'client'  => $client,
		'url'     => $feed,
		'query'   => $query,
		'expires' => $expires,
		'timeout' => 35,
	);

	# If the feed is already XML data (e.g., local music CMs, favorites menus), send it to handleFeed
	if ( ref $feed eq 'HASH' ) {
		
		main::DEBUGLOG && $log->debug("Feed is already XML data!");
		
		$args{'url'} = $feed->{'url'};
		_cliQuery_done( $feed, \%args );
		return;
	}
	
	# Some plugins may give us a callback we should use to get OPML data
	# instead of fetching it ourselves.
	if ( ref $feed eq 'CODE' ) {

		my $callback = sub {
			my $data = shift;
			my $opml;

			if ( ref $data eq 'HASH' ) {
				$opml = $data;
				$opml->{'type'}  ||= 'opml';
				$opml->{'title'} ||= $data->{name} || $request->getParam('title');
			} else {
				$opml = {
					type  => 'opml',
					title => $request->getParam('title'),
					items =>(ref $data ne 'ARRAY' ? [$data] : $data),
				};
			}

			_cliQuery_done( $opml, \%args );
		};
		
		my %args = (params => $request->getParamsCopy(), isControl => 1);

		# If we are getting an intermediate level, then we just need the one item
		# If we are getting the last level then we need all items if we are doing playall of some kind
		
		my $levels = 0;
		my $nextIndex;
		if ( defined $itemId && length($itemId) ) {
			my @index = split(/\./, $itemId);
			if (length($index[0]) >= 8) {
				shift @index;	# discard sid
			}
			$levels = scalar @index;
			($nextIndex) = $index[0] =~ /^(\d+)/;
		}
		
		if (defined $index && $quantity && !$levels && !$isPlayCommand) {
			if (defined $request->getParam('feedMode')) {
				$args{'index'} = $index;
				$args{'quantity'} = $quantity;
			} else {
				# hack to allow for some CM entries
				my $j = 10; 
				$j = $index if ($j > $index);
				$args{'index'} = $index - $j;
				$args{'quantity'} = $quantity + $j;
			}
		} elsif ($levels) {
			$args{'index'} = $nextIndex;
			$args{'quantity'} = 1;
		}
		
		if ($request->getParam('menu')) {
			if (my $sort = $prefs->get('jivealbumsort')) {
				$args{'orderBy'} = 'sort:' . $sort;
			}
		}
		
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			my $cbname = Slim::Utils::PerlRunTime::realNameForCodeRef( $feed );
			$log->debug( "Fetching OPML from coderef $cbname" );
		}

		$feed->( $client, $callback, \%args);
		
		return;
	}

	
	if ( $feed =~ /{QUERY}/ ) {
		# Support top-level search
		my $query = $request->getParam('search');
		
		if ( !$query ) {
			($query) = $itemId =~ m/^_([^.]+)/;
		}
		
		$feed =~ s/{QUERY}/$query/g;

		$args{'url'} = $feed;
	}
	
	# Lookup this browse session in cache if user is browsing below top-level
	# This avoids repated lookups to drill down the menu
	if ( $itemId && $itemId =~ /^([a-f0-9]{8})/ ) {
		my $sid = $1;
		
		# Do not use cache if this is a search query
		if ( $request->getParam('search') ) {
			# Generate a new sid
			my $newsid = Slim::Utils::Misc::createUUID();
			
			$itemId =~ s/^$sid/$newsid/;
			$request->addParam( item_id => "$itemId" ); # stringify for JSON
		}
		
		my $cache = Slim::Utils::Cache->new;
		if ( my $cached = $cache->get("xmlbrowser_$sid") ) {
			main::DEBUGLOG && $log->is_debug && $log->debug( "Using cached session $sid" );
				
			_cliQuery_done( $cached, \%args );
			return;
		}
	}

	main::DEBUGLOG && $log->debug("Asynchronously fetching feed $feed - will be back!");
	
	Slim::Formats::XML->getFeedAsync(
		\&_cliQuery_done,
		\&_cliQuery_error,
		\%args,
	);

}

my @mapAttributes = (
	{
		key => 'DEFAULT',
		func => sub {
			my ($value, @args) = @_;
			return sprintf('%s: %s', $args[0], $value);
		},
	},
	{key => 'name', args => ['TITLE'],},
	{key => 'url', args => ['URL'],
		condition => sub {$_[0] && !ref$_[0]},
	},
	{key => 'description', args => ['DESCRIPTION'],},
	{key => 'bitrate', args => ['BITRATE', 'KBPS'],
		func => sub {
			my ($value, @args) = @_;
			return sprintf('%s: %s%s', $args[0], $value, $args[1]);
		},
	},
	{key => 'duration', args => ['LENGTH'],
		func => sub {
			my ($value, @args) = @_;
			return sprintf('%s: %s:%02s', $args[0], int($value / 60), $value % 60);
		},
	},
	{key => 'listeners', args => ['NUMBER_OF_LISTENERS'],},		# Shoutcast
	{key => 'current_track', args => ['NOW_PLAYING'],},			# Shoutcast
	{key => 'genre', args => ['GENRE'],},						# Shoutcast
	{key => 'source', args => ['SOURCE'],},						# LMA
);

sub _cliQuery_done {
	my ( $feed, $params ) = @_;

	my $request    = $params->{'request'};
	my $query      = $params->{'query'};
#	my $forceTitle = $params->{'forceTitle'};
	my $client     = $request->client();
	my $window;
	
	main::INFOLOG && $log->info("_cliQuery_done(): ", $request->getRequestString());

	my $cache = Slim::Utils::Cache->new;

	my $isItemQuery = my $isPlaylistCmd = 0;
	my $xmlBrowseInterimCM = $request->getParam('xmlBrowseInterimCM');
	my $xmlbrowserPlayControl = $request->getParam('xmlbrowserPlayControl');
	
	if ($request->isQuery([[$query], ['playlist']])) {
		$isPlaylistCmd = 1;
	}
	elsif ($request->isQuery([[$query], ['items']])) {
		if ($request->getParam('touchToPlay') && !$xmlBrowseInterimCM) {
			$isPlaylistCmd = 1;
		} else {
			$isItemQuery = 1;
		}
	}

	# get our parameters
	my $index      = $request->getParam('_index') || 0;
	my $quantity   = $request->getParam('_quantity') || 0;
	my $search     = $request->getParam('search');
	my $want_url   = $request->getParam('want_url') || 0;
	my $item_id    = $request->getParam('item_id');
	my $menu       = $request->getParam('menu');
	my $url        = $request->getParam('url');
	my $trackId    = $request->getParam('track_id');
	
	# menu/jive mgmt
	my $menuMode = defined $menu;
	my $feedMode = defined $request->getParam('feedMode');
	
	my $playalbum = undef;
	if ( $client ) {
		$playalbum = $prefs->client($client)->get('playtrackalbum');
	}
	# if player pref for playtrack album is not set, get the old server pref.
	if ( !defined $playalbum ) {
		$playalbum = $prefs->get('playtrackalbum');
	}
						
	# Session ID for this browse session
 	my $sid;
	
	# select the proper list of items
	my @index = ();

	if ( defined $item_id && length($item_id) ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("item_id: $item_id");
		
		@index = split /\./, $item_id;
		
		if ( length( $index[0] ) >= 8 && $index[0] =~ /^[a-f0-9]{8}/ ) {
			# Session ID is first element in index
			$sid = shift @index;
		}
	}
	else {
		my $refs = scalar grep { ref $_->{url} } @{ $feed->{items} };
		
		# Don't cache if list has coderefs
		if ( !$refs ) {
			$sid = Slim::Utils::Misc::createUUID();
		}
	}
	
	my $subFeed = $feed;
	$subFeed->{'offset'} ||= 0;
	
	my @crumbIndex = $sid ? ( $sid ) : ();
	
	# Add top-level search to index
	if ( defined $search && !scalar @index ) {
		@crumbIndex = ( ($sid || '') . '_' . uri_escape_utf8( $search, "^A-Za-z0-9" ) );
	}
	
	if ( $sid ) {
		# Cache the feed structure for this session

		# cachetime is only set by parsers which known the content is dynamic and so can't be cached
		# for all other cases we always cache for CACHE_TIME to ensure the menu stays the same throughout the session
		my $cachetime = defined $feed->{'cachetime'} ? $feed->{'cachetime'} : CACHE_TIME;
		main::DEBUGLOG && $log->is_debug && $log->debug( "Caching session $sid for $cachetime" );
		eval { $cache->set( "xmlbrowser_$sid", $feed, $cachetime ) };
		if ( main::DEBUGLOG && $@ && $log->is_debug ) {
			$log->debug("Session not cached: $@");
		}
	}
	
	if ( my $levels = scalar @index ) {

		# descend to the selected item
		my $depth = 0;
		
		for my $i ( @index ) {
			main::DEBUGLOG && $log->debug("Considering item $i");

			$depth++;
			
			my ($in) = $i =~ /^(\d+)/;
			$subFeed = $subFeed->{'items'}->[$in - $subFeed->{'offset'}];
			$subFeed->{'offset'} ||= 0;
			
			push @crumbIndex, $i;
			
			$search = $subFeed->{'searchParam'} if (defined $subFeed->{'searchParam'});
			
			# Add search query to crumb list
			if ( $subFeed->{type} && $subFeed->{type} eq 'search' && defined $search ) {
				# Escape periods in the search string
				$crumbIndex[-1] .= '_' . uri_escape_utf8( $search, "^A-Za-z0-9" );
			}
			
			# Change URL if there is a play attribute and it's the last item
			if ( 
			       $subFeed->{play}
				&& $depth == $levels 
				&& $isPlaylistCmd
			) {
				$subFeed->{url}  = $subFeed->{play};
				$subFeed->{type} = 'audio';
			}

			# Change URL if there is a playlist attribute and it's the last item
			if ( 
			       $subFeed->{playlist}
				&& $depth == $levels
				&& $isPlaylistCmd
			) {
				$subFeed->{type} = 'playlist';
				$subFeed->{url}  = $subFeed->{playlist};
			}
			
			# Bug 15343, if we are at the lowest menu level, and we have already
			# fetched and cached this menu level, check if we should always
			# re-fetch this menu. This is used to ensure things like the Pandora
			# station list are always up to date. The reason we check depth==levels
			# is so that when you are browsing at a lower level we don't allow
			# the parent menu to be refreshed out from under the user
			if ( $depth == $levels && $subFeed->{fetched} && $subFeed->{forceRefresh} && !$params->{fromSubFeed} ) {
				main::DEBUGLOG && $log->is_debug && $log->debug("  Forcing refresh of menu");
				delete $subFeed->{fetched};
			}
			
			# If the feed is another URL, fetch it and insert it into the
			# current cached feed
			if ( (!$subFeed->{'type'} || ($subFeed->{'type'} ne 'audio')) && defined $subFeed->{'url'} && !$subFeed->{'fetched'}

				# Only fetch playlist-with-parser types if playing - so favorites get the unsubstituted (long-lived) URL
				#
				# Unfortunately, we cannot do this because playtrackalbum & touchToPlay logic interfers by
				# stripping the last component off the hierarchy.	
				# && !($isItemQuery && $subFeed->{'type'} && $subFeed->{'type'} eq 'playlist' && $subFeed->{'parser'})
			) {
				
				if ( $i =~ /(?:\d+)?_(.+)/ ) {
					$search = Slim::Utils::Unicode::utf8on(uri_unescape($1));
				}
				
				# Rewrite the URL if it was a search request
				if ( $subFeed->{type} && $subFeed->{type} eq 'search' && defined $search ) {
					my $encoded = URI::Escape::uri_escape_utf8($search);
					$subFeed->{url} =~ s/{QUERY}/$encoded/g;
				}
				
				# Setup passthrough args
				my $args = {
					'item'         => $subFeed,
					'url'          => $subFeed->{'url'},
					'feedTitle'    => $subFeed->{'name'} || $subFeed->{'title'},
					'parser'       => $subFeed->{'parser'},
					'parent'       => $feed,
					'parentURL'    => $params->{'parentURL'} || $params->{'url'},
					'currentIndex' => \@crumbIndex,
					'request'      => $request,
					'client'       => $client,
					'query'        => $query,
					'expires'      => $params->{'expires'},
					'timeout'      => $params->{'timeout'},
				};
				
				if ( ref $subFeed->{url} eq 'CODE' ) {
					
					# Some plugins may give us a callback we should use to get OPML data
					# instead of fetching it ourselves.
					my $callback = sub {
						my $data = shift;
						my $opml;

						if ( ref $data eq 'HASH' ) {
							$opml = $data;
							$opml->{'type'}  ||= 'opml';
							$opml->{'title'} = $args->{feedTitle};
						} else {
							$opml = {
								type  => 'opml',
								title => $args->{feedTitle},
								items => (ref $data ne 'ARRAY' ? [$data] : $data),
							};
						}
						
						_cliQuerySubFeed_done( $opml, $args );
					};
					
					my $pt = $subFeed->{passthrough} || [];
					my %args = (params => $feed->{'query'}, isControl => 1);
					
					if (defined $search && $subFeed->{type} && ($subFeed->{type} eq 'search' || defined $subFeed->{'searchParam'})) {
						$args{'search'} = $search;
					}
					
					# If we are getting an intermediate level, then we just need the one item
					# If we are getting the last level then we need all items if we are doing playall of some kind
					
					if (defined $index && $quantity && $depth == $levels && !$isPlaylistCmd) {
						if ($feedMode) {
							$args{'index'} = $index;
							$args{'quantity'} = $quantity;
						} else {
							# hack to allow for some CM entries
							my $j = 10; 
							$j = $index if ($j > $index);
							$args{'index'} = $index - $j;
							$args{'quantity'} = $quantity + $j;
						}
					} elsif ($depth < $levels) {
						$args{'index'} = $index[$depth];
						$args{'quantity'} = 1;
					}
					
					if ( main::DEBUGLOG && $log->is_debug ) {
						my $cbname = Slim::Utils::PerlRunTime::realNameForCodeRef( $subFeed->{url} );
						$log->debug( "Fetching OPML from coderef $cbname" );
					}

					$subFeed->{url}->( $client, $callback, \%args, @{$pt});
				}
				
				# No need to check for a cached version of this subfeed URL as getFeedAsync() will do that

				else {				
					main::DEBUGLOG && $log->debug("Asynchronously fetching subfeed " . $subFeed->{url} . " - will be back!");

					Slim::Formats::XML->getFeedAsync(
						\&_cliQuerySubFeed_done,
						\&_cliQuery_error,
						$args,
					);
				}
				
				return;
			}

			# If the feed is an audio feed, Podcast enclosure or information item, display the info
			# This is a leaf item, so show as much info as we have and go packing after that.		
			if (	$isItemQuery &&
					(
						($subFeed->{'type'} && $subFeed->{'type'} eq 'audio') || 
						$subFeed->{'enclosure'} ||
						# Bug 17385 - rss feeds include description at non leaf levels	
						($subFeed->{'description'} && $subFeed->{'type'} ne 'rss')
					)
				) {
				
				if ($feedMode) {
					$request->setRawResults($feed);
					$request->setStatusDone();
					return;
				}
				
				main::DEBUGLOG && $log->debug("Adding results for audio or enclosure subfeed");

				my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), 1);
				
				my $cnt = 0;

				if ($menuMode) {
					if ($xmlBrowseInterimCM) {
						for my $eachmenu ( @{ _playlistControlContextMenu({ request => $request, query => $query, item => $subFeed }) } ) {
							main::INFOLOG && $log->info("adding playlist Control CM item $cnt");
							$request->setResultLoopHash('item_loop', $cnt, $eachmenu);
							$cnt++;
						}
					}
				} # $menuMode
				
				else {
					$request->addResult('count', 1);
				}
				
				if ($valid) {
					
					my $loopname = $menuMode ? 'item_loop' : 'loop_loop';
					$request->addResult('offset', $start) if $menuMode;

					my %hash;
					# create an ordered hash to store this stuff... except not for menuMode
					tie (%hash, "Tie::IxHash") unless $menuMode;

					$hash{'id'} = "$item_id"; # stringify for JSON
					$hash{'name'} = $subFeed->{'name'} if defined $subFeed->{'name'};
					$hash{'title'} = $subFeed->{'title'} if defined $subFeed->{'title'};
					
					$hash{'isaudio'} = defined(hasAudio($subFeed)) + 0;				
				
					foreach my $data (keys %{$subFeed}) {
						
						if (ref($subFeed->{$data}) eq 'ARRAY') {
#							if (scalar @{$subFeed->{$data}}) {
#								$hash{'hasitems'} = scalar @{$subFeed->{$data}};
#							}
						}
						
						elsif ($data =~ /enclosure/i && defined $subFeed->{$data}) {
							
							foreach my $enclosuredata (keys %{$subFeed->{$data}}) {
								if ($subFeed->{$data}->{$enclosuredata}) {
									$hash{$data . '_' . $enclosuredata} = $subFeed->{$data}->{$enclosuredata};
								}
							}
						}
						
						elsif ($subFeed->{$data} && $data !~ /^(name|title|parser|fetched)$/) {
							$hash{$data} = $subFeed->{$data};
						}
					}
										
					if ($menuMode) {
						
						foreach my $att (@mapAttributes[1..$#mapAttributes]) {
							my $key = $hash{$att->{'key'}};
							next unless (defined $key && ($att->{'condition'} ? $att->{'condition'}->($key) : $key));
							my $func = $att->{'func'} || $mapAttributes[0]->{'func'};
							my $text = $func->($key, map {$request->string($_)} @{$att->{'args'}});
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						$request->addResult('count', $cnt);
					} # $menuMode
					
					else {
						$request->setResultLoopHash($loopname, $cnt, \%hash);
					}
				}
				$request->setStatusDone();
				return;
			} # $isItemQuery && (audio || enclosure || description)
		}
	}
	
	if ($feedMode) {
		$request->setRawResults($feed);
		$request->setStatusDone();
		return;
	}
				
	if ($isPlaylistCmd) {

		# get our parameters
		my $method = $request->getParam('_method');
		
		my $playIndex = $request->getParam('playIndex');
		
		# playIndex will only be defined if we modified the item-Id earlier, for touchToPlay
		if ($request->getParam('touchToPlay') && defined($playIndex)) {
			if ($method =~ /^(add|play)$/ && $subFeed->{'items'}->[$playIndex]->{playall}) {
				$method .= 'all';
			} else {
				$subFeed = $subFeed->{'items'}->[$playIndex];
			}
		}

		main::INFOLOG && $log->info("Play an item ($method).");

		if ($client && $method =~ /^(add|addall|play|playall|insert|load)$/i) {

			# single item
			if ((defined $subFeed->{'url'} && $subFeed->{'type'} eq 'audio' || defined $subFeed->{'enclosure'})
				&& (defined $subFeed->{'name'} || defined $subFeed->{'title'})
				&& ($method !~ /all/)) {
	
				my $title = $subFeed->{'name'} || $subFeed->{'title'};
				my $url   = $subFeed->{'url'};
	
				# Podcast enclosures
				if ( my $enc = $subFeed->{'enclosure'} ) {
					$url = $enc->{'url'};
				}
				
				# Items with a 'play' attribute will use this for playback
				if ( my $play = $subFeed->{'play'} ) {
					$url = $play;
				}
	
				if ( $url ) {

					main::INFOLOG && $log->info("$method $url");
					
					# Set metadata about this URL
					Slim::Music::Info::setRemoteMetadata( $url, {
						title   => $title,
						ct      => $subFeed->{'mime'},
						secs    => $subFeed->{'duration'},
						bitrate => $subFeed->{'bitrate'},
						cover   => $subFeed->{'cover'} || $subFeed->{'image'} || $subFeed->{'icon'} || $request->getParam('icon'),
					} );
				
					$client->execute([ 'playlist', $method, $url ]);
				}
				else {
					main::INFOLOG && $log->info("No valid URL found for: ", $title);
				}
			}
			
			# play all streams of an item (or one stream if pref is unset)
			else {
				my @urls;
				for my $item ( @{ $subFeed->{'items'} } ) {
					my $url;
					
					if ( $item->{'type'} eq 'audio' && $item->{'url'} ) {
						$url = $item->{'url'};
					}
					elsif ( $item->{'enclosure'} && $item->{'enclosure'}->{'url'} ) {
						$url = $item->{'enclosure'}->{'url'};
					}
					elsif ( $item->{'play'} ) {
						$url = $item->{'play'};
					}
					
					# Don't add non-audio items
					# In touch-to-play, only add items with the playall attribute
					if (!$url || defined($playIndex) && !$item->{'playall'}) {
						$playIndex-- if defined($playIndex) && $playIndex >= scalar @urls;
						next;
					}

					# Set metadata about this URL
					Slim::Music::Info::setRemoteMetadata( $url, {
						title   => $item->{'name'} || $item->{'title'},
						ct      => $item->{'mime'},
						secs    => $item->{'duration'},
						bitrate => $item->{'bitrate'},
						cover   => $subFeed->{'cover'} || $subFeed->{'image'} || $subFeed->{'icon'} || $request->getParam('icon'),
					} );
					
					main::idleStreams();
					
					push @urls, $url;
				}
				
				if ( @urls ) {

					my $cmd;
					if ( $method =~ /play|load/i ) {
						$cmd = 'loadtracks';
					} elsif ($method =~ /add/) {
						$cmd = 'addtracks';
						$playIndex = undef;
					} else {
						$cmd = 'inserttracks';
						$playIndex = undef;
					}
		
					if ( main::INFOLOG && $log->is_info ) {
						$log->info(sprintf("Playing/adding all items:\n%s", join("\n", @urls)));
					}
	
					$client->execute([ 'playlist', $cmd, 'listref', \@urls, undef, $playIndex ]);

					# if we're adding or inserting, show a showBriefly
					if ( $method =~ /add/ || $method eq 'insert' ) {
						my $icon = proxiedImage($subFeed->{'image'} || $subFeed->{'cover'} || $request->getParam('icon'));
						my $title = $subFeed->{'name'} || $subFeed->{'title'};
						_addingToPlaylist($client, $method, $title, $icon);
					}
				}
				else {
					main::INFOLOG && $log->info("No valid URL found for: ", ($subFeed->{'name'} || $subFeed->{'title'}));
				}
				
			}
		}
		else {
			$request->setStatusBadParams();
			return;
		}
	} # ENDIF $isPlaylistCmd

	elsif ($isItemQuery) {

		main::INFOLOG && $log->info("Get items.");
		
		my $items = $subFeed->{'items'};
		my $count = $subFeed->{'total'};;
		$count ||= defined $items ? scalar @$items : 0;
		
		# now build the result
	
		my $hasImage = 0;
		my $windowStyle;
		my $presetFavSet = 0;
		my $totalCount = $count;
		my $allTouchToPlay = 1;
		my $defeatDestructiveTouchToPlay = _defeatDestructiveTouchToPlay($request, $client);
		my %actionParamsNeeded;
		
		if ($menuMode && defined $xmlbrowserPlayControl) {

			$totalCount = 0;
			my $i = $xmlbrowserPlayControl - $subFeed->{'offset'};
			if ($i < 0 || $i > $count) {
				$log->error("Requested item index $xmlbrowserPlayControl out of range: ",
					$subFeed->{'offset'}, '..', $subFeed->{'offset'} + $count -1);
			} else {
				my $item = $items->[$i];
				for my $eachmenu (@{ 
					_playlistControlContextMenu({
						request     => $request,
						query       => $query,
						item        => $item,
						subFeed     => $subFeed,
						noFavorites => 1,
						item_id		=> scalar @crumbIndex ? join('.', @crumbIndex) : undef,
						subItemId   => $xmlbrowserPlayControl,
						playalbum   => 1,	# Allways add play-all item
					})
				})
				{
					$request->setResultLoopHash('item_loop', $totalCount, $eachmenu);
					$totalCount++;
				}
				
			}
			$request->addResult('offset', 0);
		}
			
		elsif ($menuMode || $count || $xmlBrowseInterimCM) {
		
			# Bug 7024, display an "Empty" item instead of returning an empty list
			if ( $menuMode && !$count && !$xmlBrowseInterimCM) {
				$items = [ { type => 'text', name => $request->string('EMPTY') } ];
				$totalCount = $count = 1;
			}
			
			my $loopname = $menuMode ? 'item_loop' : 'loop_loop';
			my $cnt = 0;

			if ($menuMode) {

				$request->addResult('offset', $index);

				my $firstChunk = !$index;
				if ($xmlBrowseInterimCM && !$subFeed->{'menuComplete'}) {
					for my $eachmenu (@{ _playlistControlContextMenu({ request => $request, query => $query, item => $subFeed }) }) {
						$totalCount = _fixCount(1, \$index, \$quantity, $totalCount);
						
						# Only add them the first time
						if ($firstChunk) {
							$request->setResultLoopHash('item_loop', $cnt, $eachmenu);
							$cnt++;
						}
					}
				}
				
			}

			my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);
		
			if ($valid) {
				
				my $feedActions = $subFeed->{'actions'};
				
				# Title is preferred here as it will contain the real title from the subfeed,
				# whereas name is the title of the menu item that led to this submenu and may
				# not always match
				if (my $title = $subFeed->{'title'} || $subFeed->{'name'}) {
					if ($menuMode && $subFeed->{'name2'}) {
						$title .= "\n" . $subFeed->{'name2'};
					}
					$request->addResult( 'title', $title );
				}
				
				# decide what is the next step down
				# we go to xxx items from xx items :)
				my $base; my $params = {};
				
				if ($menuMode) {
					if (!$feedActions->{'allAvailableActionsDefined'}) {
						# build the default base element
						$params = {
							'menu' => $query,
						};
					
						if ( $url ) {
							$params->{'url'} = $url;
						}
						
						if ($feed->{'query'}) {
							$params = {%$params, %{$feed->{'query'}}};
						}
						elsif ( $trackId ) {
							$params->{'track_id'} = $trackId;
						}
				
						$base = {
							'actions' => {
								'go' => {
									'cmd' => [ $query, 'items' ],
									'params' => $params,
									'itemsParams' => 'params',
								},
								'play' => {
									'player' => 0,
									'cmd' => [$query, 'playlist', 'play'],
									'itemsParams' => 'params',
									'params' => $params,
									'nextWindow' => 'nowPlaying',
								},
								'add' => {
									'player' => 0,
									'cmd' => [$query, 'playlist', 'add'],
									'itemsParams' => 'params',
									'params' => $params,
								},
								'add-hold' => {
									'player' => 0,
									'cmd' => [$query, 'playlist', 'insert'],
									'itemsParams' => 'params',
									'params' => $params,
								},
								'more' => {
									player      => 0,
									cmd         => [ $query, 'items' ],
									itemsParams => 'params',
									params      => $params,
									window      => {isContextMenu => 1},
								},
							},
						};
					}
					
					if (my $feedActions = $subFeed->{'actions'}) {
						my $n = 0;
						
						my $baseAction;
						
						if ($baseAction = _makeAction($feedActions, 'info', \%actionParamsNeeded, 1, 1)) {
							$base->{'actions'}->{'more'} = $baseAction; $n++;
						}
						if ($baseAction = _makeAction($feedActions, 'items', \%actionParamsNeeded, 1)) {
							$base->{'actions'}->{'go'} = $baseAction; $n++;
						}
						if ( $playalbum && ($baseAction = _makeAction($feedActions, 'playall', \%actionParamsNeeded, 1, 0, 'nowPlaying')) ) {
							$base->{'actions'}->{'play'} = $baseAction; $n++;
						} elsif (my $baseAction = _makeAction($feedActions, 'play', \%actionParamsNeeded, 1, 0, 'nowPlaying')) {
							$base->{'actions'}->{'play'} = $baseAction; $n++;
						}
						if ( $playalbum && ($baseAction = _makeAction($feedActions, 'addall', \%actionParamsNeeded, 1)) ) {
							$base->{'actions'}->{'add'} = $baseAction; $n++;
						} elsif (my $baseAction = _makeAction($feedActions, 'add', \%actionParamsNeeded, 1)) {
							$base->{'actions'}->{'add'} = $baseAction; $n++;
						}
						if ($baseAction = _makeAction($feedActions, 'insert', \%actionParamsNeeded, 1)) {
							$base->{'actions'}->{'add-hold'} = $baseAction; $n++;
						}
						
						if ($n >= 5) {
							$feedActions->{'allAvailableActionsDefined'} = 1;
						}
					}
					
					$base->{'actions'}->{'playControl'} = {
						player      => 0,
						window      => {isContextMenu => 1},
						cmd         => [map {$request->getRequest($_)} (0 .. ($request->getRequestCount()-1))],
						itemsParams => 'playControlParams',
						params      => $request->getParamsCopy(),
					};
					
					$request->addResult('base', $base);
				}

				# If we have a slideshow param, return all items without chunking, and only
				# include image and caption data
				if ( $request->getParam('slideshow') ) {
					my $images = [];
					for my $item ( @$items ) {
						next unless $item->{image};
						push @{$images}, {
							image   => proxiedImage($item->{image}),
							caption => $item->{name},
							date    => $item->{date},
							owner   => $item->{owner},
						};
					}

					$request->addResult( data => $images );
					$request->setStatusDone();
					return;
				}

				my $itemIndex = $start - 1;
				my $format  = $prefs->get('titleFormat')->[ $prefs->get('titleFormatWeb') ];
								
				$start -= $subFeed->{'offset'};
				$end   -= $subFeed->{'offset'};
				main::DEBUGLOG && $log->is_debug && $log->debug("Getting slice $start..$end: $totalCount; offset=", $subFeed->{'offset'}, ' quantity=', scalar @$items);
		
				my $search = $subFeed->{type} && $subFeed->{type} eq 'search';
				
				my $baseId = scalar @crumbIndex ? join('.', @crumbIndex, '') : '';
				for my $item ( @$items[$start..$end] ) {
					$itemIndex++;
					
					if ($item->{ignore}) {
						# Skip this item
						$totalCount--;
						next;
					}
					
					my $id = $baseId . $itemIndex;
					
					my $name = $item->{name};
					if (defined $name && $name ne '') {
						if (defined $item->{'label'}) {
							$name = $request->string($item->{'label'}) . $request->string('COLON') . ' ' .  $name;
						} elsif (!$search && ($item->{'hasMetadata'} || '') eq 'track') {
							$name = Slim::Music::TitleFormatter::infoFormat(undef, $format, 'TITLE', $item) || $name;
						}
					}
					
					my $isPlayable = (
						   $item->{play} 
						|| $item->{playlist} 
						|| ($item->{type} && ($item->{type} eq 'audio' || $item->{type} eq 'playlist'))
					);
			
					# keep track of station icons
					if ( 
						$isPlayable 
						&& $item->{url} && !ref $item->{url}
						&& $item->{url} =~ /^http/ 
						&& $item->{url} !~ m|\.com/api/\w+/v1/opml| 
						&& (my $cover = ($item->{image} || $item->{cover})) 
						&& !Slim::Utils::Cache->new->get("remote_image_" . $item->{url})
					) {
						$cache->set("remote_image_" . $item->{url}, $cover, 86400);
					}
					
					if ($menuMode) {
						my %hash;
						
						$hash{'type'}   = $item->{'type'}  if defined $item->{'type'};
										# search|text|textarea|audio|playlist|link|opml|replace|redirect|radio
										# radio is a radio-button selection item, not an internet-radio station 
						my $nameOrTitle = getTitle($name, $item);
						my $touchToPlay = defined(touchToPlay($item)) + 0;
						
						# if showBriefly is 1, send the name as a showBriefly
						if ($item->{showBriefly} and ( $nameOrTitle ) ) {
							$client->showBriefly({ 
										'jive' => {
											'type'    => 'popupplay',
											'text'    => [ $nameOrTitle ],
										},
									}) if $client;

							# Skip this item
							$totalCount--;

							next;
						}

						# if nowPlaying is 1, tell Jive to go to nowPlaying
						if ($item->{nowPlaying}) {
							$request->addResult('goNow', 'nowPlaying');
						}
									
						# wrap = 1 and type = textarea render in the single textarea area above items
						if ( $item->{name} && $item->{wrap} || $item->{type} && $item->{type} eq 'textarea' ) {
							$window->{textarea} = $item->{name};

							# Skip this item
							$totalCount--;
							
							# In case this is the only item, add an empty item list
							$request->setResultLoopHash($loopname, 0, {});
							
							next;
						}
						
						# Avoid including album tracks and the like in context-menus
						if ( $xmlBrowseInterimCM &&
							($item->{play} || ($item->{type} && ($item->{type} eq 'audio')))
							# Cannot do this if we might screw up paging - silly but unlikely
							&& $totalCount < scalar($quantity) )
						{
							# Skip this item
							$totalCount--;
							next;
						}
						
						# Bug 13175, support custom windowStyle - this is really naff
						if ( $item->{style} ) {
							$windowStyle = $item->{style};
						}
						
						# Bug 7077, if the item will autoplay, it has an 'autoplays=1' attribute
						if ( $item->{autoplays} ) {
							$hash{'style'} = 'itemplay';
						}
						
						elsif (my $playcontrol = $item->{'playcontrol'}) {
							if    ($playcontrol eq 'play')   {$hash{'style'} = 'item_play';}
							elsif ($playcontrol eq 'add')    {$hash{'style'} = 'item_add';}
							elsif ($playcontrol eq 'insert' && $client->revision !~ /^7\.[0-7]/) {$hash{'style'} = 'item_insert';}
						}
						
						my $itemText = $nameOrTitle;
						if ($item->{'name2'}) {
							$itemText .= "\n" . $item->{'name2'};
							$windowStyle = 'icon_list' if !$windowStyle;
						}
						elsif ( my $line2 = $item->{line2} || $item->{subtext} ) { # subtext is returned by TuneIn's OPML
							$windowStyle = 'icon_list';
							$itemText = ( $item->{line1} || $nameOrTitle ) . "\n" . $line2;
						}
						$hash{'text'} = $itemText;
						
						if ($isPlayable) {
							my $presetParams = _favoritesParams($item);
							if ($presetParams && !$xmlBrowseInterimCM) {
								$hash{'presetParams'} = $presetParams;
								$presetFavSet = 1;
							}
						}

						my $itemParams = {};

						if ( !$item->{type} || $item->{type} ne 'text' ) {							
							$itemParams->{'item_id'} = "$id", #stringify, make sure it's a string
						}

						if ( $isPlayable || $item->{isContextMenu} ) {
							$itemParams->{'isContextMenu'} = 1;
						}
						
						if ($item->{type} && $item->{type} eq 'slideshow') {
							$itemParams->{slideshow} = 1;
						}

						my %merged = (%{$params}, %{$itemParams});

						if ( $item->{icon} ) {
							$hash{'icon' . ($item->{icon} =~ /^http:/ ? '' : '-id')} = proxiedImage($item->{icon});
							$hasImage = 1;
						} elsif ( $item->{image} ) {
							$hash{'icon'} = proxiedImage($item->{image});
							$hasImage = 1;
						}
						if (my $coverid = $item->{'artwork_track_id'}) {
							$hash{'icon-id'} = proxiedImage($coverid);
							$hasImage = 1;
						}

						if ( $item->{type} && $item->{type} eq 'text' && !$item->{wrap} && !$item->{jive} ) {
							$hash{'style'} ||= 'itemNoAction';
							$hash{'action'} = 'none';
						}
						
						if ( $item->{type} && $item->{type} eq 'localservice' ) {
							$hash{'actions'} = {
								go => {
									localservice => $item->{serviceId},
								},
							};
						}

						elsif ( $item->{type} && $item->{type} eq 'search' ) {
							#$itemParams->{search} = '__INPUT__';
							
							# XXX: bug in Jive, this should really be handled by the base go action
							my $actions = {
								go => {
									cmd    => [ $query, 'items' ],
									params => {
										%$params,
										item_id     => "$id",
										search      => '__TAGGEDINPUT__',
										cachesearch => defined $item->{cachesearch} ? $item->{cachesearch} : 1, # Bug 13044, can this search be cached or not?
									},
								},
							};
							
							# Allow search results to become a slideshow
							if ( defined $item->{slideshow} ) {
								$actions->{go}->{params}->{slideshow} = $item->{slideshow};
							}
							
							my $input = {
								len  => 1,
								processingPopup => {
									text => $request->string('SEARCHING'),
								},
								help => {
									text => $request->string('JIVE_SEARCHFOR_HELP')
								},
								softbutton1 => $request->string('INSERT'),
								softbutton2 => $request->string('DELETE'),
								title => $item->{title} || $item->{name},
							};
							
							$hash{'actions'} = $actions;
							$hash{'input'} = $input;
							if ($item->{nextWindow}) {
								$hash{'nextWindow'} = $item->{nextWindow};
							}
							$allTouchToPlay = 0;
						}
						
						elsif ( !$isPlayable && !$touchToPlay && ($hash{'style'} || '') ne 'itemNoAction') {
							
							# I think that doing it this way means that, because $itemParams does not get
							# added as 'params' if !$isPlayable, therefore all the other default actions will
							# bump because SlimBrowser needs 'params' as specified in the base actions.
							
							my $actions = {
								'go' => {
									'cmd' => [ $query, 'items' ],
									'params' => \%merged,
								},
							};
							# Bug 13247, support nextWindow param
							if ( $item->{nextWindow} ) {
								$actions->{go}{nextWindow} = $item->{nextWindow};
								# Bug 15690 - if nextWindow is 'nowPlaying', assume this should be styled as a touch-to-play
								if ( $item->{nextWindow} eq 'nowPlaying' ) {
									$hash{'style'} = 'itemplay';
								}
							}
							$hash{'actions'} = $actions;
							$hash{'addAction'} = 'go';
							$allTouchToPlay = 0;
						}
						
						elsif ( $touchToPlay ) {
							if (!$defeatDestructiveTouchToPlay) {
								$itemParams->{'touchToPlay'} = "$id"; # stringify, make sure it's a string
								$itemParams->{'touchToPlaySingle'} = 1 if !$item->{'playall'};
								
								# not currently supported by 7.5 client
								$hash{'goAction'} = 'play'; 
								
								$hash{'style'} = 'itemplay';
							} else {
								# not currently supported by 7.5 client
								$hash{'goAction'} = 'playControl'; 
								$hash{'playControlParams'} = {xmlbrowserPlayControl=>"$itemIndex"};
							}
						}
						else {
							$allTouchToPlay = 0;
						}
						
						my $itemActions = $item->{'itemActions'};
						if ($itemActions) {
							
							my $actions;
							if (!$itemActions->{'allAvailableActionsDefined'}) {
								$actions = $hash{'actions'};
							}
							$actions ||= {};
							
							my $n = 0;
							
							if (my $action = _makeAction($itemActions, 'info', undef, 1, 1)) {
								$actions->{'more'} = $action; $n++;
							}
							
							# Need to be careful not to undo (effectively) a 'go' action mapping
							# (could also consider other mappings but do not curretly)
							my $goAction = $hash{'goAction'};

							if (my $action = _makeAction($itemActions, 'items', undef, 1, 0, $item->{nextWindow})) {
								# If 'go' is already mapped to something else (probably 'play')
								# then leave it alone.
								unless ($goAction) {
									$actions->{'go'} = $action; $n++;
								}
							}
							if (my $action = _makeAction($itemActions, 'play', undef, 1, 0, 'nowPlaying')) {
								$actions->{'play'} = $action; $n++;
								
								# This test should really be repeated for all the other actions,
								# in case 'go' is mapped to one of them, but that does not actually
								# happen (would have to be somewhere in this module)
								if ($goAction && $goAction eq 'play') {
									$actions->{'go'} = $action;
								}
							}

							if (my $action = _makeAction($itemActions, 'add', undef, 1)) {
								$actions->{'add'} = $action; $n++;
							}
							if (my $action = _makeAction($itemActions, 'insert', undef, 1)) {
								$actions->{'add-hold'} = $action; $n++;
							}
							$hash{'actions'} = $actions;
							
							if ($n >= 5) {
								$itemActions->{'allAvailableActionsDefined'} = 1;
							}
						}

						if (!$itemActions->{'allAvailableActionsDefined'} && %actionParamsNeeded) {
							foreach my $key (keys %actionParamsNeeded) {
								my %params;
								my @vars = @{$actionParamsNeeded{$key}};
								for (my $i = 0; $i < scalar @vars; $i += 2) {
									$params{$vars[$i]} = $item->{$vars[$i+1]};
								}
								$hash{$key} = \%params;
							}
						}
						
						if (   !$itemActions->{'allAvailableActionsDefined'}
							&& !$feedActions->{'allAvailableActionsDefined'}
							&& scalar keys %{$itemParams} && ($isPlayable || $touchToPlay) )
						{
							$hash{'params'} = $itemParams;
						}
						
						if ( $item->{jive} ) {
							my $actions = $hash{'actions'} || {};
							while (my($name, $action) = each(%{$item->{jive}->{actions} || {}})) {
								$actions->{$name} = $action;
							}
							$hash{'actions'} = $actions;
							
							for my $key ('window', 'showBigArtwork', 'style', 'nextWindow') {
								if ( $item->{jive}->{$key} ) {
									$hash{$key} = $item->{jive}->{$key};
								}
							}
							
							$hash{'icon-id'} = proxiedImage($item->{jive}->{'icon-id'}) if $item->{jive}->{'icon-id'};
						}
						
						if (exists $hash{'actions'} && scalar keys %{$hash{'actions'}}) {
							delete $hash{'action'};
							delete $hash{'style'} if $hash{'style'} && $hash{'style'} eq 'itemNoAction';
						}
						
						$hash{'textkey'} = $item->{textkey} if defined $item->{textkey};
						
						$request->setResultLoopHash($loopname, $cnt, \%hash);

					}
					else {
						# create an ordered hash to store this stuff...
						tie my %hash, "Tie::IxHash";
						
						$hash{id}    = $id;
						$hash{name}  = $name          if defined $name;
						$hash{type}  = $item->{type}  if defined $item->{type};
						$hash{title} = $item->{title} if defined $item->{title};
						$hash{image} = proxiedImage($item->{image}) if defined $item->{image};

						# add url entries if requested unless they are coderefs as this breaks serialisation
						if ($want_url && defined $item->{url} && (!ref $item->{url} || ref $item->{url} ne 'CODE')) {
							$hash{url} = $item->{url};
						}	

						$hash{isaudio} = defined(hasAudio($item)) + 0;
						
						# Bug 7684, set hasitems to 1 if any of the following are true:
						# type is not text or audio
						# items array contains items
						{
							my $hasItems = 0;
							
							if ( !defined $item->{type} || $item->{type} !~ /^(?:text|audio)$/i ) {
								$hasItems = 1;
							}
							elsif ( ref $item->{items} eq 'ARRAY' ) {
								$hasItems = scalar @{ $item->{items} };
							}
							
							$hash{hasitems} = $hasItems;
						}
					
						$request->setResultLoopHash($loopname, $cnt, \%hash);
					}
					$cnt++;
				}
			}

		}

		$request->addResult('count', $totalCount);
		
		if ($menuMode) {
			
			if ($request->getResult('base')) {
				my $baseActions = $request->getResult('base')->{'actions'};
				
				_jivePresetBase($baseActions) if $presetFavSet;
				
				if ($allTouchToPlay) {
					$baseActions->{'go'} = $defeatDestructiveTouchToPlay ? $baseActions->{'playControl'} : $baseActions->{'play'};
				}
			}
			
			if ( $windowStyle ) {
				$window->{'windowStyle'} = $windowStyle;
			} 
			elsif ( $hasImage ) {
				$window->{'windowStyle'} = 'home_menu';
			} 
			else {
				$window->{'windowStyle'} = 'text_list';
			}
			
			# Bug 13247, support windowId param
			if ( $subFeed->{windowId} ) {
				$window->{windowId} = $subFeed->{windowId};
			}

			# send any window parameters we've gathered, if we've gathered any
			if ($window) {
				$request->addResult('window', $window );
			}

			# cache SBC queries for "Recent Search" menu
			if ($search && ($request->getParam('cachesearch') || $subFeed->{'cachesearch'})) {	# Bug 13044, allow some searches to not be cached
				
				# XXX this is probably obsolete because of move to myapps
				# make a best effort to make a labeled title for the search
				my $queryTypes = {
					rhapsodydirect	=>	'PLUGIN_RHAPSODY_DIRECT_MODULE_NAME',
					mp3tunes	=>	'PLUGIN_MP3TUNES_MODULE_NAME',
					radiotime	=>	'PLUGIN_RADIOTIME_MODULE_NAME',
					slacker		=>	'PLUGIN_SLACKER_MODULE_NAME',
					live365		=>	'PLUGIN_LIVE365_MODULE_NAME',
					lma		=>	'PLUGIN_LMA_MODULE_NAME',
				};
				
				my $title = $search;
				
				if ($queryTypes->{$query}) {
					$title = $request->string($queryTypes->{$query}) . ": " . $title;
				} elsif (my $key = $subFeed->{'cachesearch'}) {
					if (length($key) > 1) {
						$key = $request->string($key) if (uc($key) eq $key);
						$title = $key . ': ' . $title;
					}
				}
		
				my $queryParams = $feed->{'query'} || {};
				my $jiveSearchCache = {
					text     => $title,
					actions  => {
						go => {
							player => 0,
							cmd => [ $query, 'items' ],
							params => {
								'item_id' => $request->getParam('item_id'),
								menu      => $query,
								search    => $search,
								%$queryParams,
							},
						},
					},
				};
				
				Slim::Control::Jive::cacheSearch($request, $jiveSearchCache);
			}
			
		}

	} # ENDIF $isItemQuery
	
	$request->setStatusDone();
}


# Fetch a feed URL that is referenced within another feed.
# After fetching, insert the contents into the original feed
sub _cliQuerySubFeed_done {
	my ( $feed, $params ) = @_;
	
	# If there's a command we need to run, run it.  This is used in various
	# places to trigger actions from an OPML result, such as to start playing
	# a new Pandora radio station
	if ( $feed->{command} ) {
		
		my @p = map { uri_unescape($_) } split / /, $feed->{command};
		my $client = $params->{request}->client();
		
		if ($client) {
			main::DEBUGLOG && $log->is_debug && $log->debug( "Executing command: " . Data::Dump::dump(\@p) );
			$client->execute( \@p );
		} else {
			$log->error('No client to execute command for.');
		}
	}
	
	# insert the sub-feed data into the original feed
	my $parent = $params->{'parent'};
	my $subFeed = $parent;
	
	for my $i ( @{ $params->{'currentIndex'} } ) {
		# Skip sid and sid + top-level search query
		next if length($i) >= 8 && $i =~ /^[a-f0-9]{8}/;
		
		# If an index contains a search query, strip it out
		$i =~ s/_.+$//g;
		
		$subFeed = $subFeed->{'items'}->[$i - ($subFeed->{'offset'} || 0)];
	}

	if (($subFeed->{'type'} && $subFeed->{'type'} eq 'replace' || $feed->{'replaceparent'}) && 
		$feed->{'items'} && scalar @{$feed->{'items'}} == 1) {
		# if child has 1 item and requests, update previous entry to avoid new menu level
		delete $subFeed->{'url'};
		my $item = $feed->{'items'}[0];
		for my $key (keys %$item) {
			$subFeed->{ $key } = $item->{ $key };
		}
	} 
	else {
		# otherwise insert items as subfeed
		$subFeed->{'items'} = $feed->{'items'};
	}

	$subFeed->{'fetched'} = 1;
	
	# Pass-through forceRefresh flag
	if ( $feed->{forceRefresh} ) {
		$subFeed->{forceRefresh} = 1;
	}
	
	# Support alternate title if it's different from this menu in the parent
	if ( $feed->{title} && $subFeed->{name} ne $feed->{title} ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("menu title was '" . $subFeed->{name} . "', changing to '" . $feed->{title} . "'");
		$subFeed->{title} = $feed->{title};
	}
	if ($feed->{'actions'}) {
		$subFeed->{'actions'} = $feed->{'actions'};
	}
	$subFeed->{'total'} = $feed->{'total'};
	$subFeed->{'offset'} = $feed->{'offset'};
	$subFeed->{'menuComplete'} = $feed->{'menuComplete'};
	
	# Mark this as coming from subFeed, so that we know to ignore forceRefresh
	$params->{fromSubFeed} = 1;

	# cachetime will only be set by parsers which know their content is dynamic
	if (defined $feed->{'cachetime'}) {
		$parent->{'cachetime'} = min( $parent->{'cachetime'} || CACHE_TIME, $feed->{'cachetime'} );
	}
			
	_cliQuery_done( $parent, $params );
}

sub _addingToPlaylist {
	my $client = shift;
	my $action = shift || 'add';
	my $title  = shift;
	my $icon   = shift;

	my $string = $action eq 'add'
		? $client->string('ADDING_TO_PLAYLIST')
		: $client->string('INSERT_TO_PLAYLIST');

	my $jivestring = $action eq 'add' 
		? $client->string('JIVE_POPUP_ADDING')
		: $client->string('JIVE_POPUP_TO_PLAY_NEXT');

	$client->showBriefly( { 
		line => [ $string ],
		jive => {
			type => 'mixed',
			text => [ $jivestring, $title ],
			style => 'add',
			'icon-id' => defined $icon ? proxiedImage($icon) : '/html/images/cover.png',
		},
	} );
}

sub findAction {
	my ($feed, $item, $actionName) = @_;
	
	if ($item && $item->{'itemActions'} && $item->{'itemActions'}->{$actionName}) {
		return wantarray ? ($item->{'itemActions'}->{$actionName}, {}) : $item->{'itemActions'}->{$actionName};
	}
	if ($item && $item->{'itemActions'} && $item->{'itemActions'}->{'allAvailableActionsDefined'}) {
		return wantarray ? () : undef;
	}
	if ($feed && $feed->{'actions'} && $feed->{'actions'}->{$actionName}) {
		return wantarray ? ($feed->{'actions'}->{$actionName}, $feed->{'actions'}) : $feed->{'actions'}->{$actionName};
	}
	return wantarray ? () : undef;
}

sub _makePlayAction {
	my ($subFeed, $item, $name, $nextWindow, $query, $mode, $item_id, $playIndex) = @_;
	
	my %params;
	my $cmd;
	
	if (my ($feedAction, $feedActions) = findAction($subFeed, $item, $name)) {
		%params = %{$feedAction->{'fixedParams'}} if $feedAction->{'fixedParams'};
		my @vars = exists $feedAction->{'variables'} ? @{$feedAction->{'variables'}} : @{$feedActions->{'commonVariables'} || []};
		for (my $i = 0; $i < scalar @vars; $i += 2) {
			$params{$vars[$i]} = $item->{$vars[$i+1]};
		}

		$cmd = $feedAction->{'command'};
	} else {
		%params = (
			'item_id' => $item_id,
		);
		$params{'playIndex'} = $playIndex if defined $playIndex;
		$params{'mode'}      = $mode if defined $mode;
		
		$cmd = [ $query, 'playlist', $name ],
	}
	
	if ($cmd) {
		$params{'menu'} = 1;

		my %action = (
			player      => 0,
			cmd         => $cmd,
			params      => \%params,
		);
		$action{'nextWindow'} = $nextWindow if $nextWindow;
		
		return \%action;
	}
	
	return undef;
}

sub _makeAction {
	my ($actions, $actionName, $actionParamsNeeded, $player, $contextMenu, $nextWindow) = @_;
	
	if (my $action = $actions->{$actionName}) {
		if ( !($action->{'command'} && scalar @{$action->{'command'}}) ) {
			return 'none';
		}
	
		my $params = $action->{'fixedParams'} || {};
		$params->{'menu'} ||= 1;
		
		my %action = (
			cmd         => $action->{'command'},
			params      => $params,
		);
		
		$action{'player'} ||= 0 if $player;
		$action{'window'} = {isContextMenu => 1} if $contextMenu;
		$action{'nextWindow'} = $nextWindow if $nextWindow;
		if (defined $actionParamsNeeded) {
			if (exists $action->{'variables'}) {
				if ($action->{'variables'}) {
					$action{'itemsParams'} = $actionName . 'Params';
					$actionParamsNeeded->{$action{'itemsParams'}} = $action->{'variables'};
				}
			} elsif ($actions->{'commonVariables'}) {
				$action{'itemsParams'} = 'commonParams';
				$actionParamsNeeded->{$action{'itemsParams'}} = $actions->{'commonVariables'};
			}
		}
		return \%action;
	}
}

sub _cliQuery_error {
	my ( $err, $params ) = @_;
	
	my $request = $params->{'request'};
	my $url     = $params->{'url'};
	
	logError("While retrieving [$url]: [$err]");
	
	$request->addResult("networkerror", $err);
	$request->addResult('count', 0);

	$request->setStatusDone();	
}

# fix the count in case we're adding additional items
# (play all) to the resultset
sub _fixCount {
	my $insertItem = shift;
	my $index      = shift;
	my $quantity   = shift;
	my $count      = shift;

	my $totalCount = $count || 0;

	if ($insertItem) {
		$totalCount++;
		if ($count) {
			if (!$$index && $count == $$quantity) {
				# count and qty are the same, don't do anything to index or quantity
			# return one less result as we only add the additional item in the first chunk
			} elsif ( !$$index ) {
				$$quantity--;
			# decrease the index in subsequent queries
			} else {
				$$index--;
			}
		}
	}

	return $totalCount;
}

sub hasAudio {
	my $item = shift;
	
	if ( $item->{'play'} ) {
		return $item->{'play'};
	}
	elsif ( $item->{'type'} && $item->{'type'} =~ /^(?:audio|playlist)$/ ) {
		return $item->{'playlist'} || $item->{'url'} || scalar @{ $item->{outline} || [] };
	}
	elsif ( $item->{'enclosure'} && $item->{'enclosure'}->{'type'} && ( $item->{'enclosure'}->{'type'} =~ /audio/ ) ) {
		return $item->{'enclosure'}->{'url'};
	}
	else {
		return undef;
	}
}

sub touchToPlay {
	my $item = shift;
	
	if ( $item->{'type'} && $item->{'type'} =~ /^(?:audio)$/ ) {
		return 1;
	}
	elsif ( $item->{'on_select'} && $item->{'on_select'} eq 'play' ) {
		return 1;
	}
	elsif ( $item->{'enclosure'} && ( $item->{'enclosure'}->{'type'} =~ /audio/ ) ) {
		return 1;
	}

	return;
}

sub hasLink {
	my $item = shift;

	# for now, only follow link in "slim" namespace
	return $item->{'slim:link'};
}

sub hasDescription {
	my $item = shift;

	my $description = $item->{'description'} || $item->{'name'};

	if ($description and !ref($description)) {

		return $description;

	} else {

		return undef;
	}
}

sub _jivePresetBase {
	my $actions = shift;
	for my $preset (0..9) {
		my $key = 'set-preset-' . $preset;
		$actions->{$key} = {
			player => 0,
			cmd    => [ 'jivefavorites', 'set_preset', "key:$preset" ],
			itemsParams => 'presetParams',
		};
	}
	return $actions;
}

sub _playlistControlContextMenu {

	my $args    = shift;
	my $query   = $args->{'query'};
	my $request = $args->{'request'};
	my $item    = $args->{'item'};

	my @contextMenu;

	my $canIcons = $request && $request->client && ($request->client->revision !~ /^7\.[0-7]/);
	
	# We only add playlist-control items for an item which is playable
	if (hasAudio($item)) {
		my $item_id = $args->{item_id} || $request->getParam('item_id') || '';
		my $mode    = $request->getParam('mode');
		my $sub_id  = $args->{'subItemId'};
		my $subFeed = $args->{'subFeed'};
		
		if (defined $sub_id) {
			$item_id .= '.' if length($item_id);
			$item_id .= $sub_id;
		}
		
		my $itemParams = {
			menu    => $request->getParam('menu'),
			item_id => $item_id,
		};
		
		my $addPlayAll = (
			   $args->{'playalbum'}
			&& defined $sub_id
			&& $subFeed && scalar @{$subFeed->{'items'} || []} > 1
			&& ($subFeed->{'playall'} || $item->{'playall'})
		);
		
		my $action;
		
		if ($action = _makePlayAction($subFeed, $item, 'add', 'parentNoRefresh', $query, $mode, $item_id)) {
			push @contextMenu, {
				text => $request->string('ADD_TO_END'),
				style => 'item_add',
				actions => {go => $action},
			},
		}
		
		if ($action = _makePlayAction($subFeed, $item, 'insert', 'parentNoRefresh', $query, $mode, $item_id)) {
			push @contextMenu, {
				text => $request->string('PLAY_NEXT'),
				style => $canIcons ? 'item_insert' : 'itemNoAction',
				actions => {go => $action},
			},
		}
		
		if ($action = _makePlayAction($subFeed, $item, 'play', 'nowPlaying', $query, $mode, $item_id)) {
			push @contextMenu, {
				text => $request->string($addPlayAll ? 'PLAY_THIS_SONG' : 'PLAY'),
				style => 'item_play',
				actions => {go => $action},
			},
		}
		
		if ($addPlayAll && ($action = _makePlayAction($subFeed, $item, 'playall', 'nowPlaying', $query, $mode, $args->{item_id} || $request->getParam('item_id'), $sub_id))) {
			push @contextMenu, {
				text => $request->string('JIVE_PLAY_ALL_SONGS'),
				style => $canIcons ? 'item_playall' : 'itemNoAction',
				actions => {go => $action},
			},
		}
	}

	# Favorites handling
	my $favParams;
	if (($favParams = _favoritesParams($item)) && !$args->{'noFavorites'}) {
	
		my $action = 'add';
	 	my $favIndex = undef;
		my $token = 'JIVE_SAVE_TO_FAVORITES';
		if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::Favorites::Plugin') ) {
			my $favs = Slim::Utils::Favorites->new($request->client);
			$favIndex = $favs->findUrl($favParams->{favorites_url});
			if (defined($favIndex)) {
				$action = 'delete';
				$token = 'JIVE_DELETE_FROM_FAVORITES';
			}
		}
		
		my $favoriteActions = {
			'go' => {
				player => 0,
				cmd    => [ 'jivefavorites', $action ],
				params => {
					title   => $favParams->{'favorites_title'},
					url     => $favParams->{'favorites_url'},
					type    => $favParams->{'favorites_type'},
					parser  => $favParams->{'parser'},
					isContextMenu => 1,
				},
			},
		};
		$favoriteActions->{'go'}{'params'}{'item_id'} = "$favIndex" if defined($favIndex);
		if (my $icon = $favParams->{'icon'} || $request->getParam('icon')) {
			$favoriteActions->{'go'}{'params'}{'icon'} = $icon;
		}
	
		push @contextMenu, {
			text => $request->string($token),
			style => $canIcons ? 'item_fav' : 'itemNoAction',
			actions => $favoriteActions,
		};
	}

	return \@contextMenu;
}

sub _favoritesParams {
	my $item = shift;
	
	my $favorites_url    = $item->{favorites_url} || $item->{play} || $item->{url};
	my $favorites_title  = $item->{title} || $item->{name};
	
	if ( $favorites_url && !ref $favorites_url && $favorites_title ) {
		if ( !$item->{favorites_url} && $item->{type} && $item->{type} eq 'playlist' && $item->{playlist} && !ref $item->{playlist}) {
			$favorites_url = $item->{playlist};
		}
		
		my %presetParams = (
			favorites_url   => $favorites_url,
			favorites_title => $favorites_title,
			favorites_type  => $item->{favorites_type} || ($item->{play} ? 'audio' : ($item->{type} || 'audio')),
		);
		$presetParams{'parser'} = $item->{'parser'} if $item->{'parser'};
		
		if (my $icon = $item->{'image'} || $item->{'icon'} || $item->{'cover'}) {
			$presetParams{'icon'} = proxiedImage($icon);
		}
		
		return \%presetParams;
	}
}

sub _defeatDestructiveTouchToPlay {
	my ($request, $client) = @_;
	my $pref;
	
	if ($client && (my $agent = $client->controllerUA)) {
		if ($agent =~ /squeezeplay/i) {
			my ($version, $revision) = ($agent =~ m%/(\d+(?:\.\d+)?)[.\d]*-r(\d+)%);
			
			return 0 if $version < 7.6;
			return 0 if $version eq '7.6' && $revision < 9337;
		}
	}
	
	$pref = $request->getParam('defeatDestructiveTouchToPlay');
	$pref = $prefs->client($client)->get('defeatDestructiveTouchToPlay') if $client && !defined $pref;
	$pref = $prefs->get('defeatDestructiveTouchToPlay') if !defined $pref;
	
	# Values:
	# 0 => no defeat
	# 1 => always defeat
	# 2 => defeat if playlist length > 1
	# 3 => defeat only if playing and current-playlist-length > 1
	# 4 => defeat only if playing and current item not a radio stream
	
	return 0 if !$pref;
	return 1 if $pref == 1 || !$client;
	return ($client->isPlaying() && $client->playingSong()->duration() && !$client->playingSong()->isPlaylist()) if $pref == 4;
	my $l = Slim::Player::Playlist::count($client);
	return 0 if $l < 2;
	return 0 if $pref == 3 && (!$client->isPlaying() || $l < 2);
	
	return 1;
}

# a name can be '0' (zero) - don't blank it
sub getTitle {
	my ($name, $item) = @_;

	my $nameOrTitle = $name;
	$nameOrTitle    = $item->{title} if !defined $nameOrTitle || $nameOrTitle eq '';
	$nameOrTitle    = '' if !defined $nameOrTitle;
	
	return $nameOrTitle;
}


1;

