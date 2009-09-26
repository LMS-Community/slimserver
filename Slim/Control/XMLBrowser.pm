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
#use Slim::Utils::Timers;

use constant CACHE_TIME => 3600; # how long to cache browse sessions

my $log = logger('formats.xml');

sub cliQuery {
	my ( $query, $feed, $request, $expires, $forceTitle ) = @_;
	
	main::INFOLOG && $log->info("cliQuery($query)");

	# check this is the correct query.
	if ($request->isNotQuery([[$query], ['items', 'playlist']])) {
		$request->setStatusBadDispatch();
		return;
	}

	$request->setStatusProcessing();
	
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

	# If the feed is already XML data (Podcast List), send it to handleFeed
	if ( ref $feed eq 'HASH' ) {
		
		main::DEBUGLOG && $log->debug("Feed is already XML data!");
		_cliQuery_done( $feed, {
			'request'    => $request,
			'client'     => $request->client,
			'url'        => $feed->{'url'},
			'query'      => $query,
			'expires'    => $expires,
#			'forceTitle' => $forceTitle,
		} );
		return;
	}
	
	my $itemId = $request->getParam('item_id');
	
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
		
		if ( defined($request->getParam('xmlBrowseInterimCM')) ) {
			_playlistControlContextMenu({ request => $request, query => $query });

			return;
		}

		my $cache = Slim::Utils::Cache->new;
		if ( my $cached = $cache->get("xmlbrowser_$sid") ) {
			main::DEBUGLOG && $log->is_debug && $log->debug( "Using cached session $sid" );
				
			_cliQuery_done( $cached, {
				'request' => $request,
				'client'  => $request->client,
				'url'     => $feed,
				'query'   => $query,
				'expires' => $expires,
				'timeout' => 35,
			} );
			return;
		}
	}

	main::DEBUGLOG && $log->debug("Asynchronously fetching feed $feed - will be back!");
	
	Slim::Formats::XML->getFeedAsync(
		\&_cliQuery_done,
		\&_cliQuery_error,
		{
			'request'    => $request,
			'client'     => $request->client,
			'url'        => $feed,
			'query'      => $query,
			'expires'    => $expires,
			'timeout'    => 35,
#			'forceTitle' => $forceTitle,
		}
	);

}

