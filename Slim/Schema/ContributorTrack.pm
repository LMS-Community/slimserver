package Slim::Schema::ContributorTrack;

# $Id$
#
# Contributor to track mapping class

use strict;
use base 'Slim::Schema::DBI';

{
	my $class = __PACKAGE__;

	$class->table('contributor_track');

	$class->add_columns(qw/role contributor track/);

	$class->set_primary_key(qw/role contributor track/);

	$class->belongs_to('contributor' => 'Slim::Schema::Contributor');
	$class->belongs_to('track'       => 'Slim::Schema::Track');
}

sub contributorsForTrackAndRole {
	my ($class, $track, $role) = @_;

	return $class->search({ track => $track, role => $role });
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
