package Slim::DataStores::DBI::PlaylistTrack;

# $Id: PlaylistTrack.pm,v 1.1 2004/12/17 20:33:04 dsully Exp $
#
# Playlist to track mapping class

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('playlist_track');
	$class->columns(Essential => qw/id position playlist track/);

	$class->has_a(playlist => 'Slim::DataStores::DBI::Track');
	$class->has_a(track => 'Slim::DataStores::DBI::Track');

	$class->add_constructor('tracksOf' => 'playlist = ? ORDER BY position');
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
