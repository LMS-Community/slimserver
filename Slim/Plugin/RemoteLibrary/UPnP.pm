package Slim::Plugin::RemoteLibrary::UPnP;

# Logitech Media Server Copyright 2001-2016 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# UPnP interface between the Control Point and player/web/plugins

use strict;
use URI::Escape qw(uri_escape uri_unescape);
use XML::Simple;

use Slim::Formats::RemoteMetadata;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring string);

use Slim::Plugin::RemoteLibrary::UPnP::MediaServer;

my $prefs = preferences('plugin.remotelibrary');
my $log   = logger('plugin.remotelibrary');
my $cache = Slim::Utils::Cache->new;

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
				
				# some servers don't return a list of icons, but only a single value
				$iconList = [ $iconList ] unless ref $iconList eq 'ARRAY';
				
				# pick the largest, and PNG over JPG (if both of same size)
				$iconList = [ sort {
					$b->{height} <=> $a->{height} || $b->{width} <=> $a->{width} 
					|| ($a->{mimetype} =~ /png/i && -1) || ($b->{mimetype} =~ /png/i && 1)
					|| ($a->{url} =~ /png$/i && -1) || ($b->{url} =~ /png$/i && 1)
				} @$iconList ];

				if ( scalar @$iconList && (my $img = $iconList->[0]->{url}) ) {
					if ($img !~ /^http/) {
						$img = _getBaseUrl($_->getlocation) . $img;
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
			image => proxiedImage($icon),
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
			type => 'textarea'
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
		my $hasIcons;
		
		my $filterRE;
		if ( my $ignoreFolders = $prefs->get('ignoreFolders') ) {
			$ignoreFolders = join( '|', split(/\s*,\s*/, $ignoreFolders) );
			$filterRE = qr/^(?:$ignoreFolders)$/i;
		}
				
		for my $child ( @{$children} ) {
			main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($child));
			
			next unless $child->{title};

			if ( defined $filterRE && $child->{title} =~ $filterRE ) {
				if ( !$child->{type} || $child->{type} =~ /^object.container(?:\.storageFolder)?$/i ) {
					main::INFOLOG && $log->is_info && $log->info("Skipping menu item, its name is on the ignore list (check settings if you don't agree): " . Data::Dump::dump($child));
					next;
				}
			}
			
			if ( $getMetadata ) {
				foreach ( qw(title artist album genre url) ) {
					push @$items, {
						name => cstring($client, uc($_)) . cstring($client, 'COLON') . ' ' . $child->{$_},
						type => 'text',
					} if $child->{$_};
				}
			}
			else {
				my $item = {
					name => $child->{title},
					type => 'link',
					url  => \&_browseUPnP,
					passthrough => [{
						device => $device,
						hierarchy => uri_escape( join( '__', $hierarchy, $child->{id} ) ),
					}],
				};
				
				if ($child->{url}) {
					$item->{play} = $child->{url};
					$item->{type} = 'audio';
					$item->{passthrough}->[0]->{metadata} = 1;

					# save metadata for later use
					$cache->set('upnp_meta_' . $child->{url}, $child, '1 week');

					# register metadata handler
					if ( !Slim::Formats::RemoteMetadata->getProviderFor($child->{url}) ) {
						my $baseUrl = _getBaseUrl($child->{url});
						
						Slim::Formats::RemoteMetadata->registerProvider(
							match => qr/\Q$baseUrl\E/,
							func => \&getMetadata,
						);
					}

					# when we're called to Play All Tracks or similar, return the stream's URL
					if ($playlist) {
						$item->{url} = $child->{url};
					}
					else {
						push @$tracks, $child->{url};
					}
				}
				elsif (!$child->{id}) {
					$item->{type} = 'textarea';
				}
				
				if ($child->{albumArtURI} && !$child->{url}) {
					$item->{image} = proxiedImage($child->{albumArtURI});
					$hasIcons++;
				}

				push @$items, $item;
			}
		}				

		# add a Play All item if there are tracks in the list
		if (@$tracks && scalar @$tracks > 1) {
			unshift @$items, {
				name => cstring($client, 'ALL_SONGS'),
				type => 'playlist',
				url  => \&_browseUPnP,
				on_select => 'play',
				image => $hasIcons ? 'html/images/playall.png' : undef,
				passthrough => [{
					device => $device,
					hierarchy => $hierarchy,
					playlist => 1,
				}],
			};
		}
	}
	
	if (!scalar @$items) {
		push @$items, {
			name => cstring($client, 'EMPTY'),
			type => 'text'
		};
	}

	$cb->($items);
}

sub getMetadata {
	my ( $client, $url ) = @_;

	my $info = $cache->get('upnp_meta_' . $url) || {};
	
	my $meta = {
		title => $info->{title},
	};
	
	if ( my $artist = $info->{artist} || $info->{actor} || $info->{contributor} || $info->{creator} ) {
		$meta->{artist} = $artist;
	}
	
	if ( my $date = $info->{date} ) {
		 if ( $date =~ /\b(\d{4})\b/ ) {
			 $meta->{year} = $1;
		 }
	}

	my %metaMapping = (
		title => 0,
		album => 0,
		genre => 0,
		originalTrackNumber => 'tracknum',
		albumArtURI => 'cover',
	);
	
	while ( my ($k, $attribute) = each %metaMapping ) {
		if ( defined $attribute && defined $info->{$k} ) {
			$meta->{$attribute || $k} = $info->{$k};
		}
	}

	return $meta;
}

sub _getBaseUrl {
	my $baseUrl = shift;
	my ($host, $port, $path, undef, undef) = Slim::Utils::Misc::crackURL($baseUrl);
	$baseUrl =~ s/\Q$path\E//;
	return $baseUrl;
}

# we don't provide our own image proxy implementation, but force use of the local imageproxy, as we can't resize remotely
my %registeredProxies;
sub proxiedImage {
	my ($url) = @_;

	my ($host) = Slim::Utils::Misc::crackURL($url);
	if (!$registeredProxies{$host}) {
		Slim::Web::ImageProxy->registerHandler(
			match => qr/\Q$host\E/i,
			func  => sub { return $_[0] },
		);
		$registeredProxies{$host}++;
	}
	
	return Slim::Web::ImageProxy::proxiedImage($url, 1);
}


1;