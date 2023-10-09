package Slim::Menu::BrowseLibrary;

use strict;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use constant MAX_ALBUMS => 500;
use constant PRIMARY_ARTIST_ROLES => 'ARTIST,ALBUMARTIST';

my $log = logger('database.info');

# Unfortunately we can't use _generic(), as there's no CLI command to get the release types
sub _releases {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $wantMeta   = $pt->{'wantMetadata'};
	my $tags       = 'lWR';
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
	foreach (@$albums) {
		my @roleIds = split(',', $_->{role_ids} || '');

		# Release Types if main artist
		if (grep { $primaryArtistIds{$_} } @roleIds) {
			$releaseTypes{$_->{release_type}}++;
		}

		# Roles on other releases
		foreach my $roleId (@roleIds) {
			next if $primaryArtistIds{$roleId};

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

	my %primaryReleaseTypes = map { { uc($_) => 1 } } @{Slim::Schema::Album->primaryReleaseTypes};
	$primaryReleaseTypes{COMPILATION} = 1;     # not in the above list but we still want to ignore it here

	my @sortedReleaseTypes = @{Slim::Schema::Album->primaryReleaseTypes}, sort {
		$a cmp $b
	} grep {
		!$primaryReleaseTypes{$_}
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
			push @items, {
				name        => $name,
				type        => 'playlist',
				playlist    => \&_tracks,
				url         => \&_albums,
				passthrough => [ { searchTags => [@$searchTags, "release_type:$releaseType"] } ],
			}
		}
	}

	$searchTags = [
		"artist_id:$artistId",
		"library_id:" . $library_id,
	];

	foreach my $role (sort keys %contributions) {
		my $name = cstring($client, $role) if Slim::Utils::Strings::stringExists($role);
		$name = ucfirst($role) if $role =~ /^[A-Z_0-9]$/;

		push @items, {
			name        => $name,
			type        => 'playlist',
			playlist    => \&_tracks,
			url         => \&_albums,
			passthrough => [ { searchTags => [@$searchTags, "role_id:$role"] } ],
		}
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

1;