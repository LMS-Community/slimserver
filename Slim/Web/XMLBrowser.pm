package Slim::Web::XMLBrowser;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class displays a generic web interface for XML feeds

use strict;

use Slim::Formats::XML;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Favorites;
use Slim::Web::HTTP;
use Slim::Web::Pages;

my $log = logger('formats.xml');

sub handleWebIndex {
	my ( $class, $args ) = @_;

	my $feed      = $args->{'feed'};
	my $title     = $args->{'title'};
	my $search    = $args->{'search'};
	my $expires   = $args->{'expires'};
	my $asyncArgs = $args->{'args'};
	my $item      = $args->{'item'} || {};
	
	# If the feed is already XML data (Podcast List), send it to handleFeed
	if ( ref $feed eq 'HASH' ) {

		handleFeed( $feed, {
			'url'     => $feed->{'url'},
			'title'   => $title,
			'search'  => $search,
			'expires' => $expires,
			'args'    => $asyncArgs,
		} );

		return;
	}
	
	# Handle plugins that want to use callbacks to fetch their own URLs
	if ( ref $feed eq 'CODE' ) {
		# get passthrough params if supplied
		my $pt = $item->{'passthrough'} || [];
		
		# Passthrough all our web params
		push @{$pt}, $asyncArgs;
		
		# first param is a $client object, but undef from webpages
		$feed->( undef, \&handleFeed, @{$pt} );
		return;
	}

	# Handle search queries
	if ( my $query = $asyncArgs->[1]->{'query'} ) {

		$log->info("Search query [$query]");

		Slim::Formats::XML->openSearch(
			\&handleFeed,
			\&handleError,
			{
				'search' => $search,
				'query'  => $query,
				'title'  => $title,
				'args'   => $asyncArgs,
			},
		);

		return;
	}

	# fetch the remote content
	Slim::Formats::XML->getFeedAsync(
		\&handleFeed,
		\&handleError,
		{
			'url'     => $feed,
			'title'   => $title,
			'search'  => $search,
			'expires' => $expires,
			'args'    => $asyncArgs,
		},
	);

	return;
}

