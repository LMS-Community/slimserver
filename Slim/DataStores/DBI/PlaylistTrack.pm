package Slim::DataStores::DBI::PlaylistTrack;

# $Id$
#
# Playlist to track mapping class

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('playlist_track');

	$class->add_columns(qw(id position playlist track));

	$class->set_primary_key('id');

	$class->belongs_to(playlist => 'Slim::DataStores::DBI::Track');
	$class->belongs_to(track => 'Slim::DataStores::DBI::Track');
}

sub deletePlaylist {
	my $class = shift;

	$class->search_literal('DELETE FROM __TABLE__ WHERE playlist = ?', @_);
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
