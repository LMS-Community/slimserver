package Slim::Utils::UPnPMediaServer;

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# UPnP interface between the Control Point and player/web/plugins

use strict;
use warnings;

use HTML::Entities;
use Tie::LLHash;
use URI::Escape qw(uri_escape);

use Slim::Buttons::BrowseUPnPMediaServer;
use Slim::Web::UPnPMediaServer;
use Slim::Networking::Select;
use Slim::Networking::UPnP::ControlPoint;
use Slim::Utils::IPDetect;
use Slim::Utils::Misc;

our $registeredCallbacks = [];

sub init {
	Slim::Buttons::BrowseUPnPMediaServer::init();
	Slim::Web::UPnPMediaServer::init();
	
	# Look for all UPnP media servers on the network
	Slim::Networking::UPnP::ControlPoint->search( {
		callback   => \&foundDevice,
		deviceType => 'urn:schemas-upnp-org:device:MediaServer:1',
	} );
}

sub foundDevice {
	my ( $device, $event ) = @_;
	
	# We'll get a callback for all UPnP devices, but we only look for media servers
	if ( $device->getdevicetype =~ /MediaServer/ ) {
		my $menuName = HTML::Entities::decode( $device->getfriendlyname );
		
		if ( $event eq 'add' ) {
			$::d_upnp && msg("UPnP: Adding new media server: $menuName\n");
		
			addDeviceMenus( $device, $menuName );
			
			# If a UPnP server crashes, it won't send out a byebye message, so we need to poll
			# periodically to see if this server is still alive
			Slim::Utils::Timers::setTimer( $device, time() + 60, \&checkServerHealth );
		}
		elsif ( $event eq 'remove' ) {
			removeDeviceMenus( $device, $menuName );
			
			Slim::Utils::Timers::killTimers( $device, \&checkServerHealth );
		}
		
		# notify anyone who is interested in devices (i.e. Rhapsody plugin)
		for my $callback ( @{$registeredCallbacks} ) {
			$callback->( $device, $event );
		}
	}
	else {
		$::d_upnp && msgf("UPnP: %s is a %s %s (%s), ignoring\n",
			$device->getfriendlyname,
			$device->getmanufacturer,
			$device->getmodelname,
			$device->getdevicetype,
		);
	}
}

sub registerCallback {
	my $callback = shift;
	
	push @{$registeredCallbacks}, $callback;
	
	if ( $::d_upnp ) {
		my $func = Slim::Utils::PerlRunTime::realNameForCodeRef( $callback );
		msg("UPnP: New device callback registered: $func\n");
	}
}

sub checkServerHealth {
	my $device = shift;
		
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&checkServerHealthOK,
		\&checkServerHealthError, 
		{
			device  => $device,
			Timeout => 5,
		}
	);
	$http->get( $device->getlocation );
}

sub checkServerHealthOK {
	my $http   = shift;
	my $device = $http->params('device');
	
	# Device is still alive, so just set a new check timer
	Slim::Utils::Timers::setTimer( $device, time() + 60, \&checkServerHealth );
}

sub checkServerHealthError {
	my $http = shift;
	
	my $device = $http->params('device');
	my $error  = $http->error;
	
	$::d_upnp && msgf("UPnP: %s failed to respond at %s, removing. (%s)\n",
		$device->getfriendlyname,
		$device->getlocation,
		$error,
	);
	
	# Remove the device from the control point
	Slim::Networking::UPnP::ControlPoint::removeDevice( $device );
	
	foundDevice( $device, 'remove' );
}

sub addDeviceMenus {
	my $device = shift;
	my $name   = shift;

	if ( !Slim::Utils::Strings::stringExists($name) ) {
		Slim::Utils::Strings::addStringPointer( uc $name, $name );
	}
	
	my $udn = $device->getudn;
	
	my %params = (
		'useMode' => 'upnpmediaserver',
		'device'  => $udn,
		'title'   => $device->getfriendlyname,
	);
	
	# cache special id=0 item
	my $cache = Slim::Utils::Cache->new;
	$cache->set( "upnp_item_info_${udn}_0", {
		title => $device->getfriendlyname,
	} );

	Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', $name, \%params);

	Slim::Web::Pages->addPageLinks(
		'browse', { 
			$name => 'browseupnp.html?device=' . $device->getudn 
			       . '&hierarchy=0&title=' . uri_escape( $params{title} )
		}
	);
}

