package Slim::Menu::BrowseLibrary;

use strict;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use constant MAX_ALBUMS => 500;
use constant PRIMARY_ARTIST_ROLES => 'ALBUMARTIST,ARTIST';

my $log = logger('database.info');

# Unfortunately we can't use _generic(), as there's no CLI command to get the release types
sub _releases {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $wantMeta   = $pt->{'wantMetadata'};
	my $tags       = 'lWRSw';
	my $library_id = $args->{'library_id'} || $pt->{'library_id'};

	my %primaryArtistIds = map { Slim::Schema::Contributor->typeToRole($_) => 1 } split(/,/, PRIMARY_ARTIST_ROLES);

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
		elsif ($_->{role_ids} =~ /[1,5]/) {
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
			$contributions{$role} = $roleId if $role;
		}
	}

	my @items;
	my $searchTags = [
		"artist_id:$artistId",
		"role_id:" . PRIMARY_ARTIST_ROLES,
		"library_id:" . $library_id,
	];

	my @primaryReleaseTypes = map { uc($_) } @{Slim::Schema::Album->primaryReleaseTypes};
	push @primaryReleaseTypes, 'COMPILATION';    # we handle compilations differently, it's not part of the primaryReleaseTypes

	my @sortedReleaseTypes = @primaryReleaseTypes, sort {
		$a cmp $b
	} grep {
		!grep /$_/, @primaryReleaseTypes;
	} keys %releaseTypes;

	foreach my $releaseType (@sortedReleaseTypes) {
		my $name;
		my $nameToken = uc($releaseType);
		foreach ($nameToken . 'S', $nameToken, 'RELEASE_TYPE_' . $nameToken . 'S', 'RELEASE_TYPE_' . $nameToken) {
			$name = cstring($client, $_) if Slim::Utils::Strings::stringExists($_);
			last if $name;
		}
		$name ||= $releaseType;

		if ($releaseTypes{uc($releaseType)}) {
			push @items, _createItem($name, $releaseType eq 'COMPILATION'
					? [ { searchTags => [@$searchTags, 'compilation:1'] } ]
					: [ { searchTags => [@$searchTags, "compilation:0", "release_type:$releaseType"] } ]);
		}
	}

	$searchTags = [
		"artist_id:$artistId",
		"library_id:" . $library_id,
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

	if (delete $contributions{TRACKARTIST}) {
		push @items, _createItem(cstring($client, 'APPEARANCES'), [ { searchTags => [@$searchTags, "role_id:TRACKARTIST"] } ]);
	}

	foreach my $role (sort keys %contributions) {
		my $name = cstring($client, $role) if Slim::Utils::Strings::stringExists($role);
		$name = ucfirst($role) if $role =~ /^[A-Z_0-9]$/;

		push @items, _createItem($name, [ { searchTags => [@$searchTags, "role_id:$role"] } ]);
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