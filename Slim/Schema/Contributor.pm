package Slim::Schema::Contributor;

# $Id$

use strict;
use base 'Slim::Schema::DBI';

use Scalar::Util qw(blessed);
use Tie::Cache::LRU;

use Slim::Schema::ResultSet::Contributor;

use Slim::Utils::Misc;

use constant CACHE_SIZE => 50;

our %contributorToRoleMap = (
	'ARTIST'      => 1,
	'COMPOSER'    => 2,
	'CONDUCTOR'   => 3,
	'BAND'        => 4,
	'ALBUMARTIST' => 5,
	'TRACKARTIST' => 6,
);

# Small LRU cache of id => contributor object mapping, to improve scanner performance
tie my %CACHE, 'Tie::Cache::LRU', CACHE_SIZE;

{
	my $class = __PACKAGE__;

	$class->table('contributors');

	$class->add_columns(qw(
		id
		name
		namesort
		musicmagic_mixable
		namesearch
		musicbrainz_id
	));

	$class->set_primary_key('id');
	$class->add_unique_constraint('namesearch' => [qw/namesearch/]);

	$class->has_many('contributorTracks' => 'Slim::Schema::ContributorTrack');
	$class->has_many('contributorAlbums' => 'Slim::Schema::ContributorAlbum');

	$class->many_to_many('tracks', 'contributorTracks' => 'contributor', undef, {
		'distinct' => 1,
		'order_by' => [qw(disc tracknum titlesort)],
	});

	$class->many_to_many('albums', 'contributorAlbums' => 'album', undef, { 'distinct' => 1 });

	if ($] > 5.007) {
		$class->utf8_columns(qw/name namesort namesearch/);
	}

	$class->resultset_class('Slim::Schema::ResultSet::Contributor');
}

sub contributorRoles {
	my $class = shift;

	return sort keys %contributorToRoleMap;
}

sub totalContributorRoles {
	my $class = shift;

	return scalar keys %contributorToRoleMap;
}

sub typeToRole {
	my $class = shift;
	my $type  = shift;

	return $contributorToRoleMap{$type} || $type;
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort) = @_;

	my $vaString = Slim::Music::Info::variousArtistString();

	$form->{'text'} = $self->name;
	
	if ($self->name eq $vaString) {
		$form->{'attributes'} .= "&album.compilation=1";
	}

	my $Imports = Slim::Music::Import->importers;

	for my $mixer (keys %{$Imports}) {

		if (defined $Imports->{$mixer}->{'mixerlink'}) {
			&{$Imports->{$mixer}->{'mixerlink'}}($self, $form, $descend);
		}
	}
}

# For saving favorites.
sub url {
	my $self = shift;

	return sprintf('db:contributor.namesearch=%s', URI::Escape::uri_escape_utf8($self->namesearch));
}

sub add {
	my $class = shift;
	my $args  = shift;

	# Pass args by name
	my $artist     = $args->{'artist'} || return;
	my $brainzID   = $args->{'brainzID'};
	my $role       = $args->{'role'}   || return;
	my $track      = $args->{'track'}  || return;
	my $artistSort = $args->{'sortBy'} || $artist;

	my @contributors = ();

	# Bug 1955 - Previously 'last one in' would win for a
	# contributorTrack - ie: contributor & role combo, if a track
	# had an ARTIST & COMPOSER that were the same value.
	#
	# If we come across that case, force the creation of a second
	# contributorTrack entry.
	#
	# Split both the regular and the normalized tags
	my @artistList   = Slim::Music::Info::splitTag($artist);
	my @sortedList   = Slim::Music::Info::splitTag($artistSort);
	
	# Using native DBI here to improve performance during scanning
	my $dbh = Slim::Schema->storage->dbh;

	for (my $i = 0; $i < scalar @artistList; $i++) {

		# The search columnn is the canonical text that we match against in a search.
		my $name   = $artistList[$i];
		my $search = Slim::Utils::Text::ignoreCaseArticles($name);
		my $sort   = Slim::Utils::Text::ignoreCaseArticles(($sortedList[$i] || $name));
		
		my $sth = $dbh->prepare_cached( 'SELECT id FROM contributors WHERE namesearch = ?' );
		$sth->execute($search);
		my ($id) = $sth->fetchrow_array;
		$sth->finish;
		
		if ( !$id ) {
			$sth = $dbh->prepare_cached( qq{
				INSERT INTO contributors
				(name, namesort, namesearch, musicbrainz_id)
				VALUES
				(?, ?, ?, ?)
			} );
			$sth->execute( $name, $sort, $search, $brainzID );
			$id = $dbh->last_insert_id(undef, undef, undef, undef);
		}
		else {
			# Bug 3069: update the namesort only if it's different than namesearch
			if ( $search ne $sort ) {
				$sth = $dbh->prepare_cached('UPDATE contributors SET namesort = ? WHERE id = ?');
				$sth->execute( $sort, $id );
			}
		}
		
		$sth = $dbh->prepare_cached( qq{
			REPLACE INTO contributor_track
			(role, contributor, track)
			VALUES
			(?, ?, ?)
		} );
		$sth->execute( $role, $id, (ref $track ? $track->id : $track) );
		
		# We need to return a DBIC object, which is really slow, use a cache
		# to help out a bit
		if ( !exists $CACHE{$id} ) {
			$CACHE{$id} = Slim::Schema->rs('Contributor')->find($id);
		}
		push @contributors, $CACHE{$id};
	}

	return wantarray ? @contributors : $contributors[0];
}

# Rescan this contributor, this simply means to make sure at least 1 track
# from this contributor still exists in the database.  If not, delete the contributor.
# XXX native DBI
sub rescan {
	my $self = shift;
	
	my $count = Slim::Schema->rs('ContributorTrack')->search( contributor => $self->id )->count;
	
	if ( !$count ) {
		delete $CACHE{ $self->id };
		
		$self->delete;
	}
}

sub wipeCaches {
	my $class = shift;
	
	tied(%CACHE)->max_size(0);
	tied(%CACHE)->max_size(CACHE_SIZE);
}

1;

__END__
