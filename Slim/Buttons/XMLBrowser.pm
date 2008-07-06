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
use Tie::IxHash;
use URI::Escape qw(uri_unescape);

use Slim::Buttons::Common;
use Slim::Control::Request;
use Slim::Formats::XML;
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
			'header'  => "{XML_ERROR} {count}",
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
		'header'  => "{XML_ERROR} {count}",
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
		_addingToPlaylist($client, $action);
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
		'header'   => fitTitle( $client, $feed->{'title'} ),

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
			if (hasDescription($item)) {
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
			'header' => fitTitle($client, $title),
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
		'header'     => fitTitle( $client, $title, scalar @{ $opml->{'items'} } ),
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
					'header'  => fitTitle( $client, $title ),
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
			elsif ( hasDescription($item) ) {

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

	my $overlay = '';

	if ( hasAudio($item) ) {

		$overlay .= $client->symbols('notesymbol');
	}
	
	$item->{type} ||= ''; # avoid warning but still display right arrow
	
	if ( $item->{type} eq 'radio' ) {
		# Display check box overlay for type=radio
		my $default = $item->{default};
		$overlay = Slim::Buttons::Common::checkBoxOverlay( $client, $default eq $item->{name} );
	}
	elsif ( $item->{type} ne 'text' && ( hasDescription($item) || hasLink($item) ) ) {

		$overlay .= $client->symbols('rightarrow');
	}

	return [ undef, $overlay ];
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

	if (my $link = hasLink($item)) {

		push @lines, {
			'name'      => '{XML_LINK}: ' . $link,
			'value'     => $link,
			'overlayRef'=> [ undef, shift->symbols('rightarrow') ],
		}
	}

	if (hasAudio($item)) {

		push @lines, {
			'name'      => '{XML_ENCLOSURE}: ' . $item->{'enclosure'}->{'url'},
			'value'     => $item->{'enclosure'}->{'url'},
			'overlayRef'=> [ undef, $client->symbols('notesymbol') ],
		};

		# its a remote audio source, use remotetrackinfo
		my %params = (
			'header'    => fitTitle( $client, $item->{'title'} ),
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
			'header'  => $item->{'title'} . ' {count}',
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
		if (hasAudio($i)) {
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
		'header'    => fitTitle( $client, $feed->{'title'} ),
		'details'   => \@lines,
		'hideTitle' => 1,
		'hideURL'   => 1,

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
	#warn Data::Dump::dump($item, $others);

	my $url   = $item->{'url'}  || $item->{'enclosure'}->{'url'};
	my $title = $item->{'name'} || $item->{'title'} || 'Unknown';
	my $type  = $item->{'type'} || $item->{'enclosure'}->{'type'} || '';
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
			'header'  => fitTitle( $client, $title ),
			'parser'  => $parser,
			'item'    => $item,
		);
		
		Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	}
	else {

		$client->bumpRight();
	}
}

# Fit a title into the available display, truncating if necessary
sub fitTitle {
	my ( $client, $title, $numItems ) = @_;
	
	# number of items in the list, to fit the (xx of xx) text properly
	$numItems ||= 2;
	my $num = '?' x length $numItems;
	
	my $max    = $client->displayWidth;
	my $length = $client->measureText( $title . " ($num of $num) ", 1 );
	
	return $title . ' {count}' if $length <= $max;
	
	while ( $length > $max ) {
		$title  = substr $title, 0, -1;
		$length = $client->measureText( $title . "... ($num of $num) ", 1 );
	}
	
	return $title . '... {count}';
}

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
			'url'        => $feed->{'url'},
			'query'      => $query,
			'expires'    => $expires,
#			'forceTitle' => $forceTitle,
		} );
		return;
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
	
	# select the proper list of items
	my @index = ();

	if (defined($item_id)) {
		
		$log->debug("Splitting $item_id");

		@index = split /\./, $item_id;
	}
	
	my $subFeed = $feed;
	
#	use Data::Dumper;
#	print Data::Dumper::Dumper($subFeed);
	
	my @crumbIndex = ();
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
				
				if ( $i =~ /\d+_(.+)/ ) {
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
							$play_string = $request->client->string('JIVE_PLAY_THIS_SONG');
							$add_string  = $request->client->string('JIVE_ADD_THIS_SONG');
						}
						else {
							# Items without duration are streams
							$play_string = $request->client->string('PLAY');
							$add_string  = $request->client->string('ADD');
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
							my $text = $request->client->string('TITLE') . ": $title";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $url = $hash{url} ) {
							my $text = $request->client->string('URL') . ": $url";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $bitrate = $hash{bitrate} ) {
							my $text = $request->client->string('BITRATE') . ": $bitrate " . $request->client->string('KBPS');
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $duration = $hash{duration} ) {
							$duration = sprintf('%s:%02s', int($duration / 60), $duration % 60);
							my $text = $request->client->string('LENGTH') . ": $duration";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $listeners = $hash{listeners} ) {
							# Shoutcast
							my $text = $request->client->string('NUMBER_OF_LISTENERS') . ": $listeners";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $current_track = $hash{current_track} ) {
							# Shoutcast
							my $text = $request->client->string('NOW_PLAYING') . ": $current_track";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $genre = $hash{genre} ) {
							# Shoutcast
							my $text = $request->client->string('GENRE') . ": $genre";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$request->addResultLoop($loopname, $cnt, 'action', 'none');
							$cnt++;
						}
						
						if ( my $source = $hash{source} ) {
							# LMA
							my $text = $request->client->string('SOURCE') . ": $source";
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
							my $string = $request->client->string($token);
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

		$log->info("Play an item.");

		# get our parameters
		my $client = $request->client();
		my $method = $request->getParam('_method');

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
				
					$client->execute([ 'playlist', 'clear' ]) if ($method =~ /play|load/i);
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
					
					if ( $item->{type} && $item->{type} !~ /^(?:text|audio)$/i ) {
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
							for my $key ('window', 'showBigArtwork', 'style', 'nextWindow', 'playHoldAction') {
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
									text => $request->client->string('JIVE_SEARCHFOR_HELP')
								},
								softbutton1 => $request->client->string('INSERT'),
								softbutton2 => $request->client->string('DELETE'),
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
	} else {
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
			?  $client->string('JIVE_POPUP_ADDING_TO_PLAYLIST', ' ') 
			:  $client->string('JIVE_POPUP_ADDING_TO_PLAY_NEXT', ' ') ;

	$client->showBriefly(
			{ line => [ $string ], },
			{ 
				jive => {
					'type'    => 'popupplay',
					'text'    => [ $string ],
				},
			},
                );
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

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Control::Request>

L<Slim::Formats::XML>

=cut

1;
