package Slim::Buttons::XMLBrowser;

# $Id$

# Copyright 2005-2007 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Buttons::XMLBrowser

=head1 DESCRIPTION

L<Slim::Buttons::XMLBrowser> creates the 'xmlbrowser' mode.  The mode allows users to scroll
through Podcast entries, RSS & OPML Outlines and play audio enclosures. 


=cut

use strict;

use Scalar::Util qw(blessed);
use URI::Escape qw(uri_unescape);

use Slim::Buttons::Common;
use Slim::Formats::XML;
use Slim::Control::XMLBrowser;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Timers;

# XXXX - not the best category, but better than d_plugins, which is what it was.
my $log = logger('formats.xml');

sub init {
	Slim::Buttons::Common::addMode('xmlbrowser', getFunctions(), \&setMode);
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

	my $title  = $client->modeParam('title');
	my $url    = $client->modeParam('url');
	my $search = $client->modeParam('search');
	my $parser = $client->modeParam('parser');
	my $opml   = $client->modeParam('opml');
	
	# Pre-filled menu of OPML items
	if ( $opml ) {
		gotOPML( $client, $url, $opml, {} );
		return;
	}

	# if no url, error
	if (!$url) {
		my @lines = (
			# TODO: l10n
			"Podcast Browse Mode requires url param",
		);

		#TODO: display the error on the client
		my %params = (
			'header'  => "{XML_ERROR}",
			'headerAddCount' => 1,
			'listRef' => \@lines,
		);

		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);

	} else {
		
		# Grab expires param here, as the block will change the param stack
		my $expires = $client->modeParam('expires');
		
		# Callbacks to report success/failure of feeds.  This is used by the
		# RSS plugin on SN to log errors.
		my $onSuccess = $client->modeParam('onSuccess');
		my $onFailure = $client->modeParam('onFailure');
		
		# the item is passed as a param so we can get passthrough params
		my $item = $client->modeParam('item');
		
		# Adjust HTTP timeout value to match the API on the other end
		my $timeout = $client->modeParam('timeout') || 5;
		
		# Should we remember where the user was browsing? (default: yes)
		my $remember = $client->modeParam('remember');
		if ( !defined $remember ) {
			$remember = 1;
		}

		# give user feedback while loading
		$client->block();
		
		my $params = {
			'client'    => $client,
			'url'       => $url,
			'search'    => $search,
			'expires'   => $expires,
			'onSuccess' => $onSuccess,
			'onFailure' => $onFailure,
			'feedTitle' => $title,
			'parser'    => $parser,
			'item'      => $item,
			'timeout'   => $timeout,
			'remember'  => $remember,
		};
		
		# Some plugins may give us a callback we should use to get OPML data
		# instead of fetching it ourselves.
		if ( ref $url eq 'CODE' ) {
			my $callback = sub {
				my $menu = shift;
				
				if ( ref $menu ne 'ARRAY' ) {
					$menu = [ $menu ];
				}
				
				my $opml = {
					type  => 'opml',
					title => $title,
					items => $menu,
				};
				
				gotFeed( $opml, $params );
			};
			
			# get passthrough params if supplied
			my $pt = $item->{'passthrough'} || [];
			
			if ( $log->is_debug ) {
				my $cbname = Slim::Utils::PerlRunTime::realNameForCodeRef($url);
				$log->debug( "Fetching OPML from coderef $cbname" );
			}
			
			return $url->( $client, $callback, @{$pt} );
		}
		
		Slim::Formats::XML->getFeedAsync( 
			\&gotFeed,
			\&gotError,
			$params,
		);

		# we're done.  gotFeed callback will finish setting up mode.
	}
}

sub gotFeed {
	my ( $feed, $params ) = @_;
	
	my $client = $params->{'client'};
	my $url    = $params->{'url'};

	# must unblock now, before pushMode is called by getRSS or gotOPML
	$client->unblock;
	
	# notify success callback if necessary
	if ( ref $params->{'onSuccess'} eq 'CODE' ) {
		my $cb = $params->{'onSuccess'};
		$cb->( $client, $url );
	}

	# "feed" was originally an RSS feed.  Now it could be either RSS or an OPML outline.
	if ($feed->{'type'} eq 'rss') {

		gotRSS($client, $url, $feed, $params);

	} elsif ($feed->{'type'} eq 'opml') {

		gotOPML($client, $url, $feed, $params);

	} else {
		$client->update();
	}
}

