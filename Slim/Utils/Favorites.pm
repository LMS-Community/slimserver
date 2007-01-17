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

		# return dummy class
		return bless({}, shift);
	}
}

# Favorites classes should define the following
sub clientAdd {}
sub findByClientAndURL {}
sub findByClientAndId {}
sub deleteByClientAndURL {}
sub deleteByClientAndId {}

1;

__END__
