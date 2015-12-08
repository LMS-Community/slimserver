package Slim::Schema::Contributor;

# $Id$

use strict;
use base 'Slim::Schema::DBI';

use Scalar::Util qw(blessed);

use Slim::Schema::ResultSet::Contributor;

use Slim::Utils::Log;
use Slim::Utils::Misc;

my %contributorToRoleMap = (
	'ARTIST'      => 1,
	'COMPOSER'    => 2,
	'CONDUCTOR'   => 3,
	'BAND'        => 4,
	'ALBUMARTIST' => 5,
	'TRACKARTIST' => 6,
);

my @contributorRoles = sort keys %contributorToRoleMap;
my @contributorRoleIds = values %contributorToRoleMap;
my $totalContributorRoles = scalar @contributorRoles; 

my %roleToContributorMap = reverse %contributorToRoleMap;

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
	
	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();

	$class->many_to_many('tracks', 'contributorTracks' => 'contributor', undef, {
		'distinct' => 1,
		'order_by' => ['disc', 'tracknum', "titlesort $collate"], # XXX won't change if language changes
	});

	$class->many_to_many('albums', 'contributorAlbums' => 'album', undef, { 'distinct' => 1 });

	if ($] > 5.007) {
		$class->utf8_columns(qw/name namesort/);
	}

	$class->resultset_class('Slim::Schema::ResultSet::Contributor');
}

sub contributorRoles {
	return @contributorRoles;
}

sub contributorRoleIds {
	return @contributorRoleIds;
}

sub totalContributorRoles {
	return $totalContributorRoles;
}

sub roleToContributorMap {
	return \%roleToContributorMap;
}

sub typeToRole {
	return $contributorToRoleMap{$_[1]} || $_[1];
}

sub roleToType {
	return $roleToContributorMap{$_[1]};
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort) = @_;

	my $vaString = Slim::Music::Info::variousArtistString();

	$form->{'text'} = $self->name;
	
	if ($self->name eq $vaString) {
		$form->{'attributes'} .= "&album.compilation=1";
	}
}

# For saving favorites.
sub url {
	my $self = shift;

	return sprintf('db:contributor.name=%s', URI::Escape::uri_escape_utf8($self->name));
}

sub add {
	my $class = shift;
	my $args  = shift;

	# Pass args by name
	my $artist     = $args->{'artist'} || return;
	my $brainzID   = $args->{'brainzID'};

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
	my @sortedList   = $args->{'sortBy'} ? Slim::Music::Info::splitTag($args->{'sortBy'}) : @artistList;
	
	# Bug 9725, split MusicBrainz tag to support multiple artists
	my @brainzIDList;
	if ($brainzID) {
		@brainzIDList = Slim::Music::Info::splitTag($brainzID);
	}
	
	# Using native DBI here to improve performance during scanning
	my $dbh = Slim::Schema->dbh;

	for (my $i = 0; $i < scalar @artistList; $i++) {

		# Bug 10324, we now match only the exact name
		my $name   = $artistList[$i];
		my $search = Slim::Utils::Text::ignoreCase($name, 1);
		my $sort   = Slim::Utils::Text::ignoreCaseArticles(($sortedList[$i] || $name));
		my $mbid   = $brainzIDList[$i];
		
		my $sth = $dbh->prepare_cached( 'SELECT id FROM contributors WHERE name = ?' );
		$sth->execute($name);
		my ($id) = $sth->fetchrow_array;
		$sth->finish;
		
		if ( !$id ) {
			$sth = $dbh->prepare_cached( qq{
				INSERT INTO contributors
				(name, namesort, namesearch, musicbrainz_id)
				VALUES
				(?, ?, ?, ?)
			} );
			$sth->execute( $name, $sort, $search, $mbid );
			$id = $dbh->last_insert_id(undef, undef, undef, undef);
		}
		else {
			# Bug 3069: update the namesort only if it's different than namesearch
			if ( $search ne Slim::Utils::Unicode::utf8toLatin1Transliterate($sort) ) {
				$sth = $dbh->prepare_cached('UPDATE contributors SET namesort = ? WHERE id = ?');
				$sth->execute( $sort, $id );
			}
		}
		
		push @contributors, $id;
	}

	return wantarray ? @contributors : $contributors[0];
}

sub isInLibrary {
	my ( $self, $library_id ) = @_;
	
	return 1 unless $library_id && $self->id;
	return 1 if $library_id == -1;

	my $dbh = Slim::Schema->dbh;
	
	my $sth = $dbh->prepare_cached( qq{
		SELECT 1 
		FROM library_contributor
		WHERE contributor = ?
		AND library = ?
		LIMIT 1
	} );
	
	$sth->execute($self->id, $library_id);
	my ($inLibrary) = $sth->fetchrow_array;
	$sth->finish;
	
	return $inLibrary;
}

# Rescan list of contributors, this simply means to make sure at least 1 track
# from this contributor still exists in the database.  If not, delete the contributor.
sub rescan {
	my ( $class, @ids ) = @_;
	
	my $log = logger('scan.scanner');
	
	my $dbh = Slim::Schema->dbh;
	
	for my $id ( @ids ) {
		my $sth = $dbh->prepare_cached( qq{
			SELECT COUNT(*) FROM contributor_track WHERE contributor = ?
		} );
		$sth->execute($id);
		my ($count) = $sth->fetchrow_array;
		$sth->finish;
	
		if ( !$count ) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Removing unused contributor: $id");

			# This will cascade within the database to contributor_album and contributor_track
			$dbh->do( "DELETE FROM contributors WHERE id = ?", undef, $id );
		}
	}
}

1;

__END__
