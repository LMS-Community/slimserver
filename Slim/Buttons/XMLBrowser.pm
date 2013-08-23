package Slim::Buttons::XMLBrowser;

# $Id$

# Copyright 2005-2009 Logitech.

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
use Slim::Utils::Prefs;

my $log = logger('formats.xml');
my $prefs = preferences('server');

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
		if ( $client->modeParam('blockPop') ) {
			$client->bumpLeft();
			return;
		}
		
		Slim::Buttons::Common::popMode($client);		
		return;
	}

	my $title  = $client->modeParam('title');
	my $url    = $client->modeParam('url');
	my $parser = $client->modeParam('parser');
	my $opml   = $client->modeParam('opml');
	my $parent = $client->modeParam('parent');
	
	# Pre-filled menu of OPML items
	if ( $opml ) {
		gotOPML( $client, $url, $opml, {} );

		$client->modeParam( handledTransition => 1 );
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
		
		$client->modeParam( handledTransition => 1 );
		return;
	}
		
	# Grab expires param here, as the block will change the param stack
	my $expires = $client->modeParam('expires');
	
	# the item is passed as a param so we can get passthrough params
	my $item = $client->modeParam('item');
	
	# Adjust HTTP timeout value to match the API on the other end
	my $timeout = $client->modeParam('timeout') || 5;
	
	# Should we remember where the user was browsing? (default: yes)
	my $remember = $client->modeParam('remember');
	if ( !defined $remember ) {
		$remember = 1;
	}
	
	# get modeParams before pusing block
	my $modeParams = $client->modeParams();

	# give user feedback while loading
	$client->block();
	
	my $params = {
		'client'    => $client,
		'url'       => $url,
		'expires'   => $expires,
		'feedTitle' => $title,
		'parser'    => $parser,
		'item'      => $item,
		'timeout'   => $timeout,
		'remember'  => $remember,
	};
	
	if (my ($feedAction, $feedActions) = Slim::Control::XMLBrowser::findAction($parent, $item, 
		($item->{'type'} && $item->{'type'} eq 'audio') ? 'info' : 'items') )
	{
		
		my @params = @{$feedAction->{'command'}};
		push @params, (0, 0);	# All items requests take _index and _quantity parameters
		if (my $params = $feedAction->{'fixedParams'}) {
			push @params, map { $_ . ':' . $params->{$_}} keys %{$params};
		}
		my @vars = exists $feedAction->{'variables'} ? @{$feedAction->{'variables'}} : @{$feedActions->{'commonVariables'} || []};
		for (my $i = 0; $i < scalar @vars; $i += 2) {
			push @params, $vars[$i] . ':' . $item->{$vars[$i+1]};
		}
		
		main::INFOLOG && $log->is_info && $log->info('Use CLI command for feed: ', join(', ', @params));
		
		my $callback = sub {
			my $opml = shift;
			$opml->{'type'}  ||= 'opml';
			$opml->{'title'} = $title;
			gotFeed( $opml, $params );
		};
	
	    push @params, 'feedMode:1';
	    push @params, 'wantMetadata:1' unless ($item->{'hasMetadata'} || '') eq 'album';
		my $proxiedRequest = Slim::Control::Request::executeRequest( $client, \@params );
		
		# wrap async requests
		if ( $proxiedRequest->isStatusProcessing ) {			
			$proxiedRequest->callbackFunction( sub { $callback->($_[0]->getResults); } );
		} else {
			$callback->($proxiedRequest->getResults);
		}
	}
	
	# Some plugins may give us a callback we should use to get OPML data
	# instead of fetching it ourselves.
	elsif ( ref $url eq 'CODE' ) {
		my $callback = sub {
			my $data = shift;
			my $opml;

			if ( ref $data eq 'HASH' ) {
				$opml = $data;
				$opml->{'type'}  ||= 'opml';
				$opml->{'title'} = $title;
			} else {
				$opml = {
					type  => 'opml',
					title => $title,
					items => (ref $data ne 'ARRAY' ? [$data] : $data),
				};
			}
			
			gotFeed( $opml, $params );
		};
		
		# get passthrough params if supplied
		my $pt = $item->{'passthrough'} || [];
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			my $cbname = Slim::Utils::PerlRunTime::realNameForCodeRef($url);
			$log->debug( "Fetching OPML from coderef $cbname" );
		}
		
		my $search = $modeParams->{'item'}->{'searchParam'} || $modeParams->{'search'};
		
		$url->( $client, $callback, {isButton => 1, params => $modeParams, search => $search}, @{$pt});
	}
	
	else {
		Slim::Formats::XML->getFeedAsync( 
			\&gotFeed,
			\&gotError,
			$params,
		);
	}
	
	# we're done.  gotFeed callback will finish setting up mode.

	# xmlbrowser always handles the pushTransition into this mode
	# - may have already transitioned to the destination mode if callbacks have already been called
	# - or waiting for callback and should show block animation now without a transitions
	$client->modeParam( handledTransition => 1 );
}

