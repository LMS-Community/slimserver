package Slim::Schema::ContributorAlbum;

# $Id$
#
# Contributor to album mapping class

use strict;
use base 'Slim::Schema::DBI';

{
	my $class = __PACKAGE__;

	$class->table('contributor_album');

	$class->add_columns(qw/role contributor album/);

	$class->set_primary_key(qw/role contributor album/);

	$class->belongs_to('contributor' => 'Slim::Schema::Contributor');
	$class->belongs_to('album'       => 'Slim::Schema::Album');
}

sub contributorsForAlbumAndRole {
	my $class = shift;

	$class->search_literal('album = ? AND role = ?', @_);
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
