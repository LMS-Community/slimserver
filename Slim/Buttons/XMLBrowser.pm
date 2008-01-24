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
		
		# Some plugins may give us a callback we should use to get OPML data
		# instead of fetching it ourselves.
		if ( ref $url eq 'CODE' ) {
			# get passthrough params if supplied
			my $pt = $item->{'passthrough'} || [];
			return $url->( $client, \&gotFeed, @{$pt} );
		}
		
		Slim::Formats::XML->getFeedAsync( 
			\&gotFeed,
			\&gotError,
			{
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
			},
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

	my $action = 'play';
	
	if ( !$params->{'action'} ) {
		# check cached action
		$action = Slim::Utils::Cache->new->get( $client->id . '_playlist_action' ) || 'play';
	}
	else {
		$action = $params->{'action'};
	}
	
	if ( $action eq 'play' ) {
		$client->execute([ 'playlist', 'play', \@urls ]);
	}
	else {
		$client->execute([ 'playlist', 'addtracks', 'listref', \@urls ]);
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
		'modeName' => ( $params->{'remember'} ) ? "XMLBrowser:$url" : undef,
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
		my @p = split / /, $opml->{'command'};
		$client->execute( \@p );
	}

	# Push staight into remotetrackinfo if asked to replace item or a playlist of one was returned
	if ($params->{'item'}->{'type'} && $params->{'item'}->{'type'} =~ /^(replace|playlist)$/ && scalar @{ $opml->{'items'} || [] } == 1) {
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
					Slim::Buttons::Common::popMode($client);
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

	my %params = (
		'url'        => $url,
		'timeout'    => $timeout,
		'item'       => $opml,
		# unique modeName allows INPUT.Choice to remember where user was browsing
		'modeName'   => ( $params->{'remember'} ) ? "XMLBrowser:$url:$title" : undef,
		'header'     => fitTitle( $client, $title, scalar @{ $opml->{'items'} } ),
		'listRef'    => $opml->{'items'},

		'isSorted'   => 1,
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
						timeout => $timeout,
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
		
		# we may have a callback as URL
		if ( ref $url eq 'CODE' ) {
			# get passthrough params if supplied
			my $pt = $item->{'passthrough'} || [];
			
			# This is not flexible enough to support passthrough items for
			# gotPlaylist(), so we need to cache the action the user wants,
			# or else an add will work like play
			if ( $action ne 'play' ) {
				Slim::Utils::Cache->new->set( $client->id . '_playlist_action', $action, 60 );
			}
			
			return $url->( $client, \&gotPlaylist, @{$pt} );
		}
		
		# Playlist item may contain child items without a URL, i.e. Rhapsody's Tracks menu item
	    elsif ( !$url && scalar @{ $item->{outline} || [] } ) {
	        gotPlaylist( 
	            { 
	                items => $item->{outline},
	            },
	            {
	                client => $client,
	                action => $action,
	                parser => $parser,
	            },
	        );
	        
	        return;
	    }
		
		Slim::Formats::XML->getFeedAsync(
			\&gotPlaylist,
			\&gotError,
			{
				'client'  => $client,
				'action'  => $action,
				'url'     => $url,
				'parser'  => $parser,
				'item'    => $item,
			},
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
			
			# Change URL if there is a play attribute
			if ( $isPlaylistCmd && $subFeed->{play} ) {
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
					$log->debug("Asynchronously fetching subfeed " . $subFeed->{url} . " - will be back!");

					Slim::Formats::XML->getFeedAsync(
						\&_cliQuerySubFeed_done,
						\&_cliQuery_error,
						$args,
					);
				}
				
				return;
			}

			# If the feed is an audio feed or Podcast enclosure, display the audio info
			# This is a leaf item, so show as much info as we have and go packing after that.
			
			
			if (	$isItemQuery &&
					(
						!defined($subFeed->{'items'}) ||
						scalar(@{$subFeed->{'items'}}) == 0 ||
						$subFeed->{'type'} eq 'audio' || 
						$subFeed->{'enclosure'} 
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
								'cmd' => [$query, 'playlist', 'load'],
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
								'cmd'     => 'load',
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
							};
							$request->addResultLoop($loopname, $cnt, 'text', $items{$mode}{'string'});
							$request->addResultLoop($loopname, $cnt, 'actions', $actions);
							$request->addResultLoop($loopname, $cnt, 'style', $items{$mode}{'style'});
							$cnt++;
						}
						
						if ( my $title = $hash{name} ) {
							my $text = $request->client->string('TITLE') . ": $title";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$cnt++;
						}
						
						if ( my $url = $hash{url} ) {
							my $text = $request->client->string('URL') . ": $url";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$cnt++;
						}
						
						if ( my $bitrate = $hash{bitrate} ) {
							my $text = $request->client->string('BITRATE') . ": $bitrate " . $request->client->string('KBPS');
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$cnt++;
						}
						
						if ( my $duration = $hash{duration} ) {
							$duration = sprintf('%s:%02s', int($duration / 60), $duration % 60);
							my $text = $request->client->string('LENGTH') . ": $duration";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$cnt++;
						}
						
						if ( my $listeners = $hash{listeners} ) {
							# Shoutcast
							my $text = $request->client->string('NUMBER_OF_LISTENERS') . ": $listeners";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$cnt++;
						}
						
						if ( my $current_track = $hash{current_track} ) {
							# Shoutcast
							my $text = $request->client->string('NOW_PLAYING') . ": $current_track";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$cnt++;
						}
						
						if ( my $genre = $hash{genre} ) {
							# Shoutcast
							my $text = $request->client->string('GENRE') . ": $genre";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
							$cnt++;
						}
						
						if ( my $source = $hash{source} ) {
							# LMA
							my $text = $request->client->string('SOURCE') . ": $source";
							$request->addResultLoop($loopname, $cnt, 'text', $text);
							$request->addResultLoop($loopname, $cnt, 'style', 'itemNoAction');
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

		if ($client && $method =~ /^(add|play|insert|load)$/i) {
			# single item
			if ((defined $subFeed->{'url'} && $subFeed->{'type'} eq 'audio' || defined $subFeed->{'enclosure'})
				&& (defined $subFeed->{'name'} || defined $subFeed->{'title'})) {
	
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
						$client->execute([ 'playlist', 'addtracks', 'listref', \@urls ]);
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

	
		# allow searching in the name field
		if ($search && @{$subFeed->{'items'}}) {
			my @found = ();
			my $i = 0;
			for my $item ( @{$subFeed->{'items'}} ) {
				if ($item->{'name'} =~ /$search/i || $item->{'title'} =~ /$search/i) {
					$item->{'_slim_id'} = $i;
					push @found, $item;
				}
				$i++;
			}
			
			$subFeed->{'items'} = \@found;
		}
	
		my $count = defined @{$subFeed->{'items'}} ? @{$subFeed->{'items'}} : 0;
		
		# now build the result
	
		my $hasImage = 0;
		
		$request->addResult('count', $count);
		
		if ($count) {
		
			my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);
		
			my $loopname = $menuMode ? 'item_loop' : 'loop_loop';
			my $cnt = 0;
			$request->addResult('offset', $start) if $menuMode;

			if ($valid) {
				
				$request->addResult( 'title', $subFeed->{'name'} || $subFeed->{'title'} );
				
				for my $item ( @{$subFeed->{'items'}}[$start..$end] ) {
					
					my $hasItems = 1;
					
					# create an ordered hash to store this stuff...
					tie (my %hash, "Tie::IxHash");
					
					$hash{'id'} = join('.', @crumbIndex, defined $item->{'_slim_id'} ? $item->{'_slim_id'} : $start + $cnt);
					$hash{'name'} = $item->{'name'} if defined $item->{'name'};
					$hash{'title'} = $item->{'title'} if defined $item->{'title'};
					$hash{'url'} = $item->{'url'} if $want_url && defined $item->{'url'};
					$hash{'image'} = $item->{'image'} if defined $item->{'image'};

					my $hasAudio = defined(hasAudio($item)) + 0;
					$hash{'isaudio'} = $hasAudio;

					foreach my $data (keys %{$item}) {
						if (ref($item->{$data}) eq 'ARRAY') {
							if (scalar @{$item->{$data}}) {
								$hasItems = scalar @{$item->{$data}};
							}
						}
					}		
					$hash{'hasitems'} = $hasItems;

					if ($menuMode) {
						
						$request->addResultLoop($loopname, $cnt, 'text', $hash{'name'} || $hash{'title'});
						
						my $params = {};
						my $id = $hash{id};
						
						if ( $item->{type} ne 'text' ) {							
							$params = {
								item_id => "$id", #stringify, make sure it's a string
							};
						}
						
						if ( $item->{image} ) {
							$request->addResultLoop( $loopname, $cnt, 'icon', $item->{image} );
							$hasImage = 1;
						}
						
						if ( $item->{type} eq 'search' ) {
							#$params->{search} = '__INPUT__';
							
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
									text => Slim::Utils::Strings::string('JIVE_SEARCHFOR_HELP')
								},
							};
							
							$request->addResultLoop( $loopname, $cnt, 'actions', $actions );
							$request->addResultLoop( $loopname, $cnt, 'input', $input );
						}
						
						if ( scalar keys %{$params} ) {
							$request->addResultLoop( $loopname, $cnt, 'params', $params );
						}
					}
					else {
						$request->setResultLoopHash($loopname, $cnt, \%hash);
					}
					$cnt++;
				}
			}

		}
		
		if ($menuMode) {

			# decide what is the next step down
			# we go to xxx items from xx items :)

			# build the base element
			my $params = {
				'menu' => $query,
			};
			
			if ( $url ) {
				$params->{'url'} = $url;
			}
			
			my $base = {
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
					},
					'add' => {
						'player' => 0,
						'cmd' => [$query, 'playlist', 'add'],
						'itemsParams' => 'params',
					},
				},
			};

			# Change window menuStyle to album if any images are in the list
			if ( $hasImage ) {
				$request->addResult('window', {
					menuStyle => 'album',
				});
			}

			$request->addResult('base', $base);
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
		my @p = split / /, $feed->{command};
		my $client = $params->{request}->client();
		$client->execute( \@p );
	}
	
	# insert the sub-feed data into the original feed
	my $parent = $params->{'parent'};
	my $subFeed = $parent;
	for my $i ( @{ $params->{'currentIndex'} } ) {
		$subFeed = $subFeed->{'items'}->[$i];
	}

	if ($subFeed->{'type'} && $subFeed->{'type'} =~ /^(replace|playlist)$/ && scalar @{ $feed->{'items'} } == 1) {
		# in the case of a replacable menu or playlist of one update previous entry to avoid new menu level
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

sub _cliQuery_error {
	my ( $err, $params ) = @_;
	
	my $request = $params->{'request'};
	my $url     = $params->{'url'};
	
	logError("While retrieving [$url]: [$err]");
	
	$request->addResult("networkerror", 1);
	$request->addResult('count', 0);

	$request->setStatusDone();	
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Control::Request>

L<Slim::Formats::XML>

=cut

1;
