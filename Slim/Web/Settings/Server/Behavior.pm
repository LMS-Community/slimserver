package Slim::Web::Settings::Server::Behavior;


# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
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
				browseagelimit groupdiscs persistPlaylists reshuffleOnRepeat saveShuffled
				variousArtistAutoIdentification
				ignoreReleaseTypes cleanupReleaseTypes groupArtistAlbumsByReleaseType
				useTPE2AsAlbumArtist variousArtistsString ratingImplementation useUnifiedArtistsList
				skipsentinel showComposerReleasesbyAlbum myClassicalGenres onlyAlbumYears
				worksScan useTIT1AsWork usePluralArtistTags)
		   );
}

sub handler {
	my ( $class, $client, $paramRef ) = @_;

	my $userDefinedRoles = $prefs->get('userDefinedRoles');

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

		foreach my $role (Slim::Schema::Contributor::defaultContributorRoles()) {
			$prefs->set(lc($role)."AlbumLink", $paramRef->{"pref_".lc($role)."AlbumLink"} ? "1" : "0");
			next if $role eq "ALBUMARTIST" || $role eq "ARTIST";
			$prefs->set(lc($role)."InArtists", $paramRef->{"pref_".lc($role)."InArtists"} ? "1" : "0");
		}
		foreach my $role (Slim::Schema::Contributor::userDefinedRoles()) {
			$userDefinedRoles->{$role}->{albumLink} = $paramRef->{"pref_".lc($role)."AlbumLink"};
			$userDefinedRoles->{$role}->{include} = $paramRef->{"pref_".lc($role)."InArtists"};
		}
		$prefs->set('userDefinedRoles', $userDefinedRoles);

		# custom role handling
		my $customRoleId = Slim::Schema::Contributor->getMinCustomRoleId();

		my $customTags = {};
		my $changed = 0;

		foreach my $pref (keys %{$paramRef}) {
			if ($pref =~ /(.*)_tag$/) {
				my $key = $1;
				my $tag = uc($paramRef->{$pref});

				if ( $tag ) {
					$customTags->{$tag} = {
						name => $paramRef->{$key . '_name'} || ucfirst(lc($tag)),
						namePlural => $paramRef->{$key . '_namePlural'} || $paramRef->{$key . '_name'} || ucfirst(lc($tag)),
						id => $userDefinedRoles->{$tag} ? $userDefinedRoles->{$tag}->{id} : $customRoleId++,
						include => $userDefinedRoles->{$tag}  ? $userDefinedRoles->{$tag}->{include} : 1,
						albumLink => $userDefinedRoles->{$tag}  ? $userDefinedRoles->{$tag}->{albumLink} : 1,
					};

					if ( !$userDefinedRoles->{$tag} || $userDefinedRoles->{$tag}->{name} ne $customTags->{$tag}->{name}
									|| $userDefinedRoles->{$tag}->{namePlural} ne $customTags->{$tag}->{namePlural} ) {
						Slim::Utils::Strings::storeExtraStrings(
							[
								{ strings => { EN => $customTags->{$tag}->{name}}, token   => $tag },
								{ strings => { EN => $customTags->{$tag}->{namePlural}}, token   => $tag . "_PLURAL" }
							]
						);
						$changed = 1;
					}
				}
			}
		}

		# set changed flag if we removed an item from the list
		$changed ||= grep { !$customTags->{$_} } keys %$userDefinedRoles;
		if ( $changed ) {
			$userDefinedRoles = $customTags;
			$prefs->set('userDefinedRoles', $customTags);
		}
	}

	$paramRef->{usesFTS} = Slim::Schema->canFulltextSearch;
	$paramRef->{customTags} = $prefs->get('userDefinedRoles');

	my $menuRoles = ();
	my $hidden = exists $paramRef->{"pref_useUnifiedArtistsList"} ? !($paramRef->{"pref_useUnifiedArtistsList"}) : !($prefs->get('useUnifiedArtistsList'));
	foreach my $role (Slim::Schema::Contributor::defaultContributorRoles()) {
		next if $role eq "ALBUMARTIST" || $role eq "ARTIST";
		push @{$menuRoles}, { name => lc($role), selected => $prefs->get(lc($role)."InArtists"), hidden => $hidden };
	}
	foreach my $role (Slim::Schema::Contributor::userDefinedRoles()) {
		push @{$menuRoles}, { name => lc($role), selected => $userDefinedRoles->{$role}->{include} };
	}
	$paramRef->{menuRoles} = $menuRoles;
	$paramRef->{userRoleCount} = scalar Slim::Schema::Contributor::userDefinedRoles();

	my $linkRoles = ();
	my $pref;
	foreach my $role (Slim::Schema::Contributor::defaultContributorRoles(), Slim::Schema::Contributor::userDefinedRoles()) {
		$pref = Slim::Schema::Contributor->isDefaultContributorRole($role) ? $prefs->get(lc($role)."AlbumLink") : $userDefinedRoles->{$role}->{albumLink};
		push @{$linkRoles}, { name => lc($role), selected => $pref };
	}
	$paramRef->{linkRoles} = $linkRoles;

	return $class->SUPER::handler( $client, $paramRef );
}


1;

__END__
