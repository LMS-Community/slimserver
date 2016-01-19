package Slim::Plugin::RemoteLibrary::UPnP::MediaServer;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# UPnP interface between the Control Point and player/web/plugins

use strict;

use HTML::Entities;
use Tie::LLHash;
use URI::Escape qw(uri_escape);

use Slim::Utils::IPDetect;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

use Slim::Plugin::RemoteLibrary::UPnP::ControlPoint;

my %devices;
#our $registeredCallbacks = [];

my $log = logger('plugin.remotelibrary');
my $prefs = preferences('plugin.remotelibrary');

# Media server model names to ignore (i.e. Rhapsody)
my $IGNORE_RE = qr{Rhapsody}i;

sub init {
	main::INFOLOG && $log->info('UPnP: Starting up');
	
	# Look for all UPnP media servers on the network
	Slim::Plugin::RemoteLibrary::UPnP::ControlPoint->search( {
		callback   => \&foundDevice,
		deviceType => 'urn:schemas-upnp-org:device:MediaServer:1',
	} );
}

sub shutdown {
	main::INFOLOG && $log->info('UPnP: Shutting down');
	
	Slim::Plugin::RemoteLibrary::UPnP::ControlPoint->shutdown();
	
	while ( my ($udn, $device) = each %devices ) {
		if ( main::INFOLOG && $log->is_info ) {
			$log->info( sprintf( "UPnP: Removing device %s", $device->getfriendlyname ) );
		}
		
		foundDevice( $device, 'remove' );
	}
}

sub getDevices {
	return \%devices;
}

sub foundDevice {
	my ( $device, $event ) = @_;
	
	# We'll get a callback for all UPnP devices, but we only look for media servers
	if ( $device->getdevicetype =~ /MediaServer/ && $device->getmodelname !~ $IGNORE_RE ) {
		if ( $event eq 'add' ) {

			main::INFOLOG && $log->info("Adding new media server: " . HTML::Entities::decode( $device->getfriendlyname ));
			
			$devices{ $device->getudn } = $device;
			
			# If a UPnP server crashes, it won't send out a byebye message, so we need to poll
			# periodically to see if this server is still alive
			Slim::Utils::Timers::setTimer( $device, time() + 60, \&checkServerHealth );
		}
		elsif ( $event eq 'remove' ) {
			delete $devices{ $device->getudn };
			
			Slim::Utils::Timers::killTimers( $device, \&checkServerHealth );
		}
	}
	else {

		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug(sprintf("%s is a %s %s (%s), ignoring",
				$device->getfriendlyname,
				$device->getmanufacturer,
				$device->getmodelname,
				$device->getdevicetype,
			));
		}
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
	
	
	if ( $log->is_warn ) {
		$log->warn(sprintf("%s failed to respond at %s, removing. (%s)",
			$device->getfriendlyname,
			$device->getlocation,
			$error,
		));
	}
	
	# Remove the device from the control point
	Slim::Plugin::RemoteLibrary::UPnP::ControlPoint::removeDevice( $device );
	
	foundDevice( $device, 'remove' );
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
	
	Slim::Plugin::RemoteLibrary::UPnP::ControlPoint->browse( \%args );
}

sub gotContainer {
	my $io   = shift;
	my $args = shift;
	my $udn  = $args->{udn};
	
	my @children;
	
	if ( $io ) {		
		# We use an IO::String object and parse in chunks to reduce memory usage
		
		local $/ = '</container>';

		my $i;
	
		while ( my $chunk = <$io> ) {
			
			# This can be slow if we have a huge file to process, so give back some time
			main::idleStreams() if !(++$i % 20);
			
			if ( $chunk =~ /<container(.*?)<\/container>/sg ) {
				push @children, _parseChunk($1);
			}
			else {
				# done with containers, do we also have items?
				if ( $chunk =~ /<item/i ) {
					$io = IO::String->new( \$chunk );
					
					local $/ = '</item>';
					while ( my $itemChunk = <$io> ) {
						
						# This can be slow if we have a huge file to process, so give back some time
						main::idleStreams() if !(++$i % 20);
						
						if ( $itemChunk =~ /<item(.*?)<\/item>/sg ) {
							my $props = _parseChunk($1);
							
							# Cache artwork if any
							if ( $props->{albumArtURI} && $props->{url} ) {
								my $cache = Slim::Utils::Cache->new;
								$cache->set( "remote_image_" . $props->{url}, $props->{albumArtURI}, '1 week' );
							}

							push @children, $props;
						}
					}
				}
			}
		}
	}
	else {
		# request failed, add 1 child with the failure message
		push @children, {
			'title' => Slim::Utils::Strings::string('PLUGIN_REMOTE_LIBRARY_UPNP_REQUEST_FAILED'),
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

sub _parseChunk {
	my $node = shift;
	
	my ($title, $url);
	my $props = {};

	if ( $node =~ m{<dc:title[^>]*>([^<]+)</dc:title>} ) {
		$title = HTML::Entities::decode($1);
		utf8::decode($title);
		# some Rhapsody titles contain '??'
		$title =~ s/\?\?/ /g;
		$props->{title} = $title;
	}

	if ( $node =~ /id="([^"]+)"/ ) {
		$props->{id} = $1;
	}

	if ( $node =~ m{<upnp:class[^>]*>([^<]+)</upnp:class>} ) {
		$props->{type} = $1;
	}

	if ( $node =~ /childCount="([^"]+)"/ ) {
		$props->{childCount} = $1;
	}

	if ( $node =~ m{<res[^>]*>([^<]+)</res>} ) {
		$url = $1;
		
		# If the UPnP server is running on the same PC as the server, URL may be localhost
		if ( my ($host) = $url =~ /(127.0.0.1|localhost)/ ) {
			my $realIP = Slim::Utils::IPDetect::IP();
			$url       =~ s/$host/$realIP/;
		}
		
		$props->{url} = $url;
	}
				
	# grab all other namespace items
	my %otherItems = $node =~ m{<\w+:(\w+)[^>]*?>([^<]+)</\w+:}g;
	for my $key ( keys %otherItems ) {
		next if $key =~ /(?:title|class)/;	# we already grabbed these above
		$props->{$key} = HTML::Entities::decode( $otherItems{$key} );
		utf8::decode($props->{$key});
	}

	if ( $url && $title ) {
		Slim::Music::Info::setTitle($url, $title);
	}
	
	return $props;
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

	if ( $log->is_error ) {
		$log->error(sprintf("Error while trying to fetch blurb text at %s: %s",
			$http->url,
			$http->error,
		));
	}

	my $container   = $http->params('container');
	my $callback    = $args->{callback};
	my $passthrough = $args->{passthrough} || [];
	$callback->( $container, @{$passthrough} );
}

1;