sub removeDeviceMenus {
	my $device = shift;
	my $name   = shift;

	Slim::Buttons::Home::delSubMenu('BROWSE_MUSIC', $name);	
	
	Slim::Web::Pages->addPageLinks(
		'browse', { $name => undef }
	);
}

sub loadContainer {
	my $args = shift;
	
	# Retarded servers such as Windows Media Connect require a certain order of XML elements (!)
	tie my %args, 'Tie::LLHash', (
		udn            => $args->{udn},
		service        => 'urn:schemas-upnp-org:service:ContentDirectory:1',
		
		# SOAP params, they MUST be in this order
		ObjectID       => $args->{id} || 0,
		BrowseFlag     => $args->{method} || 'BrowseDirectChildren',
		Filter         => '*',
		StartingIndex  => $args->{start} || 0,
		RequestedCount => $args->{limit} || 0,
		SortCriteria   => '',
		
		callback       => \&gotContainer,
		passthrough    => [ $args ],
	);
	
	Slim::Networking::UPnP::ControlPoint->browse( \%args );
}

sub gotContainer {
	my $io   = shift;
	my $args = shift;
	my $udn  = $args->{udn};
	
	my $cache = Slim::Utils::Cache->new;

	my @children;
	
	if ( $io ) {		
		# We use an IO::String object and parse in chunks to reduce memory usage
		
		local $/ = '</container>';
		while ( my $chunk = <$io> ) {
			
			# This can be slow if we have a huge file to process, so give back some time
			main::idleStreams();
			
			if ( $chunk =~ /<container(.*?)<\/container>/sg ) {
				my $node = $1;
			
				my ($title, $id, $type, $url, $childCount);
				if ( $node =~ m{<dc:title[^>]*>([^<]+)</dc:title>} ) {
					$title = HTML::Entities::decode($1);
					# some Rhapsody titles contain '??'
					$title =~ s/\?\?/ /g;
				}
				if ( $node =~ /id="([^"]+)"/ ) {
					$id = $1;
				}
				if ( $node =~ /childCount="([^"]+)"/ ) {
					$childCount = $1;
				}
				if ( $node =~ m{<res[^>]*>([^<]+)</res>} ) {
					$url = $1;
					
					# If the UPnP server is running on the same PC as SlimServer, URL may be localhost
					if ( my ($host) = $url =~ /(127.0.0.1|localhost)/ ) {
						my $realIP = Slim::Utils::IPDetect::IP();
						$url       =~ s/$host/$realIP/;
					}
				}

				my $props = {
					title      => $title,
					id         => $id,
					childCount => $childCount,
					url        => $url,
				};

				if ($url) {
					Slim::Music::Info::setTitle($url, $title);
				}
			
				# item info is cached for use in building crumb trails in the web UI
				$cache->set( "upnp_item_info_${udn}_${id}", $props, '1 hour' );
			
				push @children, $props;
			}
			else {
				# done with containers, do we also have items?
				if ( $chunk =~ /<item/i ) {
					$io = IO::String->new( \$chunk );
					
					local $/ = '</item>';
					while ( my $itemChunk = <$io> ) {
						
						# This can be slow if we have a huge file to process, so give back some time
						main::idleStreams();
						
						if ( $itemChunk =~ /<item(.*?)<\/item>/sg ) {
							my $node = $1;
							
							my ($title, $id, $type, $url);

							if ( $node =~ m{<dc:title[^>]*>([^<]+)</dc:title>} ) {
								$title = HTML::Entities::decode($1);
								# some Rhapsody titles contain '??'
								$title =~ s/\?\?/ /g;
							}
							if ( $node =~ m{<upnp:class>([^<]+)</upnp:class>} ) {
								$type = $1;
							}
							if ( $node =~ /id="([^"]+)"/ ) {
								$id = $1;
							}
							if ( $node =~ m{<res[^>]*>([^<]+)</res>} ) {
								$url = $1;
								
								# If the UPnP server is running on the same PC as SlimServer, URL may be localhost
								if ( my ($host) = $url =~ /(127.0.0.1|localhost)/ ) {
									my $realIP = Slim::Utils::IPDetect::IP();
									$url       =~ s/$host/$realIP/;
								}
							}
							
							my $props = {
								title => $title,
								id    => $id,
								url   => $url,
								type  => $type,
							};
							
							# grab all other namespace items
							my %otherItems = $node =~ m{<\w+:(\w+)>([^<]+)</\w+:}g;
							for my $key ( keys %otherItems ) {
								next if $key =~ /(?:title|class)/;	# we already grabbed these above
								$props->{$key} = HTML::Entities::decode( $otherItems{$key} );
							}

							if ($url) {
								Slim::Music::Info::setTitle($url, $title);
							}

							$cache->set( "upnp_item_info_${udn}_${id}", $props, '1 hour' );

							push @children, $props;
						}
						elsif ( $chunk =~ m{<TotalMatches>([^<]+)</TotalMatches>} ) {
							# total browse results, used for building pagination links
							my $matches = $1;
							my $id      = $args->{id};
							$cache->set( "upnp_total_matches_${udn}_${id}", $matches, '1 hour' );
						}
					}
				}
				elsif ( $chunk =~ m{<TotalMatches>([^<]+)</TotalMatches>} ) {
					# total browse results, used for building pagination links
					my $matches = $1;
					my $id      = $args->{id};
					$cache->set( "upnp_total_matches_${udn}_${id}", $matches, '1 hour' );
				}
			}
		}
	}
	else {
		# request failed, add 1 child with the failure message
		push @children, {
			'title' => Slim::Utils::Strings::string('UPNP_REQUEST_FAILED'),
		};
	}
	
	my $container = { 
		children => \@children
	};
	
	# If we are a metadata request, and have a blurbURI, fetch the blurb text
	if ( $args->{method} eq 'BrowseMetadata' ) {
		if ( my $blurbURI = $container->{children}->[0]->{blurbURI} ) {
			my $http = Slim::Networking::SimpleAsyncHTTP->new(
				\&gotBlurb,
				\&gotBlurbError,
				{
					args      => $args,
					container => $container,
				}
			);
			$http->get( $blurbURI );
			return;
		}
	}		

	my $callback    = $args->{callback};
	my $passthrough = $args->{passthrough} || [];
	$callback->( $container, @{$passthrough} );
}

