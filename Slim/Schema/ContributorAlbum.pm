package Slim::Schema::ContributorAlbum;

#
# Contributor to album mapping class

use strict;
use base 'Slim::Schema::DBI';

{
	my $class = __PACKAGE__;

	$class->table('contributor_album');

	$class->add_columns(qw/role contributor album/);
	$class->add_unique_constraint('contributorAlbum' => [qw/role contributor album/]);

	$class->set_primary_key(qw/role contributor album/);

	$class->belongs_to('contributor' => 'Slim::Schema::Contributor');
	$class->belongs_to('album'       => 'Slim::Schema::Album');
}

1;

__END__
