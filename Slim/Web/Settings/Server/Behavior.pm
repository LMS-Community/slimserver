package Slim::Web::Settings::Server::Behavior;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('BEHAVIOR_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/server/behavior.html');
}

sub prefs {
	return ($prefs,
			qw(noGenreFilter noRoleFilter searchSubString ignoredarticles splitList
				browseagelimit groupdiscs persistPlaylists reshuffleOnRepeat saveShuffled composerInArtists
				conductorInArtists bandInArtists variousArtistAutoIdentification
				ignoreReleaseTypes cleanupReleaseTypes groupArtistAlbumsByReleaseType
				useTPE2AsAlbumArtist variousArtistsString ratingImplementation useUnifiedArtistsList
				skipsentinel showComposerReleasesbyAlbum showComposerReleasesbyAlbumGenres)
		   );
}

sub handler {
	my ( $class, $client, $paramRef ) = @_;

	Slim::Schema::Album->addReleaseTypeStrings();

	$paramRef->{ratingImplementations} = Slim::Schema->ratingImplementations;

	my %releaseTypesToIgnore = map { $_ => 1 } @{ $prefs->get('releaseTypesToIgnore') || [] };

	# build list of release types, default and own
	my $ownReleaseTypes = Slim::Schema::Album->releaseTypes;
	$paramRef->{release_types} = [ map {
		my $type = $_;
		my $ucType = uc($_);

		$ownReleaseTypes = [
			grep { $_ ne $ucType } @$ownReleaseTypes
		];

		{
			id => $ucType,
			title => Slim::Schema::Album->releaseTypeName($type),
			ignore => $releaseTypesToIgnore{$ucType}
		};
	} grep {
		uc($_) ne 'ALBUM'
	} @{Slim::Schema::Album->primaryReleaseTypes} ];

	foreach (grep { $_ ne 'ALBUM' } @$ownReleaseTypes) {
		push @{$paramRef->{release_types}}, {
			id => $_,
			title => Slim::Schema::Album->releaseTypeName($_),
			ignore => $releaseTypesToIgnore{$_},
		};
	}

	if ( $paramRef->{'saveSettings'} ) {
		foreach my $releaseType (@{$paramRef->{release_types}}) {
			if ($paramRef->{'release_type_' . $releaseType->{id}}) {
				delete $releaseTypesToIgnore{$releaseType->{id}};
				delete $releaseType->{ignore};
			}
			else {
				$releaseTypesToIgnore{$releaseType->{id}} = $releaseType->{ignore} = 1;
			}
		}

		$prefs->set('releaseTypesToIgnore', [ keys %releaseTypesToIgnore ]);
	}

	return $class->SUPER::handler( $client, $paramRef );
}


1;

__END__
