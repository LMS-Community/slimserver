package Slim::Utils::Favorites;

use strict;

use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log = logger('favorites');

my $favsClassName;

sub registerFavoritesClassName {
	$favsClassName = shift;

	if ( !Slim::bootstrap::tryModuleLoad($favsClassName) ) {

		$log->info("Favorites handers set to $favsClassName");

	} else {

		$log->warn("Unable to load Favorites hander $favsClassName");

		$favsClassName = undef;
	}
}

sub new {

	if ($favsClassName) {

		return $favsClassName->new(@_);

	} else {

		return undef;
	}
}

sub enabled {
	return $favsClassName ? 1 : 0;
}

1;

# Favorites classes should contain the following methods
#
# sub new                 ( $class                        ) - contructor
# sub clientAdd           ( $class, $client, $url, $title ) - add $url with $title to favorites
# sub findByClientAndURL  ( $class, $client, $url         ) - returns index or undef for $url from favorites
# sub deleteByClientAndURL( $class, $client, $url         ) - deletes $url from favorites
# sub deleteByClientAndId ( $class, $client, $index       ) - deletes favorite with index $index

__END__