sub _cliQuery_done {
	my ( $feed, $params ) = @_;

	main::INFOLOG && $log->info("_cliQuery_done()");

	my $request    = $params->{'request'};
	my $query      = $params->{'query'};
	my $expires    = $params->{'expires'};
	my $timeout    = $params->{'timeout'};
#	my $forceTitle = $params->{'forceTitle'};
	my $window;
	
	my $cache = Slim::Utils::Cache->new;

	my $isItemQuery = my $isPlaylistCmd = 0;
	
	if ($request->isQuery([[$query], ['playlist']])) {
		$isPlaylistCmd = 1;
	}
	elsif ($request->isQuery([[$query], ['items']])) {
		$isItemQuery = 1;
	}

	# get our parameters
	my $index      = $request->getParam('_index');
	my $quantity   = $request->getParam('_quantity');

	# Bug 14100: sending requests that involve newWindow param from SP side results in no
	# _index _quantity args being sent, but XML Browser actually needs them, so they need to be hacked in
	# here and the tagged params mistakenly put in _index and _quantity need to be re-added
	# to the $request params
	if ( $index =~ /:/ ) {
		$request->addParam(split /:/, $index);
		$index = 0;
	}
	if ( $quantity =~ /:/ ) {
		$request->addParam(split /:/, $quantity);
		$quantity = 200;
	}
	my $search     = $request->getParam('search');
	my $want_url   = $request->getParam('want_url') || 0;
	my $item_id    = $request->getParam('item_id');
	my $menu       = $request->getParam('menu');
	my $url        = $request->getParam('url');
	my $trackId    = $request->getParam('track_id');
	
	# menu/jive mgmt
	my $menuMode = defined $menu;
	
	# Session ID for this browse session
 	my $sid;
	
	# select the proper list of items
	my @index = ();

	if ( defined $item_id && length($item_id) ) {
		@index = split /\./, $item_id;
		
		if ( length( $index[0] ) >= 8 ) {
			# Session ID is first element in index
			$sid = shift @index;
		}
	}
	else {
		# Create a new session ID, unless the list has coderefs
		my $refs = scalar grep { ref $_->{url} } @{ $feed->{items} };
		
		if ( !$refs ) {
			$sid = Slim::Utils::Misc::createUUID();
		}
	}
	
	my $subFeed = $feed;
	
#	use Data::Dumper;
#	print Data::Dumper::Dumper($subFeed);
	
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

		if ( $@ && $log->is_warn ) {
			$log->warn("Session not cached: $@");
		}
	}
	
	if ( my $levels = scalar @index ) {

		# descend to the selected item
		my $depth = 0;
		for my $i ( @index ) {
			main::DEBUGLOG && $log->debug("Considering item $i");

			$depth++;
			
			my ($in) = $i =~ /^(\d+)/;
			$subFeed = $subFeed->{'items'}->[$in];

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
					'expires'      => $expires,
					'timeout'      => $timeout,
				};
				
				# Check for a cached version of this subfeed URL
				if ( my $cached = Slim::Formats::XML->getCachedFeed( $subFeed->{'url'} ) ) {
					
					main::DEBUGLOG && $log->debug( "Using previously cached subfeed data for $subFeed->{url}" );
					_cliQuerySubFeed_done( $cached, $args );
				}
				
				else {
					
					# Some plugins may give us a callback we should use to get OPML data
					# instead of fetching it ourselves.
					if ( ref $subFeed->{url} eq 'CODE' ) {
						my $callback = sub {
							my $menu = shift;

							if ( ref $menu ne 'ARRAY' ) {
								$menu = [ $menu ];
							}

							my $opml = {
								type  => 'opml',
								title => $args->{feedTitle},
								items => $menu,
							};

							_cliQuerySubFeed_done( $opml, $args );
						};
						
						my $pt = $subFeed->{passthrough} || [];

						if ( main::DEBUGLOG && $log->is_debug ) {
							my $cbname = Slim::Utils::PerlRunTime::realNameForCodeRef( $subFeed->{url} );
							$log->debug( "Fetching OPML from coderef $cbname" );
						}

						return $subFeed->{url}->( $request->client, $callback, @{$pt} );
					}
								
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
				
				main::DEBUGLOG && $log->debug("Adding results for audio or enclosure subfeed");

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
				}

				$request->addResult('count', 1) if !$menuMode;
				my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), 1);
				
				if ($valid) {
					
					my $loopname = $menuMode ? 'item_loop' : 'loop_loop';
					my $cnt = 0;
					$request->addResult('offset', $start) if $menuMode;

					# create an ordered hash to store this stuff...
					tie (my %hash, "Tie::IxHash");

					$hash{'id'} = "$item_id"; # stringify for JSON
					$hash{'name'} = $subFeed->{'name'} if defined $subFeed->{'name'};
					$hash{'title'} = $subFeed->{'title'} if defined $subFeed->{'title'};
					
					my $hasAudio = defined(hasAudio($subFeed)) + 0;
					$hash{'isaudio'} = $hasAudio;				
				
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
						my %items = (
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
						
						for my $mode ( 'play', 'add' ) {
							my $actions = {
								'do' => {
									'player' => 0,
									'cmd'    => [$query, 'playlist', $items{$mode}->{'cmd'}],
									'params' => {
										'item_id' => "$item_id", # stringify for JSON
									},
									'nextWindow' => 'parent',
								},
								'play' => {
									'player' => 0,
									'cmd'    => [$query, 'playlist', $items{$mode}->{'cmd'}],
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
								},						};
							$request->addResultLoop($loopname, $cnt, 'text', $items{$mode}{'string'});
							$request->addResultLoop($loopname, $cnt, 'actions', $actions);
							$request->addResultLoop($loopname, $cnt, 'style', $items{$mode}{'style'});
							$cnt++;
						}
						
						if ( my $title = $hash{name} ) {
							my $text = $request->string('TITLE') . ": $title";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $url = $hash{url} ) {
							my $text = $request->string('URL') . ": $url";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $desc = $hash{description} ) {
							my $text = $request->string('DESCRIPTION') . ": $desc";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}

						if ( my $bitrate = $hash{bitrate} ) {
							my $text = $request->string('BITRATE') . ": $bitrate " . $request->string('KBPS');
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $duration = $hash{duration} ) {
							$duration = sprintf('%s:%02s', int($duration / 60), $duration % 60);
							my $text = $request->string('LENGTH') . ": $duration";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $listeners = $hash{listeners} ) {
							# Shoutcast
							my $text = $request->string('NUMBER_OF_LISTENERS') . ": $listeners";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $current_track = $hash{current_track} ) {
							# Shoutcast
							my $text = $request->string('NOW_PLAYING') . ": $current_track";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $genre = $hash{genre} ) {
							# Shoutcast
							my $text = $request->string('GENRE') . ": $genre";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $source = $hash{source} ) {
							# LMA
							my $text = $request->string('SOURCE') . ": $source";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
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
							$request->addResultLoop($loopname, $cnt, 'window', { 'titleStyle' => 'favorites' });
							$cnt++;
						}

						$request->addResult('count', $cnt);
					}
					
					else {
						$request->setResultLoopHash($loopname, $cnt, \%hash);
					}
				}
				$request->setStatusDone();
				return;
			}
		}
	}

	if ($isPlaylistCmd) {

		# get our parameters
		my $client = $request->client();
		my $method = $request->getParam('_method');

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
			
			# play all streams of an item
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
					next if !$url;
					
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

					if ( main::INFOLOG && $log->is_info ) {
						$log->info(sprintf("Playing/adding all items:\n%s", join("\n", @urls)));
					}
					
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
	
					my $play_index = $request->getParam('play_index') || 0;

					$client->execute([ 'playlist', $cmd, 'listref', \@urls ]);

					# if we're adding or inserting, show a showBriefly
					if ( $method =~ /add/ || $method eq 'insert' ) {
						my $icon = $request->getParam('icon');
						my $title = $request->getParam('favorites_title');
						_addingToPlaylist($client, $method, $title, $icon);
					# if not, we jump to the correct track in the list
					} else {
						$client->execute([ 'playlist', 'jump', $play_index ]);
					}
				}
			}
		}
		else {
			$request->setStatusBadParams();
			return;
		}
	}	

	elsif ($isItemQuery) {

		main::INFOLOG && $log->info("Get items.");
		
		# Bug 7024, display an "Empty" item instead of returning an empty list
		if ( $menuMode && ( !defined( $subFeed->{items} ) || !scalar @{ $subFeed->{items} } ) ) {
			$subFeed->{items} ||= [];
			push @{ $subFeed->{items} }, {
				type => 'text',
				name => $request->string('EMPTY'),
			};
		}
	
		my $count = defined @{$subFeed->{'items'}} ? @{$subFeed->{'items'}} : 0;
		
		# now build the result
	
		my $hasImage = 0;
		my $windowStyle;
		my $play_index = 0;
		
		if ($count) {
		
			# first, determine whether there should be a "Play All" item in this list
			# this determination is made by checking if there are 2 or more playable items in the list
			my $insertAll = 0;
			if ( $menuMode ) {
				
				my $mark = 0;
				for my $item ( @{$subFeed->{items}}[0..$count] ) {
					
					if ( $item->{duration} && hasAudio($item) ) {
						$mark++;
						if ($mark > 1) {
							$insertAll = 1;
							last;
						}
					}
				}
			}
			# second, fix the count, index, and quantity variables if we are adding Play All
			if ( $menuMode && $insertAll ) {
				$count = _fixCount($insertAll, \$index, \$quantity, $count);
			}
			# finally we can determine $start and $end of the chunk based on the tweaked metrics
			my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);
		
			my $loopname = $menuMode ? 'item_loop' : 'loop_loop';
			my $cnt = 0;
			$request->addResult('offset', $start) if $menuMode;

			if ($valid) {
				
				$request->addResult( 'title', $subFeed->{'name'} || $subFeed->{'title'} );
				# decide what is the next step down
				# we go to xxx items from xx items :)
				my $base; my $params = {};
				if ($menuMode) {
					# build the base element
					$params = {
						'menu' => $query,
					};
				
					if ( $url ) {
						$params->{'url'} = $url;
					}
					
					if ( $trackId ) {
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
								'player' => 0,
								'cmd' => [ $query, 'items' ],
								'itemsParams' => 'params',
								'params' => $params,
								window => {
									isContextMenu => 1,
								},
							},
						},
					};
                			$base->{'actions'} = _jivePresetBase($base->{'actions'});
					$request->addResult('base', $base);
				}

				# Bug 6874, add a "Play All" item if list contains more than 1 playable item with duration
				if ( $menuMode && $insertAll ) {
					my $actions = {
						go => {
							player => 0,
							cmd    => [ $query, 'playlist', 'playall' ],
							params => $params,
							nextWindow => 'nowPlaying',
						},
						add => {
							player => 0,
							cmd    => [ $query, 'playlist', 'addall' ],
							params => $params,
							},
						};
						
					$actions->{go}->{params}->{item_id}  = "$item_id"; # stringify for JSON
					$actions->{add}->{params}->{item_id} = "$item_id"; # stringify for JSON
					
					$actions->{play} = $actions->{go};
						
					my $text = $request->string('JIVE_PLAY_ALL');
								
					# Bug 7517, only add Play All at the top, not in the middle if we're
					# dealing with a chunked list starting at 200, etc
					if ( $start == 0 ) {
						$request->addResultLoop($loopname, $cnt, 'text', $text);
						$request->addResultLoop($loopname, $cnt, 'style', 'itemplay');
						$request->addResultLoop($loopname, $cnt, 'actions', $actions);
						$cnt++;
					}
							
					# Bug 7109, we don't want later items to have the wrong index so we need to
					# add _slim_id keys to them.
					my $cnt2 = 0;
					for my $subitem ( @{$subFeed->{items}}[$start..$end] ) {
						$subitem->{_slim_id} = $cnt2++;
					}
				}
				
				# If we have a slideshow param, return all items without chunking, and only
				# include image and caption data
				if ( $request->getParam('slideshow') ) {
					my $images = [];
					for my $item ( @{ $subFeed->{items} } ) {
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

				for my $item ( @{$subFeed->{'items'}}[$start..$end] ) {
									
					# create an ordered hash to store this stuff...
					tie my %hash, "Tie::IxHash";
					
					$hash{id}    = join('.', @crumbIndex, defined $item->{_slim_id} ? $item->{_slim_id} : $start + $cnt);
					$hash{name}  = $item->{name}  if defined $item->{name};
					$hash{type}  = $item->{type}  if defined $item->{type};
					$hash{title} = $item->{title} if defined $item->{title};
					$hash{url}   = $item->{url}   if $want_url && defined $item->{url};
					$hash{image} = $item->{image} if defined $item->{image};

					my $hasAudio = defined(hasAudio($item)) + 0;
					$hash{isaudio} = $hasAudio;
					my $touchToPlay = defined(touchToPlay($item)) + 0;
					
					# Bug 7684, set hasitems to 1 if any of the following are true:
					# type is not text or audio
					# items array contains items
					my $hasItems = 0;
					
					if ( !defined $item->{type} || $item->{type} !~ /^(?:text|audio)$/i ) {
						$hasItems = 1;
					}
					elsif ( ref $item->{items} eq 'ARRAY' ) {
						$hasItems = scalar @{ $item->{items} };
					}
					
					$hash{hasitems} = $hasItems;

					if ($menuMode) {
						# if showBriefly is 1, send the name as a showBriefly
						if ($item->{showBriefly} and ( $hash{name} || $hash{title} ) ) {
							$request->client->showBriefly({ 
										'jive' => {
											'type'    => 'popupplay',
											'text'    => [ $hash{name} || $hash{title} ],
										},
									});
							next;
						}

						# if nowPlaying is 1, tell Jive to go to nowPlaying
						if ($item->{nowPlaying}) {
							$request->addResult('goNow', 'nowPlaying');
						}
									
						# wrap = 1 and type = textarea render in the single textarea area above items
						my $textarea;
						if ( $item->{wrap} && $item->{name} ) {
							$window->{textarea} = $item->{name};
							$textarea = 1;
						}
						
						if ( $item->{type} && $item->{type} eq 'textarea' ) {
							$window->{textarea} = $item->{name};
							$textarea = 1;
						}
						
						if ( $textarea ) {
							# Skip this item
							$count--;
							
							# adjust item_id offsets because we have removed an item
							my $cnt2 = 0;
							for my $subitem ( @{$subFeed->{items}}[$start..$end] ) {
								$subitem->{_slim_id} = $cnt2++;
							}
							
							# If this is the only item, add an empty item list
							$request->setResultLoopHash($loopname, 0, {});
							
							next;
						}
						
						# Bug 13175, support custom windowStyle
						if ( $item->{style} ) {
							$windowStyle = $item->{style};
						}
						
						# Bug 7077, if the item will autoplay, it has an 'autoplays=1' attribute
						if ( $item->{autoplays} ) {
							$request->addResultLoop($loopname, $cnt, 'style', 'itemplay');
						}

						$request->addResultLoop($loopname, $cnt, 'text', $hash{'name'} || $hash{'title'});
						
						my $isPlayable = (
							   $item->{play} 
							|| $item->{playlist} 
							|| ($item->{type} && ($item->{type} eq 'audio' || $item->{type} eq 'playlist'))
						);
						
						my $itemParams = {};
						my $id = $hash{id};
						
						if ( !$item->{type} || $item->{type} ne 'text' ) {							
							$itemParams = {
								item_id => "$id", #stringify, make sure it's a string
							};
						}

						my $presetFavSet     = undef;
						my $favorites_url    = $item->{play} || $item->{url};
						my $favorites_title  = $item->{title} || $item->{name};
						if ( $favorites_url && !ref $favorites_url && $favorites_title ) {
							$itemParams->{favorites_url} = $favorites_url;
							$itemParams->{favorites_title} = $favorites_title;
							if ( $item->{image} ) {
								$itemParams->{icon} = $item->{image};
							}
							if ( $item->{type} && $item->{type} eq 'playlist' && $item->{playlist} ) {
								$itemParams->{favorites_url} = $item->{playlist};
							}
							$itemParams->{type} = $item->{type} if $item->{type};
							$itemParams->{parser} = $item->{parser} if $item->{parser};
							$presetFavSet = 1;

						}


						if ( $isPlayable || $item->{isContextMenu} ) {
							$itemParams->{'isContextMenu'} = 1;
						}

						my %merged = %$params;
						if ( scalar keys %{$itemParams} ) {
							%merged = (%{$params}, %{$itemParams});
						}

						if ( $item->{image} ) {
							$request->addResultLoop( $loopname, $cnt, 'icon', $item->{image} );
							$request->addResultLoop($loopname, $cnt, 'window', { 'titleStyle' => 'album' });
							$hasImage = 1;
						}

						if ( $item->{icon} ) {
							$request->addResultLoop( $loopname, $cnt, 'icon' . ($item->{icon} =~ /^http:/ ? '' : '-id'), $item->{icon} );
							$request->addResultLoop($loopname, $cnt, 'window', { 'titleStyle' => 'album' });
							$hasImage = 1;
						}

						if ( $item->{type} && $item->{type} eq 'text' && !$item->{wrap} && !$item->{jive} ) {
							$request->addResultLoop( $loopname, $cnt, 'style', 'itemNoAction' );
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
						}
						
						# Support type='db' for Track Info
						if ( $item->{jive} ) {
							$request->addResultLoop( $loopname, $cnt, 'actions', $item->{jive}->{actions} );
							for my $key ('window', 'showBigArtwork', 'style', 'nextWindow', 'playHoldAction', 'icon-id') {
								if ( $item->{jive}->{$key} ) {
									$request->addResultLoop( $loopname, $cnt, $key, $item->{jive}->{$key} );
								}
							}
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
								help => {
									text => $request->string('JIVE_SEARCHFOR_HELP')
								},
								softbutton1 => $request->string('INSERT'),
								softbutton2 => $request->string('DELETE'),
								title => $item->{title} || $item->{name},
							};
							
							$request->addResultLoop( $loopname, $cnt, 'actions', $actions );
							$request->addResultLoop( $loopname, $cnt, 'input', $input );
						}
						elsif ( !$isPlayable && !$touchToPlay ) {
							my $actions = {
								'go' => {
									'cmd' => [ $query, 'items' ],
									'params' => \%merged,
								},
								'add' => {
									'cmd' => [ $query, 'items' ],
									'params' => \%merged,
								},
							};
							# Bug 13247, support nextWindow param
							if ( $item->{nextWindow} ) {
								$actions->{go}{nextWindow} = $item->{nextWindow};
							}
							$request->addResultLoop( $loopname, $cnt, 'actions', $actions );
							$request->addResultLoop( $loopname, $cnt, 'addAction', 'go');
						}
						elsif ( $touchToPlay ) {
							my $all = $item->{playall} ? 'all' : '';
							my $actions = {
								more => {
									cmd         => [ $query, 'items' ],
									params      => \%merged,
									itemsParams => 'params',
								},
								go => {
									player      => 0,
									cmd         => [ $query, 'playlist', 'play' . $all ],
									itemsParams => 'params',
									params      => $itemParams,
									nextWindow  => 'nowPlaying',
								},
								'add' => {
									player      => 0,
									cmd         => [ $query, 'playlist', 'add' . $all ],
									itemsParams => 'params',
									params      => $itemParams,
								},
								'add-hold' => {
									player      => 0,
									cmd         => [$query, 'playlist', 'insert'],
									itemsParams => 'params',
									params      => $itemParams,
								}
							};
							
							if ( $item->{playall} ) {
								# Clone params or we'll end up changing data for every action
								my $cParams = Storable::dclone($itemParams);
								
								# Remember which item was pressed when playing so we can jump to it
								$cParams->{play_index} = $play_index++;
								
								# Rewrite item_id if in 'all' mode, so it plays/adds all the
								# tracks from the current level, not the single item
								$cParams->{item_id} = "$item_id";
								
								$actions->{go}->{params}  = $cParams;
								$actions->{add}->{params} = $cParams;
							}
							
							$request->addResultLoop( $loopname, $cnt, 'actions', $actions );
							$request->addResultLoop( $loopname, $cnt, 'playAction', 'go');
							$request->addResultLoop( $loopname, $cnt, 'style', 'itemplay');
						}

						if ( scalar keys %{$itemParams} && $isPlayable ) {
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

		$request->addResult('count', $count);
		
		if ($menuMode) {
			
			$window->{'windowStyle'} = $windowStyle || 'text_list';
			
			# Bug 13247, support windowId param
			if ( $subFeed->{windowId} ) {
				$window->{windowId} = $subFeed->{windowId};
			}

			# send any window parameters we've gathered, if we've gathered any
			if ($window) {
				$request->addResult('window', $window );
			}
		}
	}
	
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
		
		$subFeed = $subFeed->{'items'}->[$i];
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
	elsif ( $item->{'type'} && $item->{'type'} =~ /^(?:playlist)$/ && $item->{'parser'} ) {
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
			itemsParams => 'params',
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
	my $numItems = scalar(@contextMenu);
	$request->addResult('count', $numItems);
	$request->addResult('offset', 0);
	my $cnt = 0;
	for my $eachmenu (@contextMenu) {
		$request->setResultLoopHash('item_loop', $cnt, $eachmenu);
		$cnt++;
	}

	$request->setStatusDone();
}

1;

