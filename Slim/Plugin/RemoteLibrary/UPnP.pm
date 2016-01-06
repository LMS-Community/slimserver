package Slim::Plugin::RemoteLibrary::UPnP;

# Logitech Media Server Copyright 2001-2016 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# UPnP interface between the Control Point and player/web/plugins

use strict;
use URI::Escape qw(uri_escape uri_unescape);
use XML::Simple;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring string);

use Slim::Plugin::RemoteLibrary::UPnP::MediaServer;

my $prefs = preferences('plugin.remotelibrary');
my $log   = logger('plugin.remotelibrary');

sub init {
	my $class = shift;

	main::INFOLOG && $log->info("UPnP init...");

	Slim::Plugin::RemoteLibrary::UPnP::MediaServer->init();
	
	Slim::Plugin::RemoteLibrary::Plugin->addRemoteLibraryProvider($class);
}

sub getLibraryList {
	return unless $prefs->get('useUPnP');

	my $devices = Slim::Plugin::RemoteLibrary::UPnP::MediaServer->getDevices();
	my $items = [];
	
	foreach ( values %$devices ) {
		# don't show LMS instances if we're using remote Logitech Media Servers, too
		next if $_->getfriendlyname =~ /^Logitech Media Server/ && $prefs->get('useLMS');

		my $icon = 'plugins/RemoteLibrary/html/icon.png';
		my $description = eval { XMLin($_->getdescription) };
		
		# try to get the server's icon
		if ( $description && $description->{device} && (my $iconList = $description->{device}->{iconList}) ) {
			
			if ( $iconList = $iconList->{icon} ) {
				
				# pick the largest, and PNG over JPG (if both of same size)
				$iconList = [ sort {
					$b->{height} <=> $a->{height} || $b->{width} <=> $a->{width} 
					|| ($a->{mimetype} =~ /png/i && -1) || ($b->{mimetype} =~ /png/i && 1)
					|| ($a->{url} =~ /png$/i && -1) || ($b->{url} =~ /png$/i && 1)
				} @$iconList ];

				if ( scalar @$iconList && (my $img = $iconList->[0]->{url}) ) {
					if ($img !~ /^http/) {
						my $baseUrl = $_->getlocation;
						my ($host, $port, $path, undef, undef) = Slim::Utils::Misc::crackURL($baseUrl);
						$baseUrl =~ s/$path//;
						$img = $baseUrl . $img;
					}
					
					$icon = $img;
				}
			}
			
		}

		# create menu item
		push @$items, {
			name => $_->getfriendlyname,
			type => 'link',
			url  => \&_browseUPnP,
			image => $icon,
			passthrough => [{
				device => $_->getudn,
				hierarchy => 0,
			}],
		};
	}
	
	return $items;
}

sub _browseUPnP {
	my ($client, $cb, $args, $pt) = @_;

	my $device    = $pt->{device};
	my $hierarchy = $pt->{hierarchy};
	my @levels    = map { uri_unescape($_) } split("__", $hierarchy);

	my $id = $levels[-1];
	
	my $browse = 'BrowseDirectChildren';

	if ( $pt->{metadata} ) {
		$browse = 'BrowseMetadata';
	}

	# Async load of container
	Slim::Plugin::RemoteLibrary::UPnP::MediaServer::loadContainer( {
		udn         => $device,
		id          => $id,
		method      => $browse,
		callback    => \&gotContainer,
		passthrough => [ $client, $cb, $args, $pt ],
	} );
	
	return;
}

sub gotContainer {
	my $container = shift;
	my ($client, $cb, $args, $pt) = @_;
	
	if ( ref $container ne 'HASH' ) {
		my $error = Slim::Utils::Strings::cstring($client, 'PLUGIN_REMOTE_LIBRARY_UPNP_REQUEST_FAILED');
			
		$cb->([{
			name => $error,
			type => 'text'
		}]);

		return;
	}
	
	my $items = [];
	
	if ( defined $container->{children} ) {
		my $children = $container->{children};
		
		my $device    = $pt->{device};
		my $hierarchy = $pt->{hierarchy};
		my $getMetadata = $pt->{metadata};
		my $playlist  = $pt->{playlist};
		my $tracks    = [];
				
		for my $child ( @{$children} ) {
			if ( $getMetadata ) {
				foreach ( qw(title artist album genre url) ) {
					push @$items, {
						name => cstring($client, uc($_)) . cstring($client, 'COLON') . ' ' . $child->{$_},
						type => 'text',
					} if $child->{$_};
				}
			}
			else {
				push @$items, {
					name => $child->{title},
					type => 'link',
					url  => \&_browseUPnP,
					passthrough => [{
						device => $device,
						hierarchy => uri_escape( join( '__', $hierarchy, $child->{id} ) ),
					}],
				};
				
				if ($child->{url}) {
					$items->[-1]->{play} = $child->{url};
					$items->[-1]->{type} = 'audio';
					$items->[-1]->{passthrough}->[0]->{metadata} = 1;

					# when we're called to Play All Tracks or similar, return the stream's URL
					$items->[-1]->{url}  = $child->{url} if $playlist;

					push @$tracks, $child->{url} unless $playlist;
				}
			}
		}				

		# add a Play All item if there are tracks in the list
		if (@$tracks && scalar @$tracks > 1) {
			unshift @$items, {
				name => cstring($client, 'ALL_SONGS'),
				type => 'playlist',
				url  => \&_browseUPnP,
				on_select => 'play',
				passthrough => [{
					device => $device,
					hierarchy => $hierarchy,
					playlist => 1,
				}],
			};
		}
	}

	$cb->($items);
}

1;