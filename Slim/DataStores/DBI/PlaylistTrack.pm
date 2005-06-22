package Slim::DataStores::DBI::PlaylistTrack;

# $Id$
#
# Playlist to track mapping class

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('playlist_track');
	$class->columns(Essential => qw/id position playlist track/);

	$class->has_a(playlist => 'Slim::DataStores::DBI::Track');
	$class->has_a(track => 'Slim::DataStores::DBI::LightWeightTrack');

	$class->add_constructor('tracksOf' => 'playlist = ? ORDER BY position');

	$class->set_sql('deletePlaylist' => 'DELETE FROM __TABLE__ WHERE playlist = ?');
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
