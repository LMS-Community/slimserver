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
		'track' => {

			'title' => 'BROWSE_BY_SONG',
			'allTitle' => 'ALL_SONGS',
			'idToName' => sub {
				my $ds  = shift;
				my $id  = shift;
				my $obj = $ds->objectForId('track', $id);

				if (blessed($obj) && $obj->can('title')) {

					return $obj->title;
				}

				return '';
			},

			'resultToId' => sub {
				my $obj = shift;
				return $obj->id;
			},

			'resultToName' => sub {
				my $obj = shift;
				return $obj->title;
			},

			'resultToSortedName' => sub {
				my $obj = shift;
				return $obj->titlesort;
			},

			'find' => sub {
				my $ds = shift;
				my $level = shift;
				my $findCriteria = shift;
				my $idOnly = shift;

				if (defined $findCriteria->{'playlist'}) {

					my $obj = $ds->objectForId('track', $findCriteria->{'playlist'});

					if (blessed($obj) && $obj->can('tracks')) {

						return [ $obj->tracks ];
					}

					return [];
				}

				if (Slim::Utils::Prefs::get('noGenreFilter') && defined $findCriteria->{'genre'}) {

					if (defined $findCriteria->{'album'}) {

						# Don't filter by genre - it's unneccesary and
						# creates a intensive query. We're already at
						# the track level for an album. Same goes for artist.
						delete $findCriteria->{'genre'};
						delete $findCriteria->{'artist'};
						delete $findCriteria->{'contributor_track.role'};

					} elsif (defined($findCriteria->{'artist'})) {

						# Don't filter by genre - it's unneccesary and
						# creates a intensive query. We're already at
						# the track level for an artist.
						delete $findCriteria->{'genre'};
					}
				}

				# Check to see if our only criteria is an
				# Album. If so, we can simply get the album's tracks.
				if (scalar keys %$findCriteria == 1 && defined $findCriteria->{'album'}) {

					my $albumObj = $ds->objectForId('album', $findCriteria->{'album'});

					if (blessed($albumObj) && $albumObj->can('tracks')) {

						return [ $albumObj->tracks ];
					}
				}

				# Because we store directories, etc in the
				# tracks table - only pull out items that are
				# 'audio' this is needed because we're using
				# idOnly - so ->find doesn't call
				# ->_includeInTrackCount. That should be able
				# to go away shortly as well.
				$findCriteria->{'audio'} = 1;

				return $ds->find({
					'field'  => 'lightweighttrack',
					'find'   => $findCriteria,
					'sortBy' => exists $findCriteria->{'album'} ? 'tracknum' : 'title',
					'idOnly' => $idOnly,
				});
			},

			'search' => sub {
				my $ds = shift;
				my $terms = shift;
				my $type = shift || 'track';
				my $idOnly = shift;

				return $ds->find({
					'field'  => $type,
					'find'   => {
						'track.titlesearch' => $terms,
						'audio'             => 1,
					},
					'sortBy' => 'title',
					'idOnly' => $idOnly,
				});
			},

			'listItem' => sub {
				my $ds   = shift;
				my $form = shift;
				my $item = shift;


				$form->{'text'}  = Slim::Music::Info::standardTitle(undef, $item);

				$form->{'artist'} = $item->artist;
				$form->{'album'}  = $item->album;

				my ($id, $url) = $item->get(qw(id url));

				$form->{'item'}            = $id;
				$form->{'itempath'}        = $url;
				$form->{'itemobj'}         = $item;

				my $webFormat = Slim::Utils::Prefs::getInd("titleFormat",Slim::Utils::Prefs::get("titleFormatWeb"));
				$form->{'includeArtist'}       = ($webFormat !~ /ARTIST/);
				$form->{'includeAlbum'}        = ($webFormat !~ /ALBUM/) ;
				$form->{'noArtist'}            = Slim::Utils::Strings::string('NO_ARTIST');
				$form->{'noAlbum'}             = Slim::Utils::Strings::string('NO_ALBUM');

				my $Imports = Slim::Music::Import->importers;

				for my $mixer (keys %{$Imports}) {
				
					if (defined $Imports->{$mixer}->{'mixerlink'}) {
						&{$Imports->{$mixer}->{'mixerlink'}}($item,$form,0);
					}
				}

				#$form->{'mixerlinks'} = $Slim::Web::Pages::additionalLinks{'mixer'};
			},

			'ignoreArticles' => 1,
			'alphaPageBar' => sub {
				my $findCriteria = shift;

				return !exists $findCriteria->{'album'};
			},
		},

		'genre' => {
			'title' => 'BROWSE_BY_GENRE',
			'allTitle' => 'ALL_GENRES',

			'idToName' => sub {
				my $ds  = shift;
				my $id  = shift;
				my $obj = $ds->objectForId('genre', $id);

				if (blessed($obj) && $obj->can('name')) {

					return $obj->name;
				}

				return '';
			},

			'resultToId' => sub {
				my $obj = shift;
				return $obj->id;
			},

			'resultToName' => sub {
				my $obj = shift;
				return $obj->name;
			},

			'resultToSortedName' => sub {
				my $obj = shift;
				return $obj->namesort;
			},

			'find' => sub {
				my $ds = shift;
				my $level = shift;
				my $findCriteria = shift;
				my $idOnly = shift;

				return $ds->find({
					'field'  => 'genre',
					'find'   => $findCriteria,
					'sortBy' => 'genre',
					'idOnly' => $idOnly,
				});
			},

			'listItem' => sub {
				my $ds = shift;
				my $form = shift;
				my $item = shift;
				my $itemname = shift;
				my $descend = shift;

				my $Imports = Slim::Music::Import->importers;

				for my $mixer (keys %{$Imports}) {
				
					if (defined $Imports->{$mixer}->{'mixerlink'}) {
						&{$Imports->{$mixer}->{'mixerlink'}}($item,$form,$descend);
					}
				}

				#$form->{'mixerlinks'} = $Slim::Web::Pages::additionalLinks{'mixer'};
			},

			'ignoreArticles' => 0,
			'alphaPageBar' => sub { return 1; },
		},

		'album' => {
			'title' => 'BROWSE_BY_ALBUM',
			'allTitle' => 'ALL_ALBUMS',

			'idToName' => sub {
				my $ds  = shift;
				my $id  = shift;
				my $obj = $ds->objectForId('album', $id);

				if (blessed($obj) && $obj->can('title')) {

					return $obj->title;
				}

				return '';
			},

			'resultToId' => sub {
				my $obj = shift;
				return $obj->id;
			},

			'resultToName' => sub {
				my $obj = shift;
				return $obj->title;
			},

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

					return $obj->titlesort;

				}
			},

			'find' => sub {
				my $ds           = shift;
				my $level        = shift;
				my $findCriteria = shift;
				my $idOnly       = shift;
				my $sort         = shift;

				# The user may not want to include all the composers / conductors
				if (my $roles = $ds->artistOnlyRoles) {

					$findCriteria->{'contributor.role'} = $roles;
				}

				if (Slim::Utils::Prefs::get('noGenreFilter') && 
					defined $findCriteria->{'genre'} &&
					defined $findCriteria->{'artist'}) {

					# Don't filter by genre - it's unneccesary and
					# creates a intensive query. We're already at
					# the album level for an artist
					delete $findCriteria->{'genre'};
				}

				# Bug: 2192 - Don't filter out compilation
				# albums at the artist level - we want to see all of them for an artist.
				if ($findCriteria->{'artist'} && !$findCriteria->{'album.compilation'}) {

					delete $findCriteria->{'album.compilation'};
				}

				# if sort includes artist ensure album contributor is used so all VA albums appear in one place
				if ($sort =~ /artist/) {

					# This allows SQL::Abstract to see a scalar
					# reference passed and treat it as literal.
 					$findCriteria->{'contributorId'} = \'= albums.contributor';

				}

				return $ds->find({
					'field'  => 'album',
					'find'   => $findCriteria,
					'sortBy' => $sort || 'album',
					'idOnly' => $idOnly,
				});
			},

			'search' => sub {
				my $ds     = shift;
				my $terms  = shift;
				my $type   = shift || 'album';
				my $idOnly = shift;

				return $ds->find({
					'field'  => $type,
					'find'   => { "album.titlesearch" => $terms },
					'sortBy' => $type,
					'idOnly' => $idOnly,
				});
			},

			'listItem' => sub {
				my $ds           = shift;
				my $form         = shift;
				my $item         = shift;
				my $itemname     = shift;
				my $descend      = shift;
				my $findCriteria = shift;
				my $sort         = shift;

				$form->{'text'}       = $item->title;
				$form->{'coverThumb'} = $item->artwork || 0;
				$form->{'size'}       = Slim::Utils::Prefs::get('thumbSize');

				$form->{'item'}       = $itemname;

				if (my $showYear = Slim::Utils::Prefs::get('showYear') || $sort =~ /^year/) {

					# Don't show years when browsing years..
					if (!$findCriteria->{'year'}) {
						$form->{'showYear'} = $showYear;
						$form->{'year'} = $item->year;
					}
				}

				# Show the artist in the album view
				if (Slim::Utils::Prefs::get('showArtist') || $sort =~ /^artist/) {

					if (my $contributor = $item->contributor) {

						$form->{'artist'}        = $contributor;
						$form->{'includeArtist'} = defined $findCriteria->{'artist'} ? 0 : 1;
						$form->{'noArtist'}      = Slim::Utils::Strings::string('NO_ARTIST');

					}
				}

				my $Imports = Slim::Music::Import->importers;

				for my $mixer (keys %{$Imports}) {
				
					if (defined $Imports->{$mixer}->{'mixerlink'}) {
						&{$Imports->{$mixer}->{'mixerlink'}}($item,$form,$descend);
					}
				}
			},

			'ignoreArticles' => 1,

			'alphaPageBar' => sub {
				my $findCriteria = shift;
				my $sort = shift; 

				return (!defined($sort) || $sort =~ /^artist|^album/ ) ? 1 : 0;
			},

		},

		'artwork' => {
			'title' => 'BROWSE_BY_ARTWORK',

			'idToName' => sub {
				my $ds  = shift;
				my $id  = shift;
				my $obj = $ds->objectForId('album', $id);

				if (blessed($obj) && $obj->can('title')) {

					return $obj->title;
				}

				return '';
			},

			'resultToId' => sub {
				my $obj = shift;
				return $obj->id;
			},

			'resultToName' => sub {
				my $obj = shift;
				return $obj->title;
			},

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

					return $obj->titlesort;

				}
			},

			'find' => sub {
				my $ds = shift;
				my $level = shift;
				my $findCriteria = shift;
				my $idOnly = shift;
				my $sort = shift;

				# remove albums with no artwork if requested
				if (!Slim::Utils::Prefs::get('includeNoArt')) {

					$findCriteria->{'album.artwork'} = { '!=' => undef };

				}

				if (Slim::Utils::Prefs::get('noGenreFilter') && 
					defined $findCriteria->{'genre'} &&
					defined $findCriteria->{'artist'}) {

					# Don't filter by genre - it's unneccesary and
					# creates a intensive query. We're already at
					# the album level for an artist
					delete $findCriteria->{'genre'};
				}

				# Bug: 2192 - Don't filter out compilation
				# albums at the artist level - we want to see all of them for an artist.
				if ($findCriteria->{'artist'} && !$findCriteria->{'album.compilation'}) {

					delete $findCriteria->{'album.compilation'};
				}

				# if sort includes artist ensure album contributor is used so all VA albums appear in one place
				if ($sort =~ /artist/) {

					# This allows SQL::Abstract to see a scalar
					# reference passed and treat it as literal.
 					$findCriteria->{'contributorId'} = \'= albums.contributor';

				}

				return $ds->find({
					'field'  => 'artwork',
					'find'   => $findCriteria,
					'sortBy' => $sort || 'album',
					'idOnly' => $idOnly,
				});

			},

			'listItem' => sub {
				my $ds           = shift;
				my $form         = shift;
				my $item         = shift;
				my $itemname     = shift;
				my $descend      = shift;
				my $findCriteria = shift;
				my $sort         = shift;

				$form->{'text'}       = $item->title;
				$form->{'coverThumb'} = $item->artwork || 0;
				$form->{'size'}       = Slim::Utils::Prefs::get('thumbSize');
				$form->{'item'}       = $itemname;
				$form->{'artwork'}    = 1;

				if (my $showYear = Slim::Utils::Prefs::get('showYear') || $sort =~ /^year/) {

					# Don't show years when browsing years..
					if (!$findCriteria->{'year'}) {
						$form->{'showYear'} = $showYear;
						$form->{'year'} = $item->year;
					}
				}

				# Show the artist in the album view
				if (Slim::Utils::Prefs::get('showArtist') || $sort =~ /^artist/) {

					$form->{'artist'}        = $item->contributor;
					$form->{'noArtist'}      = Slim::Utils::Strings::string('NO_ARTIST');
				}

				my $Imports = Slim::Music::Import->importers;

				for my $mixer (keys %{$Imports}) {
				
					if (defined $Imports->{$mixer}->{'mixerlink'}) {
						&{$Imports->{$mixer}->{'mixerlink'}}($item,$form,1);
					}
				}
			},

			'alphaPageBar' => sub {
				my $findCriteria = shift;
				my $sort = shift; 

				return (!defined($sort) || $sort =~ /^artist|^album/ ) ? 1 : 0;
			},

			'suppressAll'      => 1,
			'nameTransform'    => 'album',
			'descendTransform' => 'album,track',
			'ignoreArticles'   => 1,
		},

		'artist' => {
			'title' => 'BROWSE_BY_ARTIST',
			'allTitle' => 'ALL_ARTISTS',

			'idToName' => sub {
				my $ds = shift;
				my $id = shift;
				my $obj = $ds->objectForId('contributor', $id);

				if (blessed($obj) && $obj->can('name')) {

					return $obj->name;
				}
			},

			'resultToId' => sub {
				my $obj = shift;
				return $obj->id;
			},

			'resultToName' => sub {
				my $obj = shift;
				return $obj->name;
			},

			'resultToSortedName' => sub {
				my $obj = shift;
				return $obj->namesort;
			},

			'find' => sub {
				my $ds = shift;
				my $level = shift;
				my $findCriteria = shift;
				my $idOnly = shift;

				# The user may not want to include all the composers / conductors
				if (my $roles = $ds->artistOnlyRoles) {

					$findCriteria->{'contributor.role'} = $roles;
				}

				if (Slim::Utils::Prefs::get('variousArtistAutoIdentification')) {

					$findCriteria->{'album.compilation'} = 0;
				}

				return $ds->find({
					'field'  => 'artist',
					'find'   => $findCriteria,
					'sortBy' => 'artist',
					'idOnly' => $idOnly,
				});
			},

			'search' => sub {
				my $ds = shift;
				my $terms = shift;
				my $type = shift || 'contributor';
				my $idOnly = shift;

				my $find = {
					'contributor.namesearch' => $terms,
				};

				# Bug: 2479 - Don't include roles if the user has them unchecked.
				if (my $roles = $ds->artistOnlyRoles) {

					$find->{'contributor.role'} = $roles;
				}

				return $ds->find({
					'field'  => $type,
					'find'   => $find,
					'sortBy' => $type,
					'idOnly' => $idOnly,
				});
			},

			'listItem' => sub {
				my $ds   = shift;
				my $form = shift;
				my $item = shift;
				my $itemname = shift;
				my $descend = shift;

				$form->{'text'} = $item->name;

				my $Imports = Slim::Music::Import->importers;

				for my $mixer (keys %{$Imports}) {
				
					if (defined $Imports->{$mixer}->{'mixerlink'}) {
						&{$Imports->{$mixer}->{'mixerlink'}}($item, $form, $descend);
					}
				}
				
				#$form->{'mixerlinks'} = $Slim::Web::Pages::additionalLinks{'mixer'};
			},

			'ignoreArticles' => 1,
			'alphaPageBar' => sub { return 1; },
		},

		'default' => {
			'title' => 'BROWSE',
			'allTitle' => 'ALL',
			'idToName' => sub { my $ds = shift; return shift },
			'resultToId' => sub { return shift },
			'resultToName' => sub { return shift },
			'resultToSortedName' => sub { return shift },

			'find' => sub { 
				my $ds = shift;
				my $level = shift;
				my $findCriteria = shift;
				my $idOnly = shift;

				return $ds->find({
					'field'  => $level,
					'find'   => $findCriteria,
					'sortBy' => $level,
					'idOnly' => $idOnly,
				});
			},

			'listItem' => sub { },
			'ignoreArticles' => 0
		}
	);

	# These can refer to other entries.
	$fieldInfo{'age'} = {
		'title' => 'BROWSE_NEW_MUSIC',
		'allTitle' => 'ALL_ALBUMS',

		'idToName'           => $fieldInfo{'album'}->{'idToName'},
		'resultToId'         => $fieldInfo{'album'}->{'resultToId'},
		'resultToName'       => $fieldInfo{'album'}->{'resultToName'},
		'resultToSortedName' => $fieldInfo{'album'}->{'resultToSortedName'},
		'listItem'           => $fieldInfo{'album'}->{'listItem'},

		'find' => sub {
			my $ds = shift;
			my $level = shift;
			my $findCriteria = shift;
			my $idOnly = shift;

			return $ds->find({
				'field'  => 'album',
				'find'   => $findCriteria,
				'sortBy' => 'age',
				'limit'  => Slim::Utils::Prefs::get('browseagelimit'),
				'offset' => 0,
				'idOnly' => $idOnly,
			});
		},

		'nameTransform' => 'album',
		'descendTransform' => 'track',
		'allTransform' => 'tracksByAgeAndAlbum',
		'ignoreArticles' => 1,
		'alphaPageBar' => sub { return 0; },
	};

	$fieldInfo{'tracksByAgeAndAlbum'} = {
		'title' => 'BROWSE_NEW_MUSIC',
		'allTitle' => 'ALL_ALBUMS',

		'idToName'           => $fieldInfo{'track'}->{'idToName'},
		'resultToId'         => $fieldInfo{'track'}->{'resultToId'},
		'resultToName'       => $fieldInfo{'track'}->{'resultToName'},
		'resultToSortedName' => $fieldInfo{'track'}->{'resultToSortedName'},
		'listItem'           => $fieldInfo{'track'}->{'listItem'},

		'find' => sub {
			my $ds = shift;
			my $level = shift;
			my $findCriteria = shift;
			my $idOnly = shift;

			# Call into age to get album IDs - poor man's sub-select
			# Perhaps DBIx::Class's join capabilities can help in the future.
			my $albums = &{$fieldInfo{'age'}->{'find'}}($ds, $level, { 'audio' => 1 }, 1);

			return $ds->find({
				'field'  => 'lightweighttrack',
				'find'   => {
					'album' => $albums,
				},
				'sortBy' => 'age',
			});
		},

		'ignoreArticles' => 0,
		'alphaPageBar' => sub { return 0; },
		'suppressAll' => 0,
	};

	$fieldInfo{'year'} = {
		'title' => 'BROWSE_BY_YEAR',
		'allTitle' => 'ALL_YEARS',

		'idToName'           => $fieldInfo{'default'}->{'idToName'},
		'resultToId'         => $fieldInfo{'default'}->{'resultToId'},
		'resultToName'       => $fieldInfo{'default'}->{'resultToName'},
		'resultToSortedName' => $fieldInfo{'default'}->{'resultToSortedName'},
		'find'               => $fieldInfo{'default'}->{'find'},

		'listItem' => sub {
			my $ds = shift;
			my $list_form = shift;

			$list_form->{'showYear'} = 0;
		},

		'ignoreArticles' => 1,
		'alphaPageBar' => sub { return 0; },
	};

	$fieldInfo{'playlist'} = {
		'title' => 'SAVED_PLAYLISTS',

		'idToName'           => $fieldInfo{'track'}->{'idToName'},
		'resultToId'         => $fieldInfo{'track'}->{'resultToId'},
		'resultToName'       => $fieldInfo{'track'}->{'resultToName'},
		'resultToSortedName' => $fieldInfo{'track'}->{'resultToSortedName'},
		'listItem'           => $fieldInfo{'track'}->{'listItem'},
		'search'             => $fieldInfo{'track'}->{'search'},

		'find' => sub {
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
		'resultToId'         => $fieldInfo{'track'}->{'resultToId'},
		'resultToName'       => $fieldInfo{'track'}->{'resultToName'},
		'resultToSortedName' => $fieldInfo{'track'}->{'resultToSortedName'},
		'search'             => $fieldInfo{'track'}->{'search'},

		'find' => sub {
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