sub gotError {
	my ( $err, $params ) = @_;
	
	my $client = $params->{'client'};
	my $url    = $params->{'url'};

	$log->error("Error: While retrieving [$url]: [$err]");

	# unblock client
	$client->unblock;
	
	# notify failure callback if necessary
	if ( ref $params->{'onFailure'} eq 'CODE' ) {

		my $cb = $params->{'onFailure'};
		$cb->( $client, $url, $err );
	}

	#TODO: display the error on the client
	my %params = (
		'header'  => "{XML_ERROR}",
		'headerAddCount' => 1, 
		'listRef' => [ $err ],
	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
}

sub gotPlaylist {
	my ( $feed, $params ) = @_;
	
	my $client = $params->{'client'};

	# must unblock now, before pushMode is called by getRSS or gotOPML
	$client->unblock;
	$client->update;

	my @urls = ();

	for my $item (@{$feed->{'items'}}) {
	    
	    # Allow uppercase URL
	    $item->{'url'} ||= $item->{'URL'};
		
		# Only add audio items in the playlist
		if ( $item->{'play'} ) {
			$item->{'url'}  = $item->{'play'};
			$item->{'type'} = 'audio';
		}
		
		next unless $item->{'type'} eq 'audio';

		push @urls, $item->{'url'};
		
		# Set metadata about this URL
		Slim::Music::Info::setRemoteMetadata( $item->{'url'}, {
			title   => $item->{'name'} || $item->{'title'} || $item->{'text'},
			ct      => $item->{'mime'},
			secs    => $item->{'duration'},
			bitrate => $item->{'bitrate'},
		} );
		
		# This loop may have a lot of items and a lot of database updates
		main::idleStreams();
	}

	my $action = $params->{'action'} || 'play';
		
	if ( $action eq 'play' ) {
		$client->execute([ 'playlist', 'play', \@urls ]);
	}
	else {
		my $cmd = $action eq 'insert' ? 'inserttracks' : 'addtracks';
		$client->execute([ 'playlist', $cmd, 'listref', \@urls ]);
		Slim::Control::XMLBrowser::_addingToPlaylist($client, $action);
	}
}

sub gotRSS {
	my ($client, $url, $feed, $params) = @_;

	# Include an item to access feed info
	if (($feed->{'items'}->[0]->{'value'} ne 'description') &&
		# skip this if xmlns:slim is used, and no description found
		!($feed->{'xmlns:slim'} && !$feed->{'description'})) {

		my %desc = (
			'name'       => '{XML_FEED_DESCRIPTION}',
			'value'      => 'description',
			'onRight'    => sub {
				my $client = shift;
				my $item   = shift;
				displayFeedDescription($client, $client->modeParam('feed'));
			},

			# play all enclosures...
			'onPlay'     => sub {
				my $client = shift;
				
				Slim::Music::Info::setTitle( 
					$client->modeParam('url'),
					$client->modeParam('feed')->{'title'},
				);

				# play this feed as a playlist
				$client->execute(
					[ 'playlist', 'play',
					$client->modeParam('url'),
					$client->modeParam('feed')->{'title'},
				] );
			},

			'onAdd'      => sub {
				my $client = shift;
				
				Slim::Music::Info::setTitle( 
					$client->modeParam('url'),
					$client->modeParam('feed')->{'title'},
				);				

				# addthis feed as a playlist
				$client->execute(
					[ 'playlist', 'add',
					$client->modeParam('url'),
					$client->modeParam('feed')->{'title'},
				] );
			},

			'overlayRef' => [ undef, shift->symbols('rightarrow') ],
		);

		unshift @{$feed->{'items'}}, \%desc; # prepend
	}

	# use INPUT.Choice mode to display the feed.
	my %params = (
		'url'      => $url,
		'feed'     => $feed,
		# unique modeName allows INPUT.Choice to remember where user was browsing
		'modeName' => 
			( defined $params->{remember} && $params->{remember} == 0 ) 
			? undef : "XMLBrowser:$url",
		'header'   => $feed->{'title'},
		'headerAddCount' => 1,

		# TODO: we show only items here, we skip the description of the entire channel
		'listRef'  => $feed->{'items'},

		'name' => sub {
			my $client = shift;
			my $item   = shift;
			return $item->{'title'};
		},

		'onRight' => sub {
			my $client = shift;
			my $item   = shift;
			if (Slim::Control::XMLBrowser::hasDescription($item)) {
				displayItemDescription($client, $item);
			} else {
				displayItemLink($client, $item);
			}
		},

		'onPlay' => sub {
			my $client = shift;
			my $item   = shift;
			playItem($client, $item);
		},

		'onAdd' => sub {
			my $client = shift;
			my $item   = shift;
			playItem($client, $item, 'add');
		},

		'overlayRef' => \&overlaySymbol,
	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
}

# use INPUT.Choice to display an OPML list of links. OPML support added
# because podcast alley uses OPML to list its top 10, and newest
# podcasts.  Currently this has been tested only with those OPML
# examples, it may or may not work perfectly with others.
#
# recusively browse OPML outline
sub gotOPML {
	my ($client, $url, $opml, $params) = @_;
	
	# If there's a command we need to run, run it.  This is used in various
	# places to trigger actions from an OPML result, such as to start playing
	# a new Pandora radio station
	if ( $opml->{'command'} ) {
		my @p = map { uri_unescape($_) } split / /, $opml->{'command'};
		$log->is_debug && $log->debug( "Executing command: " . Data::Dump::dump(\@p) );
		$client->execute( \@p );
	}

	# Push staight into remotetrackinfo if asked to replace item or a playlist of one was returned with a parser
	if ($params->{'item'}->{'type'} &&
		($params->{'item'}->{'type'} eq 'replace' || 
		 ($params->{'item'}->{'type'} eq 'playlist' && $params->{'item'}->{'parser'} && scalar @{ $opml->{'items'} || [] } == 1) ) ) {
		my $item  = $opml->{'items'}[0];
		my $title = $item->{'name'} || $item->{'title'};
		my $url   = $item->{'url'};

		my %params = (
			'url'    => $url,
			'title'  => $title,
			'header' => $title,
			'headerAddCount' => 1,
		);

		if (!defined $url) {
			$params{'hideTitle'} = 1;
			$params{'hideURL'}   = 1;
		}

		if ($item->{'description'}) {
			my ($curline, @lines) = _breakItemIntoLines( $client, $item );
			$params{'details'} = \@lines;
		}

		return Slim::Buttons::Common::pushModeLeft($client, 'remotetrackinfo', \%params);
	}

	my $title = $opml->{'name'} || $opml->{'title'};
	
	# Add search option only if we are at the top level
	if ( $params->{'search'} && $title eq $params->{'feedTitle'} ) {
		push @{ $opml->{'items'} }, {
			name   => $client->string('SEARCH_STREAMS'),
			search => $params->{'search'},
			items  => [],
		};
	}

	# Remember previous timeout value
	my $timeout = $params->{'timeout'};

	my $radioDefault;

	my $index = 0;
	for my $item ( @{ $opml->{'items'} || [] } ) {
		
		# Add value keys to all items, so INPUT.Choice remembers state properly
		if ( !defined $item->{'value'} ) {
			$item->{'value'} = $item->{'name'};
		}
		
		# Copy timeout to items with a URL
		if ( $item->{'url'} ) {
			$item->{'timeout'} = $timeout;
		}
		
		# For radio buttons, copy default value to all other radio items
		if ( $item->{type} ) {
			if ( $item->{type} eq 'radio' && $item->{default} ) {
				$radioDefault = $item->{default};
			}
			elsif ( $item->{type} eq 'radio' ) {
				$item->{default} = $radioDefault;
			}
		}
		
		# Wrap text if needed
		if ( $item->{'wrap'} ) {
			my ($curline, @lines) = _breakItemIntoLines( $client, $item );
			
			my @wrapped;
			for my $line ( @lines ) {
				push @wrapped, {
					name  => $line,
					value => $line,
					type  => 'text',
					items => [],
				};
			}
			
			splice @{ $opml->{'items'} }, $index, 1, @wrapped;
		}
		
		$index++;
	}
	
	# If there is only 1 item and it has a 'showBriefly' attribute, it's a message that 
	# should be shown with showBriefly, not pushed
	if ( scalar @{ $opml->{'items'} } == 1 && $opml->{'items'}->[0]->{'showBriefly'} ) {
		my $item = $opml->{'items'}->[0];
		
		# If it also has a 'nowplaying' attribute, return to Now Playing afterwards
		my $callback = sub {};
		if ( $item->{'nowPlaying'} ) {
			$callback = sub {
				if ( blessed($client) ) {
					Slim::Buttons::Common::pushMode( $client, 'playlist' );
				}
			};
		}
		else {
			$callback = sub {
				if ( blessed($client) ) {
					my $popback = $item->{popback} || 1;
					
					while ( $popback-- ) {
						Slim::Buttons::Common::popMode($client);
					}
					
					# Refresh the menu if requested
					if ( $item->{refresh} ) {
						if ( my $refresh = $client->modeParameterStack->[-2]->{onRefresh} ) {
							# Get the new menu, pass a callback to support async refreshing
							$refresh->( $client, sub {
								my $refreshed = shift;
								
								# Get the INPUT.Choice mode and replace a few things
								my $choice = $client->modeParameterStack->[-1];
								$choice->{item}     = $refreshed;
								$choice->{listRef}  = $refreshed->{items};
							
								# valueRef caches the menu item for some reason, so we need to replace it
								my $listIndex = $choice->{listIndex};
								my $valueRef  = $choice->{listRef}->[ $listIndex ];
								$choice->{valueRef} = \$valueRef;
							
								$log->debug('Refreshed menu');
							
								$client->update;
							} );
						}
					}
				}
			};
		}
		
		$client->showBriefly( {
			line => [ $opml->{'title'}, $item->{'value'} ]
		},
		{
			scroll   => 1,
			callback => $callback,
		} );
		
		return;
	}
	
	if ( $log->is_debug ) {
		if ( $opml->{sorted} ) {
			$log->debug( 'Treating list as sorted' );
		}
		else {
			$log->debug( 'Treating list as unsorted' );
		}
	}
	
	my %params = (
		'url'        => $url,
		'timeout'    => $timeout,
		'item'       => $opml,
		# unique modeName allows INPUT.Choice to remember where user was browsing
		'modeName' => 
			( defined $params->{remember} && $params->{remember} == 0 ) 
			? undef : "XMLBrowser:$url:$title",
		'header'     => $title,
		'headerAddCount' => 1,
		'listRef'    => $opml->{'items'},

		'isSorted'   => $opml->{sorted} || 0,
		'lookupRef'  => sub {
			my $index = shift;

			return $opml->{'items'}->[$index]->{'name'};
		},

		'onRight'    => sub {
			my $client = shift;
			my $item   = shift;

			my $hasItems = ( ref $item->{'items'} eq 'ARRAY' ) ? scalar @{$item->{'items'}} : 0;
			my $isAudio  = ($item->{'type'} && $item->{'type'} eq 'audio') ? 1 : 0;
			my $itemURL  = $item->{'url'};
			my $title    = $item->{'name'} || $item->{'title'};
			my $parser   = $item->{'parser'};
			
			# Set itemURL to value, but only if value was not created from the name above
			if (!defined $itemURL && $item->{'value'} && $item->{'value'} ne $item->{'name'}) {
				$itemURL = $item->{'value'};
			}
			
			# Type = 'redirect', hack to allow XMLBrowser items to push into
			# other modes, used by TrackInfo menu
			if ( $item->{type} && $item->{type} eq 'redirect' 
				&& $item->{player} && $item->{player}->{mode} && $item->{player}->{modeParams} ) {

				Slim::Buttons::Common::pushModeLeft( 
					$client, 
					$item->{player}->{mode}, 
					$item->{player}->{modeParams} 
				);
				return;
			}
			
			# For type=radio items, don't push right, but submit the URL in the background.
			# After a good response, update the checkbox to the newly selected value
			if ( $item->{type} && $item->{type} eq 'radio' ) {
				
				# Did the user select a different item than the default?
				if ( $item->{default} ne $item->{name} ) {
						
					# Submit the URL in the background
					$client->block();
					
					$log->debug("Submitting $itemURL in the background for radio selection");
				
					Slim::Formats::XML->getFeedAsync(
						sub { 
							$log->debug("Status OK for $itemURL");
							
							# Change the default value in all other radio items
							for my $sibling ( @{ $opml->{items} } ) {
								next if $sibling->{type} ne 'radio';
								$sibling->{default} = $item->{name};
							}
							
							$client->unblock();
							
							$client->update();
						},
						\&gotError,
						{
							client => $client,
							url    => $itemURL,
						},
					);
				}
			}
			
			# Allow text-only items that go nowhere and just bump
			elsif ( $item->{'type'} && $item->{'type'} eq 'text' ) {
				$client->bumpRight();
			}
			elsif ( $item->{'search'} || $item->{'type'} eq 'search' ) {
				
				my $title;
				
				if ( $item->{'search'} ) {
					# Old-style search interface
					$title = $params->{'feedTitle'} . ' - ' . $client->string('SEARCH_STREAMS');
				}
				else {
					# New-style URL search interface
					$title = $item->{'name'};
				}
				
				my %params = (
					'header'          => $title,
					'cursorPos'       => 0,
					'charsRef'        => 'UPPER',
					'numberLetterRef' => 'UPPER',
					'callback'        => \&handleSearch,
					'item'            => $item,
				);
				
				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Text', \%params);
			}
			elsif ( $itemURL && !$hasItems ) {

				# follow a link
				my %params = (
					'url'     => $itemURL,
					'timeout' => $timeout,
					'title'   => $title,
					'header'  => $title,
					'headerAddCount' => 1,
					'item'    => $item,
					'parser'  => $parser,
				);

				if ($isAudio) {

					# Additional info if known
					my @details = ();
					if ( $item->{'bitrate'} ) {
						push @details, '{BITRATE}: ' . $item->{'bitrate'} . ' {KBPS}';
					}
					
					if ( my $duration = $item->{'duration'} ) {
						$duration = sprintf('%s:%02s', int($duration / 60), $duration % 60);
						push @details, '{LENGTH}: ' . $duration;
					}

					if ( $item->{'listeners'} ) {
						# Shoutcast
						push @details, '{NUMBER_OF_LISTENERS}: ' . $item->{'listeners'}
					}

					if ( $item->{'current_track'} ) {
						# Shoutcast
						push @details, '{NOW_PLAYING}: ' . $item->{'current_track'};
					}

					if ( $item->{'genre'} ) {
						# Shoutcast
						push @details, '{GENRE}: ' . $item->{'genre'};
					}

					if ( $item->{'source'} ) {
						# LMA Source
						push @details, '{SOURCE}: ' . $item->{'source'};
					}

					if ( $item->{'description'} ) {
						push @details, $item->{'description'};
					}

					$params{'details'} = \@details;
					
					Slim::Buttons::Common::pushModeLeft($client, 'remotetrackinfo', \%params);

				} else {

					Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);
				}

			}
			elsif ( $hasItems && ref($item->{'items'}) eq 'ARRAY' ) {

				# recurse into OPML item
				gotOPML(
					$client,
					$client->modeParam('url'),
					$item,
					{
						timeout  => $timeout,
						remember => $params->{remember},
					},
				);

			}
			elsif ( Slim::Control::XMLBrowser::hasDescription($item) ) {

				displayItemDescription($client, $item);

			} 
			else {

				$client->bumpRight();
			}
		},

		'onPlay'     => sub {
			my $client = shift;
			my $item   = shift;

			if ( $opml->{'playall'} || $item->{'playall'} ) {
				# Play all items from this level
				playItem( $client, $item, 'play', $opml->{'items'} );
			}
			else {
				# Play just a single item
				playItem( $client, $item );
			}
		},
		'onAdd'      => sub {
			my $client = shift;
			my $item   = shift;

			playItem($client, $item,'add');
		},
		
		'overlayRef' => \&overlaySymbol,
	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
}

sub handleSearch {
	my ( $client, $exitType ) = @_;
	
	$exitType = uc $exitType;
	
	if ( $exitType eq 'BACKSPACE' ) {
		
		Slim::Buttons::Common::popModeRight($client);
	}
	elsif ( $exitType eq 'NEXTCHAR' ) {
		
		my $item         = $client->modeParam('item');
		my $oldSearchURL = $item->{'search'};
		my $searchURL    = $item->{'url'};
		my $searchString = ${ $client->modeParam('valueRef') };
		
		if ( main::SLIM_SERVICE ) {
			# XXX: not sure why this is only needed on SN
			my $rightarrow = $client->symbols('rightarrow');
			$searchString  =~ s/$rightarrow//;
		}
		
		# Don't allow null search string
		return $client->bumpRight if $searchString eq '';
		
		$log->info("Search query [$searchString]");
		
		if ( $oldSearchURL ) {
		
			# Old OpenSearch method
			$client->block( 
				$client->string('SEARCHING'),
				$searchString
			);
			
			Slim::Formats::XML->openSearch(
				\&gotFeed,
				\&gotError,
				{
					'search' => $searchURL,
					'query'  => $searchString,
					'client' => $client,
				},
			);
		}
		else {
			
			# New URL method, replace {QUERY} with search query
			$searchURL =~ s/{QUERY}/$searchString/g;
			
			my %params = (
				'header'   => 'SEARCHING',
				'modeName' => "XMLBrowser:$searchURL:$searchString",
				'url'      => $searchURL,
				'title'    => $searchString,
				'timeout'  => $item->{'timeout'},
				'parser'   => $item->{'parser'},
			);
			
			Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
		}
	}
	else {
		
		$client->bumpRight();
	}
}

sub overlaySymbol {
	my ($client, $item) = @_;

	my $overlay;

	if ( $item->{type} && $item->{type} eq 'radio' ) {
		# Display check box overlay for type=radio
		my $default = $item->{default};
		$overlay = Slim::Buttons::Common::radioButtonOverlay( $client, $default eq $item->{name} );
	}
	elsif ( Slim::Control::XMLBrowser::hasAudio($item) ) {
		$overlay = $client->symbols('notesymbol');
	}
	elsif ( $item->{type} ne 'text' ) {
		$overlay = $client->symbols('rightarrow');
	}

	return [ undef, $overlay ];
}

sub _breakItemIntoLines {
	my ($client, $item) = @_;

	my @lines   = ();
	my $curline = '';
	my $description = $item->{'description'} || $item->{'name'};

	while ($description =~ /(\S+)/g) {

		my $newline = $curline . ' ' . $1;

		if ($client->measureText($newline, 2) > $client->displayWidth) {
			push @lines, Slim::Formats::XML::trim($curline);
			$curline = $1;
		} else {
			$curline = $newline;
		}
	}

	if ($curline) {
		push @lines, Slim::Formats::XML::trim($curline);
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

	if (my $link = Slim::Control::XMLBrowser::hasLink($item)) {

		push @lines, {
			'name'      => '{XML_LINK}: ' . $link,
			'value'     => $link,
			'overlayRef'=> [ undef, shift->symbols('rightarrow') ],
		}
	}

	if (Slim::Control::XMLBrowser::hasAudio($item)) {

		push @lines, {
			'name'      => '{XML_ENCLOSURE}: ' . $item->{'enclosure'}->{'url'},
			'value'     => $item->{'enclosure'}->{'url'},
			'overlayRef'=> [ undef, $client->symbols('notesymbol') ],
		};

		# its a remote audio source, use remotetrackinfo
		my %params = (
			'header'    => $item->{'title'},
			'headerAddCount' => 1,
			'title'     => $item->{'title'},
			'url'       => $item->{'enclosure'}->{'url'},
			'details'   => \@lines,
			'onRight'   => sub {
				my $client = shift;
				my $item = $client->modeParam('item');
				displayItemLink($client, $item);
			},
			'hideTitle' => 1,
			'hideURL'   => 1,
		);

		Slim::Buttons::Common::pushModeLeft($client, 'remotetrackinfo', \%params);

	} else {
		# its not audio, use INPUT.Choice to display...

		my %params = (
			'item'    => $item,
			'header'  => $item->{'title'},
			'headerAddCount' => 1,
			'listRef' => \@lines,

			'onRight' => sub {
				my $client = shift;
				my $item   = $client->modeParam('item');
				displayItemLink($client, $item);
			},

			'onPlay'  => sub {
				my $client = shift;
				my $item   = $client->modeParam('item');
				playItem($client, $item);
			},

			'onAdd'   => sub {
				my $client = shift;
				my $item   = $client->modeParam('item');
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
	my ($curline, @lines) = _breakItemIntoLines($client, $feed);

	# how many enclosures?
	my $count = 0;

	for my $i (@{$feed->{'items'}}) {
		if (Slim::Control::XMLBrowser::hasAudio($i)) {
			$count++;
		}
	}

	if ($count) {
		push @lines, {
			'name'           => '{XML_AUDIO_ENCLOSURES}: ' . $count,
			'value'          => $feed,
			'overlayRef'     => [ undef, $client->symbols('notesymbol') ],
		};
	}

	push @lines, '{URL}: ' . $client->modeParam('url');

	$feed->{'lastBuildDate'}  && push @lines, '{XML_DATE}: ' . $feed->{'lastBuildDate'};
	$feed->{'managingEditor'} && push @lines, '{XML_EDITOR}: ' . $feed->{'managingEditor'};
	
	# TODO: more lines to show feed date, ttl, source, etc.
	# even a line to play all enclosures

	my %params = (
		'url'       => $client->modeParam('url'),
		'title'     => $feed->{'title'},
		'feed'      => $feed,
		'header'    => $feed->{'title'},
		'headerAddCount' => 1,
		'details'   => \@lines,
		'hideTitle' => 1,
		'hideURL'   => 1,

	);

	Slim::Buttons::Common::pushModeLeft($client, 'remotetrackinfo', \%params);
}

sub displayItemLink {
	my $client = shift;
	my $item = shift;

	my $url = Slim::Control::XMLBrowser::hasLink($item);

	if (!$url) {
		$client->bumpRight();
		return;
	}

	# use PLUGIN.podcast mode to show the next url
	my %params = (
		'url'   => $url,
		'title' => $item->{'title'},
	);

	Slim::Buttons::Common::pushModeLeft($client, 'xmlbrowser', \%params);
}

sub playItem {
	my $client = shift;
	my $item   = shift;
	my $action = shift || 'play';
	my $others = shift || [];      # other items to add to playlist (action=play only)

	# verbose debug
	#warn "playItem: " . Data::Dump::dump($item, $others) . "\n";

	my $url   = $item->{'url'}  || $item->{'enclosure'}->{'url'};
	my $title = $item->{'name'} || $item->{'title'} || 'Unknown';
	my $type  = $item->{'type'} || $item->{'enclosure'}->{'type'} || 'audio';
	my $parser= $item->{'parser'};
	
	# If the item has a 'play' attribute, use that URL to play
	if ( $item->{'play'} ) {
		$url  = $item->{'play'};
		$type = 'audio';
	}
	elsif ( $item->{'playlist'} ) {
		# Or if there's a playlist attribute, use that as the playlist
		$url  = $item->{'playlist'};
		$type = 'playlist';
	}
	elsif ( $item->{'type'} eq 'redirect' && $item->{'player'} 
		&& $item->{'player'}->{'mode'} && $item->{'player'}->{'mode'} eq 'browsedb'
		&& $item->{'player'}->{'modeParams'}) {

		my $functions = Slim::Buttons::BrowseDB::getFunctions();

		if ($functions->{'play'}) {

			foreach (keys %{ $item->{'player'}->{'modeParams'} }) {
				$client->modeParam($_, $item->{'player'}->{'modeParams'}->{$_}); 
			}
			$client->modeParam('itemTitle', $item->{'name'});
						
			$functions->{'play'}->($client, $action, lc($action) eq 'add' ? 1 : 0);
		} 
	}
	
	$log->debug("Playing item, action: $action, type: $type, $url");
	
	if ( $type =~ /audio/i ) {

		my $string;
		my $duration;
		
		if ($action eq 'add') {

			$string = $client->string('ADDING_TO_PLAYLIST');

		} else {

			if (Slim::Player::Playlist::shuffle($client)) {

				$string = $client->string('PLAYING_RANDOMLY_FROM');

			} else {

				$string   = $client->string('NOW_PLAYING') . ' (' . $client->string('CONNECTING_FOR') . ')';
				$duration = 10;
			}
		}

		$client->showBriefly( {
			'line' => [ $string, $title ]
		}, {
			'duration' => $duration
		});
		
		if ( scalar @{$others} ) {
			# Emulate normal track behavior where playing a single track adds
			# all other tracks from that album to the playlist.
			
			# Add everything from $others to the playlist, it will include the item
			# we want to play.  Then jump to the index of the selected item
			my @urls;
			
			# Index to jump to
			my $index = 0;
			
			my $count = 0;
			
			for my $other ( @{$others} ) {
				my $otherURL = $other->{'url'}  || $other->{'enclosure'}->{'url'};
				my $title    = $other->{'name'} || $other->{'title'} || 'Unknown';
				
				if ( $other->{'play'} ) {
					$otherURL        = $other->{'play'};
					$other->{'type'} = 'audio';
				}
				
				# Don't add non-audio items
				next if !$other->{'type'} || $other->{'type'} ne 'audio';
				
				push @urls, $otherURL;
				
				# Is this item the one to jump to?
				if ( $url eq $otherURL ) {
					$index = $count;
				}

				# Set metadata about this URL
				Slim::Music::Info::setRemoteMetadata( $otherURL, {
					title   => $title,
					ct      => $other->{'mime'},
					secs    => $other->{'duration'},
					bitrate => $other->{'bitrate'},
				} );

				# This loop may have a lot of items and a lot of database updates
				main::idleStreams();
				
				$count++;
			}
			
			$client->execute([ 'playlist', 'clear' ]);
			$client->execute([ 'playlist', 'addtracks', 'listref', \@urls ]);
			$client->execute([ 'playlist', 'jump', $index ]);
		}
		else {
			# Set metadata about this URL
			Slim::Music::Info::setRemoteMetadata( $url, {
				title   => $title,
				ct      => $item->{'mime'},
				secs    => $item->{'duration'},
				bitrate => $item->{'bitrate'},
			} );
			
			$client->execute([ 'playlist', $action, $url, $title ]);
		}
	}
	elsif ($type eq 'playlist') {

		# URL is remote, load it asynchronously...
		# give user feedback while loading
		$client->block();
		
		my $params = {
			'client'  => $client,
			'action'  => $action,
			'url'     => $url,
			'parser'  => $parser,
			'item'    => $item,
			'timeout' => $item->{'timeout'},
		};
		
		# we may have a callback as URL
		if ( ref $url eq 'CODE' ) {
			my $callback = sub {
				my $menu = shift;
				
				if ( ref $menu ne 'ARRAY' ) {
					$menu = [ $menu ];
				}
				
				my $opml = {
					type  => 'opml',
					title => $title,
					items => $menu,
				};
				
				gotPlaylist( $opml, $params );
			};
			
			# get passthrough params if supplied
			my $pt = $item->{'passthrough'} || [];
			
			if ( $log->is_debug ) {
				my $cbname = Slim::Utils::PerlRunTime::realNameForCodeRef($url);
				$log->debug( "Fetching OPML playlist from coderef $cbname" );
			}
			
			return $url->( $client, $callback, @{$pt} );
		}
		
		# Playlist item may contain child items without a URL, i.e. Rhapsody's Tracks menu item
		elsif ( !$url && scalar @{ $item->{outline} || [] } ) {
			gotPlaylist( 
				{ 
					items => $item->{outline},
				},
				$params,
			);
			
			return;
		}
		
		# Bug 9492, playlist defined in a single OPML file
		elsif ( ref $item->{items} eq 'ARRAY' && scalar @{ $item->{items} } ) {
			gotPlaylist(
				{
					items => $item->{items},
				},
				$params,
			);
			
			return;
		}		
		
		Slim::Formats::XML->getFeedAsync(
			\&gotPlaylist,
			\&gotError,
			$params,
		);

	}
	elsif ( ref($item->{'items'}) eq 'ARRAY' && scalar @{$item->{'items'}} ) {

		# it's not an audio item, so recurse into OPML item
		gotOPML($client, $client->modeParam('url'), $item);
	}
	elsif ( $url && $title ) {
		
		# Push into the URL as if the user pressed right
		my %params = (
			'url'     => $url,
			'timeout' => $client->modeParam('timeout'),
			'title'   => $title,
			'header'  => $title,
			'headerAddCount' => 1,
			'parser'  => $parser,
			'item'    => $item,
		);
		
		Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	}
	else {

		$client->bumpRight();
	}
}


# some calls which have been moved to Slim::Control::XMLBrowser
# keep them here for compatibility with 3rd party apps
sub cliQuery {
	$log->error('deprecated call - please use Slim::Control::XMLBrowser::cliQuery() instead');
	Slim::Control::XMLBrowser::cliQuery(@_);
}

sub hasAudio {
	$log->error('deprecated call - please use Slim::Control::XMLBrowser::hasAudio() instead');
	Slim::Control::XMLBrowser::hasAudio(@_);
}

sub hasDescription {
	$log->error('deprecated call - please use Slim::Control::XMLBrowser::hasDescription() instead');
	Slim::Control::XMLBrowser::hasDescription(@_);
}

sub hasLink {
	$log->error('deprecated call - please use Slim::Control::XMLBrowser::hasLink() instead');
	Slim::Control::XMLBrowser::hasLink(@_);
}


=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Control::Request>

L<Slim::Formats::XML>

=cut

1;
