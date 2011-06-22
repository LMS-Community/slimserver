package Slim::Buttons::BrowseUPnPMediaServer;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::BrowseUPnPMediaServer

=head1 DESCRIPTION

L<Slim::Buttons::BrowseUPnPMediaServer> is a Logitech Media Server module for 
browsing services provided by UPnP servers

=cut

use strict;

use Slim::Utils::UPnPMediaServer;
use Slim::Buttons::Common;
use Slim::Utils::Misc;

sub init {
	Slim::Buttons::Common::addMode( 'upnpmediaserver', getFunctions(), \&setMode );
}

sub getFunctions {
	return {};
}

sub setMode {
	my $client = shift;
	my $method = shift;

	my $device = $client->modeParam('device');
	if ( $method eq 'pop' || !defined $device ) {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $id = $client->modeParam('containerId') || 0;
	
	my $browse = 'BrowseDirectChildren';
	if ( $client->modeParam('metadata') ) {
		$browse = 'BrowseMetadata';
	}
	
	my $title = $client->modeParam('title');
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
	
	# Add value keys to all items, so INPUT.Choice remembers state properly
	for my $item ( @{$children} ) {
		if ( !defined $item->{value} ) {
			$item->{value} = $item->{id};
		}
	}
	
	# if we got metadata, use remotetrackinfo
	if ( $browse eq 'BrowseMetadata' ) {
		
		my $item = $children->[0];
		
		my %params = (
			header  => $title,
			headerAddCount => 1,
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
		header         => $title,
		headerAddCount => 1,
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
			   'line'    => [ $client->string('CONNECTING_FOR'), $item->{title} ],
			   'overlay' => [ undef, $client->symbols('notesymbol') ]
		   });

		   $client->execute([ 'playlist', 'play', $item->{url} ]);
		},
		onAdd          => sub {
			my $client = shift;
			my $item   = shift;

			return unless ( defined($item) && $item->{url} );

			$client->showBriefly( {
			 'line'    => [ $client->string('ADDING_TO_PLAYLIST'), $item->{title} ],
			 'overlay' => [ undef, $client->symbols('notesymbol') ]
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
		$overlay = $client->symbols('rightarrow');
	}
	elsif ($item->{'url'}) {
		$overlay = $client->symbols('notesymbol');
	}

	return [ undef, $overlay ];
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Utils::UPnPMediaServer>

=cut

1;