sub getItemInfo {
	my $udn = shift;
	my $id  = shift;

	my $cache = Slim::Utils::Cache->new;
	return $cache->get( "upnp_item_info_${udn}_${id}");
}

sub getTotalMatches {
	my $udn = shift;
	my $id  = shift;

	my $cache = Slim::Utils::Cache->new;
	return $cache->get( "upnp_total_matches_${udn}_${id}");
}

sub gotBlurb {
	my $http = shift;
	my $args = $http->params('args');
	
	my $container = $http->params('container');
	my $content   = $http->content;
	
	if ( $content ) {
		# translate newlines
		$content =~ s/\\n/\n\n/g;
		$container->{children}->[0]->{blurbText} = $content;
	}

	my $callback    = $args->{callback};
	my $passthrough = $args->{passthrough} || [];
	$callback->( $container, @{$passthrough} );
}

sub gotBlurbError {
	my $http  = shift;
	my $args  = $http->params('args');
	
	$::d_upnp && msgf("UPnP: Error while trying to fetch blurb text at %s: %s\n",
		$http->url,
		$http->error,
	);

	my $container   = $http->params('container');
	my $callback    = $args->{callback};
	my $passthrough = $args->{passthrough} || [];
	$callback->( $container, @{$passthrough} );
}

1;
