package Slim::Menu::BrowseLibrary;

use strict;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

use constant MAX_ALBUMS => 500;

my $log = logger('database.info');
my $prefs = preferences('server');

# Unfortunately we can't use _generic(), as there's no CLI command to get the release types
sub _releases {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $wantMeta   = $pt->{'wantMetadata'};
	my $tags       = 'lWRSw';
	my $library_id = $args->{'library_id'} || $pt->{'library_id'};
	my $orderBy    = $args->{'orderBy'} || $pt->{'orderBy'};
	my $menuMode   = $args->{'params'}->{'menu_mode'};
	my $menuRoles  = $args->{'params'}->{'menu_roles'};

	Slim::Schema::Album->addReleaseTypeStrings();

	@searchTags = grep {
		$_ !~ /^role_id:/
	} grep {
		# library_id:-1 is supposed to clear/override the global library_id
		$_ && $_ !~ /(?:library_id\s*:\s*-1|remote_library)/
	} @searchTags;

	# we want all roles, as we're going to group
	push @searchTags, 'role_id:' . join(',', Slim::Schema::Contributor->contributorRoleIds);

	my @artistIds = grep /artist_id:/, @searchTags;
	my $artistId;
	if (scalar @artistIds) {
		$artistIds[0] =~ /artist_id:(\d+)/;
		$artistId = $1;
	}

	my $index = $args->{index};
	my $quantity = $args->{quantity};
	my $query = 'albums';

	push @searchTags, 'tags:' . $tags if defined $tags;

	main::INFOLOG && $log->is_info && $log->info("$query ($index, $quantity): tags ->", join(', ', @searchTags));

	# get the artist's albums list to create releses sub-items etc.
	my $requestRef = [ $query, 0, MAX_ALBUMS, @searchTags ];
	my $request = Slim::Control::Request->new( $client ? $client->id() : undef, $requestRef );
	$request->execute();

	$log->error($request->getStatusText()) if $request->isStatusError();

	my $albums = $request->getResult('albums_loop');

	# compile list of release types and contributions
	my %releaseTypes;
	my %contributions;
	my %isPrimaryArtist;
	my %albumList;
	foreach (@$albums) {
		# map to role's name for readability
		$_->{role_ids} = join(',', map { Slim::Schema::Contributor->roleToType($_) } split(',', $_->{role_ids} || ''));

		my $genreMatch = undef;
		if ( !( $menuMode && $menuMode ne 'artists' && $menuRoles ) && $prefs->get('showComposerReleasesbyAlbum')==2 ) {
			my $requestRef = [ 'genres', 0, MAX_ALBUMS, "album_id:".$_->{id} ];
			my $request = Slim::Control::Request->new( undef, $requestRef );
			$request->execute();
			$log->error($request->getStatusText()) if $request->isStatusError();
			my $genres= $request->getResult('genres_loop');
			foreach my $genre (@$genres) {
				$genreMatch ||= grep {uc($genre->{genre}) eq $_} split(/,/, uc($prefs->get('showComposerReleasesbyAlbumGenres')));
				last if $genreMatch;
			}
		}

		$_->{role_ids} =~ s/COMPOSER/COMPOSERALBUM/ if ( ( $menuMode && $menuMode ne 'artists' && $menuRoles ) || $genreMatch || $prefs->get('showComposerReleasesbyAlbum')==1 );

		my $addToMainReleases = sub {
			$isPrimaryArtist{$_->{id}}++;
			$releaseTypes{$_->{release_type}}++;
			$albumList{$_->{release_type}} ||= [];
			push @{$albumList{$_->{release_type}}}, $_->{id};
		};

		if ($_->{compilation}) {
			$_->{release_type} = 'COMPILATION';
			$addToMainReleases->();
			# only list outside the compilations if Composer/Conductor
			next unless $_->{role_ids} =~ /COMPOSER|CONDUCTOR/ && $_->{role_ids} !~ /ARTIST|BAND/;
		}
		# Release Types if album artist
		elsif ( $_->{role_ids} =~ /ALBUMARTIST/ ) {
			$addToMainReleases->();
			next;
		}
		# Consider this artist the main (album) artist if there's no other, defined album artist
		elsif ( $_->{role_ids} =~ /ARTIST/ ) {
			my $albumArtist = Slim::Schema->first('ContributorAlbum', {
				album => $_->{id},
				role  => Slim::Schema::Contributor->typeToRole('ALBUMARTIST'),
				contributor => { '!=' => $_->{artist_id} }
			});

			if (!$albumArtist) {
				$addToMainReleases->();
				next;
			}
		}

		# Roles on other releases
		foreach my $role ( grep { $_ ne 'ALBUMARTIST' } split(',', $_->{role_ids} || '') ) {
			# don't list as trackartist, if the artist is albumartist, too
			next if $role eq 'TRACKARTIST' && $isPrimaryArtist{$_->{id}};

			$contributions{$role} ||= [];
			push @{$contributions{$role}}, $_->{id};
		}
	}

	my @items;
	my $searchTags = [
		"artist_id:$artistId",
		"library_id:$library_id",
	];

	my @primaryReleaseTypes = map { uc($_) } @{Slim::Schema::Album->primaryReleaseTypes};
	push @primaryReleaseTypes, 'COMPILATION';    # we handle compilations differently, it's not part of the primaryReleaseTypes
	my %primaryReleaseTypes = map { $_ => 1 } @primaryReleaseTypes;

	my @sortedReleaseTypes = (@primaryReleaseTypes, sort {
		$a cmp $b
	} grep {
		!$primaryReleaseTypes{$_};
	} keys %releaseTypes);

	foreach my $releaseType (@sortedReleaseTypes) {
		my $name = Slim::Schema::Album->releaseTypeName($releaseType, $client);

		if ($releaseTypes{uc($releaseType)}) {
			push @items, _createItem($name, $releaseType eq 'COMPILATION'
					? [ { searchTags => [@$searchTags, 'compilation:1', "album_id:" . join(',', @{$albumList{$releaseType}})], orderBy => $orderBy } ]
					: [ { searchTags => [@$searchTags, "compilation:0", "release_type:$releaseType", "album_id:" . join(',', @{$albumList{$releaseType}})], orderBy => $orderBy } ]);
		}
	}

	$searchTags = [
		"artist_id:$artistId",
		"library_id:$library_id",
	];

	if (my $albumIds = delete $contributions{COMPOSERALBUM}) {
		push @items, _createItem(cstring($client, 'COMPOSERALBUMS'), [ { searchTags => [@$searchTags, "role_id:COMPOSER", "album_id:" . join(',', @$albumIds)] } ]);
	}

	if (my $albumIds = delete $contributions{COMPOSER}) {
		push @items, {
			name        => cstring($client, 'COMPOSITIONS'),
			image       => 'html/images/playlists.png',
			type        => 'playlist',
			playlist    => \&_tracks,
			# for compositions we want to have the compositions only, not the albums
			url         => \&_tracks,
			passthrough => [ { searchTags => [@$searchTags, "role_id:COMPOSER", "album_id:" . join(',', @$albumIds)] } ],
		};
	}

	if (my $albumIds = delete $contributions{TRACKARTIST}) {
		push @items, _createItem(cstring($client, 'APPEARANCES'), [ { searchTags => [@$searchTags, "role_id:TRACKARTIST", "album_id:" . join(',', @$albumIds)] } ]);
	}

	foreach my $role (sort keys %contributions) {
		my $name = cstring($client, $role) if Slim::Utils::Strings::stringExists($role);
		push @items, _createItem($name || ucfirst($role), [ { searchTags => [@$searchTags, "role_id:$role", "album_id:" . join(',', @{$contributions{$role}})] } ]);
	}

	# if there's only one category, display it directly
	if (scalar @items == 1 && (my $handler = $items[0]->{url})) {
		$handler->($client, $callback, $args, $pt);
	}
	# we didn't find anything
	elsif (!scalar @items) {
		_albums($client, $callback, $args, $pt);
	}
	# navigate categories if there's more than one
	else {
		# add extra items
		foreach ( grep { $_ } map { $_->($artistId) } @{getExtraItems('artist')} ) {
			push @items, $_;
		}

		# add "All" item
		push @items, {
			name        => cstring($client, 'ALL_RELEASES'),
			image       => 'html/images/albums.png',
			type        => 'playlist',
			playlist    => \&_tracks,
			url         => \&_albums,
			passthrough => [{ searchTags => $pt->{'searchTags'} || [] }],
		};

		my $result = $quantity == 1 ? {
			items => [ $items[$index] ],
			total => $quantity,
		} : {
			items => \@items,
			total => scalar @items,
		};

		$result->{offset} = $index;
		$result->{sorted} = 1;

		$callback->($result);
	}
}

sub _createItem {
	my ($name, $pt) = @_;

	return {
		name        => $name,
		image       => 'html/images/albums.png',
		type        => 'playlist',
		playlist    => \&_tracks,
		url         => \&_albums,
		passthrough => $pt,
	};
}

1;
