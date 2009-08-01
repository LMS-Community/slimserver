package Slim::Utils::Favorites;

use strict;

use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log = logger('favorites');

my $favsClassName;

sub registerFavoritesClassName {
	$favsClassName = shift;

	if ( !Slim::bootstrap::tryModuleLoad($favsClassName) ) {

		main::INFOLOG && $log->info("Favorites handers set to $favsClassName");

	} else {

		$log->warn("Unable to load Favorites hander $favsClassName");

		$favsClassName = undef;
	}
}

sub new {
	my $class = shift;

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
# sub new         ( $class, $client      ) - contructor
# sub add         ( $class, $url, $title ) - add $url with $title to favorites
# sub hasUrl      ( $class, $url         ) - return true or false whether $url is in favorites
# sub findUrl     ( $class, $url         ) - returns index or undef for $url
# sub deleteUrl   ( $class, $url         ) - deletes $url from favorites
# sub deleteIndex ( $class, $index       ) - deletes favorite with index $index
# all             ( $class               ) - return array of hashes for all playable favorites

__END__
