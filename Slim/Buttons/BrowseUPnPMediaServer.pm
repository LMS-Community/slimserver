package Slim::Buttons::BrowseUPnPMediaServer;

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Player UI for UPnP servers

use strict;

use Slim::Utils::UPnPMediaServer;
use Slim::Buttons::Common;
use Slim::Utils::Misc;
use Slim::Display::Display;

sub init {
	Slim::Buttons::Common::addMode( 'upnpmediaserver', getFunctions(), \&setMode );
}

sub getFunctions {
	return {};
}

sub setMode {
	my $client = shift;
	my $method = shift;

	my $device = $client->param('device');
	if ( $method eq 'pop' || !defined $device ) {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $id = $client->param('containerId') || 0;
	
	my $browse = 'BrowseDirectChildren';
	if ( $client->param('metadata') ) {
		$browse = 'BrowseMetadata';
	}
	
	my $title = $client->param('title');
	HTML::Entities::decode($title);
	
	# give user feedback while loading
	$client->block(
		$client->string('XML_LOADING'),
		$title,
	);
	
	# Async load of container
	Slim::Utils::UPnPMediaServer::loadContainer( {
		udn         => $device,
		id          => $id,
		method      => $browse,
		callback    => \&gotContainer,
		passthrough => [ $client, $device, $id, $title, $browse ],
	} );
}

sub gotContainer {
	my $container = shift;
	my ( $client, $device, $id, $title, $browse ) = @_;
	
	$client->unblock;

	unless ($container) {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $children = $container->{'children'} || [];
	
	# if we got metadata, use remotetrackinfo
	if ( $browse eq 'BrowseMetadata' ) {
		
		my $item = $children->[0];
		
		my %params = (
			header  => $title . ' {count}',
			title   => $title,
			url     => $item->{url},
		);
		
		my @details;
		if ( $item->{artist} ) {
			push @details, '{ARTIST}: ' . $item->{artist};
		}
		if ( $item->{album} ) {
			push @details, '{ALBUM}: ' . $item->{album};
		}
		if ( $item->{type} ) {
			push @details, '{TYPE}: ' . $item->{type};
		}
		if ( $item->{blurbText} ) {
			# translate newlines into spaces
			$item->{blurbText} =~ s/\n/ /g;
			push @details, '{COMMENT}: ' . $item->{blurbText};
		}
		$params{details} = \@details;
		
		Slim::Buttons::Common::pushModeLeft( $client, 'remotetrackinfo', \%params );
		return;
	}

	my %params = (
		header         => $title . ' {count}',
		modeName       => "$device:$id",
		listRef        => $children,
		overlayRef     => \&listOverlayCallback,
		isSorted       => 1,
		lookupRef      => sub {
			my $index = shift;
			return $children->[$index]->{title};
		},
		onRight        => sub {
			my $client = shift;
			my $item   = shift;

			unless ( defined($item) && $item->{childCount} ) {
				#$client->bumpRight();
				#return;
			}

			my %params = (
				device      => $device,
				containerId => $item->{id},
				title       => $item->{title},
				metadata    => ( !defined $item->{childCount} ) ? 1 : 0,
			);
			
			Slim::Buttons::Common::pushMode( $client, 'upnpmediaserver', \%params );
		},
		onPlay         => sub {
			my $client = shift;
			my $item   = shift;

		   return unless ( defined($item) && $item->{url} );

		   $client->showBriefly( {
			   'line1'    => $client->string('CONNECTING_FOR'), 
			   'line2'    => $item->{title}, 
			   'overlay2' => $client->symbols('notesymbol'),
		   });

		   $client->execute([ 'playlist', 'play', $item->{url} ]);
		},
		onAdd          => sub {
			my $client = shift;
			my $item   = shift;

			return unless ( defined($item) && $item->{url} );

			$client->showBriefly( {
			 'line1'    => $client->string('ADDING_TO_PLAYLIST'), 
			 'line2'    => $item->{title}, 
			 'overlay2' => $client->symbols('notesymbol'),
			});

			$client->execute([ 'playlist', 'add', $item->{url} ]);
		},

		# Parameters that reflect the state of this mode
		device         => $device,
		containerId    => $id,
	);
	
	Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Choice', \%params );
}

sub listOverlayCallback {
	my $client = shift;
	my $item   = shift;
	my $overlay;

	return [ undef, undef ] unless defined($item);

	if ($item->{'childCount'}) {
		$overlay = Slim::Display::Display::symbol('rightarrow');
	}
	elsif ($item->{'url'}) {
		$overlay = Slim::Display::Display::symbol('notesymbol');
	}

	return [ undef, $overlay ];
}

1;