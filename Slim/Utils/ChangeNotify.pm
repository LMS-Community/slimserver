package Slim::Utils::ChangeNotify;

# $Id$

=head1 NAME

Slim::Utils::ChangeNotify

=head1 DESCRIPTION

Class cluster for finding changed files.

=head1 SEE ALSO

L<Slim::Utils::ChangeNotify::Linux>, L<Slim::Utils::ChangeNotify::Win32>

=cut

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

	Slim::bootstrap::tryModuleLoad($loader);

	if ($@ && $@ =~ /Can't/) {

		msg("No Notification Class for OS: [$os]\n");
		return;
	}

	msg("Using changeNotify loader: $loader\n");

	return $loader->newWatcher;
}

1;

__END__
