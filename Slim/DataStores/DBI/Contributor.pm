package Slim::DataStores::DBI::Contributor;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('contributors');
	$class->columns(Essential => qw/id name namesort moodlogic_id moodlogic_mixable musicmagic_mixable/);
	$class->columns(Stringify => qw/name/);

	$class->has_many('contributorTracks' => ['Slim::DataStores::DBI::ContributorTrack' => 'contributor']);
}

our @fields = qw(contributor artist composer conductor band trackArtist albumArtist);

sub contributorFields {
	return \@fields;
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
