package Slim::Schema::PlaylistTrack;

#
# Playlist to track mapping class

use strict;
use base 'Slim::Schema::DBI';

use Slim::Schema::ResultSet::PlaylistTrack;

{
	my $class = __PACKAGE__;

	$class->table('playlist_track');

	$class->add_columns(qw(id position playlist track));

	$class->set_primary_key('id');

	$class->belongs_to(playlist => 'Slim::Schema::Track');

	$class->resultset_class('Slim::Schema::ResultSet::PlaylistTrack');
}

# The relationship to the Track objects is done here

sub inflate_result {
	my ($class, $source, $me, $prefetch) = @_;
	
	return Slim::Schema->objectForUrl({
				'url'        => $me->{track},
				'create'     => 1,
				'readTags'   => 1,
				'playlistId' => $me->{playlist},
			});
}

1;

__END__
