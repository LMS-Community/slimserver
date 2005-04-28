package Slim::DataStores::DBI::LightWeightTrack;

use strict;
use base 'Slim::DataStores::DBI::Track';

# LightWeightTrack is a subclass of the Track class, based on the same
# underlying table. It's a quicker way to get a set of track search
# results if all that's required is the URL and content type. Since
# this class has a smaller set of essential columns, the inflation cost
# is smaller.

our %primaryColumns = (
	'id' => 'id',
);

our %essentialColumns = (
	'url' => 'url',
	'ct' => 'content_type',
	'multialbumsortkey' => 'multialbumsortkey',
	'album' => 'album',
);

our %otherColumns;
{
	for my $key (keys %Slim::DataStores::DBI::Track::allColumns) {
		if (grep $key ne $_, (keys %primaryColumns, 
				      keys %essentialColumns)) {
			$otherColumns{$key} = $Slim::DataStores::DBI::Track::allColumns{$key};
		}
	}

	my $class = __PACKAGE__;

	$class->table('tracks');

	$class->columns(Primary => keys %primaryColumns);
	$class->columns(Essential => keys %essentialColumns);
	$class->columns(Others => keys %otherColumns);
	$class->columns(Stringify => qw/url/);
}
