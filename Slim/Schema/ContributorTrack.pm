package Slim::Schema::ContributorTrack;

#
# Contributor to track mapping class

use strict;
use base 'Slim::Schema::DBI';

{
	my $class = __PACKAGE__;

	$class->table('contributor_track');

	$class->add_columns(qw/role contributor track/);

	$class->set_primary_key(qw/role contributor track/);
	$class->add_unique_constraint('role_contributor_track' => [qw/role contributor track/]);

	$class->belongs_to('contributor' => 'Slim::Schema::Contributor');
	$class->belongs_to('track'       => 'Slim::Schema::Track');
}

1;

__END__
