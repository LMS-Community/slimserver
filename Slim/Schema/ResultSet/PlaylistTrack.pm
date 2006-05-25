package Slim::Schema::ResultSet::PlaylistTrack;

# $Id$

use strict;
use base qw(Slim::Schema::ResultSet::Track);

sub alphaPageBar   { 0 }
sub ignoreArticles { 0 }

sub browseBodyTemplate {
	return 'browse_playlist.html';
}

1;
