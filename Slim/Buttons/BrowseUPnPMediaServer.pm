package Slim::Buttons::BrowseUPnPMediaServer;

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use XML::Simple;
use UPnP::ControlPoint;

use Slim::Utils::UPnPMediaServer;
use Slim::Buttons::Common;
use Slim::Utils::Misc;
use Slim::Display::Display;

our %positions = ();

sub init {
	Slim::Buttons::Common::addMode('upnpmediaserver', getFunctions(),\&setMode);
}

our %functions = (
   'play' => sub {
	   my $client = shift;
	   
	   my $listIndex = $client->param( 'listIndex');
	   my $items = $client->param('listRef');
	   my $currentItem = $items->[$listIndex];
	   
	   return unless (defined($currentItem) &&
					  $currentItem->{'url'});
	   
	   my $url = $currentItem->{'url'};
	   my $title = $currentItem->{'title'};
	   $client->showBriefly( {
		   'line1'    => $client->string('CONNECTING_FOR'), 
		   'line2'    => $title, 
		   'overlay2' => $client->symbols('notesymbol'),
	   });

	   $client->execute([ 'playlist', 'play', $url ]);
   },
   'add' => sub {
	   my $client = shift;

	   my $listIndex = $client->param( 'listIndex');
	   my $items = $client->param('listRef');
	   my $currentItem = $items->[$listIndex];
	   
	   return unless (defined($currentItem) &&
					  $currentItem->{'url'});

	   my $url = $currentItem->{'url'};
	   my $title = $currentItem->{'title'};
	   $client->showBriefly( {
		   'line1'    => $client->string('ADDING_TO_PLAYLIST'), 
		   'line2'    => $title, 
		   'overlay2' => $client->symbols('notesymbol'),
	   });
	   
	   $client->execute([ 'playlist', 'add', $url ]);
   }				  
);

sub getFunctions {
	return \%functions;
}


sub listExitCallback {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);

	my $listIndex = $client->param('listIndex');
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} 
	# Right means select the current item
	elsif ($exittype eq 'RIGHT') {
		my $items = $client->param('listRef');
		my $device = $client->param('device');

		my $currentItem = $items->[$listIndex];
		unless (defined($currentItem) &&
				$currentItem->{'childCount'}) {
			$client->bumpRight();
			return;
		}

		my %params = (
			'device' => $device,
			'containerId' => $currentItem->{'id'},
			'title' => $currentItem->{'title'},
		);

		Slim::Buttons::Common::pushModeLeft($client, 'upnpmediaserver', \%params);
	}
	else {
		$client->bumpRight();
	}
}

sub listNameCallback {
	my $client = shift;
	my $item = shift;
	my $index = shift;

	return '' unless defined($item);
	return $item->{'title'};
}

sub listOverlayCallback {
	my $client = shift;
	my $item = shift;
	my ($overlay1, $overlay2);

	return (undef, undef) unless defined($item);

	if ($item->{'childCount'}) {
		$overlay2 = Slim::Display::Display::symbol('rightarrow');
	}
	elsif ($item->{'url'}) {
		$overlay2 = Slim::Display::Display::symbol('notesymbol');
	}

	return ($overlay1, $overlay2);
}

sub setMode {
	my $client = shift;
	my $method = shift;

	my $device = $client->param('device');
	if ($method eq 'pop' || !defined($device)) {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	unless (exists $positions{$client}) {
		$positions{$client} = {};
	}

	unless (exists $positions{$client}{$device}) {
		$positions{$client}{$device} = {};
	}

	my $id = $client->param('containerId') || 0;
	my $listIndex = $positions{$client}{$device}{$id} || 0;

	# Reload the container every time (as opposed to getting a cached
	# one), since it may have changed.
	my $container = Slim::Utils::UPnPMediaServer::loadContainer($device->UDN, $id);
	unless ($container) {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $children = $container->{'children'} || [];

	my %params = (

		# Parameters for INPUT.List
		header => $client->param('title') || Slim::Utils::UPnPMediaServer::getDisplayName($device->UDN),
		headerAddCount => (scalar(@$children) > 0),
		listRef => $children,
		listIndex => $listIndex,
		noWrap => (scalar(@$children) <= 1),
		callback => \&listExitCallback,
		externRef => \&listNameCallback,
		externRefArgs  => 'CVI',
		overlayRef => \&listOverlayCallback,
		onChange => sub {
			my $client = shift;
			my $i = shift;

			$positions{$client}{$device}{$id} = $i;
		},
		onChangeArgs => 'CI',
		isSorted => ($id eq '0') ? undef : 'L',
		lookupRef => ($id eq '0') ? undef : sub {
			my $index = shift;
			my $item = $children->[$index];
			
			if ($item) {
				return $item->{'title'};
			}
			return '';
		},

		# Parameters that reflect the state of this mode
		device => $device,
		containerId => $id,
	);

	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
}

1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
