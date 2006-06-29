package Slim::Utils::ChangeNotify;

# $Id$
#
# Class cluster for finding changed files.

use strict;

use Slim::Utils::Misc;

sub new {
	my $class = shift;

	my $os     = $^O;
	my $loader = '';

	if ($os eq 'linux') {

		$loader = 'Slim::Utils::ChangeNotify::Linux';

	} elsif ($os eq 'win32') {

		$loader = 'Slim::Utils::ChangeNotify::Win32';
	}

	eval "use $loader";

	if ($@ && $@ =~ /Can't/) {

		msg("No Notification Class for OS: [$os]\n");
		return;
	}

	msg("Using changeNotify loader: $loader\n");

	return $loader->newWatcher;
}

1;

__END__
