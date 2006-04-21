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
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Web::HTTP;
use Slim::Web::Pages;

sub handleWebIndex {
	my $class = shift;
	my $feed  = shift;
	my $title = shift;
	
	# If the feed is already XML data (Podcast List), send it to handleFeed
	if ( ref $feed eq 'HASH' ) {
		handleFeed( $feed, {
			'url'   => $feed->{'url'},
			'title' => $title,
			'args'  => \@_,
		} );
		return;
	}

	# fetch the remote content
	Slim::Formats::XML->getFeedAsync(
		\&handleFeed,
		\&handleError,
		{
			'url'   => $feed,
			'title' => $title,
			'args'  => \@_,
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
	my @index = split /\./, $stash->{'index'};
	
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
			if ( $subFeed->{'type'} ne 'audio' && defined $subFeed->{'url'} ) {

				Slim::Formats::XML->getFeedAsync(
					\&handleSubFeed,
					\&handleError,
					{
						'url'          => $subFeed->{'url'},
						'parent'       => $feed,
						'parentURL'    => $params->{'parentURL'} || $params->{'url'},
						'currentIndex' => \@crumbIndex,
						'args'         => [ $client, $stash, $callback, $httpClient, $response ],
					},
				);
				return;
			}
			
			# If the feed is an audio feed or Podcast enclosure, display the audio info
			if ( $subFeed->{'type'} eq 'audio' || $subFeed->{'enclosure'} ) {
				$stash->{'streaminfo'} = {
					'item'  => $subFeed,
					'index' => join '.', @index,
				};
			}
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
	}
	
	# play/add stream
	if ( $client && $stash->{'action'} && $stash->{'action'} =~ /play|add/ ) {
		my $play  = ($stash->{'action'} eq 'play');
		my $url   = $stash->{'streaminfo'}->{'item'}->{'url'};
		my $title = $stash->{'streaminfo'}->{'item'}->{'name'} 
			|| $stash->{'streaminfo'}->{'item'}->{'title'};
		
		# Podcast enclosures
		if ( my $enc = $stash->{'streaminfo'}->{'item'}->{'enclosure'} ) {
			$url = $enc->{'url'};
		}
		
		if ( $url ) {
			$::d_plugins && msg("XMLBrowser: playing/adding $url\n");
		
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
	else {
		
		my $itemCount = scalar @{ $stash->{'items'} };
		
			
			my $clientId = ( $client ) ? $client->id : undef;
			my $otherParams = 'index=' . join('.', @index) 
					. '&player=' . $clientId;
			
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
	$stash->{'msg'} = string('WEB_XML_ERROR') . "$title: ($error)";
	
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
	$subFeed->{'url'}   = undef;
	
	# re-cache the parsed XML to include the sub-feed
	my $cache = Slim::Utils::Cache->new();
	my $expires = 300;
	if ( my $data = $cache->get( $params->{'parentURL'} ) ) {
		if ( defined $data->{'_expires'} && $data->{'_expires'} > 0 ) {
			$expires = time - ( $data->{'_time'} + $data->{'_expires'} );
		}
	}
	$::d_plugins && msg("Web::XML: re-caching parsed XML for $expires seconds\n");
	$cache->set( $params->{'parentURL'} . '_parsedXML', $parent, $expires );
	
	handleFeed( $parent, $params );
}

sub processTemplate {	
	return Slim::Web::HTTP::filltemplatefile( @_ );
}

1;