sub gotFeed {
	my ( $feed, $params ) = @_;
	
	my $client = $params->{'client'};
	my $url    = $params->{'url'};

	# must unblock now, before pushMode is called by getRSS or gotOPML
	$client->unblock;
	
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
			cover   => $item->{'image'} || $item->{'cover'},
		} );
		
		# This loop may have a lot of items and a lot of database updates
		main::idleStreams();
	}

	if (@urls) {

		my $action = $params->{'action'} || 'play';
		
		if ( $action eq 'play' ) {
			$client->execute([ 'playlist', 'play', \@urls ]);
			if (Slim::Buttons::Common::mode($client) ne 'playlist') {
				Slim::Buttons::Common::pushModeLeft($client, 'playlist');
			}
		}
		else {
			my $cmd = $action eq 'insert' ? 'inserttracks' : 'addtracks';
			$client->execute([ 'playlist', $cmd, 'listref', \@urls ]);
			Slim::Control::XMLBrowser::_addingToPlaylist($client, $action);
		}

	} else {

		$client->showBriefly({ line => [ undef, $client->string('PLAYLIST_EMPTY') ] });
	}
}

sub gotRSS {
	my ($client, $url, $feed, $params) = @_;

	# Include an item to access feed info
	if (($feed->{'items'}->[0]->{'value'} ne 'description') &&
		# skip this if xmlns:slim is used, and no description found
		!($feed->{'xmlns:slim'} && !$feed->{'description'})) {

		my %desc = (
			'title'      => '{XML_FEED_DESCRIPTION}',
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
				my $client   = shift;
				my $functarg = $_[2];
				
				my $action = $functarg eq 'single' ? 'add' : 'insert';
				
				Slim::Music::Info::setTitle( 
					$client->modeParam('url'),
					$client->modeParam('feed')->{'title'},
				);				

				# addthis feed as a playlist
				$client->execute(
					[ 'playlist', $action,
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
		
		'blockPop' => $client->modeParam('blockPop'),
		
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
				displayItemDescription($client, $item, $feed);
			} elsif ($item->{items}) {
				gotRSS($client, $url, $item, $params);
			} else {
				displayItemLink($client, $item);
			}
		},

		'onPlay' => sub {
			my $client = shift;
			my $item   = shift;
			playItem($client, $item, $feed);
		},

		'onAdd' => sub {
			my $client   = shift;
			my $item     = shift;
			my $functarg = shift;
			
			my $action = $functarg eq 'single' ? 'add' : 'insert';
			
			playItem($client, $item, $feed, $action);
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
		main::DEBUGLOG && $log->is_debug && $log->debug( "Executing command: " . Data::Dump::dump(\@p) );
		$client->execute( \@p );
		
		# Abort after the command if requested (allows OPML to execute i.e. button home)
		if ( $opml->{abort} ) {
			$log->is_debug && $log->debug('Aborting OPML');
			return;
		}
	}

	# Push staight into remotetrackinfo if asked to replace item or a playlist of one was returned with a parser
	if (($params->{'item'}->{'type'} && $params->{'item'}->{'type'} eq 'replace' || $opml->{'replaceparent'}) &&
		 $opml->{'items'} && scalar @{$opml->{'items'}} == 1) {
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
	
	# Remember previous timeout value
	my $timeout = $params->{'timeout'};

	my $radioDefault;

	for (my $index = 0; $index < scalar @{ $opml->{'items'} || []}; ) {
		my $item = $opml->{'items'}->[$index];
		
		if (my $label = delete $item->{'label'}) {
			$item->{'name'} = $client->string($label) . $client->string('COLON') . ' ' . $item->{'name'};
		}

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
			elsif ( $item->{type} eq 'textarea' ) {
				# Skip textarea type, this is for non-ip3k devices
				splice @{ $opml->{items} }, $index, 1;
				next;
			}
		}
		
		# Check for an 'ignore' param, a 'hide' == 'ip3k' param (probably obsolete) and skip the item in this UI
		# or it is a playcontrol item - don't need those for ip3k
		if ( $item->{ignore} || ($item->{hide} && $item->{hide} =~ /ip3k/) || $item->{'playcontrol'}) {
			splice @{ $opml->{items} }, $index, 1;
			next;
		}

		# keep track of station icons
		if ( 
			( $item->{play} || $item->{playlist} || ($item->{type} && ($item->{type} eq 'audio' || $item->{type} eq 'playlist')) )
			&& $item->{url} =~ /^http/ 
			&& $item->{url} !~ m|\.com/api/\w+/v1/opml| 
			&& ( my $cover = $item->{image} || $item->{cover} )
			&& !Slim::Utils::Cache->new->get("remote_image_" . $item->{url})
		) {
			Slim::Utils::Cache->new->set("remote_image_" . $item->{url}, $cover, 86400);
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
								
								if (ref $refreshed ne 'HASH') {
									$log->error('Cannot refresh menu; did not get HASH from refresh callback');
									Slim::Buttons::Common::popMode($client);
									$client->update;
									return;
								}
								
								# Get the INPUT.Choice mode and replace a few things
								my $choice = $client->modeParameterStack->[-1];
								$choice->{item}     = $refreshed;
								$choice->{listRef}  = $refreshed->{items};
							
								# valueRef caches the menu item for some reason, so we need to replace it
								my $listIndex = $choice->{listIndex};
								my $valueRef  = $choice->{listRef}->[ $listIndex ];
								$choice->{valueRef} = \$valueRef;
							
								main::DEBUGLOG && $log->debug('Refreshed menu');
							
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
	
	if ( main::DEBUGLOG && $log->is_debug ) {
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
		'windowId'   => $opml->{windowId} || '',
		'header'     => $title,
		'headerAddCount' => 1,
		'listRef'    => $opml->{'items'},
		
		'blockPop'   => $client->modeParam('blockPop'),

		'isSorted'   => $opml->{sorted} || 0,
		'lookupRef'  => sub {
			my $index = shift;
			my $item  = $opml->{'items'}->[$index];
			my $hasMetadata = $item->{'hasMetadata'} || '';
				
			if ($hasMetadata eq 'track') {
				return Slim::Music::Info::standardTitle($client, undef, $item) || $item->{name};
			} elsif ($hasMetadata eq 'album') {
				my $name = $item->{name};
				
				if ($prefs->get('showYear')) {
					my $year = $item->{'year'};
					$name .= " ($year)" if $year;
				}
		
				if ($prefs->get('showArtist') && (my $artist = $item->{'artist'} || $item->{'name2'})) {
					$name .= sprintf(' %s %s', $client->string('BY'), $artist);
				}
				
				return $name;
			} else {
				return $item->{name};
			}
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
			
			# Bug 13247, if there is a nextWindow value, pop back until we
			# find the mode with a matching windowId.
			# XXX: refresh that item?
			if ( my $nextWindow = $item->{nextWindow} ) {
				# Ignore special nextWindow values used by SP
				if ( $nextWindow !~ /^(?:home|parent|nowPlaying)$/ ) {		
					while ( Slim::Buttons::Common::mode($client) ) {
						Slim::Buttons::Common::popModeRight($client);
						if ( $client->modeParam('windowId') eq $nextWindow ) {
							last;
						}
					}
					return;
				}
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
					
					main::DEBUGLOG && $log->debug("Submitting $itemURL in the background for radio selection");
				
					Slim::Formats::XML->getFeedAsync(
						sub { 
							main::DEBUGLOG && $log->debug("Status OK for $itemURL");
							
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
			elsif ( $item->{'type'} && $item->{'type'} eq 'search' ) {
				
				# Search elements may include alternate title
				my $title = $item->{title} || $item->{name};
				
				my %params = (
					'header'          => $title,
					'cursorPos'       => 0,
					'charsRef'        => $item->{kbtype} || 'UPPER',
					'numberLetterRef' => $item->{kbtype} || 'UPPER',
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
					'parent'  => $opml,
					'parser'  => $parser,
				);

				if ($isAudio && ref $itemURL ne 'CODE' && !Slim::Control::XMLBrowser::findAction($opml, $item, 'info')) {

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

				displayItemDescription($client, $item, $opml);

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
				playItem( $client, $item, $opml, 'play', $opml->{'items'} );
			}
			else {
				# Play just a single item
				playItem( $client, $item, $opml );
			}
		},
		'onAdd'      => sub {
			my $client   = shift;
			my $item     = shift;
			my $functarg = shift;
			
			my $action = $functarg eq 'single' ? 'add' : 'insert';
			
			playItem($client, $item, $opml, $action);
		},
		'onCreateMix'     => sub {
			my $client = shift;
			my $item   = shift;

			# Play just a single item
			contextMenu( $client, $item, $opml );
		},
		
		'overlayRef' => \&overlaySymbol,
	);

	# if a list has textkeys defined, use these for numberScroll within Input.Choice
	if ($opml->{'sorted'} && $opml->{'items'}->[0] && defined $opml->{'items'}->[0]->{'textkey'}) {
		$params{'textkeyRef'} = sub {
			my $item = $opml->{'items'}->[shift] || return;
			return $item->{'textkey'} || $item->{'name'};
		};
	}

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
		my $searchURL    = $item->{'url'};
		my $searchString = ${ $client->modeParam('valueRef') };
		
		if ( main::SLIM_SERVICE ) {
			# XXX: not sure why this is only needed on SN
			my $rightarrow = $client->symbols('rightarrow');
			$searchString  =~ s/$rightarrow//;
		}
		
		# Don't allow null search string
		return $client->bumpRight if $searchString eq '';
		
		main::INFOLOG && $log->info("Search query [$searchString]");
			
		# Replace {QUERY} with search query
		$searchURL =~ s/{QUERY}/$searchString/g;
		
		my %params = (
			'header'   => 'SEARCHING',
			'modeName' => "XMLBrowser:$searchURL:$searchString",
			'url'      => $searchURL,
			'title'    => $searchString,
			'search'   => $searchString,
			'timeout'  => $item->{'timeout'},
			'parser'   => $item->{'parser'},
			'item'     => $item, # passed to carry passthrough params forward
		);
		
		Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	}
	else {
		
		$client->bumpRight();
	}
}

sub overlaySymbol {
	my ($client, $item) = @_;

	my $overlay;
	
	if ( ref $item ne 'HASH' ) {
		$overlay = $client->symbols('rightarrow');
	}
	elsif ( $item->{type} && $item->{type} eq 'radio' ) {
		# Display check box overlay for type=radio
		my $default = $item->{default};
		$overlay = Slim::Buttons::Common::radioButtonOverlay( $client, $default eq $item->{name} );
	}
	elsif ( $item->{url} && ref $item->{url} eq 'CODE' && (!$item->{type} || $item->{type} ne 'audio') ) {
		# Show rightarrow if there are more browseable levels below us
		$overlay = $client->symbols('rightarrow');
	}
	elsif ( Slim::Control::XMLBrowser::hasAudio($item) ) {
		$overlay = $client->symbols('notesymbol');
	}
	elsif ( !$item->{type} || $item->{type} ne 'text' ) {
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
	my $opml = shift;

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
		
		if ($item->{'enclosure'} && $item->{'enclosure'}->{'url'}) {

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
		}
		
		else {
			$client->bumpRight();
		}

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
				playItem($client, $item, $opml );
			},

			'onAdd'   => sub {
				my $client   = shift;
				my $item     = $client->modeParam('item');
				my $functarg = $_[2];
				
				my $action = $functarg eq 'single' ? 'add' : 'insert';
				
				playItem($client, $item, $action, $opml);
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

sub _showPlayAction {
	my $client = shift;
	my $action = shift;
	my $title = shift;
	
	my $string;
	my $duration;
	
	if ($action eq 'add') {
		$string = $client->string('ADDING_TO_PLAYLIST');
	}
	elsif ( $action eq 'insert' ) {
		$string = $client->string('INSERT_TO_PLAYLIST');
	}
	else {

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
}

sub playItem {
	my $client = shift;
	my $item   = shift;
	my $feed   = shift;
	my $action = shift || 'play';
	my $others = shift; 	     # other items to add to playlist (action=play only)

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
	
	main::DEBUGLOG && $log->debug("Playing item, action: $action, type: $type, $url");
	
	my $playalbum = $prefs->client($client)->get('playtrackalbum');

	# if player pref for playtrack album is not set, get the old server pref.
	if (!defined $playalbum) { $playalbum = $prefs->get('playtrackalbum'); }
	
	# Use action from item or parent feed if available

	my $actionKey = $action;
	if ($actionKey =~ /^(add|play)$/ && $others && $playalbum) {
		$actionKey .= 'all';
	}
	
	if (my ($feedAction, $feedActions) = Slim::Control::XMLBrowser::findAction($feed, $item, $actionKey)) {
		
		my @params = @{$feedAction->{'command'}};
		if (my $params = $feedAction->{'fixedParams'}) {
			push @params, map { $_ . ':' . $params->{$_}} keys %{$params};
		}
		my @vars = exists $feedAction->{'variables'} ? @{$feedAction->{'variables'}} : @{$feedActions->{'commonVariables'} || []};
		for (my $i = 0; $i < scalar @vars; $i += 2) {
			push @params, $vars[$i] . ':' . $item->{$vars[$i+1]};
		}
		
		main::INFOLOG && $log->is_info && $log->info("Use CLI command for $action($actionKey): ", join(', ', @params));
		
		_showPlayAction($client, $action, $title);

		Slim::Control::Request::executeRequest( $client, \@params );

		if ($action ne 'add' && $action ne 'insert' && Slim::Buttons::Common::mode($client) ne 'playlist') {
			Slim::Buttons::Common::pushModeLeft($client, 'playlist');
		}
	}
	
	elsif ( $type =~ /audio/i ) {

		_showPlayAction($client, $action, $title);

		if ( $others && $playalbum && scalar @{$others} ) {
			# Emulate normal track behavior where playing a single track adds
			# all other tracks from that album to the playlist.
			
			# Add everything from $others to the playlist, it will include the item
			# we want to play.  Then jump to the index of the selected item
			my @urls;
			
			# Index to jump to
			my $index;
			
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
					cover   => $other->{'image'} || $other->{'cover'},
				} );

				# This loop may have a lot of items and a lot of database updates
				main::idleStreams();
				
				$count++;
			}
			
			$index = undef if $action ne 'play';
			$client->execute([ 'playlist', $action.'tracks', 'listref', \@urls, undef, $index ]);
		}
		else {
			# Set metadata about this URL
			Slim::Music::Info::setRemoteMetadata( $url, {
				title   => $title,
				ct      => $item->{'mime'},
				secs    => $item->{'duration'},
				bitrate => $item->{'bitrate'},
				cover   => $item->{'image'} || $item->{'cover'},
			} );
			
			$client->execute([ 'playlist', $action, $url, $title ]);
		}

		if ($action ne 'add' && $action ne 'insert' && Slim::Buttons::Common::mode($client) ne 'playlist') {
			Slim::Buttons::Common::pushModeLeft($client, 'playlist');
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
				my $data = shift;
				my $opml;

				if ( ref $data eq 'HASH' ) {
					$opml = $data;
					$opml->{'type'}  ||= 'opml';
					$opml->{'title'} = $title;
				} else {
					$opml = {
						type  => 'opml',
						title => $title,
						items => (ref $data ne 'ARRAY' ? [$data] : $data),
					};
				}
				
				gotPlaylist( $opml, $params );
			};
			
			# get passthrough params if supplied
			my $pt = $item->{'passthrough'} || [];
			
			if ( main::DEBUGLOG && $log->is_debug ) {
				my $cbname = Slim::Utils::PerlRunTime::realNameForCodeRef($url);
				$log->debug( "Fetching OPML playlist from coderef $cbname" );
			}
			
			return $url->( $client, $callback, { isButton => 1 }, @{$pt} );
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

sub contextMenu {
	my $client = shift;
	my $item   = shift;
	my $feed   = shift;

	my $title = $item->{'name'} || $item->{'title'} || 'Unknown';
	my $type  = $item->{'type'} || $item->{'enclosure'}->{'type'} || 'audio';
	
	my $expires = $client->modeParam('expires');
	
	# Adjust HTTP timeout value to match the API on the other end
	my $timeout = $client->modeParam('timeout') || 5;
	
	# Should we remember where the user was browsing? (default: yes)
	my $remember = $client->modeParam('remember');
	if ( !defined $remember ) {
		$remember = 1;
	}
	
	# get modeParams before pusing block
	my $modeParams = $client->modeParams();

	my $params = {
		'client'    => $client,
		'expires'   => $expires,
		'feedTitle' => $title,
		'item'      => $item,
		'timeout'   => $timeout,
		'remember'  => $remember,
	};
	
	main::DEBUGLOG && $log->debug("Context menu for :", $title);
	
	if (my ($feedAction, $feedActions) = Slim::Control::XMLBrowser::findAction($feed, $item, 'info')) {
		
		my @params = @{$feedAction->{'command'}};
		if (my $params = $feedAction->{'fixedParams'}) {
			push @params, map { $_ . ':' . $params->{$_}} keys %{$params};
		}
		my @vars = exists $feedAction->{'variables'} ? @{$feedAction->{'variables'}} : @{$feedActions->{'commonVariables'} || []};
		for (my $i = 0; $i < scalar @vars; $i += 2) {
			push @params, $vars[$i] . ':' . $item->{$vars[$i+1]};
		}
		
		main::INFOLOG && $log->is_info && $log->info("Use CLI command for info: ", join(', ', @params));
		
		my $callback = sub {
			my $opml = shift;
			$opml->{'type'}  ||= 'opml';
			$opml->{'title'} = $title;
			
			# XXX maybe bumpRight if no entries in menu
			
			gotFeed( $opml, $params );
		};
	
	    push @params, 'feedMode:1';
		my $proxiedRequest = Slim::Control::Request::executeRequest( $client, \@params );
		
		# wrap async requests
		if ( $proxiedRequest->isStatusProcessing ) {			
			$proxiedRequest->callbackFunction( sub { $callback->($_[0]->getResults); } );
		} else {
			$callback->($proxiedRequest->getResults);
		}
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
