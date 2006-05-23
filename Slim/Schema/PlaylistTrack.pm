package Slim::Schema::PlaylistTrack;

# $Id$
#
# Playlist to track mapping class

use strict;
use base 'Slim::Schema::DBI';

{
	my $class = __PACKAGE__;

	$class->table('playlist_track');

	$class->add_columns(qw(id position playlist track));

	$class->set_primary_key('id');

	$class->belongs_to(playlist => 'Slim::Schema::Track');
	$class->belongs_to(track => 'Slim::Schema::Track');
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
