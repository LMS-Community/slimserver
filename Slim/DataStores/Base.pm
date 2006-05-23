package Slim::DataStores::Base;

# $Id$

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Class::Virtually::Abstract);

use Scalar::Util qw(blessed);

use Slim::Utils::Misc;

our %fieldInfo = ();

my $init = 0;

=head1 NAME

Slim::DataStores::Base - Abstract Base class for implementing a SlimServer datastore.

=head1 SYNOPSIS

This is an Abstract Base class that provides compile time enforcement of
required methods needed to fully implement a SlimServer datastore. Subclasses
should override all of these methods.

=cut

{
	my $class = __PACKAGE__;

	# Exporter spews some warnings..
	$^W = 0;

	$class->virtual_methods(qw(
		new classForType contentType objectForUrl objectForId find count
		totalTime updateTrack newTrack updateOrCreate
		delete markAllEntriesStale markEntryAsValid markEntryAsInvalid
		cleanupStaleEntries cleanupStaleTrackEntries cleanupStaleTableEntries
		wipeCaches wipeAllData forceCommit clearExternalPlaylists clearInternalPlaylists
		getPlaylists getPlaylistForClient readTags setAlbumArtwork 
		commonAlbumTitlesChanged mergeVariousArtistsAlbums
	));

}

sub init {
	my $class = shift;

	%fieldInfo = (
		'Album' => {
			'resultToSortedName' => sub {
				my $obj = shift;
				my $sort = shift;

				if (defined($sort) && $sort =~ /^artist/ ) {
					
					if (blessed($obj->contributor) && $obj->contributor->can('namesort')) {

						return $obj->contributor->namesort;
						
					} else {

						return '';

					}

				} else {

					return $obj->namesort;

				}
			},
		},

		'Artwork' => {
			'title' => 'BROWSE_BY_ARTWORK',

			'browse' => sub {
				my $ds = shift;
				my $level = shift;
				my $findCriteria = shift;

				# remove albums with no artwork if requested
				if (!Slim::Utils::Prefs::get('includeNoArt')) {

					$findCriteria->{'album.artwork'} = { '!=' => undef };

				}

				# XXXX - same as album
			},

			'listItem' => sub {
				my $ds           = shift;
				my $form         = shift;

				$form->{'artwork'}    = 1;
				# XXXX - same as album
			},

			'suppressAll'      => 1,
			'nameTransform'    => 'album',
			'descendTransform' => 'album,track',
			'ignoreArticles'   => 1,
		},
	);

	# These can refer to other entries.
	$fieldInfo{'age'} = {

		'nameTransform' => 'album',
		'descendTransform' => 'track',
		'allTransform' => 'tracksByAgeAndAlbum',
	};

	$fieldInfo{'tracksByAgeAndAlbum'} = {
		'title' => 'BROWSE_NEW_MUSIC',
		'allTitle' => 'ALL_ALBUMS',

		'browse' => sub {
			my $ds = shift;
			my $level = shift;
			my $findCriteria = shift;
			my $idOnly = shift;

			# Call into age to get album IDs - poor man's sub-select
			# Perhaps DBIx::Class's join capabilities can help in the future.
			my $albums = &{$fieldInfo{'age'}->{'browse'}}($ds, $level, { 'audio' => 1 }, 1);

			return $ds->find({
				'field'  => 'lightweighttrack',
				'browse'   => {
					'album' => $albums,
				},
				'sortBy' => 'age',
			});
		},

		'ignoreArticles' => 0,
		'alphaPageBar' => sub { return 0; },
		'suppressAll' => 0,
	};

	$fieldInfo{'playlist'} = {
		'title' => 'SAVED_PLAYLISTS',

		'idToName'           => $fieldInfo{'track'}->{'idToName'},
		'resultToName'       => $fieldInfo{'track'}->{'resultToName'},
		'resultToSortedName' => $fieldInfo{'track'}->{'resultToSortedName'},
		'listItem'           => $fieldInfo{'track'}->{'listItem'},
		'search'             => $fieldInfo{'track'}->{'search'},

		'browse' => sub {
			my ($ds, $level, $findCriteria) = @_;

			return [ $ds->getPlaylists() ];
		},

		'ignoreArticles' => 0,
		'alphaPageBar' => sub { return 0; },
		'suppressAll' => 1,
	};

	$fieldInfo{'playlistTrack'} = {
		'title' => 'SAVED_PLAYLISTS',

		'idToName'           => $fieldInfo{'track'}->{'idToName'},
		'resultToName'       => $fieldInfo{'track'}->{'resultToName'},
		'resultToSortedName' => $fieldInfo{'track'}->{'resultToSortedName'},
		'search'             => $fieldInfo{'track'}->{'search'},

		'browse' => sub {
			my ($ds, $level, $findCriteria) = @_;

			if (defined $findCriteria->{'playlist'}) {

				my $obj = $ds->objectForId('playlist', $findCriteria->{'playlist'});

				if (!blessed($obj) || !$obj->can('tracks')) {

					return [];
				}

				# If the playlist has changed - re-import it.
				if ($obj->url =~ m!^file://!) {
					Slim::Utils::Misc::findAndScanDirectoryTree(undef, $obj);
				}

				return [ $obj->tracks ];
			}

			return [];
		},

		'listItem' => sub {
			my ($ds, $form, $item) = @_;

			&{$fieldInfo{'track'}->{'listItem'}}($ds, $form, $item);

			# Don't use the caller's attributes - those will be
			# referring to playlist,playlistTrack, which isn't
			# what we want. Everything else is the same as 'track' though'
			$form->{'attributes'} = sprintf('&track=%d', $item->id);
		},

		'browseBodyTemplate' => 'browse_playlist.html',
		#'browsePwdTemplate'  => 
		#'browseListTemplate' => 

		'ignoreArticles' => 0,
		'alphaPageBar' => sub { return 0; },
		'suppressAll' => 0,
		'nameTransform' => 'track',
	};

	# Allow these items to be used as parameters.
	$fieldInfo{'album.compilation'} = {};

	$init = 1;
}

sub queryFields {
	my $class = shift;

	$class->init unless $init;

	return keys %fieldInfo;
}

sub fieldInfo {
	my $class = shift;

	$class->init unless $init;

	return \%fieldInfo;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
