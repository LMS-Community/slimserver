package Slim::DataStores::DBI::LightWeightTrack;

use strict;
use base 'Slim::DataStores::DBI::Track';

# LightWeightTrack is a subclass of the Track class, based on the same
# underlying table. It's a quicker way to get a set of track search
# results if all that's required is the URL and content type. Since
# this class has a smaller set of essential columns, the inflation cost
# is smaller.

our @essentialColumns = qw(id url content_type multialbumsortkey album);
our @otherColumns     = ();

INIT: {
	my $class = __PACKAGE__;

	my %essentialKeys = map { $_ => 1 } @essentialColumns;

	# Merge in columns that aren't in our essential from our super class
	# to the 'Others' column group.
	for my $key ($class->SUPER::columns('Essential')) {

		if (!$essentialKeys{$key}) {

			push @otherColumns, $key;
		}
	}

	$class->table('tracks');

	$class->columns(Primary   => 'id');
	$class->columns(Essential => @essentialColumns);
	$class->columns(Others    => @otherColumns);
	$class->columns(Stringify => qw/url/);
}

# Call SUPER explictly, as ->bitrate isn't a pure ->get of the column, but
# does some calculations instead.
sub bitrate {
	my $self = shift;

	return $self->SUPER::bitrate(@_);
}

1;

__END__
