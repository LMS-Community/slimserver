package Slim::Utils::UPnPMediaServer;

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use XML::Simple;
use UPnP::ControlPoint;

use Slim::Buttons::BrowseUPnPMediaServer;
use Slim::Web::UPnPMediaServer;
use Slim::Networking::Select;
use Slim::Utils::Misc;

my %devices = ();
my $controlPoint = undef;
my $deviceSearch = undef;
my @callbacks = ();

sub init {
	Slim::Buttons::BrowseUPnPMediaServer::init();
	Slim::Web::UPnPMediaServer::init();
}

sub checkDeviceAdd {
	my $device = shift;
	my $callback = shift;

	my ($menuName, $displayTitle) = &$callback($device, 'deviceAdded');

	# Don't add any menus, etc if the callback returns undef.
	if (defined $menuName && defined $displayTitle) {

		$devices{$device->UDN}{'items'}{'0'} = {
			'title' => $displayTitle,
		};

		addDeviceMenus($device, $menuName);
	}
}

sub findServer {
	my $callback = shift;

	push @callbacks, $callback;
	if (defined($deviceSearch)) {
		for my $device (values %devices) {
			checkDeviceAdd($device, $callback);
		}
	}
	else {
		$controlPoint = UPnP::ControlPoint->new();
		my @sockets = $controlPoint->sockets;
		for my $socket (@sockets) {
			Slim::Networking::Select::addRead($socket, \&handleCallback);
		}
		$deviceSearch = $controlPoint->searchByType('urn:schemas-upnp-org:device:MediaServer:1', \&deviceCallback);
	}
}

sub handleCallback {
	my $socket = shift;

	$controlPoint->handleOnce($socket);
}

sub deviceCallback {
	my ($search, $device, $action) = @_;

	if ($action eq 'deviceAdded') {
		unless ($devices{$device->UDN}) {		
			my $service = $device->getService("urn:upnp-org:serviceId:CDS_1-0");

			if (!$service) {
				$service = $device->getService("urn:upnp-org:serviceId:ContentDirectory");
			}

			my $proxy = $service->controlProxy if defined($service);

			return unless defined($proxy);

			$devices{$device->UDN} = {
				'controlProxy' => $proxy,
				'containers' => {},
				'items' => {},
			};
		}

		for my $callback (@callbacks) {
			checkDeviceAdd($device, $callback);
		}
	}
	elsif ($action eq 'deviceRemoved') {
		if ($devices{$device->UDN}) {
			for my $callback (@callbacks) {
				if (my ($menuName, $displaytitle) = &$callback($device, $action)) {
					removeDeviceMenus($device, $menuName);
					last;
				}
			}
			delete $devices{$device->UDN};
		}
	}
}

sub addDeviceMenus {
	my $device = shift;
	my $name = shift;

	if (!Slim::Utils::Strings::stringExists($name)) {
		Slim::Utils::Strings::addStringPointer(uc($name), $name);
	}
	
	my %params = (
		'useMode' => 'upnpmediaserver',
		'device' => $device,
	);

	Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', $name, \%params);

	Slim::Web::Pages->addPageLinks(
		'browse', { $name => 'browseupnp.html?device='.$device->UDN.'&hierarchy=0' }
	);
}

sub removeDeviceMenus {
	my $device = shift;
	my $name = shift;

	Slim::Buttons::Home::delSubMenu('BROWSE_MUSIC', $name);	
	
	Slim::Web::Pages->addPageLinks(
		'browse', { $name => undef }
	);
}

sub getContainerInfo {
	my $deviceUDN = shift;
	my $id = shift;

	my $container = $devices{$deviceUDN}{'containers'}{$id};
	unless ($container) {
		$container = loadContainer($deviceUDN, $id);
	}
	
	return $container;
}

