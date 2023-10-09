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

	my @artistIds = grep /artist_id:/, @searchTags;
	my $artistId;
	if (scalar @artistIds) {
		$artistIds[0] =~ /artist_id:(\d+)/;
		$artistId = $1;
	}

	my $index = 0;
	my $quantity = MAX_ALBUMS;
	my $query = 'albums';

	push @searchTags, 'tags:' . $tags if defined $tags;

	main::INFOLOG && $log->is_info && $log->info("$query ($index, $quantity): tags ->", join(', ', @searchTags));

	# get the artist's albums list to create releses sub-items etc.
	my $requestRef = [ $query, $index, $quantity, @searchTags ];
	my $request = Slim::Control::Request->new( $client ? $client->id() : undef, $requestRef );
	$request->execute();

	$log->error($request->getStatusText()) if $request->isStatusError();

	my $albums = $request->getResult('albums_loop');

	# compile list of release types and contributions
	my %releaseTypes;
	my %contributions;
	my %isPrimaryArtist;
	foreach (@$albums) {
		# Release Types if main artist
		if ($_->{role_ids} =~ /[1,5]/) {
			$releaseTypes{$_->{release_type}}++;
			next;
		}
		elsif ($_->{compilation}) {
			$releaseTypes{COMPILATION}++;
			# don't list as track artist on a compilation
			next if $_->{role_ids} =~ /[156]/;
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

	my $result = $args->{quantity} == 1 ? {
		items => [ $items[$args->{index}] ],
		total => $args->{quantity},
	} : {
		items => \@items,
		total => scalar @items,
	};

	if ( !scalar @items ) {
		$result->{items} = [ {
			type  => 'text',
			title => cstring($client, 'EMPTY'),
		} ];

		$result->{total} = 1;
	}

	$result->{offset} = $args->{index};
	$result->{sorted} = 1;

	# show album list if there's no sub-category
	if ($result->{total} > 1 || $args->{quantity} == 1) {
		$callback->($result);
	}
	else {
		_albums($client, $callback, $args, $pt)
	}
}

sub _createItem {
	my ($name, $pt) = @_;

	return {
		name        => $name,
		type        => 'playlist',
		playlist    => \&_tracks,
		url         => \&_albums,
		passthrough => $pt,
	};
}

1;