sub handleFeed {
	my ( $feed, $params ) = @_;
	my ( $client, $stash, $callback, $httpClient, $response ) = @{ $params->{'args'} };

	$stash->{'pagetitle'} = $feed->{'title'} || string($params->{'title'});
	
	my $template = 'xmlbrowser.html';
	
	# breadcrumb
	my @crumb = ( {
		'name'  => $feed->{'title'} || string($params->{'title'}),
		'index' => undef,
	} );
		
	# select the proper list of items
	my @index = ();

	if (defined $stash->{'index'}) {

		@index = split /\./, $stash->{'index'};
	}

	# favorites class to allow add/del of urls to favorites, but not when browsing favorites list itself
	my $favs = Slim::Utils::Favorites->new($client) unless $feed->{'favorites'};
	my $favsItem;

	# action is add/delete favorite: pop the last item off the index as we want to display the whole page not the item
	# keep item id in $favsItem so we can process it later
	if ($stash->{'action'} && $stash->{'action'} =~ /^(favadd|favdel)$/ && @index) {
		$favsItem = pop @index;
	}

	if ( scalar @index ) {
		
		# index links for each crumb item
		my @crumbIndex = ();
		
		# descend to the selected item
		my $subFeed = $feed;
		for my $i ( @index ) {
			$subFeed = $subFeed->{'items'}->[$i];
			
			push @crumbIndex, $i;
			push @crumb, {
				'name'  => $subFeed->{'name'} || $subFeed->{'title'},
				'index' => join '.', @crumbIndex,
			};
			
			# If the feed is another URL, fetch it and insert it into the
			# current cached feed
			$subFeed->{'type'} ||= '';
			if ( $subFeed->{'type'} ne 'audio' && defined $subFeed->{'url'} ) {
				
				# Setup passthrough args
				my $args = {
					'url'          => $subFeed->{'url'},
					'feedTitle'    => $subFeed->{'name'} || $subFeed->{'title'},
					'parser'       => $subFeed->{'parser'},
					'expires'      => $params->{'expires'},
					'parent'       => $feed,
					'parentURL'    => $params->{'parentURL'} || $params->{'url'},
					'currentIndex' => \@crumbIndex,
					'args'         => [ $client, $stash, $callback, $httpClient, $response ],
				};
				
				if ( ref $subFeed->{'url'} eq 'CODE' ) {
					my $pt = $subFeed->{'passthrough'} || [];
					push @{$pt}, $args;
					$subFeed->{'url'}->( undef, \&handleSubFeed, @{$pt} );
					return;
				}

				Slim::Formats::XML->getFeedAsync(
					\&handleSubFeed,
					\&handleError,
					$args,
				);
				return;
			}
		}
			
		# If the feed contains no sub-items, display item details
		if ( !$subFeed->{'items'} 
			 ||
			 ( ref $subFeed->{'items'} eq 'ARRAY' && !scalar @{ $subFeed->{'items'} } ) 
		) {
			$stash->{'streaminfo'} = {
				'item'  => $subFeed,
				'index' => join '.', @index,
			};
		}
					
		$stash->{'pagetitle'} = $subFeed->{'name'};
		$stash->{'crumb'}     = \@crumb;
		$stash->{'items'}     = $subFeed->{'items'};
		$stash->{'index'}     = join( '.', @index ) . '.';
	}
	else {
		$stash->{'pagetitle'} = $feed->{'title'} || string($params->{'title'});
		$stash->{'crumb'}     = \@crumb;
		$stash->{'items'}     = $feed->{'items'};
		
		# insert a search box on the top-level page if we support searching
		# for this feed
		if ( $params->{'search'} ) {
			$stash->{'search'} = 1;
		}

		if (defined $favsItem) {
			$stash->{'index'} = undef;
		}
	}
	
	# play/add stream
	if ( $client && $stash->{'action'} && $stash->{'action'} =~ /^(play|add)$/ ) {
		my $play  = ($stash->{'action'} eq 'play');
		my $url   = $stash->{'streaminfo'}->{'item'}->{'url'};
		my $title = $stash->{'streaminfo'}->{'item'}->{'name'} 
			|| $stash->{'streaminfo'}->{'item'}->{'title'};
		
		# Podcast enclosures
		if ( my $enc = $stash->{'streaminfo'}->{'item'}->{'enclosure'} ) {
			$url = $enc->{'url'};
		}
		
		if ( $url ) {

			$log->info("Playing/adding $url");
		
			Slim::Music::Info::setTitle( $url, $title );
		
			if ( $play ) {
				$client->execute([ 'playlist', 'clear' ]);
				$client->execute([ 'playlist', 'play', $url ]);
			}
			else {
				$client->execute([ 'playlist', 'add', $url ]);
			}
		
			my $webroot = $stash->{'webroot'};
			$webroot =~ s/(.*?)plugins.*$/$1/;
			$template = 'xmlbrowser_redirect.html';
		}
	}
	# play all/add all
	elsif ( $client && $stash->{'action'} && $stash->{'action'} =~ /^(playall|addall)$/ ) {
		my $play  = ($stash->{'action'} eq 'playall');
		
		my @urls;
		for my $item ( @{ $stash->{'items'} } ) {
			if ( $item->{'type'} eq 'audio' && $item->{'url'} ) {
				push @urls, $item->{'url'};
				Slim::Music::Info::setTitle( $item->{'url'}, $item->{'name'} || $item->{'title'} );
			}
			elsif ( $item->{'enclosure'} && $item->{'enclosure'}->{'url'} ) {
				push @urls, $item->{'enclosure'}->{'url'};
				Slim::Music::Info::setTitle( $item->{'url'}, $item->{'name'} || $item->{'title'} );
			}
		}
		
		if ( @urls ) {

			$log->info(sprintf("Playing/adding all items:\n%s", join("\n", @urls)));
			
			if ( $play ) {
				$client->execute([ 'playlist', 'loadtracks', 'listref', \@urls ]);
			}
			else {
				$client->execute([ 'playlist', 'addtracks', 'listref', \@urls ]);
			}

			my $webroot = $stash->{'webroot'};
			$webroot =~ s/(.*?)plugins.*$/$1/;
			$template = 'xmlbrowser_redirect.html';
		}
	}
	else {
		
		# Check if any of our items contain audio, so we can display an
		# 'All Songs' link
		for my $item ( @{ $stash->{'items'} } ) {
			if ( ( $item->{'type'} && $item->{'type'} eq 'audio' ) || $item->{'enclosure'} ) {
				$stash->{'itemsHaveAudio'} = 1;
				$stash->{'currentIndex'}   = join '.', @index;
				last;
			}
		}
		
		my $itemCount = scalar @{ $stash->{'items'} };
			
		my $clientId = ( $client ) ? $client->id : undef;
		my $otherParams = 'index=' . join('.', @index) . '&player=' . $clientId;
		if ( $stash->{'query'} ) {
			$otherParams = 'query=' . $stash->{'query'} . '&' . $otherParams;
		}
			
		$stash->{'pageinfo'} = Slim::Web::Pages->pageInfo({
				'itemCount'   => $itemCount,
				'path'        => 'index.html',
				'otherParams' => $otherParams,
				'start'       => $stash->{'start'},
				'perPage'     => $stash->{'itemsPerPage'},
		});
		
		$stash->{'start'} = $stash->{'pageinfo'}{'startitem'};

		if ($stash->{'pageinfo'}{'totalpages'} > 1) {
			@{ $stash->{'items'} } = splice @{ $stash->{'items'} }, $stash->{'start'}, $stash->{'pageinfo'}{'itemsperpage'};
		}
	}

	if ($favs) {
		my @items = @{$stash->{'items'}};

		if (defined $favsItem && $items[$favsItem]) {
			if ($stash->{'action'} eq 'favadd') {
				$favs->add($items[$favsItem]->{'url'} || $items[$favsItem]->{'feedurl'}, $items[$favsItem]->{'name'});
			} elsif ($stash->{'action'} eq 'favdel') {
				$favs->deleteUrl($items[$favsItem]->{'url'} || $items[$favsItem]->{'feedurl'});
			}
		}
	
		for my $item (@items) {
			if ($item->{'url'} || $item->{'feedurl'}) {
				$item->{'favorites'} = $favs->hasUrl( $item->{'url'} || $item->{'feedurl'} ) ? 2 : 1;
			}
		}
	}

	my $output = processTemplate($template, $stash);
	
	# done, send output back to Web module for display
	$callback->( $client, $stash, $output, $httpClient, $response );
}

