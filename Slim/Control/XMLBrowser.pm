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
#use Slim::Utils::Timers;

use constant CACHE_TIME => 3600; # how long to cache browse sessions

my $log = logger('formats.xml');
my $prefs = preferences('server');

sub cliQuery {
	my ( $query, $feed, $request, $expires, $forceTitle ) = @_;

	main::INFOLOG && $log->info("cliQuery($query)");

	# check this is the correct query.
	if ($request->isNotQuery([[$query], ['items', 'playlist']])) {
		$request->setStatusBadDispatch();
		return;
	}

	$request->setStatusProcessing();
	
	my $itemId     = $request->getParam('item_id');	# get our parameters
	my $index      = $request->getParam('_index');
	my $quantity   = $request->getParam('_quantity');

	# Bug 14100: sending requests that involve newWindow param from SP side results in no
	# _index _quantity args being sent, but XML Browser actually needs them, so they need to be hacked in
	# here and the tagged params mistakenly put in _index and _quantity need to be re-added
	# to the $request params
	if ( $index =~ /:/ ) {
		$request->addParam(split (/:/, $index));
		$index = 0;
		$request->addParam('_index', $index);
	}
	if ( $quantity =~ /:/ ) {
		$request->addParam(split(/:/, $quantity));
		$quantity = 200;
		$request->addParam('_quantity', $quantity);
	}
	
	my $isPlayCommand = $request->isQuery([[$query], ['playlist']]);
	
	# Handle touch-to-play
	if ($request->getParam('touchToPlay') && !$request->getParam('xmlBrowseInterimCM')) {

		$isPlayCommand = 1;
		
		# A hack to handle clients that cannot map the 'go' action
		if (!$request->getParam('_method')) {
			$request->addParam('_method', 'play');
			$request->addResult('goNow', 'nowPlaying');
		}
		
		my $playalbum = undef;
		if ( $request->client ) {
			$playalbum = $prefs->client($request->client)->get('playtrackalbum');
		}
	
		# if player pref for playtrack album is not set, get the old server pref.
		if ( !defined $playalbum ) {
			$playalbum = $prefs->get('playtrackalbum');
		}
		
		if ($playalbum) {
			$itemId =~ s/(.*)\.(\d+)/$1/;			# strip off last node
			$request->addParam('playIndex', $2);	# and save in playIndex
			$request->addParam('item_id', $itemId);
		}
		
	}
	
	# cache SBC queries for "Recent Search" menu
	if (
		   $request->isQuery([[$query], ['items']]) 
		&& defined($request->getParam('menu')) 
		&& defined($request->getParam('search'))
		&& $request->getParam('cachesearch') # Bug 13044, allow some searches to not be cached
	) {
		
		# make a best effort to make a labeled title for the search
		my $queryTypes = {
			rhapsodydirect	=>	'PLUGIN_RHAPSODY_DIRECT_MODULE_NAME',
			mp3tunes	=>	'PLUGIN_MP3TUNES_MODULE_NAME',
			radiotime	=>	'PLUGIN_RADIOTIME_MODULE_NAME',
			slacker		=>	'PLUGIN_SLACKER_MODULE_NAME',
			live365		=>	'PLUGIN_LIVE365_MODULE_NAME',
			lma		=>	'PLUGIN_LMA_MODULE_NAME',
		};
		
		my $title = $request->getParam('search');
		
		if ($queryTypes->{$query}) {
			$title = $request->string($queryTypes->{$query}) . ": " . $title;
		}

		my $jiveSearchCache = {
			text     => $title,
			actions  => {
				go => {
					player => 0,
					cmd => [ $query, 'items' ],
					params => {
						'item_id' => $request->getParam('item_id'),
						menu      => $query,
						search    => $request->getParam('search'),
					},
				},
			},
		};
		
		Slim::Control::Jive::cacheSearch($request, $jiveSearchCache);
	}

	my $playlistControlCM = [];
	
	# Bug 15824-- push playlist control items for favorites item CMs
	# note: making the judgment to put the playlistControl items in a CM by looking if the command is not '*info' is a hack
	# 	*info menus need to not get these items though, since they deliver them through their own menus
	my $localMusicInfoRequest = $request->getRequest(0) =~ /info$/;
	if ( defined($request->getParam('xmlBrowseInterimCM')) && !$localMusicInfoRequest ) {
		$playlistControlCM = _playlistControlContextMenu({ request => $request, query => $query });
	}
	
	my %args = (
		'request' => $request,
		'client'  => $request->client,
		'url'     => $feed,
		'query'   => $query,
		'expires' => $expires,
		'playlistControlCM' => $playlistControlCM,
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
		
		my %args = (params => $request->getParamsCopy());

		# If we are getting an intermediate level, then we just need the one item
		# If we are getting the last level then we need all items if we are doing playall of some kind
		
		my $levels = 0;
		my $nextIndex;
		if ( defined $itemId && length($itemId) ) {
			my @index = split(/\./, $itemId);
			$levels = scalar @index;
			$nextIndex = $index[0] =~ /^(\d+)/;
		}
		
		if ($index && $quantity && !$levels && !$isPlayCommand) {
			
			# XXX hack to allow for some CM entries
			my $j = 10; 
			$j = $index if ($j > $index);
			$args{'index'} = $index - $j;
			$args{'quantity'} = $quantity + $j;
		} elsif ($levels) {
			$args{'index'} = $nextIndex;
			$args{'quantity'} = 1;
		}
		
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			my $cbname = Slim::Utils::PerlRunTime::realNameForCodeRef( $feed );
			$log->debug( "Fetching OPML from coderef $cbname" );
		}

		$feed->( $request->client, $callback, \%args);
		
		return;
	}

	
	
	
	if ( $feed =~ /{QUERY}/ ) {
		# Support top-level search
		my $query = $request->getParam('search');
		
		if ( !$query ) {
			($query) = $itemId =~ m/^_([^.]+)/;
		}
		
		$feed =~ s/{QUERY}/$query/g;
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
			return sprintf('%s: %s:%02s', int($value / 60), $value % 60);
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
	my $playlistControlCM = $params->{'playlistControlCM'} || [];
#	my $forceTitle = $params->{'forceTitle'};
	my $window;
	
	main::INFOLOG && $log->info("_cliQuery_done(): ", $request->getRequestString());

	my $cache = Slim::Utils::Cache->new;

	my $isItemQuery = my $isPlaylistCmd = 0;
	
	if ($request->isQuery([[$query], ['playlist']])) {
		$isPlaylistCmd = 1;
	}
	elsif ($request->isQuery([[$query], ['items']])) {
		if ($request->getParam('touchToPlay') && !$request->getParam('xmlBrowseInterimCM')) {
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
	
#	warn Data::Dump::dump($feed) . "\n";

	my @crumbIndex = $sid ? ( $sid ) : ();
	
	# Add top-level search to index
	if ( $search && !scalar @index ) {
		if ( $sid ) {
			@crumbIndex = ( $sid . '_' . uri_escape_utf8( $search, "^A-Za-z0-9" ) );
		}
		else {
			@crumbIndex = ( '_' . uri_escape_utf8( $search, "^A-Za-z0-9" ) );
		}
	}
	
	if ( $sid ) {
		# Cache the feed structure for this session

		# cachetime is only set by parsers which known the content is dynamic and so can't be cached
		# for all other cases we always cache for CACHE_TIME to ensure the menu stays the same throughout the session
		my $cachetime = defined $feed->{'cachetime'} ? $feed->{'cachetime'} : CACHE_TIME;

		main::DEBUGLOG && $log->is_debug && $log->debug( "Caching session $sid for $cachetime" );
		
		eval { $cache->set( "xmlbrowser_$sid", $feed, $cachetime ) };

		if ( $@ && $log->is_debug ) {
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
			# Add search query to crumb list
			if ( $subFeed->{type} && $subFeed->{type} eq 'search' && $search ) {
				# Escape periods in the search string
				push @crumbIndex, $i . '_' . uri_escape_utf8( $search, "^A-Za-z0-9" );
			}
			else {
				push @crumbIndex, $i;
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
			if ( (!$subFeed->{'type'} || ($subFeed->{'type'} ne 'audio')) && defined $subFeed->{'url'} && !$subFeed->{'fetched'} ) {
				
				if ( $i =~ /(?:\d+)?_(.+)/ ) {
					$search = uri_unescape($1);
				}
				
				# Rewrite the URL if it was a search request
				if ( $subFeed->{type} && $subFeed->{type} eq 'search' ) {
					$subFeed->{url} =~ s/{QUERY}/$search/g;
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
					'client'       => $request->client,
					'query'        => $query,
					'expires'      => $params->{'expires'},
					'timeout'      => $params->{'timeout'},
					'playlistControlCM' => $playlistControlCM,
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
					my %args = (params => $feed->{'query'});
					
					if ($search && $subFeed->{type} && $subFeed->{type} eq 'search') {
						$args{'search'} = $search;
					}
					
					# If we are getting an intermediate level, then we just need the one item
					# If we are getting the last level then we need all items if we are doing playall of some kind
					
					if ($index && $quantity && $depth == $levels && !$isPlaylistCmd) {
						
						# XXX hack to allow for some CM entries
						my $j = 10; 
						$j = $index if ($j > $index);
						$args{'index'} = $index - $j;
						$args{'quantity'} = $quantity + $j;
					} elsif ($depth < $levels) {
						$args{'index'} = $index[$depth];
						$args{'quantity'} = 1;
					}
					
					if ( main::DEBUGLOG && $log->is_debug ) {
						my $cbname = Slim::Utils::PerlRunTime::realNameForCodeRef( $subFeed->{url} );
						$log->debug( "Fetching OPML from coderef $cbname" );
					}

					$subFeed->{url}->( $request->client, $callback, \%args, @{$pt});
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
						$subFeed->{'description'}	
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

					# decide what is the next step down
					# generally, we go nowhere after this, so we get menu:nowhere...
					# build the base element
					my $base = {
						'actions' => {
							# no go, we ain't going anywhere!
					
							# we play/add the current track id
							'play' => {
								'player' => 0,
								'cmd' => [$query, 'playlist', 'play'],
								'params' => {
									'item_id' => "$item_id", # stringify for JSON
								},
								'nextWindow' => 'nowPlaying',
							},
							'add' => {
								'player' => 0,
								'cmd' => [$query, 'playlist', 'add'],
								'params' => {
									'item_id' => "$item_id", # stringify for JSON
								},
							},
							'add-hold' => {
								'player' => 0,
								'cmd' => [$query, 'playlist', 'insert'],
								'params' => {
									'item_id' => "$item_id", # stringify for JSON
								},
							},
						},
					};
					$request->addResult('base', $base);
					
					for my $eachmenu (@$playlistControlCM) {
						main::INFOLOG && $log->info("adding playlist Control CM item $cnt");
						$request->setResultLoopHash('item_loop', $cnt, $eachmenu);
						$cnt++;
					}
				} # $menuMode
				
				else {
					$request->addResult('count', 1);
				}
				
				if ($valid) {
					
					my $loopname = $menuMode ? 'item_loop' : 'loop_loop';
					$request->addResult('offset', $start) if $menuMode;

					# create an ordered hash to store this stuff...
					tie (my %hash, "Tie::IxHash");

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
						
						# setup hash for different items between play and add
						my %modeitems = (
							'play' => {
								'string'  => $request->string('PLAY'),
								'style'   => 'itemplay',
								'cmd'     => 'play',
							},
							'add' => {
								'string'  => $request->string('ADD'),
								'style'   => 'itemadd',
								'cmd'     => 'add',
							},
						);
						
						if (! defined($request->getParam('xmlBrowseInterimCM')) ) {
							for my $mode ( 'play', 'add' ) {
								my $actions = {
									'do' => {
										'player' => 0,
										'cmd'    => [$query, 'playlist', $modeitems{$mode}->{'cmd'}],
										'params' => {
											'item_id' => "$item_id", # stringify for JSON
										},
										'nextWindow' => 'parent',
									},
									'play' => {
										'player' => 0,
										'cmd'    => [$query, 'playlist', $modeitems{$mode}->{'cmd'}],
										'params' => {
											'item_id' => "$item_id", # stringify for JSON
										},
									},
									# add always adds
									'add' => {
										'player' => 0,
										'cmd'    => [$query, 'playlist', 'add'],
										'params' => {
											'item_id' => "$item_id", # stringify for JSON
										},
									},
									'add-hold' => {
										'player' => 0,
										'cmd'    => [$query, 'playlist', 'insert'],
										'params' => {
											'item_id' => "$item_id", # stringify for JSON
										},
									},
								};
								$request->addResultLoop($loopname, $cnt, 'text', $modeitems{$mode}{'string'});
								$request->addResultLoop($loopname, $cnt, 'actions', $actions);
								$request->addResultLoop($loopname, $cnt, 'style', $modeitems{$mode}{'style'});
								$cnt++;
							}
						}
						
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
						
						if (! defined($request->getParam('xmlBrowseInterimCM')) ) {
							if ( my ($url, $title) = ($hash{url}, $hash{name}) ) {
								# first see if $url is already a favorite
								my $action = 'add';
	 							my $favIndex = undef;
								my $token = 'JIVE_SAVE_TO_FAVORITES';
								if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::Favorites::Plugin') ) {
									my $favs = Slim::Utils::Favorites->new($request->client);
									$favIndex = $favs->findUrl($url);
									if (defined($favIndex)) {
										$action = 'delete';
										$token = 'JIVE_DELETE_FROM_FAVORITES';
									}
								}
								my $actions = {
									'go' => {
										player => 0,
										cmd    => [ 'jivefavorites', $action ],
										params => {
											title   => $title,
											url     => $url,
											isContextMenu => 1,
										},
									},
								};
								$actions->{'go'}{'params'}{'icon'} = $hash{image} if defined($hash{image});
								$actions->{'go'}{'params'}{'item_id'} = "$favIndex" if defined($favIndex);
								my $string = $request->string($token);
								$request->addResultLoop($loopname, $cnt, 'text', $string);
								$request->addResultLoop($loopname, $cnt, 'actions', $actions);
								$request->addResultLoop($loopname, $cnt, 'style', 'item');
								$cnt++;
							}
						}

						$request->addResult('count', $cnt);
					} # $menuMode
					
					else {
						$request->setResultLoopHash($loopname, $cnt, \%hash);
					}
				}
				$request->setStatusDone();
				return;
			}
		}
	}
	
	if ($feedMode) {
		$request->setRawResults($feed);
		$request->setStatusDone();
		return;
	}
				
	if ($isPlaylistCmd) {

		# get our parameters
		my $client = $request->client();
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
					} );
				
					$client->execute([ 'playlist', $method, $url ]);
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
						$playIndex-- if defined($playIndex);
						next;
					}

					# Set metadata about this URL
					Slim::Music::Info::setRemoteMetadata( $url, {
						title   => $item->{'name'} || $item->{'title'},
						ct      => $item->{'mime'},
						secs    => $item->{'duration'},
						bitrate => $item->{'bitrate'},
					} );
					
					main::idleStreams();
					
					push @urls, $url;
				}
				
				if ( @urls ) {

					if ( $method =~ /play|load/i ) {
						$client->execute([ 'playlist', 'clear' ]);
					}

					my $cmd;
					if ($method =~ /add/) {
						$cmd = 'addtracks';
					}
					else {
						$cmd = 'inserttracks';
					}
		
					if ( main::INFOLOG && $log->is_info ) {
						$log->info(sprintf("Playing/adding all items:\n%s", join("\n", @urls)));
					}
	
					$client->execute([ 'playlist', $cmd, 'listref', \@urls ]);

					# if we're adding or inserting, show a showBriefly
					if ( $method =~ /add/ || $method eq 'insert' ) {
						my $icon = $request->getParam('icon');
						my $title = $request->getParam('favorites_title');
						_addingToPlaylist($client, $method, $title, $icon);
					# if not, we jump to the correct track in the list
					} else {
						$client->execute([ 'playlist', 'jump', ($playIndex || 0)]);
					}
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
		
		
		# Bug 7024, display an "Empty" item instead of returning an empty list
		if ( $menuMode && !$count ) {
			$items = [ { type => 'text', name => $request->string('EMPTY') } ];
			$count = 1;
		}
	
		# now build the result
	
		my $hasImage = 0;
		my $windowStyle;
		my $presetFavSet = 0;
		my $totalCount = $count;
		my $allTouchToPlay = 1;
		my %actionParamsNeeded;
		
		if ($count) {
		
			my $loopname = $menuMode ? 'item_loop' : 'loop_loop';
			my $cnt = 0;

			if ($menuMode) {

				$request->addResult('offset', $index);

				my $firstChunk = !$index;
				for my $eachmenu (@$playlistControlCM) {
					$totalCount = _fixCount(1, \$index, \$quantity, $totalCount);
					
					# Only add them the first time
					if ($firstChunk) {
						$request->setResultLoopHash('item_loop', $cnt, $eachmenu);
						$cnt++;
					}
				}
				
			}

			my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);
		
			if ($valid) {
				
				my $feedActions = $subFeed->{'actions'};
				
				if (my $title = $subFeed->{'name'} || $subFeed->{'title'}) {
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
						
						my $playalbum = undef;
						if ( $request->client ) {
							$playalbum = $prefs->client($request->client)->get('playtrackalbum');
						}
						# if player pref for playtrack album is not set, get the old server pref.
						if ( !defined $playalbum ) {
							$playalbum = $prefs->get('playtrackalbum');
						}
						
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
					
					$request->addResult('base', $base);
				}

				# If we have a slideshow param, return all items without chunking, and only
				# include image and caption data
				if ( $request->getParam('slideshow') ) {
					my $images = [];
					for my $item ( @$items ) {
						next unless $item->{image};
						push @{$images}, {
							image   => $item->{image},
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
				
				$start -= $subFeed->{'offset'};
				$end   -= $subFeed->{'offset'};
				main::DEBUGLOG && $log->is_debug && $log->debug("Getting slice $start..$end: $totalCount; offset=", $subFeed->{'offset'});
				
				for my $item ( @$items[$start..$end] ) {
					$itemIndex++;
					
					# create an ordered hash to store this stuff...
					tie my %hash, "Tie::IxHash";
					
					$hash{id}    = join('.', @crumbIndex, $itemIndex);
					$hash{name}  = $item->{name}  if defined $item->{name};
					$hash{name}  = $request->string($item->{'label'}) . $request->string('COLON') . ' ' .  $hash{'name'} if $hash{'name'} && defined $item->{'label'};
					$hash{type}  = $item->{type}  if defined $item->{type};
					$hash{title} = $item->{title} if defined $item->{title};
					$hash{url}   = $item->{url}   if $want_url && defined $item->{url};
					$hash{image} = $item->{image} if defined $item->{image};

					$hash{isaudio} = defined(hasAudio($item)) + 0;
					my $touchToPlay = defined(touchToPlay($item)) + 0;
					
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
					
					if ($menuMode) {
						# if showBriefly is 1, send the name as a showBriefly
						if ($item->{showBriefly} and ( $hash{name} || $hash{title} ) ) {
							$request->client->showBriefly({ 
										'jive' => {
											'type'    => 'popupplay',
											'text'    => [ $hash{name} || $hash{title} ],
										},
									});

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
						
						# Bug 7077, if the item will autoplay, it has an 'autoplays=1' attribute
						if ( $item->{autoplays} ) {
							$request->addResultLoop($loopname, $cnt, 'style', 'itemplay');
						}
						
						my $itemText = $hash{'name'} || $hash{'title'};
						if ($item->{'name2'}) {
							$itemText .= "\n" . $item->{'name2'};
							$windowStyle = 'icon_list' if !$windowStyle;
						}
						$request->addResultLoop($loopname, $cnt, 'text', $itemText);
						
						my $isPlayable = (
							   $item->{play} 
							|| $item->{playlist} 
							|| ($item->{type} && ($item->{type} eq 'audio' || $item->{type} eq 'playlist'))
						);
						
						my $itemParams = {};
						my $id = $hash{id};
						
						if ( !$item->{type} || $item->{type} ne 'text' ) {							
							$itemParams->{'item_id'} = "$id", #stringify, make sure it's a string
						}

						my $favorites_url    = $item->{favorites_url} || $item->{play} || $item->{url};
						my $favorites_title  = $item->{title} || $item->{name};
						
						if ( $favorites_url && !ref $favorites_url && $favorites_title ) {
							my $presetParams = {
								favorites_url   => $favorites_url,
								favorites_title => $favorites_title,
								favorites_type  => $item->{type} || 'audio',
							};
							
							if ( !$item->{favorites_url} && $item->{type} && $item->{type} eq 'playlist' && $item->{playlist} ) {
								$presetParams->{favorites_url} = $item->{playlist};
							}
							$presetParams->{parser} = $item->{parser} if $item->{parser};
							
							$request->addResultLoop( $loopname, $cnt, 'presetParams', $presetParams );
							$presetFavSet = 1;
						}

						if ( $isPlayable || $item->{isContextMenu} ) {
							$itemParams->{'isContextMenu'} = 1;
						}
						
						$itemParams->{'textkey'} = $item->{textkey} if defined $item->{textkey};

						my %merged = (%{$params}, %{$itemParams});

						if ( $item->{icon} ) {
							$request->addResultLoop( $loopname, $cnt, 'icon' . ($item->{icon} =~ /^http:/ ? '' : '-id'), $item->{icon} );
							$hasImage = 1;				
						} elsif ( $item->{image} ) {
							$request->addResultLoop( $loopname, $cnt, 'icon', $item->{image} );
							$hasImage = 1;
						}

						if ( $item->{type} && $item->{type} eq 'text' && !$item->{wrap} && !$item->{jive} ) {
							$request->addResultLoop( $loopname, $cnt, 'style', 'itemNoAction' );
							$request->addResultLoop( $loopname, $cnt, 'action', 'none' );
						}
						
						# Support type='db' for Track Info
						if ( $item->{jive} ) {
							$request->addResultLoop( $loopname, $cnt, 'actions', $item->{jive}->{actions} );
							for my $key ('window', 'showBigArtwork', 'style', 'nextWindow', 'playHoldAction', 'icon-id') {
								if ( $item->{jive}->{$key} ) {
									$request->addResultLoop( $loopname, $cnt, $key, $item->{jive}->{$key} );
								}
							}
							$allTouchToPlay = 0;
						}
						
						elsif ( $item->{type} && $item->{type} eq 'search' ) {
							#$itemParams->{search} = '__INPUT__';
							
							# XXX: bug in Jive, this should really be handled by the base go action
							my $actions = {
								go => {
									cmd    => [ $query, 'items' ],
									params => {
										item_id     => "$id",
										menu        => $query,
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
							
							$request->addResultLoop( $loopname, $cnt, 'actions', $actions );
							$request->addResultLoop( $loopname, $cnt, 'input', $input );
							if ($item->{nextWindow}) {
								$request->addResultLoop( $loopname, $cnt, 'nextWindow', $item->{nextWindow} );
							}
							$allTouchToPlay = 0;
						}
						elsif ( !$isPlayable && !$touchToPlay ) {
							
							# I think that doing is this way means that, because $itemParams does not get
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
									$request->addResultLoop( $loopname, $cnt, 'style', 'itemplay');
								}
							}
							$request->addResultLoop( $loopname, $cnt, 'actions', $actions );
							$request->addResultLoop( $loopname, $cnt, 'addAction', 'go');
							$allTouchToPlay = 0;
						}
						elsif ( $touchToPlay ) {
							
							# XXX need to redo the all-items logic
							# so can use playall/addall actions
							# need to add play_index item if missing for all-items
							# or something
							
							$itemParams->{'touchToPlay'} = "$id"; # stringify, make sure it's a string
							
							# XXX not currently supported by client
							$request->addResultLoop( $loopname, $cnt, 'goAction', 'play'); 
							
							$request->addResultLoop( $loopname, $cnt, 'style', 'itemplay');
						}
						else {
							$allTouchToPlay = 0;
						}
						
						my $itemActions = $item->{'itemActions'};
						if ($itemActions) {
							
							my $actions;
							if (!$itemActions->{'allAvailableActionsDefined'}) {
								$actions = $request->getResultLoop($loopname, $cnt, 'actions');
							}
							$actions ||= {};
							
							my $n = 0;
							
							if (my $action = _makeAction($itemActions, 'info', undef, 1, 1)) {
								$actions->{'more'} = $action; $n++;
							}
							if (my $action = _makeAction($itemActions, 'items', undef, 1)) {
								$actions->{'go'} = $action; $n++;
							}
							if (my $action = _makeAction($itemActions, 'play', undef, 1, 0, 'nowPlaying')) {
								$actions->{'play'} = $action; $n++;
							}
							if (my $action = _makeAction($itemActions, 'add', undef, 1)) {
								$actions->{'add'} = $action; $n++;
							}
							if (my $action = _makeAction($itemActions, 'insert', undef, 1)) {
								$actions->{'add-hold'} = $action; $n++;
							}
							$request->addResultLoop( $loopname, $cnt, 'actions', $actions );
							
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
								$request->addResultLoop( $loopname, $cnt, $key, \%params );
							}
						}
						
						if (   !$itemActions->{'allAvailableActionsDefined'}
							&& !$feedActions->{'allAvailableActionsDefined'}
							&& scalar keys %{$itemParams} && ($isPlayable || $touchToPlay) )
						{
							$request->addResultLoop( $loopname, $cnt, 'params', $itemParams );
						}
						
					}
					else {
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
				
				$baseActions->{'go'} = $baseActions->{'play'} if $allTouchToPlay;
			}
			
			if ( $windowStyle ) {
				$window->{'windowStyle'} = $windowStyle;
			} 
			elsif ( $hasImage ) {
				$window->{'windowStyle'} = 'icon_list';
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
		
		main::DEBUGLOG && $log->is_debug && $log->debug( "Executing command: " . Data::Dump::dump(\@p) );
		$client->execute( \@p );
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

	if ($subFeed->{'type'} &&
		($subFeed->{'type'} eq 'replace' || 
		 ($subFeed->{'type'} eq 'playlist' && $subFeed->{'parser'} && scalar @{ $feed->{'items'} } == 1) ) ) {
		 	
		# in the case of a replacable menu or playlist of one with parser update previous entry to avoid new menu level
		my $item = $feed->{'items'}[0];
		if ($subFeed->{'type'} eq 'replace') {
			delete $subFeed->{'url'};
		}
		
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
	
	if ($feed->{'actions'}) {
		$subFeed->{'actions'} = $feed->{'actions'};
	}
	$subFeed->{'total'} = $feed->{'total'};
	$subFeed->{'offset'} = $feed->{'offset'};
	
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
			'icon-id' => defined $icon ? $icon : '/html/music/cover.png',
		},
	} );
}

sub findAction {
	my ($feed, $item, $actionName) = @_;
	
	if ($item && $item->{'itemActions'} && $item->{'itemActions'}->{$actionName}) {
		return wantarray ? ($item->{'itemActions'}->{$actionName}, {}) : $item->{'itemActions'}->{$actionName};
	}
	if ($feed && $feed->{'actions'} && $feed->{'actions'}->{$actionName}) {
		return wantarray ? ($feed->{'actions'}->{$actionName}, $feed->{'actions'}) : $feed->{'actions'}->{$actionName};
	}
	return wantarray ? () : undef;
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

	if ($insertItem && $count > 1) {
		$totalCount++;
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
	elsif ( $item->{'enclosure'} && ( $item->{'enclosure'}->{'type'} =~ /audio/ ) ) {
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
	elsif ( $item->{'type'} && $item->{'type'} eq 'playlist' && $item->{'parser'} ) {
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
	my $client  = $request->client;
	my $params  = $request->{_params};
	my $itemParams = {
		favorites_title => $params->{'favorites_title'},
		favorites_url   => $params->{'favorites_url'},
		favorites_type  => $params->{'favorites_type'},
		menu => $params->{'menu'},
		type => $params->{'type'},
		icon => $params->{'icon'},
		item_id => $params->{'item_id'},
	};


	my @contextMenu = (
		{
			text => $request->string('ADD_TO_END'),
			actions => {
				go => {
				player => 0,
					cmd    => [ $query, 'playlist', 'add'],
					params => $itemParams,
					nextWindow => 'parentNoRefresh',
				},
			},
		},
		{
			text => $request->string('PLAY_NEXT'),
			actions => {
				go => {
				player => 0,
					cmd    => [ $query, 'playlist', 'insert'],
					params => $itemParams,
					nextWindow => 'parentNoRefresh',
				},
			},
		},
		{
			text => $request->string('PLAY'),
			style => 'itemplay',
			actions => {
				go => {
					player => 0,
					cmd    => [ $query, 'playlist', 'play'],
					params => $itemParams,
					nextWindow => 'nowPlaying',
				},
			},
		},
	);

	# Favorites handling
	my $action = 'add';
 	my $favIndex = undef;
	my $token = 'JIVE_SAVE_TO_FAVORITES';
	if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::Favorites::Plugin') ) {
		my $favs = Slim::Utils::Favorites->new($request->client);
		$favIndex = $favs->findUrl($itemParams->{favorites_url});
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
				title   => $itemParams->{'favorites_title'},
				url     => $itemParams->{'favorites_url'},
				type    => $itemParams->{'favorites_type'},
				isContextMenu => 1,
			},
		},
	};
	$favoriteActions->{'go'}{'params'}{'item_id'} = "$favIndex" if defined($favIndex);
	$favoriteActions->{'go'}{'params'}{'icon'}    = $itemParams->{icon} if defined($itemParams->{icon});

	push @contextMenu, {
		text => $request->string($token),
		actions => $favoriteActions,
	};

	my $numItems = scalar(@contextMenu);
	$request->addResult('count', $numItems);
	$request->addResult('offset', 0);
	my $cnt = 0;
	return \@contextMenu;

}


1;

