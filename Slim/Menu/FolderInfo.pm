package Slim::Menu::FolderInfo;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Provides OPML-based extensible menu for folder info

=head1 NAME

Slim::Menu::FolderInfo

=head1 DESCRIPTION

Provides a dynamic OPML-based folder info menu to all UIs and allows
plugins to register additional menu items.

=cut

use strict;

use base qw(Slim::Menu::Base);

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

sub init {
	my $class = shift;
	$class->SUPER::init();
	
	Slim::Control::Request::addDispatch(
		[ 'folderinfo', 'items', '_index', '_quantity' ],
		[ 0, 1, 1, \&cliQuery ]
	);
}

sub name {
	return 'FOLDER_INFO';
}

##
# Register all the information providers that we provide.
# This order is defined at http://wiki.slimdevices.com/index.php/UserInterfaceHierarchy
#
sub registerDefaultInfoProviders {
	my $class = shift;
	
	$class->SUPER::registerDefaultInfoProviders();

	$class->registerInfoProvider( addFolder => (
		menuMode  => 1,
		after    => 'top',
		func      => \&addFolderEnd,
	) );

	$class->registerInfoProvider( addFolderNext => (
		menuMode  => 1,
		after    => 'addFolder',
		func      => \&addFolderNext,
	) );

	$class->registerInfoProvider( playItem => (
		menuMode  => 1,
		after    => 'addFolderNext',
		func      => \&playFolder,
	) );


}

sub addFolderNext {
	my ( $client, $tags ) = @_;
	addFolder( $client, $tags, 'insert', cstring($client, 'PLAY_NEXT') );
}

sub addFolderEnd {
	my ( $client, $tags ) = @_;
	addFolder( $client, $tags, 'add', cstring($client, 'ADD_TO_END') );
}

sub addFolder {
	my ($client, $tags, $cmd, $label) = @_;

	return [] if !blessed($client);

	my $actions = {
		go => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				folder_id => $tags->{folder_id},
				cmd => $cmd,
			},
			nextWindow => 'parent',
		},
	};
	$actions->{play} = $actions->{go};
	$actions->{add}  = $actions->{go};

	return [ {
		type        => 'text',
		playcontrol => $cmd,
		name        => $label,
		jive        => {
			actions => $actions
		}, 
	} ];
}


sub playFolder {
	my ( $client, $tags) = @_;

	return [] if !blessed($client);

	my $actions = {
		go => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				folder_id => $tags->{folder_id},
				cmd => 'load',
			},
			nextWindow => 'nowPlaying',
		},
	};
	$actions->{play} = $actions->{go};
	$actions->{add}  = $actions->{go};

	return [ {
		type        => 'text',
		playcontrol => 'play',
		name        => cstring($client, 'PLAY'),
		jive        => {
			actions => $actions
		}, 
	} ];
}


# keep a very small cache of feeds to allow browsing into a folder info feed
# we will be called again without $url or $albumId when browsing into the feed
tie my %cachedFeed, 'Tie::Cache::LRU', 2;

sub cliQuery {
	my $request = shift;
	
	# WebUI or newWindow param from SP side results in no
	# _index _quantity args being sent, but XML Browser actually needs them, so they need to be hacked in
	# here and the tagged params mistakenly put in _index and _quantity need to be re-added
	# to the $request params
	my $index      = $request->getParam('_index');
	my $quantity   = $request->getParam('_quantity');
	if ( $index =~ /:/ ) {
		$request->addParam(split (/:/, $index));
		$index = 0;
		$request->addParam('_index', $index);
	}
	if ( $quantity =~ /:/ ) {
		$request->addParam(split(/:/, $quantity));
		$quantity = 200;
		$request->addParam('_quantity', $quantity);
	}
	
	my $client    = $request->client;
	my $folder_id = $request->getParam('folder_id');
	my $menuMode  = $request->getParam('menu') || 0;
	my $connectionId = $request->connectionID || '';

	unless ( $folder_id || $cachedFeed{$connectionId} ) {
		$request->setStatusBadParams();
		return;
	}

	my $feed;

	if ( $folder_id ) {
		my $tags = {
			folder_id => $folder_id,
			menuMode  => $menuMode,
		};
		
		$feed = Slim::Menu::FolderInfo->menu( $client, $tags );
	}
	elsif ( $cachedFeed{ $connectionId } ) {
		$feed = $cachedFeed{ $connectionId };
	}
	
	$cachedFeed{ $connectionId } = $feed if $feed;
	
	Slim::Control::XMLBrowser::cliQuery( 'folderinfo', $feed, $request );
}

1;