sub handleError {
	my ( $error, $params ) = @_;
	my ( $client, $stash, $callback, $httpClient, $response ) = @{ $params->{'args'} };
	
	my $template = 'xmlbrowser.html';
	
	my $title = string($params->{'title'});
	$stash->{'pagetitle'} = $title;
	$stash->{'msg'} = sprintf(string('WEB_XML_ERROR'), $title, $error);
	
	my $output = processTemplate($template, $stash);
	
	# done, send output back to Web module for display
	$callback->( $client, $stash, $output, $httpClient, $response );
}

# Fetch a feed URL that is referenced within another feed.
# After fetching, insert the contents into the original feed
sub handleSubFeed {
	my ( $feed, $params ) = @_;
	my ( $client, $stash, $callback, $httpClient, $response ) = @{ $params->{'args'} };
	
	# insert the sub-feed data into the original feed
	my $parent = $params->{'parent'};
	my $subFeed = $parent;
	for my $i ( @{ $params->{'currentIndex'} } ) {
		$subFeed = $subFeed->{'items'}->[$i];
	}
	$subFeed->{'items'} = $feed->{'items'};
	
	# No caching for callback-based plugins
	# XXX: this is a bit slow as it has to re-fetch each level
	if ( ref $subFeed->{'url'} eq 'CODE' ) {
		
		# Clear URL so it's not fetched again, save for favorites use first
		$subFeed->{'feedurl'} = $subFeed->{'url'};
		$subFeed->{'url'} = undef;
		
		# Clear passthrough data as it won't be needed again
		delete $subFeed->{'passthrough'};
	}
	else {
		
		# Clear URL so it's not fetched again, save for favorites use first
		$subFeed->{'feedurl'} = $subFeed->{'url'};
		$subFeed->{'url'} = undef;
		
		# re-cache the parsed XML to include the sub-feed
		my $cache = Slim::Utils::Cache->new();
		my $expires = $Slim::Formats::XML::XML_CACHE_TIME;

		$log->info("Re-caching parsed XML for $expires seconds.");

		$cache->set( $params->{'parentURL'} . '_parsedXML', $parent, $expires );
	}
	
	handleFeed( $parent, $params );
}

sub processTemplate {	
	return Slim::Web::HTTP::filltemplatefile( @_ );
}

1;