sub loadContainer {
	my $deviceUDN = shift;
	my $id = shift;

	my $proxy = $devices{$deviceUDN}{'controlProxy'};
	return undef unless defined($proxy);

	my $result = $proxy->Browse($id, "BrowseDirectChildren", "*", 0, 0, "");

	if ( defined $result && $result->isSuccessful ) {
		# Regular expression based parsing of the XML. This is
		# because we've seen cases of non well-formed XML and
		# XML::Parser is not forgiving.
		my $xml = $result->getValue("Result");
		my @children;

		my @containerNodes = ();
		while ($xml =~ /<container(.*?)<\/container>/sg) {
			push(@containerNodes, $1);
		}

		foreach my $node (@containerNodes) {
			my ($title, $id, $type, $url, $childCount);
			if ($node =~ /<dc:title>(.*?)<\/dc:title>/s) {
				$title = HTML::Entities::decode($1);
			}
			if ($node =~ /<upnp:class>(.*?)<\/upnp:class>/s) {
				$type = $1;
			}
			if ($node =~ /id="(.*?)"/s) {
				$id = $1;
			}
			if ($node =~ /childCount="(.*?)"/s) {
				$childCount = $1;
			}
			if ($node =~ /<res(.*?)>(.*?)<\/res>/s) {
				$url = $2;
			}

			my $props = {
				'title' => $title,
				'id' => $id,
				'childCount' => $childCount,
				'url' => $url,
				'type' => $type,
			};
			$devices{$deviceUDN}{'items'}{$id} = $props;
			
			push @children, $props;
		}

		my @itemNodes = ();
		while ($xml =~ /<item(.*?)<\/item>/sg) {
			push(@itemNodes, $1);
		}

		foreach my $node (@itemNodes) {
			my ($title, $id, $type, $url, $album, $artist, $artURI, $blurbURI);
			
			if ($node =~ /<dc:title>(.*?)<\/dc:title>/s) {
				$title = HTML::Entities::decode($1);
			}
			if ($node =~ /<upnp:class>(.*?)<\/upnp:class>/s) {
				$type = $1;
			}
			if ($node =~ /id="(.*?)"/s) {
				$id = $1;
			}
			if ($node =~ /<res(.*?)>(.*?)<\/res>/s) {
				$url = $2;
			}
			if ($node =~ /<upnp:album>(.*?)<\/upnp:album>/s) {
				$album = HTML::Entities::decode($1);
			}
			if ($node =~ /<upnp:artist>(.*?)<\/upnp:artist>/s) {
				$artist = HTML::Entities::decode($1);
			}
			if ($node =~ /<upnp:albumArtURI>(.*?)<\/upnp:albumArtURI>/s) {
				$artURI = HTML::Entities::decode($1);
			}
			if ($node =~ /<upnp:blurbURI>(.*?)<\/upnp:blurbURI>/s) {
				$blurbURI = HTML::Entities::decode($1);
			}

			my $props = {
				'title' => $title,
				'id' => $id,
				'url' => $url,
				'type' => $type,
				'album' => $album,
				'artist' => $artist,
				'albumArtURI' => $artURI,
				'blurbURI' => $blurbURI,
			};
			$devices{$deviceUDN}{'items'}{$id} = $props;
			if ($url) {
				Slim::Music::Info::setTitle($url, $title);
			}

			push @children, $props;
		}

		$devices{$deviceUDN}{'containers'}{$id} = {
			'children' => \@children,
		};
	}
	else {
		# request failed, add 1 child with the failure message
		$devices{$deviceUDN}{'containers'}{$id} = {
			'children' => [ {
				'title' => Slim::Utils::Strings::string('UPNP_REQUEST_FAILED'),
			} ],
		};
	}

	return $devices{$deviceUDN}{'containers'}{$id};
}

sub getItemInfo {
	my $deviceUDN = shift;
	my $id = shift;

	my $item = $devices{$deviceUDN}{'items'}{$id};

	# If the item is a container, make sure it's loaded as well, since
	# we will need information (child item titles, for instance) from
	# it.
	if ((defined($item) && $item->{'childCount'}) ||
		($id eq '0')) {
		my $container = getContainerInfo($deviceUDN, $id);
	}

	return $item;
}

sub getDisplayName {
	my $deviceUDN = shift;

	return '' unless exists $devices{$deviceUDN};

	my $item = $devices{$deviceUDN}{'items'}{'0'};
	return $item->{'title'};
}

1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
