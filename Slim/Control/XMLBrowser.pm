package Slim::Control::XMLBrowser;

# $Id: XMLBrowser.pm 23262 2008-09-23 19:21:03Z andy $

# Copyright 2005-2007 Logitech.

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
use URI::Escape qw(uri_unescape);

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
	
	$log->info("cliQuery($query)");

	# check this is the correct query.
	if ($request->isNotQuery([[$query], ['items', 'playlist']])) {
		$request->setStatusBadDispatch();
		return;
	}

	$request->setStatusProcessing();
	
	# cache SBC queries for "Recent Search" menu
	if ( $request->isQuery([[$query], ['items']]) && defined($request->getParam('menu')) && defined($request->getParam('search')) ) {
		
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
		
		$log->debug("Feed is already XML data!");
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
			$request->addParam( item_id => $itemId );
		}
		
		my $cache = Slim::Utils::Cache->new;
		if ( my $cached = $cache->get("xmlbrowser_$sid") ) {
			$log->is_debug && $log->debug( "Using cached session $sid" );
				
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

	$log->debug("Asynchronously fetching feed $feed - will be back!");
	
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

	$log->info("_cliQuery_done()");

	my $request    = $params->{'request'};
	my $query      = $params->{'query'};
	my $expires    = $params->{'expires'};
	my $timeout    = $params->{'timeout'};
#	my $forceTitle = $params->{'forceTitle'};
	my $window;
	my $textArea;
	
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
			@crumbIndex = ( $sid . '_' . $search );
		}
		else {
			@crumbIndex = ( '_' . $search );
		}
	}
	
	if ( $sid ) {
		# Cache the feed structure for this session
		$log->is_debug && $log->debug( "Caching session $sid" );
		
		$cache->set( "xmlbrowser_$sid", $feed, CACHE_TIME );
	}
	
	if ( my $levels = scalar @index ) {

		# descend to the selected item
		my $depth = 0;
		for my $i ( @index ) {
			$log->debug("Considering item $i");

			$depth++;
			
			$subFeed = $subFeed->{'items'}->[$i];

			# Add search query to crumb list
			if ( $subFeed->{type} && $subFeed->{type} eq 'search' && $search ) {
				push @crumbIndex, $i . '_' . $search;
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
			if ( $subFeed->{'type'} ne 'audio' && defined $subFeed->{'url'} && !$subFeed->{'fetched'} ) {
				
				if ( $i =~ /(?:\d+)?_(.+)/ ) {
					$search = $1;
				}
				
				# Rewrite the URL if it was a search request
				if ( $subFeed->{type} eq 'search' ) {
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
					
					$log->debug( "Using previously cached subfeed data for $subFeed->{url}" );
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

						if ( $log->is_debug ) {
							my $cbname = Slim::Utils::PerlRunTime::realNameForCodeRef( $subFeed->{url} );
							$log->debug( "Fetching OPML from coderef $cbname" );
						}

						return $subFeed->{url}->( $request->client, $callback, @{$pt} );
					}
								
					$log->debug("Asynchronously fetching subfeed " . $subFeed->{url} . " - will be back!");

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
						$subFeed->{'type'} eq 'audio' || 
						$subFeed->{'enclosure'} ||
						$subFeed->{'description'}	
					)
				) {
				
				$log->debug("Adding results for audio or enclosure subfeed");

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
									'item_id' => $item_id,
								},
							},
							'add' => {
								'player' => 0,
								'cmd' => [$query, 'playlist', 'add'],
								'params' => {
									'item_id' => $item_id,
								},
							},
							'add-hold' => {
								'player' => 0,
								'cmd' => [$query, 'playlist', 'insert'],
								'params' => {
									'item_id' => $item_id,
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

					$hash{'id'} = $item_id;
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
						my ($play_string, $add_string);
						if ( $hash{duration} ) {
							# Items with a duration are songs
							$play_string = $request->string('JIVE_PLAY_THIS_SONG');
							$add_string  = $request->string('JIVE_ADD_THIS_SONG');
						}
						else {
							# Items without duration are streams
							$play_string = $request->string('PLAY');
							$add_string  = $request->string('ADD');
						}
						
						# setup hash for different items between play and add
						my %items = (
							'play' => {
								'string'  => $play_string,
								'style'   => 'itemplay',
								'cmd'     => 'play',
							},
							'add' => {
								'string'  => $add_string,
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
										'item_id' => $item_id,
									},
								},
								'play' => {
									'player' => 0,
									'cmd'    => [$query, 'playlist', $items{$mode}->{'cmd'}],
									'params' => {
										'item_id' => $item_id,
									},
								},
								# add always adds
								'add' => {
									'player' => 0,
									'cmd'    => [$query, 'playlist', 'add'],
									'params' => {
										'item_id' => $item_id,
									},
								},
								'add-hold' => {
									'player' => 0,
									'cmd'    => [$query, 'playlist', 'insert'],
									'params' => {
										'item_id' => $item_id,
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
							my $token = 'JIVE_ADD_TO_FAVORITES';
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
									},
								},
							};
							$actions->{'go'}{'params'}{'icon'} = $hash{image} if defined($hash{image});
							$actions->{'go'}{'params'}{'item_id'} = $favIndex if defined($favIndex);
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

		$log->info("Play an item ($method).");

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

					$log->info("$method $url");
					
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

					if ($url) {

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
				}
				
				if ( @urls ) {

					if ( $log->is_info ) {
						$log->info(sprintf("Playing/adding all items:\n%s", join("\n", @urls)));
					}
					
					if ( $method =~ /play|load/i ) {
						$client->execute([ 'playlist', 'play', \@urls ]);
					}
					else {
						my $cmd = $method eq 'insert' ? 'inserttracks' : 'addtracks';
						$client->execute([ 'playlist', $cmd, 'listref', \@urls ]);
						_addingToPlaylist($client, $method);
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

		$log->info("Get items.");
		
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
						},
					};
					$request->addResult('base', $base);
				}

				# Bug 6874, add a "Play All" item if list contains more than 1 playable item with duration
				if ( $menuMode && $insertAll ) {
					my $actions = {
						do => {
							player => 0,
							cmd    => [ $query, 'playlist', 'playall' ],
							params => $params,
						},
						add => {
							player => 0,
							cmd    => [ $query, 'playlist', 'addall' ],
							params => $params,
							},
						};
						
					$actions->{do}->{params}->{item_id}  = $item_id;
					$actions->{add}->{params}->{item_id} = $item_id;
					
					$actions->{play} = $actions->{do};
						
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
				
				for my $item ( @{$subFeed->{'items'}}[$start..$end] ) {
					
					next if $textArea;
					
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
						}

						# if nowPlaying is 1, tell Jive to go to nowPlaying
						if ($item->{nowPlaying}) {
							$request->addResult('goNow', 'nowPlaying');
						}

					
						if ( $item->{wrap} && $item->{name}) {
							$window->{'textArea'} = $item->{name};
							# no menu when we're sending a textArea, but we need a count of 0 sent
							$request->addResult('count', 0);
							$textArea++;
						}
						
						# Bug 7077, if the item will autoplay, it has an 'autoplays=1' attribute
						if ( $item->{autoplays} ) {
							$request->addResultLoop($loopname, $cnt, 'style', 'itemplay');
						}

						$request->addResultLoop($loopname, $cnt, 'text', $hash{'name'} || $hash{'title'});
						
						my $isPlayable = (
							   $item->{play} 
							|| $item->{playlist} 
							|| $item->{type} eq 'audio'
							|| $item->{type} eq 'playlist'
						);
						
						my $itemParams = {};
						my $id = $hash{id};
						
						if ( $item->{type} ne 'text' ) {							
							$itemParams = {
								item_id => "$id", #stringify, make sure it's a string
							};
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

						if ( $item->{type} eq 'text' && !$hasImage && !$item->{wrap} && !$item->{jive} ) {
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
						
						elsif ( $item->{type} eq 'search' ) {
							#$itemParams->{search} = '__INPUT__';
							
							# XXX: bug in Jive, this should really be handled by the base go action
							my $actions = {
								go => {
									cmd    => [ $query, 'items' ],
									params => {
										item_id => "$id",
										menu    => $query,
										search  => '__TAGGEDINPUT__',
									},
								},
							};									
							
							my $input = {
								len  => 3,
								help => {
									text => $request->string('JIVE_SEARCHFOR_HELP')
								},
								softbutton1 => $request->string('INSERT'),
								softbutton2 => $request->string('DELETE'),
							};
							
							$request->addResultLoop( $loopname, $cnt, 'actions', $actions );
							$request->addResultLoop( $loopname, $cnt, 'input', $input );
						}
						elsif ( !$isPlayable ) {
							my %merged = %$params;
							if ( scalar keys %{$itemParams} ) {
								%merged = (%{$params}, %{$itemParams});
							}
							my $actions = {
								'go' => {
									'cmd' => [ $query, 'items' ],
									'params' => \%merged,
								},
								'play' => {
									'cmd' => [ $query, 'items' ],
									'params' => \%merged,
								},
								'add' => {
									'cmd' => [ $query, 'items' ],
									'params' => \%merged,
								},
							};
							$request->addResultLoop( $loopname, $cnt, 'actions', $actions );
							$request->addResultLoop( $loopname, $cnt, 'playAction', 'go');
							$request->addResultLoop( $loopname, $cnt, 'addAction', 'go');
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

		$request->addResult('count', $count) unless $window->{textArea};
		
		if ($menuMode) {


			# Change window menuStyle to album if any images are in the list
			if ( $hasImage ) {
				$window->{'menuStyle'} = 'album';
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
		
		$log->is_debug && $log->debug( "Executing command: " . Data::Dump::dump(\@p) );
		$client->execute( \@p );
	}
	
	# insert the sub-feed data into the original feed
	my $parent = $params->{'parent'};
	my $subFeed = $parent;
	
	for my $i ( @{ $params->{'currentIndex'} } ) {
		# Skip sid and sid + top-level search query
		next if length($i) >= 8 && $i =~ /^[a-f0-9]{8}/;
		
		# If an index contains a search query, strip it out
		$i =~ s/[^\d]//g;
		
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
		
		# Update the title value in case it's different from the previous menu
		if ( $feed->{'title'} ) {
			$subFeed->{'name'} = $feed->{'title'};
		}
	}

	$subFeed->{'fetched'} = 1;
	
	_cliQuery_done( $parent, $params );
}

sub _addingToPlaylist {
	my $client = shift;
	my $action = shift || 'add';

	my $string = $action eq 'add'
		? $client->string('ADDING_TO_PLAYLIST')
		: $client->string('INSERT_TO_PLAYLIST');

	my $jivestring = $action eq 'add' 
		? $client->string('JIVE_POPUP_ADDING_TO_PLAYLIST', ' ') 
		: $client->string('JIVE_POPUP_ADDING_TO_PLAY_NEXT', ' ');

	$client->showBriefly( { 
		line => [ $string ],
		jive => {
			type => 'popupplay',
			text => [ $jivestring ],
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

1;
