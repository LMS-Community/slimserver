package Slim::Web::UPnPMediaServer;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Web UI for UPnP servers

use strict;

use URI::Escape qw(uri_escape uri_unescape);

use Slim::Utils::UPnPMediaServer;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

sub init {
	Slim::Web::Pages->addPageFunction( qr/^browseupnp\.(?:htm|xml)/, \&browseUPnP );
	Slim::Web::Pages->addPageFunction( qr/^upnpinfo\.(?:htm|xml)/, \&browseUPnP );
}

sub browseUPnP {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $device    = $params->{device};
	my $hierarchy = $params->{hierarchy};
	my $player    = $params->{player};
	my @levels    = map { uri_unescape($_) } split("__", $hierarchy);
	
	$params->{browseby} = uc( $params->{title} ) || 'BROWSE';

	my $id = $levels[-1];
	
	my $browse = 'BrowseDirectChildren';
	if ( $params->{metadata} ) {
		$browse = 'BrowseMetadata';
	}
	
	# Async load of container
	Slim::Utils::UPnPMediaServer::loadContainer( {
		udn         => $device,
		id          => $id,
		method      => $browse,
		limit       => $params->{itemsPerPage} || preferences('server')->get('itemsPerPage'),
		start       => $params->{start} || 0,
		callback    => \&gotContainer,
		passthrough => [ $client, $params, $callback, $httpClient, $response ],
	} );
	
	return;
}

sub gotContainer {
	my $container = shift;
	my ($client, $params, $callback, $httpClient, $response) = @_;
	
	unless ( ref $container eq 'HASH' ) {
		my $error = defined($client) 
			? $client->string('UPNP_REQUEST_FAILED') 
			: Slim::Utils::Strings::string('UPNP_REQUEST_FAILED');
			
		# Use the xmlbrowser template for errors
		$params->{pagetitle} = $params->{title};
		$params->{msg} = $error;

		# done, send output back to Web module for display
		my $output = Slim::Web::HTTP::filltemplatefile( 'xmlbrowser.html', $params );
		$callback->( $client, $params, $output, $httpClient, $response );
		return;
	}
	
	my $device    = $params->{device};
	my $hierarchy = $params->{hierarchy};
	my $player    = $params->{player};
	my @levels    = map { uri_unescape($_) } split("__", $hierarchy);

	# Construct the pwd header
	for (my $i = 0; $i < scalar @levels; $i++) {
		
		my $item = Slim::Utils::UPnPMediaServer::getItemInfo( $device, $levels[$i] );
		next unless defined($item);

		my $hierarchy = uri_escape( join( '__', @levels[0..$i] ) );
		my $title     = HTML::Entities::decode( $item->{title} );
		
		my $href 
			= 'href="browseupnp.html?device=' . uri_escape($device)
			. '&hierarchy=' . $hierarchy
			. '&player=' . uri_escape($player)
			. '"';
		
		push @{ $params->{pwd_list} }, {
			 href  => $href,
			 title => $title,
		};
	}

	if ( defined $container->{children} ) {
		my $items = $container->{children};
		
		my $otherparams = "&".join('&',
			"device=$device",
			'player=' . Slim::Utils::Misc::escape($player || ''),
			'hierarchy=' . uri_escape($hierarchy),
		);
		
		# Get the itemCount value from the TotalMatches field
		my $totalMatches = Slim::Utils::UPnPMediaServer::getTotalMatches( $device, $levels[-1] );
		
		$params->{pageinfo} = Slim::Web::Pages::Common->pageInfo( {
			itemCount   => $totalMatches || scalar @{$items},
			path        => $params->{path},
			otherParams => $otherparams,
			start       => $params->{start},
			perPage     => $params->{itemsPerPage},
		} );
		
		$params->{start} = $params->{pageinfo}->{startitem};
		
		my $count = 0;

		# Add an All Songs link if we have any songs in this list
		for my $item ( @{$items} ) {
			if ( $item->{url} ) {
				
				my $href 
					= 'browseupnp.html?device=' . uri_escape($device)
					. '&hierarchy=' . $hierarchy
					. '&player=' . uri_escape($player);
				
				push @{ $params->{browse_items} }, {
					hierarchy   => undef,
					showplayall => 1,
					playallhref => $href . '&cmd=playall',
					addallhref  => $href . '&cmd=addall',
					text        => string('ALL_SONGS'),
					odd         => $count % 2,
				};
				
				$count++;
				
				last;
			}
		}
				
		for my $item ( @{$items} ) {
			
			my $hier = uri_escape( join( '__', $hierarchy, $item->{id} ) );
			
			my $args
				= '?device=' . uri_escape($device)
				. '&hierarchy=' . $hier
				. '&player=' . uri_escape($player);
			
			# browse link
			my $href 
				= 'href="' . $params->{webroot} 
				. 'browseupnp.html' . $args . '"';
			
			# info link
			my $infohref 
				= 'href="' . $params->{webroot} 
				. 'upnpinfo.html' . $args 
				. '&metadata=0"';
			
			push @{ $params->{browse_items} }, {
				hierarchy   => $hier,
				descend     => ( $item->{childCount} || !$item->{url} ) ? 1 : 0,
				showplay    => ( $item->{url} ) ? 1 : 0,
				showdescend => ( $item->{childCount} || !$item->{url} ) ? 1 : 0,
				text        => $item->{title},
				href        => $href,
				infohref    => $infohref,
				odd         => $count % 2,
				itemobj     => $item,
			};
			
			$count++;
		}				
	}
	
	# Handle Play All/Add All commands
	if ( defined $container->{children} && $params->{cmd} && $client ) {
		my @urls;
		
		for my $item ( @{ $container->{children} } ) {
			push @urls, $item->{url} if $item->{url};
		}
		
		if ( $params->{cmd} eq 'playall' ) {
			$client->execute([ 'playlist', 'loadtracks', 'listref', \@urls ]);
		}
		else {
			$client->execute([ 'playlist', 'addtracks', 'listref', \@urls ]);
		}
	}
	
	my $output;
	
	if ( $params->{metadata} ) {
		
		# Item detail view
		$params->{itemobj} = $params->{browse_items}->[0]->{itemobj} || $params->{browse_items}->[1]->{itemobj};
		
		# Remove the last crumbtail item's link
		delete $params->{pwd_list}->[-1]->{href};
		
		$output = Slim::Web::HTTP::filltemplatefile( 'upnpinfo.html', $params );
	}
	else {
		$output = Slim::Web::HTTP::filltemplatefile( 'browsedb.html', $params );
	}
	$callback->( $client, $params, $output, $httpClient, $response );

}

1;

