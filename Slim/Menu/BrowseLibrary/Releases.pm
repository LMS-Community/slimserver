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

	my %primaryArtistIds;

	if ($prefs->get('useUnifiedArtistsList')) {
		foreach (Slim::Schema::Contributor->contributorRoles) {
			if ( $prefs->get(lc($_) . 'InArtists') || $_ =~ /ALBUMARTIST|ARTIST/) {
				$primaryArtistIds{Slim::Schema::Contributor->typeToRole($_)} = 1;
			}
		}
	}
	else {
		%primaryArtistIds = map { $_ => 1 } Slim::Schema::Contributor->contributorRoleIds();
	}

	Slim::Schema::Album->addReleaseTypeStrings();

	@searchTags = grep {
		$_ !~ /^role_id:/
	} grep {
		# library_id:-1 is supposed to clear/override the global library_id
		$_ && $_ !~ /(?:library_id\s*:\s*-1|remote_library)/
	} @searchTags;

	# we want all roles, as we're going to group
	push @searchTags, 'role_id:1,2,3,4,5,6';

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
	foreach (@$albums) {
		if ($_->{compilation}) {
			$releaseTypes{COMPILATION}++;
			# only list outside the compilations if Composer/Conductor
			next if $_->{role_ids} !~ /[23]/;
		}
		# Release Types if main artist
		elsif ( grep { $primaryArtistIds{$_} } split(//, $_->{role_ids}) ) {
			$releaseTypes{$_->{release_type}}++;
			next;
		}

		# Roles on other releases
		my @roleIds = split(',', $_->{role_ids} || '');
		foreach my $roleId (@roleIds) {
			next if $primaryArtistIds{$roleId};

			# don't list as trackartist, if the artist is albumartist, too
			next if $roleId == 6 && $isPrimaryArtist{$_->{id}};

			my $role = Slim::Schema::Contributor->roleToType($roleId);
			if ($role) {
				$contributions{$role} ||= [];
				push @{$contributions{$role}}, $_->{id};
			}
		}
	}

	my @items;
	my $searchTags = [
		"artist_id:$artistId",
		"role_id:" . join(',', keys %primaryArtistIds),
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
					? [ { searchTags => [@$searchTags, 'compilation:1'], orderBy => $orderBy } ]
					: [ { searchTags => [@$searchTags, "compilation:0", "release_type:$releaseType"], orderBy => $orderBy } ]);
		}
	}

	$searchTags = [
		"artist_id:$artistId",
		"library_id:$library_id",
	];

	if (delete $contributions{COMPOSER}) {
		push @items, {
			name        => cstring($client, 'COMPOSITIONS'),
			image       => 'html/images/playlists.png',
			type        => 'playlist',
			playlist    => \&_tracks,
			# for compositions we want to have the compositions only, not the albums
			url         => \&_tracks,
			passthrough => [ { searchTags => [@$searchTags, "role_id:COMPOSER"] } ],
		};
	}

	if (my $albums = delete $contributions{TRACKARTIST}) {
		push @items, _createItem(cstring($client, 'APPEARANCES'), [ { searchTags => [@$searchTags, "role_id:TRACKARTIST", "album_id:" . join(',', @$albums)] } ]);
	}

	foreach my $role (sort keys %contributions) {
		my $name = cstring($client, $role) if Slim::Utils::Strings::stringExists($role);
		$name = ucfirst($role) if $role =~ /^[A-Z_0-9]$/;

		push @items, _createItem($name, [ { searchTags => [@$searchTags, "role_id:$role", "album_id:" . join(',', @{$contributions{$role}})] } ]);
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
			name        => cstring($client, 'ALL_ALBUMS'),
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